import 'package:shared_preferences/shared_preferences.dart';

import '../../features/settings/domain/credential_settings.dart';
import '../../features/settings/domain/vault_protection.dart';

class SharedPreferencesCredentialSettingsStore
    implements CredentialSettingsStore {
  SharedPreferencesCredentialSettingsStore({
    SharedPreferencesAsync? preferences,
  }) : _preferences = preferences ?? SharedPreferencesAsync();

  static const _saveSshPasswordsKey = 'credentials.save_ssh_passwords.v1';
  static const _vaultProtectionModeKey = 'credentials.vault_protection.v1';
  final SharedPreferencesAsync _preferences;

  @override
  Future<CredentialSettings?> read() async {
    final modeName = await _preferences.getString(_vaultProtectionModeKey);
    return CredentialSettings(
      saveSshPasswords:
          await _preferences.getBool(_saveSshPasswordsKey) ?? false,
      vaultProtectionMode: VaultProtectionMode.values.firstWhere(
        (value) => value.name == modeName,
        orElse: () => VaultProtectionMode.none,
      ),
    );
  }

  @override
  Future<void> save(CredentialSettings settings) async {
    await Future.wait([
      _preferences.setBool(_saveSshPasswordsKey, settings.saveSshPasswords),
      _preferences.setString(
        _vaultProtectionModeKey,
        settings.vaultProtectionMode.name,
      ),
    ]);
  }
}
