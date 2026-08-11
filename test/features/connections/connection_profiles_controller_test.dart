import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termethis/features/connections/application/connection_profiles_controller.dart';
import 'package:termethis/features/connections/domain/connection_profile.dart';
import 'package:termethis/features/connections/domain/connection_profile_repository.dart';
import 'package:termethis/features/connections/domain/credential_vault.dart';

void main() {
  test('秘密鍵の置き換えと接続先削除で古いVaultデータを削除する', () async {
    final repository = EphemeralConnectionProfileRepository();
    final vault = EphemeralCredentialVault();
    final container = ProviderContainer(
      overrides: [
        connectionProfileRepositoryProvider.overrideWithValue(repository),
        credentialVaultProvider.overrideWithValue(vault),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      connectionProfilesProvider,
      (previous, next) {},
    );
    addTearDown(subscription.close);
    await container.read(connectionProfilesProvider.future);
    final controller = container.read(connectionProfilesProvider.notifier);

    const base = ConnectionProfile(
      id: 'key-profile',
      name: '鍵認証',
      host: 'ssh.example.com',
      port: 22,
      username: 'tester',
      authenticationType: AuthenticationType.privateKey,
    );
    final first = await controller.save(
      base,
      replacementPrivateKey: const PrivateKeyCredential(
        pem: 'first-key',
        label: 'id_first',
        isEncrypted: false,
      ),
    );
    final firstHandle = CredentialHandle(first.credentialReference!);
    expect((await vault.readPrivateKey(firstHandle))?.pem, 'first-key');

    final second = await controller.save(
      first,
      replacementPrivateKey: const PrivateKeyCredential(
        pem: 'second-key',
        label: 'id_second',
        isEncrypted: false,
      ),
    );
    final secondHandle = CredentialHandle(second.credentialReference!);
    expect(await vault.readPrivateKey(firstHandle), isNull);
    expect((await vault.readPrivateKey(secondHandle))?.pem, 'second-key');

    await controller.delete(base.id);
    expect(await vault.readPrivateKey(secondHandle), isNull);
    expect(await repository.findById(base.id), isNull);
  });
}
