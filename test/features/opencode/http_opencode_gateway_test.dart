import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:termethis/features/opencode/domain/opencode_gateway.dart';
import 'package:termethis/infrastructure/opencode/http_opencode_gateway.dart';

void main() {
  test('公式APIでセッション、コマンド、エージェント、作業状態を取得する', () async {
    final requests = <http.Request>[];
    final connection =
        HttpOpenCodeGateway(
          clientFactory: () => MockClient((request) async {
            requests.add(request);
            switch ('${request.method} ${request.url.path}') {
              case 'GET /global/health':
                return _json({'healthy': true, 'version': '1.18.15'});
              case 'GET /session':
                return _json([
                  {'id': 'ses_1', 'title': '既存'},
                ]);
              case 'POST /session':
                return _json({'id': 'ses_2', 'title': 'Termethis'});
              case 'GET /session/ses_2/message':
                return _json([
                  {
                    'info': {
                      'id': 'blank',
                      'role': 'assistant',
                      'time': {'created': 1},
                    },
                    'parts': [
                      {'id': 'blank-part', 'type': 'text', 'text': '  \n '},
                    ],
                  },
                  {
                    'info': {
                      'id': 'msg_1',
                      'role': 'assistant',
                      'time': {'created': 2},
                    },
                    'parts': [
                      {'id': 'text-1', 'type': 'text', 'text': '完了しました'},
                      {
                        'id': 'tool-1',
                        'type': 'tool',
                        'tool': 'edit',
                        'state': {'status': 'running', 'title': 'ファイルを編集'},
                      },
                    ],
                  },
                ]);
              case 'GET /session/status':
                return _json({
                  'ses_2': {'type': 'busy'},
                });
              case 'GET /session/ses_2/todo':
                return _json([
                  {
                    'id': 'todo-1',
                    'content': '不具合を修正',
                    'status': 'in_progress',
                    'priority': 'high',
                  },
                ]);
              case 'GET /session/ses_2/diff':
                return _json([
                  {
                    'file': 'lib/main.dart',
                    'before': '',
                    'after': '',
                    'additions': 12,
                    'deletions': 3,
                  },
                ]);
              case 'GET /command':
                return _json([
                  {
                    'name': 'review',
                    'description': '変更を確認',
                    'template': 'Review',
                    'subtask': true,
                  },
                ]);
              case 'GET /agent':
                return _json([
                  {'name': 'build', 'mode': 'primary', 'builtIn': true},
                ]);
              case 'POST /session/ses_2/prompt_async':
                return http.Response('', 204);
              case 'POST /session/ses_2/command':
              case 'POST /session/ses_2/permissions/per_1':
                return _json(true);
            }
            return http.Response('not found', 404);
          }),
        ).connect(
          const OpenCodeConnectRequest(
            host: 'server.local',
            port: 4096,
            username: 'opencode',
            password: 'secret',
            directory: '/srv/project',
          ),
        );

    expect((await connection.health()).version, '1.18.15');
    expect((await connection.listSessions()).single.title, '既存');
    expect((await connection.createSession(title: 'Termethis')).id, 'ses_2');
    final messages = await connection.listMessages('ses_2');
    expect(messages, hasLength(1));
    expect(messages.single.displayText, '完了しました');
    expect(messages.single.activities.single.label, 'ファイルを編集');
    expect(
      messages.single.activities.single.status,
      OpenCodeActivityStatus.running,
    );
    expect(
      (await connection.sessionStatus('ses_2')).state,
      OpenCodeRunState.busy,
    );
    expect((await connection.listTodos('ses_2')).single.content, '不具合を修正');
    expect((await connection.listDiff('ses_2')).single.additions, 12);
    expect((await connection.listCommands()).single.name, 'review');
    expect((await connection.listAgents()).single.name, 'build');

    await connection.sendMessage('ses_2', '直してください', agent: 'build');
    await connection.executeCommand('ses_2', 'review', 'develop');
    await connection.replyPermission(
      'ses_2',
      'per_1',
      OpenCodePermissionResponse.once,
    );

    expect(
      requests.every(
        (request) => request.url.queryParameters['directory'] == '/srv/project',
      ),
      isTrue,
    );
    expect(
      requests.first.headers['authorization'],
      'Basic ${base64Encode(utf8.encode('opencode:secret'))}',
    );
    final asyncPrompt = jsonDecode(
      requests
          .firstWhere((item) => item.url.path.endsWith('prompt_async'))
          .body,
    );
    expect(asyncPrompt['agent'], 'build');
    expect(asyncPrompt['parts'].single, {'type': 'text', 'text': '直してください'});
    final command = jsonDecode(
      requests
          .firstWhere(
            (item) =>
                item.method == 'POST' && item.url.path.endsWith('/command'),
          )
          .body,
    );
    expect(command, {'command': 'review', 'arguments': 'develop'});
    expect(jsonDecode(requests.last.body), {'response': 'once'});
  });

  test('401を認証エラーへ分類する', () async {
    final connection =
        HttpOpenCodeGateway(
          clientFactory: () => MockClient((_) async => http.Response('', 401)),
        ).connect(
          const OpenCodeConnectRequest(
            host: 'server.local',
            port: 4096,
            username: 'opencode',
          ),
        );

    await expectLater(
      connection.health(),
      throwsA(
        isA<OpenCodeGatewayFailure>().having(
          (error) => error.code,
          'code',
          'unauthorized',
        ),
      ),
    );
  });

  test('SSEを再取得せずメッセージ差分、進捗、変更ファイルへ変換する', () async {
    final connection = HttpOpenCodeConnection(
      const OpenCodeConnectRequest(
        host: 'server.local',
        port: 4096,
        username: 'opencode',
      ),
      _SseClient(),
    );

    final events = await connection.watchSession('ses_1').toList();

    expect(events, hasLength(5));
    expect(events[0].type, OpenCodeSessionEventType.textPartUpdated);
    expect(events[0].textPart?.text, '処理中');
    expect(events[1].type, OpenCodeSessionEventType.statusChanged);
    expect(events[1].status?.state, OpenCodeRunState.busy);
    expect(events[2].todos?.single.status, 'in_progress');
    expect(events[3].diff?.single.path, 'lib/main.dart');
    expect(events[4].permission?.id, 'per_1');
    expect(events[4].permission?.permission, 'シェルを実行');
    expect(events[4].permission?.patterns, ['git status']);
  });
}

http.Response _json(Object value) => http.Response.bytes(
  utf8.encode(jsonEncode(value)),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

class _SseClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(
    http.BaseRequest request,
  ) async => http.StreamedResponse(
    Stream.value(
      utf8.encode(
        [
          [
            'data: {"type":"message.part.updated","properties":{"part":{"id":"part-1","messageID":"msg-1","sessionID":"ses_1","type":"text","text":"処理中"}}}',
            'data: {"type":"session.status","properties":{"sessionID":"ses_1","status":{"type":"busy"}}}',
            'data: {"type":"todo.updated","properties":{"sessionID":"ses_1","todos":[{"id":"todo-1","content":"修正","status":"in_progress","priority":"high"}]}}',
            'data: {"type":"session.diff","properties":{"sessionID":"ses_1","diff":[{"file":"lib/main.dart","before":"","after":"","additions":1,"deletions":0}]}}',
            'data: {"type":"permission.updated","properties":{"id":"per_1","sessionID":"ses_1","title":"シェルを実行","pattern":["git status"]}}',
          ].join('\r\n\r\n'),
          '\r\n\r\n',
        ].join(),
      ),
    ),
    200,
  );
}
