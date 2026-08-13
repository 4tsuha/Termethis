import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';

import '../../features/connections/domain/credential_vault.dart';
import '../../features/settings/domain/vault_protection.dart';
import 'secure_value_store.dart';

typedef VaultDirectoryProvider = Future<Directory> Function();

class EncryptedFileCredentialVault implements LockableCredentialVault {
  EncryptedFileCredentialVault(
    this._secureStore,
    this._directoryProvider, {
    AesGcm? cipher,
    VaultProtectionGateway? protectionGateway,
    this._protectionMode = VaultProtectionMode.none,
  }) : _cipher = cipher ?? AesGcm.with256bits(),
       _protectionGateway =
           protectionGateway ?? const UnavailableVaultProtectionGateway();

  factory EncryptedFileCredentialVault.androidDefaults({
    required VaultProtectionGateway protectionGateway,
    required VaultProtectionMode protectionMode,
  }) {
    return EncryptedFileCredentialVault(
      const FlutterSecureValueStore(),
      () async {
        final supportDirectory = await getApplicationSupportDirectory();
        return Directory('${supportDirectory.path}/credential_vault');
      },
      protectionGateway: protectionGateway,
      protectionMode: protectionMode,
    );
  }

  static const _masterKeyName = 'credential_vault.master_key.v1';
  static const _recordVersion = 1;
  static const _maximumPemLength = 1024 * 1024;

  final SecureValueStore _secureStore;
  final VaultDirectoryProvider _directoryProvider;
  final AesGcm _cipher;
  final Random _random = Random.secure();
  final VaultProtectionGateway _protectionGateway;
  VaultProtectionMode _protectionMode;

  Future<SecretKey>? _masterKeyFuture;

  @override
  Future<CredentialHandle> putPrivateKey(
    PrivateKeyCredential credential,
  ) async {
    if (credential.pem.length > _maximumPemLength) {
      throw const CredentialVaultFailure(
        CredentialVaultFailureCode.unavailable,
      );
    }

    try {
      final clearText = utf8.encode(
        jsonEncode({
          'version': _recordVersion,
          'type': 'privateKey',
          'pem': credential.pem,
          'label': credential.label,
          'isEncrypted': credential.isEncrypted,
          'passphrase': credential.passphrase,
        }),
      );
      final secretBox = await _cipher.encrypt(
        clearText,
        secretKey: await _masterKey(),
      );
      final handle = CredentialHandle(_randomId());
      final envelope = jsonEncode({
        'version': _recordVersion,
        'nonce': base64Encode(secretBox.nonce),
        'cipherText': base64Encode(secretBox.cipherText),
        'mac': base64Encode(secretBox.mac.bytes),
      });
      final file = await _fileFor(handle);
      await file.parent.create(recursive: true);
      final temporaryFile = File('${file.path}.tmp');
      await temporaryFile.writeAsString(envelope, flush: true);
      await temporaryFile.rename(file.path);
      return handle;
    } on CredentialVaultFailure {
      rethrow;
    } catch (error) {
      throw CredentialVaultFailure(
        CredentialVaultFailureCode.unavailable,
        error,
      );
    }
  }

  @override
  Future<CredentialHandle> putPassword(PasswordCredential credential) async {
    if (credential.password.length > 64 * 1024) {
      throw const CredentialVaultFailure(
        CredentialVaultFailureCode.unavailable,
      );
    }
    try {
      final clearText = utf8.encode(
        jsonEncode({
          'version': _recordVersion,
          'type': 'password',
          'password': credential.password,
        }),
      );
      final secretBox = await _cipher.encrypt(
        clearText,
        secretKey: await _masterKey(),
      );
      final handle = CredentialHandle(_randomId());
      final envelope = jsonEncode({
        'version': _recordVersion,
        'nonce': base64Encode(secretBox.nonce),
        'cipherText': base64Encode(secretBox.cipherText),
        'mac': base64Encode(secretBox.mac.bytes),
      });
      final file = await _fileFor(handle);
      await file.parent.create(recursive: true);
      final temporaryFile = File('${file.path}.tmp');
      await temporaryFile.writeAsString(envelope, flush: true);
      await temporaryFile.rename(file.path);
      return handle;
    } catch (error) {
      throw CredentialVaultFailure(
        CredentialVaultFailureCode.unavailable,
        error,
      );
    }
  }

  @override
  Future<PrivateKeyCredential?> readPrivateKey(CredentialHandle handle) async {
    try {
      await _requireUnlocked();
      final file = await _fileFor(handle);
      if (!await file.exists()) {
        return null;
      }
      final envelope = jsonDecode(await file.readAsString());
      if (envelope is! Map<String, dynamic>) {
        throw const CredentialVaultFailure(
          CredentialVaultFailureCode.corruptData,
        );
      }
      if (envelope['version'] != _recordVersion) {
        throw const CredentialVaultFailure(
          CredentialVaultFailureCode.unsupportedVersion,
        );
      }
      final secretBox = SecretBox(
        base64Decode(envelope['cipherText'] as String),
        nonce: base64Decode(envelope['nonce'] as String),
        mac: Mac(base64Decode(envelope['mac'] as String)),
      );
      final clearText = await _cipher.decrypt(
        secretBox,
        secretKey: await _masterKey(),
      );
      final record = jsonDecode(utf8.decode(clearText));
      if (record is! Map<String, dynamic> ||
          record['version'] != _recordVersion) {
        throw const CredentialVaultFailure(
          CredentialVaultFailureCode.corruptData,
        );
      }
      if (record['type'] != 'privateKey') return null;
      return PrivateKeyCredential(
        pem: record['pem'] as String,
        label: record['label'] as String,
        isEncrypted: record['isEncrypted'] as bool,
        passphrase: record['passphrase'] as String?,
      );
    } on CredentialVaultFailure {
      rethrow;
    } on SecretBoxAuthenticationError catch (error) {
      throw CredentialVaultFailure(
        CredentialVaultFailureCode.corruptData,
        error,
      );
    } catch (error) {
      throw CredentialVaultFailure(
        CredentialVaultFailureCode.corruptData,
        error,
      );
    }
  }

  @override
  Future<PasswordCredential?> readPassword(CredentialHandle handle) async {
    try {
      await _requireUnlocked();
      final record = await _readRecord(handle);
      if (record == null || record['type'] != 'password') return null;
      return PasswordCredential(record['password'] as String);
    } on CredentialVaultFailure {
      rethrow;
    } catch (error) {
      throw CredentialVaultFailure(
        CredentialVaultFailureCode.corruptData,
        error,
      );
    }
  }

  Future<Map<String, dynamic>?> _readRecord(CredentialHandle handle) async {
    final file = await _fileFor(handle);
    if (!await file.exists()) return null;
    final envelope = jsonDecode(await file.readAsString());
    if (envelope is! Map<String, dynamic> ||
        envelope['version'] != _recordVersion) {
      throw const CredentialVaultFailure(
        CredentialVaultFailureCode.corruptData,
      );
    }
    final secretBox = SecretBox(
      base64Decode(envelope['cipherText'] as String),
      nonce: base64Decode(envelope['nonce'] as String),
      mac: Mac(base64Decode(envelope['mac'] as String)),
    );
    final clearText = await _cipher.decrypt(
      secretBox,
      secretKey: await _masterKey(),
    );
    final record = jsonDecode(utf8.decode(clearText));
    if (record is! Map<String, dynamic> ||
        record['version'] != _recordVersion) {
      throw const CredentialVaultFailure(
        CredentialVaultFailureCode.corruptData,
      );
    }
    return record;
  }

  @override
  Future<void> delete(CredentialHandle handle) async {
    try {
      final file = await _fileFor(handle);
      if (await file.exists()) {
        await file.delete();
      }
    } on CredentialVaultFailure {
      rethrow;
    } catch (error) {
      throw CredentialVaultFailure(
        CredentialVaultFailureCode.unavailable,
        error,
      );
    }
  }

  Future<SecretKey> _masterKey() {
    return _masterKeyFuture ??= _loadOrCreateMasterKey();
  }

  Future<void> _requireUnlocked() async {
    final mode = _protectionMode;
    if (mode == VaultProtectionMode.none) return;
    final status = await _protectionGateway.status(mode);
    if (status.keyInvalidated) {
      throw const CredentialVaultFailure(
        CredentialVaultFailureCode.keystoreKeyInvalidated,
      );
    }
    if (!status.available) {
      throw const CredentialVaultFailure(
        CredentialVaultFailureCode.biometricUnavailable,
      );
    }
    if (status.locked) {
      throw const CredentialVaultFailure(
        CredentialVaultFailureCode.vaultLocked,
      );
    }
  }

  @override
  void clearCachedSecrets() {
    _masterKeyFuture = null;
  }

  @override
  void setProtectionMode(Object mode) {
    if (mode is VaultProtectionMode) _protectionMode = mode;
  }

  Future<SecretKey> _loadOrCreateMasterKey() async {
    final stored = await _secureStore.read(_masterKeyName);
    if (stored != null) {
      try {
        final bytes = base64Decode(stored);
        if (bytes.length == 32) {
          return SecretKey(bytes);
        }
      } catch (_) {
        throw const CredentialVaultFailure(
          CredentialVaultFailureCode.corruptData,
        );
      }
      throw const CredentialVaultFailure(
        CredentialVaultFailureCode.corruptData,
      );
    }

    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    await _secureStore.write(_masterKeyName, base64Encode(bytes));
    return SecretKey(bytes);
  }

  Future<File> _fileFor(CredentialHandle handle) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{20,80}$').hasMatch(handle.value)) {
      throw const CredentialVaultFailure(
        CredentialVaultFailureCode.invalidHandle,
      );
    }
    final directory = await _directoryProvider();
    return File('${directory.path}/${handle.value}.vault');
  }

  String _randomId() {
    final bytes = List<int>.generate(24, (_) => _random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}
