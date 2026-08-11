import 'dart:convert';

import 'package:flutter/services.dart';

import '../../features/connections/domain/private_key_importer.dart';
import '../../src/rust/api/core.dart' as rust;

class AndroidPrivateKeyImporter implements PrivateKeyImporter {
  const AndroidPrivateKeyImporter([
    this._channel = const MethodChannel('jp.yts.termethis/private_key_picker'),
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
      final isEncrypted = await rust.privateKeyIsEncrypted(pem: pem);
      if (!isEncrypted) await rust.validatePrivateKey(pem: pem);
      return ImportedPrivateKey(
        pem: pem,
        label: name,
        isEncrypted: isEncrypted,
      );
    } catch (error) {
      throw PrivateKeyImportFailure(
        PrivateKeyImportFailureCode.invalidKey,
        error,
      );
    }
  }
}

class RustSshPrivateKeyValidator implements PrivateKeyValidator {
  @override
  Future<void> validate(ImportedPrivateKey key, {String? passphrase}) async {
    if (key.isEncrypted && (passphrase == null || passphrase.isEmpty)) {
      throw const PrivateKeyImportFailure(
        PrivateKeyImportFailureCode.passphraseRequired,
      );
    }
    try {
      await rust.validatePrivateKey(
        pem: key.pem,
        passphrase: key.isEncrypted ? passphrase : null,
      );
    } catch (error) {
      throw PrivateKeyImportFailure(
        key.isEncrypted
            ? PrivateKeyImportFailureCode.invalidPassphrase
            : PrivateKeyImportFailureCode.invalidKey,
        error,
      );
    }
  }
}
