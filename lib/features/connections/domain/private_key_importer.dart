class ImportedPrivateKey {
  const ImportedPrivateKey({
    required this.pem,
    required this.label,
    required this.isEncrypted,
  });

  final String pem;
  final String label;
  final bool isEncrypted;
}

abstract interface class PrivateKeyImporter {
  Future<ImportedPrivateKey?> pick();
}

abstract interface class PrivateKeyValidator {
  Future<void> validate(ImportedPrivateKey key, {String? passphrase});
}

enum PrivateKeyImportFailureCode {
  tooLarge,
  invalidEncoding,
  invalidKey,
  passphraseRequired,
  invalidPassphrase,
  unsupportedKey,
}

class PrivateKeyImportFailure implements Exception {
  const PrivateKeyImportFailure(this.code, [this.cause]);

  final PrivateKeyImportFailureCode code;
  final Object? cause;

  @override
  String toString() => 'PrivateKeyImportFailure($code)';
}
