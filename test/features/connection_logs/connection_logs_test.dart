import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:termethis/features/connection_logs/domain/connection_log_entry.dart';
import 'package:termethis/features/connection_logs/domain/connection_log_repository.dart';
import 'package:termethis/features/connections/domain/connection_profile.dart';
import 'package:termethis/features/terminal/application/ssh_session_controller.dart';
import 'package:termethis/features/terminal/domain/ssh_failure.dart';
import 'package:termethis/features/terminal/domain/ssh_gateway.dart';
import 'package:termethis/infrastructure/terminal/utf8_terminal_codec.dart';

void main() {
  const profile = ConnectionProfile(
    id: 'profile-1',
    name: '開発サーバー',
    host: 'server.example.com',
    port: 2222,
    username: 'developer',
  );

  test('接続状態をタブと接続先に関連付けて記録する', () async {
    final logs = EphemeralConnectionLogRepository();
    final controller = SshSessionController(
      _SuccessfulGateway(),
      const Utf8TerminalCodec(),
      profile: profile,
      tabId: 'tab-1',
      connectionLogs: logs,
    );
    addTearDown(controller.dispose);

    await controller.connect(
      authentication: const SshPasswordAuthentication('secret'),
      onUnknownHostKey: (_) async => true,
      onInteractivePrompt: (_) async => const [],
    );
    await controller.disconnect();

    final entries = (await logs.list()).reversed.toList();
    expect(entries.map((entry) => entry.state), [
      ConnectionLogState.connecting,
      ConnectionLogState.authenticating,
      ConnectionLogState.openingPty,
      ConnectionLogState.connected,
      ConnectionLogState.closing,
      ConnectionLogState.closed,
    ]);
    expect(entries.every((entry) => entry.profileId == profile.id), isTrue);
    expect(entries.every((entry) => entry.profileName == profile.name), isTrue);
    expect(entries.every((entry) => entry.target == profile.target), isTrue);
    expect(entries.every((entry) => entry.tabId == 'tab-1'), isTrue);
  });

  test('失敗時は公開用コードだけを保存し原因の詳細を含めない', () async {
    final logs = EphemeralConnectionLogRepository();
    final controller = SshSessionController(
      _FailingGateway(),
      const Utf8TerminalCodec(),
      profile: profile,
      tabId: 'tab-sensitive',
      connectionLogs: logs,
    );
    addTearDown(controller.dispose);

    await controller.connect(
      authentication: const SshPasswordAuthentication('do-not-log'),
      onUnknownHostKey: (_) async => true,
      onInteractivePrompt: (_) async => const [],
    );

    final failure = (await logs.list()).first;
    expect(failure.state, ConnectionLogState.failed);
    expect(failure.failureCode, SshFailureCode.authenticationFailed);
    final serialized = failure.toJson().toString();
    expect(serialized, isNot(contains('do-not-log')));
    expect(serialized, isNot(contains('server response')));
    expect(serialized, isNot(contains('cause')));
  });

  test('古い記録を上限で破棄し一覧取得と全削除ができる', () async {
    final logs = EphemeralConnectionLogRepository(maximumEntries: 2);
    for (var index = 0; index < 3; index++) {
      await logs.append(
        ConnectionLogEntry(
          timestamp: DateTime.utc(2026, 8, 12, 10, index),
          profileId: 'profile-$index',
          profileName: 'server-$index',
          target: 'user@server-$index:22',
          tabId: 'tab-$index',
          state: ConnectionLogState.connected,
        ),
      );
    }

    expect((await logs.list()).map((entry) => entry.tabId), ['tab-2', 'tab-1']);
    await logs.clear();
    expect(await logs.list(), isEmpty);
  });
}

class _SuccessfulGateway implements SshGateway {
  @override
  Future<SshConnection> connect(SshConnectRequest request) async {
    request.onAuthenticationStarted();
    request.onOpeningPty();
    return _Connection();
  }
}

class _FailingGateway implements SshGateway {
  @override
  Future<SshConnection> connect(SshConnectRequest request) {
    throw const SshFailure(
      SshFailureCode.authenticationFailed,
      'server response with sensitive detail',
    );
  }
}

class _Connection implements SshConnection {
  @override
  Future<void> close() async {
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<void> get done => _done.future;

  final _done = Completer<void>();

  @override
  void resize(int width, int height, int pixelWidth, int pixelHeight) {}

  @override
  Stream<Uint8List> get stderr => const Stream.empty();

  @override
  Stream<Uint8List> get stdout => const Stream.empty();

  @override
  void write(Uint8List data) {}
}
