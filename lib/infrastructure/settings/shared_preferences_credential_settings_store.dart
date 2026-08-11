import 'package:shared_preferences/shared_preferences.dart';

import '../../features/settings/domain/credential_settings.dart';

class SharedPreferencesCredentialSettingsStore
    implements CredentialSettingsStore {
  SharedPreferencesCredentialSettingsStore({
    SharedPreferencesAsync? preferences,
  }) : _preferences = preferences ?? SharedPreferencesAsync();

  static const _saveSshPasswordsKey = 'credentials.save_ssh_passwords.v1';
  final SharedPreferencesAsync _preferences;

  @override
  Future<CredentialSettings?> read() async => CredentialSettings(
    saveSshPasswords: await _preferences.getBool(_saveSshPasswordsKey) ?? false,
  );

  @override
  Future<void> save(CredentialSettings settings) =>
      _preferences.setBool(_saveSshPasswordsKey, settings.saveSshPasswords);
}
