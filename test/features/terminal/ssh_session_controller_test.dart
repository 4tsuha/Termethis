import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:termethis/features/connections/domain/connection_profile.dart';
import 'package:termethis/features/terminal/application/ssh_session_controller.dart';
import 'package:termethis/features/terminal/domain/ssh_gateway.dart';
import 'package:termethis/infrastructure/terminal/utf8_terminal_codec.dart';
import 'package:xterm/xterm.dart';

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
    controller.toggleAlt();
    controller.terminal.textInput('x');
    controller.sendKey(TerminalKey.escape);
    controller.sendKey(TerminalKey.tab);

    expect(utf8.decode(connection.writes.first), '日本語');
    expect(connection.writes[1], [3]);
    expect(utf8.decode(connection.writes[2]), '\x1bx');
    expect(utf8.decode(connection.writes[3]), '\x1b');
    expect(utf8.decode(connection.writes[4]), '\t');

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

  test('SSH受信チャンクを16ms単位でまとめてターミナルへ反映する', () async {
    final connection = _FakeConnection();
    final controller = SshSessionController(
      _FakeGateway(connection),
      const Utf8TerminalCodec(),
      profile: const ConnectionProfile(
        id: 'batch',
        name: '大量出力',
        host: 'localhost',
        port: 22,
        username: 'user',
      ),
      maxLines: 2000,
    );
    var activityCount = 0;
    final renderedChunks = <String>[];
    controller.setViewportVisible(true);
    controller.addTerminalActivityListener(() => activityCount++);
    controller.addTerminalDataListener(renderedChunks.add);

    await controller.connect(
      authentication: const SshPasswordAuthentication('secret'),
      onUnknownHostKey: (_) async => true,
      onInteractivePrompt: (_) async => const [],
    );
    connection.emitStdout('first');
    connection.emitStdout('second');
    await Future<void>.delayed(Duration.zero);

    expect(controller.terminal.maxLines, 2000);
    expect(
      controller.terminal.buffer.getText(),
      isNot(contains('firstsecond')),
    );

    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(controller.terminal.buffer.getText(), contains('firstsecond'));
    expect(renderedChunks, ['firstsecond']);
    expect(activityCount, 1);
    controller.dispose();
  });

  test('WebGL使用時のFlutter互換バッファを200行に抑える', () {
    final controller = SshSessionController(
      _FakeGateway(_FakeConnection()),
      const Utf8TerminalCodec(),
      profile: const ConnectionProfile(
        id: 'compact',
        name: 'WebGL',
        host: 'localhost',
        port: 22,
        username: 'user',
      ),
      maxLines: 10000,
      compactFlutterBuffer: true,
    );

    expect(controller.terminal.maxLines, 200);
    controller.dispose();
  });

  test('WebGL使用時は障害時までFlutter互換端末の解析を遅延する', () async {
    final connection = _FakeConnection();
    final controller = SshSessionController(
      _FakeGateway(connection),
      const Utf8TerminalCodec(),
      profile: const ConnectionProfile(
        id: 'deferred-fallback',
        name: 'WebGL',
        host: 'localhost',
        port: 22,
        username: 'user',
      ),
      compactFlutterBuffer: true,
    );

    await controller.connect(
      authentication: const SshPasswordAuthentication('secret'),
      onUnknownHostKey: (_) async => true,
      onInteractivePrompt: (_) async => const [],
    );
    connection.emitStdout('WebGL only');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(controller.terminal.buffer.getText(), isNot(contains('WebGL only')));
    expect(controller.webTerminalReplay.data, contains('WebGL only'));

    controller.enableFlutterTerminalMirror();

    expect(controller.terminal.buffer.getText(), contains('WebGL only'));
    controller.dispose();
  });

  test('WebGL端末のスナップショットと非表示中の差分を再生する', () async {
    final connection = _FakeConnection();
    final controller = SshSessionController(
      _FakeGateway(connection),
      const Utf8TerminalCodec(),
      profile: const ConnectionProfile(
        id: 'web-replay',
        name: 'WebGL再生',
        host: 'localhost',
        port: 22,
        username: 'user',
      ),
      compactFlutterBuffer: true,
    );
    final events = <WebTerminalDataEvent>[];
    controller.addWebTerminalDataListener(events.add);

    await controller.connect(
      authentication: const SshPasswordAuthentication('secret'),
      onUnknownHostKey: (_) async => true,
      onInteractivePrompt: (_) async => const [],
    );
    connection.emitStdout('first');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(events, hasLength(1));
    expect(events.single.sequence, 1);
    expect(events.single.data, 'first');
    expect(controller.webTerminalReplay.data, 'first');
    expect(controller.saveWebTerminalSnapshot('snapshot', 1), isTrue);

    connection.emitStdout('second');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final fullReplay = controller.webTerminalReplay;
    expect(fullReplay.throughSequence, 2);
    expect(fullReplay.data, 'snapshotsecond');
    final delta = controller.webTerminalReplayAfter(1);
    expect(delta.resetRequired, isFalse);
    expect(delta.data, 'second');
    controller.dispose();
  });

  test('古いWebGL表示世代には端末全体の再構築を要求する', () async {
    final connection = _FakeConnection();
    final controller = SshSessionController(
      _FakeGateway(connection),
      const Utf8TerminalCodec(),
      profile: const ConnectionProfile(
        id: 'web-reset',
        name: 'WebGL復元',
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
    connection.emitStdout('before');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(controller.saveWebTerminalSnapshot('serialized', 1), isTrue);

    final replay = controller.webTerminalReplayAfter(0);
    expect(replay.resetRequired, isTrue);
    expect(replay.data, 'serialized');
    controller.dispose();
  });

  test('大量出力ではWebGL履歴の定期チェックポイントを要求する', () async {
    final connection = _FakeConnection();
    final controller = SshSessionController(
      _FakeGateway(connection),
      const Utf8TerminalCodec(),
      profile: const ConnectionProfile(
        id: 'web-checkpoint',
        name: 'WebGL長時間出力',
        host: 'localhost',
        port: 22,
        username: 'user',
      ),
      compactFlutterBuffer: true,
    );

    await controller.connect(
      authentication: const SshPasswordAuthentication('secret'),
      onUnknownHostKey: (_) async => true,
      onInteractivePrompt: (_) async => const [],
    );
    connection.emitStdout('x' * (140 * 1024));
    await Future<void>.delayed(Duration.zero);

    expect(controller.webTerminalCheckpointNeeded, isTrue);
    final replay = controller.webTerminalReplay;
    expect(
      controller.saveWebTerminalSnapshot('serialized', replay.throughSequence),
      isTrue,
    );
    expect(controller.webTerminalCheckpointNeeded, isFalse);
    controller.dispose();
  });

  test('WebGL履歴はチェックポイント前も長い出力を途中で切らない', () async {
    final connection = _FakeConnection();
    final controller = SshSessionController(
      _FakeGateway(connection),
      const Utf8TerminalCodec(),
      profile: const ConnectionProfile(
        id: 'web-long-replay',
        name: 'WebGL長文保持',
        host: 'localhost',
        port: 22,
        username: 'user',
      ),
      compactFlutterBuffer: true,
    );

    await controller.connect(
      authentication: const SshPasswordAuthentication('secret'),
      onUnknownHostKey: (_) async => true,
      onInteractivePrompt: (_) async => const [],
    );
    final output = List.generate(
      5000,
      (index) => 'line-${index.toString().padLeft(4, '0')}\r\n',
    ).join();
    connection.emitStdout(output * 6);
    await Future<void>.delayed(Duration.zero);

    final replay = controller.webTerminalReplay;
    expect(replay.resetRequired, isFalse);
    expect(replay.data.length, output.length * 6);
    expect(replay.data, startsWith('line-0000'));
    expect(replay.data, endsWith('line-4999\r\n'));
    controller.dispose();
  });

  test('描画と履歴のバックプレッシャーを重ねても受信を再開する', () async {
    final connection = _FakeConnection();
    final controller = SshSessionController(
      _FakeGateway(connection),
      const Utf8TerminalCodec(),
      profile: const ConnectionProfile(
        id: 'web-backpressure',
        name: 'WebGL流量制御',
        host: 'localhost',
        port: 22,
        username: 'user',
      ),
      compactFlutterBuffer: true,
    );

    await controller.connect(
      authentication: const SshPasswordAuthentication('secret'),
      onUnknownHostKey: (_) async => true,
      onInteractivePrompt: (_) async => const [],
    );
    connection.emitStdout('x' * (1024 * 1024));
    await Future<void>.delayed(Duration.zero);
    final checkpoint = controller.webTerminalReplay;

    controller.setOutputBackpressure(true);
    connection.emitStdout('held-output');
    expect(
      controller.saveWebTerminalSnapshot(
        'serialized',
        checkpoint.throughSequence,
      ),
      isTrue,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(controller.webTerminalReplay.data, isNot(contains('held-output')));

    controller.setOutputBackpressure(false);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(controller.webTerminalReplay.data, contains('held-output'));
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

  void emitStdout(String value) {
    _stdout.add(Uint8List.fromList(utf8.encode(value)));
  }
}
