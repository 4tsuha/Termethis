import 'dart:async';

class CredentialHandle {
  const CredentialHandle(this.value);

  final String value;

  @override
  bool operator ==(Object other) =>
      other is CredentialHandle && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

class PrivateKeyCredential {
  const PrivateKeyCredential({
    required this.pem,
    required this.label,
    required this.isEncrypted,
    this.passphrase,
  });

  final String pem;
  final String label;
  final bool isEncrypted;
  final String? passphrase;
}

enum CredentialVaultFailureCode {
  unavailable,
  corruptData,
  unsupportedVersion,
  invalidHandle,
}

class CredentialVaultFailure implements Exception {
  const CredentialVaultFailure(this.code, [this.cause]);

  final CredentialVaultFailureCode code;
  final Object? cause;

  @override
  String toString() => 'CredentialVaultFailure($code)';
}

abstract interface class CredentialVault {
  Future<CredentialHandle> putPrivateKey(PrivateKeyCredential credential);

  Future<PrivateKeyCredential?> readPrivateKey(CredentialHandle handle);

  Future<void> delete(CredentialHandle handle);
}

class EphemeralCredentialVault implements CredentialVault {
  final Map<String, PrivateKeyCredential> _credentials = {};
  int _nextId = 0;

  @override
  Future<CredentialHandle> putPrivateKey(
    PrivateKeyCredential credential,
  ) async {
    final handle = CredentialHandle('ephemeral-${_nextId++}');
    _credentials[handle.value] = credential;
    return handle;
  }

  @override
  Future<PrivateKeyCredential?> readPrivateKey(CredentialHandle handle) async {
    return _credentials[handle.value];
  }

  @override
  Future<void> delete(CredentialHandle handle) async {
    _credentials.remove(handle.value);
  }
}
