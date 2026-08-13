import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../features/opencode/domain/opencode_gateway.dart';

class HttpOpenCodeGateway implements OpenCodeGateway {
  const HttpOpenCodeGateway({this.clientFactory = http.Client.new});

  final http.Client Function() clientFactory;

  @override
  OpenCodeConnection connect(OpenCodeConnectRequest request) =>
      HttpOpenCodeConnection(request, clientFactory());
}

class HttpOpenCodeConnection implements OpenCodeConnection {
  HttpOpenCodeConnection(this.request, this._client);

  final OpenCodeConnectRequest request;
  final http.Client _client;
  bool _closed = false;

  Uri _uri(String path, [Map<String, String>? query]) => Uri(
    scheme: 'http',
    host: request.host,
    port: request.port,
    path: path,
    queryParameters: {
      if (request.directory?.trim() case final directory?
          when directory.isNotEmpty)
        'directory': directory,
      ...?query,
    },
  );

  Map<String, String> get _headers => {
    HttpHeaders.acceptHeader: 'application/json',
    if (request.password case final password? when password.isNotEmpty)
      HttpHeaders.authorizationHeader:
          'Basic ${base64Encode(utf8.encode('${request.username}:$password'))}',
  };

  @override
  Future<OpenCodeServerInfo> health() async {
    final response = await _get('/global/health');
    final body = _object(response.body);
    if (body['healthy'] != true) {
      throw const OpenCodeGatewayFailure(
        'unhealthy',
        'OpenCode Serve is unhealthy',
      );
    }
    return OpenCodeServerInfo(version: '${body['version'] ?? ''}');
  }

  @override
  Future<List<OpenCodeRemoteSession>> listSessions() async {
    final response = await _get('/session');
    final list = jsonDecode(response.body);
    if (list is! List) throw const FormatException('Invalid OpenCode sessions');
    return list.whereType<Map>().map(_session).toList(growable: false);
  }

  @override
  Future<OpenCodeRemoteSession> createSession({required String title}) async {
    final response = await _post('/session', {'title': title});
    return _session(_object(response.body));
  }

  @override
  Future<List<OpenCodeChatMessage>> listMessages(String sessionId) async {
    final response = await _get('/session/$sessionId/message');
    final list = jsonDecode(response.body);
    if (list is! List) throw const FormatException('Invalid OpenCode messages');
    return list.whereType<Map>().map(_message).toList(growable: false);
  }

  @override
  Future<OpenCodeChatMessage> sendMessage(String sessionId, String text) async {
    final response = await _post('/session/$sessionId/message', {
      'parts': [
        {'type': 'text', 'text': text},
      ],
    }, timeout: const Duration(minutes: 10));
    return _message(_object(response.body));
  }

  @override
  Future<void> abort(String sessionId) async {
    await _post('/session/$sessionId/abort', const {});
  }

  @override
  Future<void> replyPermission(
    String sessionId,
    String permissionId,
    OpenCodePermissionResponse response,
  ) async {
    await _post('/permission/$permissionId/reply', {'reply': response.name});
  }

  @override
  Stream<OpenCodeSessionEvent> watchSession(String sessionId) async* {
    final streamed = await _client.send(
      http.Request('GET', _uri('/event'))
        ..headers.addAll({
          ..._headers,
          HttpHeaders.acceptHeader: 'text/event-stream',
        }),
    );
    if (streamed.statusCode != 200) {
      throw OpenCodeGatewayFailure(
        'http_${streamed.statusCode}',
        'OpenCode event stream failed',
      );
    }
    var buffer = '';
    await for (final chunk in streamed.stream.transform(utf8.decoder)) {
      if (_closed) break;
      buffer += chunk.replaceAll('\r\n', '\n');
      final frames = buffer.split('\n\n');
      buffer = frames.removeLast();
      for (final frame in frames) {
        for (final line in frame.split('\n')) {
          if (!line.startsWith('data:')) continue;
          final value = jsonDecode(line.substring(5).trim());
          if (value is! Map) continue;
          final type = '${value['type'] ?? ''}';
          final properties = value['properties'];
          final part = properties is Map ? properties['part'] : null;
          final eventSession = properties is Map
              ? properties['sessionID'] ??
                    (part is Map ? part['sessionID'] : null)
              : null;
          if (eventSession != sessionId) continue;
          if (type == 'permission.updated' ||
              type == 'permission.asked' ||
              type == 'permission.v2.asked') {
            final id = properties is Map ? '${properties['id'] ?? ''}' : '';
            if (id.isEmpty) continue;
            final patternValues = properties is Map
                ? properties['patterns'] ?? properties['resources']
                : null;
            final patterns = patternValues is List
                ? patternValues.map((value) => '$value').toList(growable: false)
                : const <String>[];
            yield OpenCodeSessionEvent.permissionRequested(
              OpenCodePermissionRequest(
                id: id,
                sessionId: sessionId,
                permission: properties is Map
                    ? '${properties['permission'] ?? properties['action'] ?? 'operation'}'
                    : 'operation',
                patterns: patterns,
              ),
            );
          } else {
            yield const OpenCodeSessionEvent.contentChanged();
          }
        }
      }
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
    _client.close();
  }

  Future<http.Response> _get(String path) => _guard(
    () => _client.get(_uri(path), headers: _headers),
    const Duration(seconds: 15),
  );

  Future<http.Response> _post(
    String path,
    Map<String, Object?> body, {
    Duration timeout = const Duration(seconds: 20),
  }) => _guard(
    () => _client.post(
      _uri(path),
      headers: {..._headers, HttpHeaders.contentTypeHeader: 'application/json'},
      body: jsonEncode(body),
    ),
    timeout,
  );

  Future<http.Response> _guard(
    Future<http.Response> Function() request,
    Duration timeout,
  ) async {
    try {
      final response = await request().timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw OpenCodeGatewayFailure(
          response.statusCode == 401
              ? 'unauthorized'
              : 'http_${response.statusCode}',
          response.statusCode == 401
              ? 'OpenCode Serve authentication failed'
              : 'OpenCode Serve returned ${response.statusCode}',
        );
      }
      return response;
    } on OpenCodeGatewayFailure {
      rethrow;
    } on TimeoutException {
      throw const OpenCodeGatewayFailure('timeout', 'OpenCode Serve timed out');
    } on SocketException {
      throw const OpenCodeGatewayFailure(
        'unreachable',
        'OpenCode Serve is unreachable',
      );
    } on http.ClientException {
      throw const OpenCodeGatewayFailure(
        'unreachable',
        'OpenCode Serve is unreachable',
      );
    }
  }

  Map<String, dynamic> _object(String source) {
    final value = jsonDecode(source);
    if (value is! Map) throw const FormatException('Invalid OpenCode response');
    return value.map((key, value) => MapEntry('$key', value));
  }

  OpenCodeRemoteSession _session(Map value) => OpenCodeRemoteSession(
    id: '${value['id']}',
    title: '${value['title'] ?? 'OpenCode'}',
  );

  OpenCodeChatMessage _message(Map value) {
    final info = value['info'];
    final parts = value['parts'];
    final roleName = info is Map ? '${info['role']}' : '';
    final text = parts is List
        ? parts
              .whereType<Map>()
              .where((part) => part['type'] == 'text')
              .map((part) => '${part['text'] ?? ''}')
              .where((text) => text.isNotEmpty)
              .join('\n')
        : '';
    return OpenCodeChatMessage(
      id: info is Map ? '${info['id']}' : '',
      role: roleName == 'user'
          ? OpenCodeMessageRole.user
          : OpenCodeMessageRole.assistant,
      text: text,
    );
  }
}
