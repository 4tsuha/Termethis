import 'vault_protection.dart';

class CredentialSettings {
  const CredentialSettings({
    this.saveSshPasswords = false,
    this.vaultProtectionMode = VaultProtectionMode.none,
  });

  final bool saveSshPasswords;
  final VaultProtectionMode vaultProtectionMode;

  CredentialSettings copyWith({
    bool? saveSshPasswords,
    VaultProtectionMode? vaultProtectionMode,
  }) => CredentialSettings(
    saveSshPasswords: saveSshPasswords ?? this.saveSshPasswords,
    vaultProtectionMode: vaultProtectionMode ?? this.vaultProtectionMode,
  );
}

abstract interface class CredentialSettingsStore {
  Future<CredentialSettings?> read();
  Future<void> save(CredentialSettings settings);
}

class EphemeralCredentialSettingsStore implements CredentialSettingsStore {
  const EphemeralCredentialSettingsStore();

  @override
  Future<CredentialSettings?> read() async => null;

  @override
  Future<void> save(CredentialSettings settings) async {}
}
