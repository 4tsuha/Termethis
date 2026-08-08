import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/services.dart';

import '../../features/connections/domain/private_key_importer.dart';

class AndroidPrivateKeyImporter implements PrivateKeyImporter {
  const AndroidPrivateKeyImporter([
    this._channel = const MethodChannel(
      'jp.hgzt23678.ssh_terminal_ja/private_key_picker',
    ),
  ]);

  final MethodChannel _channel;

  @override
  Future<ImportedPrivateKey?> pick() async {
    late final Map<String, Object?>? result;
    try {
      result = await _channel.invokeMapMethod<String, Object?>(
        'pickPrivateKey',
      );
    } on PlatformException catch (error) {
      throw PrivateKeyImportFailure(
        error.code == 'key_too_large'
            ? PrivateKeyImportFailureCode.tooLarge
            : PrivateKeyImportFailureCode.invalidKey,
        error,
      );
    }
    if (result == null) {
      return null;
    }
    final bytes = result['bytes'];
    final name = result['name'];
    if (bytes is! Uint8List || name is! String) {
      throw const PrivateKeyImportFailure(
        PrivateKeyImportFailureCode.invalidKey,
      );
    }

    late String pem;
    try {
      pem = utf8.decode(bytes);
    } on FormatException catch (error) {
      throw PrivateKeyImportFailure(
        PrivateKeyImportFailureCode.invalidEncoding,
        error,
      );
    }

    try {
      return ImportedPrivateKey(
        pem: pem,
        label: name,
        isEncrypted: SSHKeyPair.isEncryptedPem(pem),
      );
    } on UnsupportedError catch (error) {
      throw PrivateKeyImportFailure(
        PrivateKeyImportFailureCode.unsupportedKey,
        error,
      );
    } catch (error) {
      throw PrivateKeyImportFailure(
        PrivateKeyImportFailureCode.invalidKey,
        error,
      );
    }
  }
}

class DartSshPrivateKeyValidator implements PrivateKeyValidator {
  @override
  Future<void> validate(ImportedPrivateKey key, {String? passphrase}) async {
    if (key.isEncrypted && (passphrase == null || passphrase.isEmpty)) {
      throw const PrivateKeyImportFailure(
        PrivateKeyImportFailureCode.passphraseRequired,
      );
    }
    try {
      SSHKeyPair.fromPem(key.pem, key.isEncrypted ? passphrase : null);
    } on SSHKeyDecryptError catch (error) {
      throw PrivateKeyImportFailure(
        PrivateKeyImportFailureCode.invalidPassphrase,
        error,
      );
    } on UnsupportedError catch (error) {
      throw PrivateKeyImportFailure(
        PrivateKeyImportFailureCode.unsupportedKey,
        error,
      );
    } catch (error) {
      throw PrivateKeyImportFailure(
        PrivateKeyImportFailureCode.invalidKey,
        error,
      );
    }
  }
}
