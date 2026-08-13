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
  testWidgets('Material 3チャットで履歴を表示してメッセージを送信する', (tester) async {
    final connection = _FakeConnection();
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

    expect(find.text('既存の応答'), findsOneWidget);
    expect(find.text('何を作りますか？'), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('opencode-composer')),
      '修正してください',
    );
    await tester.tap(find.byTooltip('送信'));
    await tester.pumpAndSettle();

    expect(connection.lastPrompt, '修正してください');
    expect(find.text('完了しました'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('720dp以上でセッションペインを表示する', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectionProfileRepositoryProvider.overrideWithValue(
            EphemeralConnectionProfileRepository(
              initialProfiles: const [
                ConnectionProfile(
                  id: 'oc',
                  name: 'OpenCode',
                  host: 'host',
                  port: 4096,
                  username: 'opencode',
                  connectionType: ConnectionType.opencode,
                ),
              ],
            ),
          ),
          openCodeGatewayProvider.overrideWithValue(
            _FakeGateway(_FakeConnection()),
          ),
        ],
        child: const MaterialApp(
          home: OpenCodeChatScreen(profileId: 'oc', tabId: 'tab'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Serve 1.2.3'), findsOneWidget);
    expect(find.byTooltip('新しいセッション'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FakeGateway implements OpenCodeGateway {
  const _FakeGateway(this.connection);
  final OpenCodeConnection connection;
  @override
  OpenCodeConnection connect(OpenCodeConnectRequest request) => connection;
}

class _FakeConnection implements OpenCodeConnection {
  String? lastPrompt;
  var messages = const [
    OpenCodeChatMessage(
      id: 'm1',
      role: OpenCodeMessageRole.assistant,
      text: '既存の応答',
    ),
  ];

  @override
  Future<void> abort(String sessionId) async {}
  @override
  Future<void> replyPermission(
    String sessionId,
    String permissionId,
    OpenCodePermissionResponse response,
  ) async {}
  @override
  Future<void> close() async {}
  @override
  Future<OpenCodeRemoteSession> createSession({required String title}) async =>
      const OpenCodeRemoteSession(id: 's2', title: '新規');
  @override
  Future<OpenCodeServerInfo> health() async =>
      const OpenCodeServerInfo(version: '1.2.3');
  @override
  Future<List<OpenCodeRemoteSession>> listSessions() async => const [
    OpenCodeRemoteSession(id: 's1', title: '既存'),
  ];
  @override
  Future<List<OpenCodeChatMessage>> listMessages(String sessionId) async =>
      messages;
  @override
  Future<OpenCodeChatMessage> sendMessage(String sessionId, String text) async {
    lastPrompt = text;
    const response = OpenCodeChatMessage(
      id: 'm2',
      role: OpenCodeMessageRole.assistant,
      text: '完了しました',
    );
    messages = [
      ...messages,
      OpenCodeChatMessage(id: 'u1', role: OpenCodeMessageRole.user, text: text),
      response,
    ];
    return response;
  }

  @override
  Stream<OpenCodeSessionEvent> watchSession(String sessionId) =>
      const Stream.empty();
}
