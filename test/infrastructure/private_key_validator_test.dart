import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_terminal_ja/features/connections/domain/private_key_importer.dart';
import 'package:ssh_terminal_ja/infrastructure/ssh/android_private_key_importer.dart';

void main() {
  test('OpenSSH Ed25519秘密鍵を検証する', () async {
    final pem = OpenSSHEd25519KeyPair(
      Uint8List(32),
      Uint8List(64),
      'test-key',
    ).toPem();
    final key = ImportedPrivateKey(
      pem: pem,
      label: 'id_ed25519',
      isEncrypted: SSHKeyPair.isEncryptedPem(pem),
    );

    await DartSshPrivateKeyValidator().validate(key);
  });

  test('不正な秘密鍵を拒否する', () async {
    const key = ImportedPrivateKey(
      pem: 'not a private key',
      label: 'broken.pem',
      isEncrypted: false,
    );

    expect(
      () => DartSshPrivateKeyValidator().validate(key),
      throwsA(isA<PrivateKeyImportFailure>()),
    );
  });
}
