import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mosh_dart/ocb.dart';
import 'package:termethis/features/terminal/infrastructure/mosh_connection.dart';

void main() {
  group('MoshBootstrap', () {
    test('mosh-serverの接続情報を標準出力から抽出する', () {
      final bootstrap = MoshBootstrap.parse(
        'MOSH CONNECT 60001 AAECAwQFBgcICQoLDA0ODw==\n',
        fallbackHost: 'example.com',
      );

      expect(bootstrap.host, 'example.com');
      expect(bootstrap.port, 60001);
      expect(bootstrap.key, 'AAECAwQFBgcICQoLDA0ODw==');
    });

    test('接続情報がない出力を拒否する', () {
      expect(
        () => MoshBootstrap.parse(
          'mosh-server: command not found',
          fallbackHost: 'example.com',
        ),
        throwsFormatException,
      );
    });
  });

  test('MoshのAES-OCBはRFC 7253互換の暗号文を生成する', () {
    final key = _hex('000102030405060708090a0b0c0d0e0f');
    final nonce = _hex('bbaa99887766554433221102');
    final plaintext = _hex('0001020304050607');
    final expected = '6dd42c17cbf9c7835dfd6e630e8f98eb3d2a49b0dc0f314e';

    final encrypted = AesOcb(key).encrypt(nonce, plaintext);

    expect(_toHex(encrypted), expected);
    expect(AesOcb(key).decrypt(nonce, encrypted), plaintext);
  });
}

Uint8List _hex(String value) => Uint8List.fromList([
  for (var index = 0; index < value.length; index += 2)
    int.parse(value.substring(index, index + 2), radix: 16),
]);

String _toHex(Uint8List value) =>
    value.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
