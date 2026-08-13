import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:termethis/features/connections/domain/connection_profile.dart';
import 'package:termethis/features/remote_desktop/application/rdp_session_registry.dart';
import 'package:termethis/src/rust/api/rdp.dart' as rust;

void main() {
  const profile = ConnectionProfile(
    id: 'rdp-1',
    name: 'Windows',
    host: '192.0.2.1',
    port: 3389,
    username: 'user',
    connectionType: ConnectionType.rdp,
  );

  for (var run = 1; run <= 3; run++) {
    test('非同期失敗後にセッションを解放して再接続できる（反復$run）', () async {
      final backend = _FakeRdpBackend();
      final controller = RdpSessionController(profile, backend: backend);

      await controller.connect(
        password: 'secret',
        domain: '',
        width: 800,
        height: 600,
      );
      expect(controller.sessionId, 1);
      expect(await controller.sendText('too early'), isFalse);
      expect(backend.sentTexts, isEmpty);
      backend.statuses.add(_status('failed', error: '認証失敗'));
      await _waitUntil(() => controller.sessionId == null);

      expect(controller.state, 'failed');
      expect(controller.error, '認証失敗');
      expect(backend.closed, [1]);

      await controller.connect(
        password: 'secret',
        domain: '',
        width: 800,
        height: 600,
      );
      expect(controller.sessionId, 2);
      backend.statuses.add(_status('ready'));
      await _waitUntil(() => controller.state == 'ready');
      expect(await controller.sendText('dir'), isTrue);
      expect(backend.sentTexts, ['dir']);
      expect(backend.connectCount, 2);
      await controller.close();
      expect(backend.closed, [1, 2]);
    });

    test('接続処理中に閉じると生成されたネイティブセッションを閉じる（反復$run）', () async {
      final backend = _FakeRdpBackend(delayConnect: true);
      final controller = RdpSessionController(profile, backend: backend);

      final connecting = controller.connect(
        password: '',
        domain: '',
        width: 800,
        height: 600,
      );
      await _waitUntil(() => controller.state == 'connecting');
      await controller.close();
      backend.completeConnect();
      await connecting;

      expect(controller.state, 'closed');
      expect(controller.sessionId, isNull);
      expect(backend.closed, [1]);
    });

    test('同じタブIDで接続先が変わると旧Controllerを閉じる（反復$run）', () async {
      final backend = _FakeRdpBackend();
      final registry = RdpSessionRegistry(backend: backend);
      final first = registry.open('tab-1', profile);
      await first.connect(password: '', domain: '', width: 800, height: 600);
      final replacement = registry.open(
        'tab-1',
        const ConnectionProfile(
          id: 'rdp-2',
          name: 'Other Windows',
          host: '192.0.2.2',
          port: 3389,
          username: 'other',
          connectionType: ConnectionType.rdp,
        ),
      );
      await _waitUntil(() => backend.closed.contains(1));

      expect(replacement, isNot(same(first)));
      expect(registry.find('tab-1'), same(replacement));
      expect(first.state, 'closed');
      registry.dispose();
    });

    test('接続応答がない場合は期限切れで解放する（反復$run）', () async {
      final backend = _FakeRdpBackend();
      final controller = RdpSessionController(
        profile,
        backend: backend,
        connectionTimeout: const Duration(milliseconds: 20),
      );

      await controller.connect(
        password: '',
        domain: '',
        width: 800,
        height: 600,
      );
      await _waitUntil(() => controller.sessionId == null);

      expect(controller.state, 'failed');
      expect(controller.error, contains('応答がありません'));
      expect(backend.closed, [1]);
    });
  }
}

rust.RustRdpStatus _status(String state, {String? error}) => rust.RustRdpStatus(
  sequence: 0,
  width: 800,
  height: 600,
  state: state,
  errorMessage: error,
  renderer: 'test renderer',
);

Future<void> _waitUntil(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('状態遷移が期限内に完了しませんでした。');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class _FakeRdpBackend implements RdpBackend {
  _FakeRdpBackend({this.delayConnect = false});

  final bool delayConnect;
  final statuses = StreamController<rust.RustRdpStatus>.broadcast();
  final closed = <int>[];
  final sentTexts = <String>[];
  Completer<void>? _connectGate;
  int connectCount = 0;

  @override
  Future<rust.RustRdpConnectResult> connect(
    rust.RustRdpConnectRequest request,
  ) async {
    connectCount++;
    if (delayConnect) {
      _connectGate ??= Completer<void>();
      await _connectGate!.future;
    }
    return rust.RustRdpConnectResult(
      sessionId: connectCount,
      renderer: 'test renderer',
    );
  }

  void completeConnect() => _connectGate?.complete();

  @override
  Future<rust.RustRdpStatus> readStatus(int sessionId) => statuses.stream.first;

  @override
  Future<void> close(int sessionId) async => closed.add(sessionId);

  @override
  Future<void> sendScancode(int sessionId, int scancode, bool pressed) async {}

  @override
  Future<void> sendText(int sessionId, String text) async =>
      sentTexts.add(text);
}
