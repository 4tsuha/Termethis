import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termethis/features/connections/application/connection_profiles_controller.dart';
import 'package:termethis/features/connections/domain/connection_profile.dart';
import 'package:termethis/features/connections/domain/connection_profile_repository.dart';
import 'package:termethis/features/opencode/application/opencode_providers.dart';
import 'package:termethis/features/opencode/domain/opencode_gateway.dart';
import 'package:termethis/features/opencode/presentation/opencode_chat_screen.dart';

void main() {
  testWidgets('空白メッセージを隠し、依頼を非同期送信する', (tester) async {
    final connection = _FakeConnection();
    await _pumpScreen(tester, connection);

    expect(find.text('既存の応答'), findsOneWidget);
    expect(find.byKey(const ValueKey('blank-message')), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('opencode-composer')),
      '修正してください',
    );
    await tester.tap(find.byTooltip('送信'));
    await tester.pump();

    expect(connection.lastPrompt, '修正してください');
    expect(find.text('修正してください'), findsOneWidget);
    expect(find.text('エージェントが作業しています'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('リモートコマンドと変更ファイルの内訳を表示する', (tester) async {
    final connection = _FakeConnection();
    await _pumpScreen(tester, connection);

    await tester.tap(find.byTooltip('リモートコマンド').first);
    await tester.pumpAndSettle();
    expect(find.text('/review'), findsOneWidget);
    await tester.tap(find.text('/review'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('opencode-command-arguments')),
      'develop',
    );
    await tester.tap(find.text('実行'));
    await tester.pump();
    expect(connection.lastCommand, 'review');
    expect(connection.lastArguments, 'develop');

    connection.emit(
      const OpenCodeSessionEvent.statusChanged(OpenCodeSessionStatus.idle()),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('作業の進捗と変更ファイル'));
    await tester.pumpAndSettle();
    expect(find.text('作業の内訳'), findsOneWidget);
    expect(find.text('lib/main.dart'), findsOneWidget);
    expect(find.text('+12'), findsOneWidget);
    expect(find.text('-3'), findsOneWidget);
  });

  testWidgets('840dp以上はセッション、会話、作業内訳の3ペインになる', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpScreen(tester, _FakeConnection());

    expect(find.text('Serve 1.18.15'), findsOneWidget);
    expect(find.text('作業の内訳'), findsOneWidget);
    expect(find.text('変更されたファイル'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320dp幅でも操作がオーバーフローしない', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpScreen(tester, _FakeConnection());

    expect(find.byKey(const ValueKey('opencode-composer')), findsOneWidget);
    expect(find.byTooltip('リモートコマンド'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpScreen(
  WidgetTester tester,
  _FakeConnection connection,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        connectionProfileRepositoryProvider.overrideWithValue(
          EphemeralConnectionProfileRepository(
            initialProfiles: const [
              ConnectionProfile(
                id: 'oc',
                name: 'OpenCode',
                host: 'server.local',
                port: 4096,
                username: 'opencode',
                connectionType: ConnectionType.opencode,
              ),
            ],
          ),
        ),
        openCodeGatewayProvider.overrideWithValue(_FakeGateway(connection)),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: OpenCodeChatScreen(profileId: 'oc', tabId: 'tab'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeGateway implements OpenCodeGateway {
  const _FakeGateway(this.connection);

  final OpenCodeConnection connection;

  @override
  OpenCodeConnection connect(OpenCodeConnectRequest request) => connection;
}

class _FakeConnection implements OpenCodeConnection {
  final _events = StreamController<OpenCodeSessionEvent>.broadcast();
  String? lastPrompt;
  String? lastCommand;
  String? lastArguments;

  void emit(OpenCodeSessionEvent event) => _events.add(event);

  @override
  Future<void> abort(String sessionId) async {}

  @override
  Future<void> close() async {}

  @override
  Future<OpenCodeRemoteSession> createSession({required String title}) async =>
      const OpenCodeRemoteSession(id: 's2', title: '新規');

  @override
  Future<void> executeCommand(
    String sessionId,
    String command,
    String arguments, {
    String? agent,
  }) async {
    lastCommand = command;
    lastArguments = arguments;
  }

  @override
  Future<OpenCodeServerInfo> health() async =>
      const OpenCodeServerInfo(version: '1.18.15');

  @override
  Future<List<OpenCodeAgent>> listAgents() async => const [
    OpenCodeAgent(name: 'build', mode: 'primary', builtIn: true),
  ];

  @override
  Future<List<OpenCodeCommand>> listCommands() async => const [
    OpenCodeCommand(name: 'review', description: '変更を確認'),
  ];

  @override
  Future<List<OpenCodeFileChange>> listDiff(String sessionId) async => const [
    OpenCodeFileChange(path: 'lib/main.dart', additions: 12, deletions: 3),
  ];

  @override
  Future<List<OpenCodeChatMessage>> listMessages(
    String sessionId, {
    int limit = 200,
  }) async => const [
    OpenCodeChatMessage(
      id: 'blank-message',
      role: OpenCodeMessageRole.assistant,
      text: '  \n ',
    ),
    OpenCodeChatMessage(
      id: 'm1',
      role: OpenCodeMessageRole.assistant,
      text: '既存の応答',
    ),
  ];

  @override
  Future<List<OpenCodeRemoteSession>> listSessions() async => const [
    OpenCodeRemoteSession(id: 's1', title: '既存'),
  ];

  @override
  Future<List<OpenCodeTodoItem>> listTodos(String sessionId) async => const [
    OpenCodeTodoItem(
      id: 'todo-1',
      content: 'UIを修正',
      status: 'in_progress',
      priority: 'high',
    ),
  ];

  @override
  Future<void> replyPermission(
    String sessionId,
    String permissionId,
    OpenCodePermissionResponse response,
  ) async {}

  @override
  Future<void> sendMessage(
    String sessionId,
    String text, {
    String? agent,
  }) async {
    lastPrompt = text;
  }

  @override
  Future<OpenCodeSessionStatus> sessionStatus(String sessionId) async =>
      const OpenCodeSessionStatus.idle();

  @override
  Stream<OpenCodeSessionEvent> watchSession(String sessionId) => _events.stream;
}
