class CredentialSettings {
  const CredentialSettings({this.saveSshPasswords = false});

  final bool saveSshPasswords;

  CredentialSettings copyWith({bool? saveSshPasswords}) => CredentialSettings(
    saveSshPasswords: saveSshPasswords ?? this.saveSshPasswords,
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
