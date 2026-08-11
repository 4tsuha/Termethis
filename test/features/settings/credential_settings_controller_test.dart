import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termethis/features/connections/application/connection_profiles_controller.dart';
import 'package:termethis/features/connections/domain/connection_profile.dart';
import 'package:termethis/features/connections/domain/connection_profile_repository.dart';
import 'package:termethis/features/connections/domain/credential_vault.dart';
import 'package:termethis/features/settings/application/credential_settings_controller.dart';
import 'package:termethis/features/settings/domain/credential_settings.dart';

void main() {
  test('パスワード保存を無効にすると保存済みSSHパスワードも削除する', () async {
    final repository = EphemeralConnectionProfileRepository();
    final vault = EphemeralCredentialVault();
    final store = _MemoryCredentialSettingsStore();
    final handle = await vault.putPassword(const PasswordCredential('secret'));
    await repository.save(
      ConnectionProfile(
        id: 'password-profile',
        name: 'Password SSH',
        host: 'example.com',
        port: 22,
        username: 'tester',
        credentialReference: handle.value,
      ),
    );
    final container = ProviderContainer(
      overrides: [
        connectionProfileRepositoryProvider.overrideWithValue(repository),
        credentialVaultProvider.overrideWithValue(vault),
        initialCredentialSettingsProvider.overrideWithValue(
          const CredentialSettings(saveSshPasswords: true),
        ),
        credentialSettingsStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(credentialSettingsProvider).saveSshPasswords, isTrue);
    await container
        .read(credentialSettingsProvider.notifier)
        .setSaveSshPasswords(false);

    expect(
      container.read(credentialSettingsProvider).saveSshPasswords,
      isFalse,
    );
    expect(store.saved?.saveSshPasswords, isFalse);
    expect(
      (await repository.findById('password-profile'))?.credentialReference,
      isNull,
    );
    expect(await vault.readPassword(handle), isNull);
  });
}

class _MemoryCredentialSettingsStore implements CredentialSettingsStore {
  CredentialSettings? saved;

  @override
  Future<CredentialSettings?> read() async => saved;

  @override
  Future<void> save(CredentialSettings settings) async {
    saved = settings;
  }
}
