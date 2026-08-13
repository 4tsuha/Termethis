import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mosh_dart/mosh_pb.dart';
import 'package:mosh_dart/mosh_transport.dart';
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

    test('範囲外UDPポートと128-bitでない鍵を拒否する', () {
      expect(
        () => MoshBootstrap.parse(
          'MOSH CONNECT 70000 AAECAwQFBgcICQoLDA0ODw==',
          fallbackHost: 'example.com',
        ),
        throwsFormatException,
      );
      expect(
        () => MoshBootstrap.parse(
          'MOSH CONNECT 60001 AQID',
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
  test('unacknowledged state is not retransmitted before RTO', () {
    final transport = MoshTransport.client(AesOcb(Uint8List(16)));
    transport.sendNew(Uint8List.fromList([1, 2, 3]));

    expect(transport.tick(), isNotEmpty);
    expect(transport.tick(), isEmpty);
    expect(transport.nextTickDelay, isNot(Duration.zero));
  });

  for (var run = 1; run <= 3; run++) {
    test('UDP無応答を期限切れとして終了する（反復$run）', () async {
      final server = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      await expectLater(
        MoshConnection.connect(
          MoshBootstrap(
            host: InternetAddress.loopbackIPv4.address,
            port: server.port,
            key: 'AAECAwQFBgcICQoLDA0ODw==',
          ),
          handshakeTimeout: const Duration(milliseconds: 80),
        ),
        throwsA(isA<SocketException>()),
      );
      server.close();
    });

    test('不正UDPパケットでは接続成立扱いにしない（反復$run）', () async {
      final server = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final clientPort = Completer<int>();
      final serverSubscription = server.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = server.receive();
        if (datagram == null) return;
        if (!clientPort.isCompleted) clientPort.complete(datagram.port);
      });
      final connecting = MoshConnection.connect(
        MoshBootstrap(
          host: InternetAddress.loopbackIPv4.address,
          port: server.port,
          key: 'AAECAwQFBgcICQoLDA0ODw==',
        ),
        handshakeTimeout: const Duration(milliseconds: 100),
      );
      final port = await clientPort.future.timeout(const Duration(seconds: 1));
      for (var index = 0; index < 5; index++) {
        server.send(Uint8List(32), InternetAddress.loopbackIPv4, port);
      }

      await expectLater(connecting, throwsA(isA<SocketException>()));
      await serverSubscription.cancel();
      server.close();
    });

    test('明示切断でタイマーとソケットを停止する（反復$run）', () async {
      final peer = await _MoshTestPeer.start(output: 'ready-$run');
      final connection =
          await MoshConnection.connect(
            MoshBootstrap(
              host: InternetAddress.loopbackIPv4.address,
              port: peer.port,
              key: 'AAECAwQFBgcICQoLDA0ODw==',
            ),
            handshakeTimeout: const Duration(seconds: 1),
          ).timeout(
            const Duration(seconds: 2),
            onTimeout: () {
              throw TimeoutException(
                'Mosh test connection did not become ready',
              );
            },
          );

      expect(
        await connection.stdout.first.timeout(const Duration(seconds: 1)),
        Uint8List.fromList('ready-$run'.codeUnits),
      );

      await connection.close().timeout(
        const Duration(seconds: 1),
        onTimeout: () => throw TimeoutException('Mosh client did not close'),
      );
      await connection.done.timeout(const Duration(milliseconds: 200));
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await peer.close().timeout(
        const Duration(seconds: 1),
        onTimeout: () => throw TimeoutException('Mosh test peer did not close'),
      );
    });
  }

  test(
    'QEMU mosh-serverと実UDP接続してシェル出力を往復する',
    () async {
      final host = Platform.environment['TERMETHIS_MOSH_TEST_HOST']!;
      final port = int.parse(Platform.environment['TERMETHIS_MOSH_TEST_PORT']!);
      final key = Platform.environment['TERMETHIS_MOSH_TEST_KEY']!;
      final connection = await MoshConnection.connect(
        MoshBootstrap(host: host, port: port, key: key),
        handshakeTimeout: const Duration(seconds: 10),
      );
      final output = BytesBuilder(copy: false);
      final marker = 'termethis-mosh-ok';
      final received = Completer<void>();
      final subscription = connection.stdout.listen((chunk) {
        output.add(chunk);
        if (utf8
                .decode(output.toBytes(), allowMalformed: true)
                .contains(marker) &&
            !received.isCompleted) {
          received.complete();
        }
      });
      connection.resize(80, 24, 0, 0);
      connection.write(Uint8List.fromList(utf8.encode('echo $marker\n')));

      await received.future.timeout(const Duration(seconds: 15));

      await subscription.cancel();
      await connection.close();
    },
    skip:
        Platform.environment['TERMETHIS_MOSH_TEST_HOST'] == null ||
            Platform.environment['TERMETHIS_MOSH_TEST_PORT'] == null ||
            Platform.environment['TERMETHIS_MOSH_TEST_KEY'] == null
        ? 'QEMU Mosh統合試験の環境変数が未設定です。'
        : false,
  );
}

class _MoshTestPeer {
  _MoshTestPeer._(this._socket, this._subscription);

  final RawDatagramSocket _socket;
  final StreamSubscription<RawSocketEvent> _subscription;

  int get port => _socket.port;

  static Future<_MoshTestPeer> start({required String output}) async {
    final socket = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final transport = MoshTransport.server(
      AesOcb(_hex('000102030405060708090a0b0c0d0e0f')),
    );
    var sentOutput = false;
    late final StreamSubscription<RawSocketEvent> subscription;
    subscription = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      Datagram? datagram;
      while ((datagram = socket.receive()) != null) {
        transport.recv(datagram!.data);
        if (!sentOutput) {
          transport.sendNew(
            marshalHostMessage([
              HostInstruction(hoststring: Uint8List.fromList(output.codeUnits)),
            ]),
          );
          sentOutput = true;
        }
        for (final response in transport.tick()) {
          socket.send(response, datagram.address, datagram.port);
        }
      }
    });
    return _MoshTestPeer._(socket, subscription);
  }

  Future<void> close() async {
    await _subscription.cancel();
    _socket.close();
  }
}

Uint8List _hex(String value) => Uint8List.fromList([
  for (var index = 0; index < value.length; index += 2)
    int.parse(value.substring(index, index + 2), radix: 16),
]);

String _toHex(Uint8List value) =>
    value.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
