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

class PasswordCredential {
  const PasswordCredential(this.password);
  final String password;
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

  Future<CredentialHandle> putPassword(PasswordCredential credential);

  Future<PasswordCredential?> readPassword(CredentialHandle handle);

  Future<void> delete(CredentialHandle handle);
}

class EphemeralCredentialVault implements CredentialVault {
  final Map<String, Object> _credentials = {};
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
    final value = _credentials[handle.value];
    return value is PrivateKeyCredential ? value : null;
  }

  @override
  Future<CredentialHandle> putPassword(PasswordCredential credential) async {
    final handle = CredentialHandle('ephemeral-${_nextId++}');
    _credentials[handle.value] = credential;
    return handle;
  }

  @override
  Future<PasswordCredential?> readPassword(CredentialHandle handle) async {
    final value = _credentials[handle.value];
    return value is PasswordCredential ? value : null;
  }

  @override
  Future<void> delete(CredentialHandle handle) async {
    _credentials.remove(handle.value);
  }
}
