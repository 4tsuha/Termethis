import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_terminal_ja/features/connections/domain/connection_profile.dart';
import 'package:ssh_terminal_ja/features/terminal/application/ssh_session_controller.dart';
import 'package:ssh_terminal_ja/features/terminal/domain/ssh_gateway.dart';
import 'package:ssh_terminal_ja/infrastructure/terminal/utf8_terminal_codec.dart';

void main() {
  test('接続後の日本語入力とCtrl入力をSSHへ送る', () async {
    final connection = _FakeConnection();
    final gateway = _FakeGateway(connection);
    final controller = SshSessionController(
      gateway,
      const Utf8TerminalCodec(),
      profile: const ConnectionProfile(
        id: 'test',
        name: 'テスト',
        host: 'localhost',
        port: 22,
        username: 'user',
      ),
    );

    await controller.connect(
      authentication: const SshPasswordAuthentication('secret'),
      onUnknownHostKey: (_) async => true,
      onInteractivePrompt: (_) async => const [],
    );

    expect(controller.status, SshSessionStatus.connected);
    controller.terminal.textInput('日本語');
    controller.toggleControl();
    controller.terminal.textInput('c');

    expect(utf8.decode(connection.writes.first), '日本語');
    expect(connection.writes.last, [3]);

    await controller.disconnect();
    expect(controller.status, SshSessionStatus.closed);
    controller.dispose();
  });

  test('リモート切断を再接続待ちとして通知する', () async {
    final connection = _FakeConnection();
    final controller = SshSessionController(
      _FakeGateway(connection),
      const Utf8TerminalCodec(),
      profile: const ConnectionProfile(
        id: 'remote-close',
        name: 'テスト',
        host: 'localhost',
        port: 22,
        username: 'user',
      ),
    );

    await controller.connect(
      authentication: const SshPasswordAuthentication('secret'),
      onUnknownHostKey: (_) async => true,
      onInteractivePrompt: (_) async => const [],
    );
    connection.finishRemote();
    await Future<void>.delayed(Duration.zero);

    expect(controller.status, SshSessionStatus.reconnectPrompt);
    controller.dispose();
  });

  test('秘密鍵認証情報をGatewayへ渡す', () async {
    final connection = _FakeConnection();
    final gateway = _FakeGateway(connection);
    final controller = SshSessionController(
      gateway,
      const Utf8TerminalCodec(),
      profile: const ConnectionProfile(
        id: 'private-key',
        name: '鍵認証',
        host: 'localhost',
        port: 22,
        username: 'user',
        authenticationType: AuthenticationType.privateKey,
      ),
    );

    await controller.connect(
      authentication: const SshPrivateKeyAuthentication(
        pem: 'private-key-pem',
        passphrase: 'passphrase',
      ),
      onUnknownHostKey: (_) async => true,
      onInteractivePrompt: (_) async => const [],
    );

    final authentication = gateway.lastRequest?.authentication;
    expect(authentication, isA<SshPrivateKeyAuthentication>());
    expect(
      (authentication as SshPrivateKeyAuthentication).passphrase,
      'passphrase',
    );
    controller.dispose();
  });
}

class _FakeGateway implements SshGateway {
  _FakeGateway(this.connection);

  final _FakeConnection connection;
  SshConnectRequest? lastRequest;

  @override
  Future<SshConnection> connect(SshConnectRequest request) async {
    lastRequest = request;
    request.onAuthenticationStarted();
    request.onOpeningPty();
    return connection;
  }
}

class _FakeConnection implements SshConnection {
  final _stdout = StreamController<Uint8List>();
  final _stderr = StreamController<Uint8List>();
  final _done = Completer<void>();
  final List<Uint8List> writes = [];

  @override
  Stream<Uint8List> get stdout => _stdout.stream;

  @override
  Stream<Uint8List> get stderr => _stderr.stream;

  @override
  Future<void> get done => _done.future;

  @override
  void write(Uint8List data) => writes.add(data);

  @override
  void resize(int width, int height, int pixelWidth, int pixelHeight) {}

  @override
  Future<void> close() async {
    await _stdout.close();
    await _stderr.close();
    if (!_done.isCompleted) {
      _done.complete();
    }
  }

  void finishRemote() {
    if (!_done.isCompleted) {
      _done.complete();
    }
  }
}
