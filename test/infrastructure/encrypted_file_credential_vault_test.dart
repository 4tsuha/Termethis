import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_terminal_ja/features/connections/domain/credential_vault.dart';
import 'package:ssh_terminal_ja/infrastructure/secure_storage/encrypted_file_credential_vault.dart';
import 'package:ssh_terminal_ja/infrastructure/secure_storage/secure_value_store.dart';

void main() {
  late Directory directory;
  late _MemorySecureValueStore secureStore;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vbterminal-vault-test-');
    secureStore = _MemorySecureValueStore();
  });

  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('秘密鍵とパスフレーズを暗号化し、再生成後も復号する', () async {
    const credential = PrivateKeyCredential(
      pem:
          '-----BEGIN OPENSSH PRIVATE KEY-----\nsecret\n-----END OPENSSH PRIVATE KEY-----',
      label: 'id_ed25519',
      isEncrypted: true,
      passphrase: '鍵のパスフレーズ',
    );
    var vault = EncryptedFileCredentialVault(
      secureStore,
      () async => directory,
    );

    final handle = await vault.putPrivateKey(credential);
    final vaultFile = File('${directory.path}/${handle.value}.vault');
    final encrypted = await vaultFile.readAsString();

    expect(encrypted, isNot(contains('OPENSSH PRIVATE KEY')));
    expect(encrypted, isNot(contains('鍵のパスフレーズ')));

    vault = EncryptedFileCredentialVault(secureStore, () async => directory);
    final restored = await vault.readPrivateKey(handle);

    expect(restored?.pem, credential.pem);
    expect(restored?.label, credential.label);
    expect(restored?.isEncrypted, isTrue);
    expect(restored?.passphrase, credential.passphrase);

    await vault.delete(handle);
    expect(await vault.readPrivateKey(handle), isNull);
  });

  test('暗号化blobの改変を検出する', () async {
    final vault = EncryptedFileCredentialVault(
      secureStore,
      () async => directory,
    );
    final handle = await vault.putPrivateKey(
      const PrivateKeyCredential(
        pem: 'test-key',
        label: 'id_test',
        isEncrypted: false,
      ),
    );
    final file = File('${directory.path}/${handle.value}.vault');
    final envelope = await file.readAsString();
    await file.writeAsString(
      '${envelope.substring(0, envelope.length - 5)}AAAAA',
    );

    expect(
      () => vault.readPrivateKey(handle),
      throwsA(
        isA<CredentialVaultFailure>().having(
          (error) => error.code,
          'code',
          CredentialVaultFailureCode.corruptData,
        ),
      ),
    );
  });

  test('パストラバーサルを含む参照を拒否する', () async {
    final vault = EncryptedFileCredentialVault(
      secureStore,
      () async => directory,
    );

    expect(
      () => vault.readPrivateKey(const CredentialHandle('../secret')),
      throwsA(
        isA<CredentialVaultFailure>().having(
          (error) => error.code,
          'code',
          CredentialVaultFailureCode.invalidHandle,
        ),
      ),
    );
  });
}

class _MemorySecureValueStore implements SecureValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}
