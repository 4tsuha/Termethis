import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:termethis/features/opencode/domain/opencode_gateway.dart';
import 'package:termethis/infrastructure/opencode/http_opencode_gateway.dart';

void main() {
  test('health、セッション作成、履歴、送信を公式API形式で処理する', () async {
    final requests = <http.Request>[];
    final gateway = HttpOpenCodeGateway(
      clientFactory: () => MockClient((request) async {
        requests.add(request);
        switch ('${request.method} ${request.url.path}') {
          case 'GET /global/health':
            return http.Response('{"healthy":true,"version":"1.2.3"}', 200);
          case 'GET /session':
            return http.Response.bytes(
              utf8.encode('[{"id":"ses_1","title":"既存"}]'),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          case 'POST /session':
            return http.Response('{"id":"ses_2","title":"Termethis"}', 200);
          case 'GET /session/ses_2/message':
            return http.Response.bytes(
              utf8.encode(
                '[{"info":{"id":"msg_1","role":"assistant"},"parts":[{"type":"text","text":"完了"}]}]',
              ),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          case 'POST /session/ses_2/message':
            return http.Response.bytes(
              utf8.encode(
                '{"info":{"id":"msg_2","role":"assistant"},"parts":[{"type":"text","text":"応答"}]}',
              ),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          case 'POST /permission/per_1/reply':
            return http.Response('true', 200);
        }
        return http.Response('not found', 404);
      }),
    );
    final connection = gateway.connect(
      const OpenCodeConnectRequest(
        host: 'server.local',
        port: 4096,
        username: 'opencode',
        password: 'secret',
        directory: '/srv/project',
      ),
    );

    expect((await connection.health()).version, '1.2.3');
    expect((await connection.listSessions()).single.id, 'ses_1');
    expect((await connection.createSession(title: 'Termethis')).id, 'ses_2');
    expect((await connection.listMessages('ses_2')).single.text, '完了');
    expect((await connection.sendMessage('ses_2', '直して')).text, '応答');
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
    final prompt = jsonDecode(requests[4].body) as Map<String, dynamic>;
    expect((prompt['parts'] as List).single, {'type': 'text', 'text': '直して'});
    expect(jsonDecode(requests.last.body), {'reply': 'once'});
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

  test('SSEの権限要求をセッションイベントへ変換する', () async {
    final connection = HttpOpenCodeConnection(
      const OpenCodeConnectRequest(
        host: 'server.local',
        port: 4096,
        username: 'opencode',
      ),
      _SseClient(),
    );

    final event = await connection.watchSession('ses_1').first;

    expect(event.type, OpenCodeSessionEventType.permissionRequested);
    expect(event.permission?.id, 'per_1');
    expect(event.permission?.permission, 'bash');
    expect(event.permission?.patterns, ['git status']);
  });
}

class _SseClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(
    http.BaseRequest request,
  ) async => http.StreamedResponse(
    Stream.value(
      utf8.encode(
        'data: {"type":"permission.asked","properties":{"id":"per_1","sessionID":"ses_1","permission":"bash","patterns":["git status"]}}\r\n\r\n',
      ),
    ),
    200,
  );
}
