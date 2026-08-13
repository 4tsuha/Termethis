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
    final body = _object(await _get('/global/health'));
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
    final list = _list(await _get('/session'), 'sessions');
    return list.whereType<Map>().map(_session).toList(growable: false);
  }

  @override
  Future<OpenCodeRemoteSession> createSession({required String title}) async {
    final response = await _post('/session', {'title': title});
    return _session(_object(response));
  }

  @override
  Future<List<OpenCodeChatMessage>> listMessages(
    String sessionId, {
    int limit = 200,
  }) async {
    final list = _list(
      await _get('/session/$sessionId/message', {'limit': '$limit'}),
      'messages',
    );
    return list
        .whereType<Map>()
        .map(_message)
        .where((message) => message.isVisible)
        .toList(growable: false);
  }

  @override
  Future<OpenCodeSessionStatus> sessionStatus(String sessionId) async {
    final statuses = _object(await _get('/session/status'));
    final value = statuses[sessionId];
    return value is Map ? _status(value) : const OpenCodeSessionStatus.idle();
  }

  @override
  Future<List<OpenCodeTodoItem>> listTodos(String sessionId) async {
    final list = _list(await _get('/session/$sessionId/todo'), 'todos');
    return list.whereType<Map>().map(_todo).toList(growable: false);
  }

  @override
  Future<List<OpenCodeFileChange>> listDiff(String sessionId) async {
    final list = _list(await _get('/session/$sessionId/diff'), 'diff');
    return list.whereType<Map>().map(_diff).toList(growable: false);
  }

  @override
  Future<List<OpenCodeCommand>> listCommands() async {
    final list = _list(await _get('/command'), 'commands');
    return list.whereType<Map>().map(_command).toList(growable: false);
  }

  @override
  Future<List<OpenCodeAgent>> listAgents() async {
    final list = _list(await _get('/agent'), 'agents');
    return list.whereType<Map>().map(_agent).toList(growable: false);
  }

  @override
  Future<void> sendMessage(
    String sessionId,
    String text, {
    String? agent,
  }) async {
    await _post('/session/$sessionId/prompt_async', {
      if (agent?.isNotEmpty == true) 'agent': agent,
      'parts': [
        {'type': 'text', 'text': text},
      ],
    }, timeout: const Duration(seconds: 30));
  }

  @override
  Future<void> executeCommand(
    String sessionId,
    String command,
    String arguments, {
    String? agent,
  }) async {
    await _post('/session/$sessionId/command', {
      'command': command,
      'arguments': arguments,
      if (agent?.isNotEmpty == true) 'agent': agent,
    }, timeout: const Duration(minutes: 10));
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
    await _post('/session/$sessionId/permissions/$permissionId', {
      'response': response.name,
    });
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
        final data = frame
            .split('\n')
            .where((line) => line.startsWith('data:'))
            .map((line) => line.substring(5).trim())
            .join('\n');
        if (data.isEmpty) continue;
        final value = jsonDecode(data);
        if (value is! Map) continue;
        final event = _event(value, sessionId);
        if (event != null) yield event;
      }
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
    _client.close();
  }

  Future<http.Response> _get(String path, [Map<String, String>? query]) =>
      _guard(
        () => _client.get(_uri(path, query), headers: _headers),
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

  dynamic _json(http.Response response) =>
      jsonDecode(utf8.decode(response.bodyBytes));

  Map<String, dynamic> _object(http.Response response) {
    final value = _json(response);
    if (value is! Map) throw const FormatException('Invalid OpenCode response');
    return value.map((key, value) => MapEntry('$key', value));
  }

  List<dynamic> _list(http.Response response, String name) {
    final value = _json(response);
    if (value is! List) throw FormatException('Invalid OpenCode $name');
    return value;
  }

  OpenCodeRemoteSession _session(Map value) => OpenCodeRemoteSession(
    id: '${value['id']}',
    title: '${value['title'] ?? 'OpenCode'}',
  );

  OpenCodeChatMessage _message(Map value) {
    final info = value['info'];
    final parts = value['parts'];
    final roleName = info is Map ? '${info['role']}' : '';
    final textParts = <OpenCodeTextPart>[];
    final activities = <OpenCodeMessageActivity>[];
    if (parts is List) {
      for (final part in parts.whereType<Map>()) {
        if (part['type'] == 'text') {
          if (part['ignored'] == true) continue;
          final text = '${part['text'] ?? ''}';
          if (text.trim().isEmpty) continue;
          textParts.add(
            OpenCodeTextPart(
              id: '${part['id'] ?? textParts.length}',
              text: text,
            ),
          );
          continue;
        }
        final activity = _activity(part);
        if (activity != null) activities.add(activity);
      }
    }
    final created = info is Map && info['time'] is Map
        ? (info['time'] as Map)['created']
        : null;
    return OpenCodeChatMessage(
      id: info is Map ? '${info['id']}' : '',
      role: roleName == 'user'
          ? OpenCodeMessageRole.user
          : OpenCodeMessageRole.assistant,
      textParts: textParts,
      activities: activities,
      createdAt: created is num
          ? DateTime.fromMillisecondsSinceEpoch(created.toInt())
          : null,
    );
  }

  OpenCodeMessageActivity? _activity(Map part) {
    final type = '${part['type'] ?? ''}';
    final id = '${part['id'] ?? type}';
    return switch (type) {
      'tool' => _toolActivity(id, part),
      'subtask' => OpenCodeMessageActivity(
        id: id,
        label: '${part['agent'] ?? 'エージェント'}を実行',
        detail: _optionalText(part['description']),
        status: OpenCodeActivityStatus.running,
      ),
      'agent' => OpenCodeMessageActivity(
        id: id,
        label: 'エージェント: ${part['name'] ?? ''}',
      ),
      'retry' => OpenCodeMessageActivity(
        id: id,
        label: '再試行 ${part['attempt'] ?? ''}',
        detail: _errorText(part['error']),
        status: OpenCodeActivityStatus.error,
      ),
      'compaction' => OpenCodeMessageActivity(id: id, label: 'コンテキストを圧縮'),
      'patch' => OpenCodeMessageActivity(
        id: id,
        label: 'ファイルを更新',
        detail: part['files'] is List
            ? '${(part['files'] as List).length}件'
            : null,
        status: OpenCodeActivityStatus.completed,
      ),
      'file' => OpenCodeMessageActivity(
        id: id,
        label: 'ファイルを添付',
        detail: _optionalText(part['filename']),
      ),
      _ => null,
    };
  }

  OpenCodeMessageActivity _toolActivity(String id, Map part) {
    final state = part['state'];
    final statusName = state is Map ? '${state['status'] ?? ''}' : '';
    return OpenCodeMessageActivity(
      id: id,
      label: state is Map && _optionalText(state['title']) != null
          ? '${state['title']}'
          : '${part['tool'] ?? 'ツール'}',
      detail: statusName == 'error' && state is Map
          ? _optionalText(state['error'])
          : null,
      status: switch (statusName) {
        'pending' => OpenCodeActivityStatus.pending,
        'running' => OpenCodeActivityStatus.running,
        'completed' => OpenCodeActivityStatus.completed,
        'error' => OpenCodeActivityStatus.error,
        _ => OpenCodeActivityStatus.info,
      },
    );
  }

  OpenCodeSessionStatus _status(Map value) {
    final type = '${value['type'] ?? ''}';
    return OpenCodeSessionStatus(
      state: switch (type) {
        'busy' => OpenCodeRunState.busy,
        'retry' => OpenCodeRunState.retry,
        _ => OpenCodeRunState.idle,
      },
      attempt: value['attempt'] is num
          ? (value['attempt'] as num).toInt()
          : null,
      message: _optionalText(value['message']),
      nextRetryAt: value['next'] is num
          ? DateTime.fromMillisecondsSinceEpoch((value['next'] as num).toInt())
          : null,
    );
  }

  OpenCodeTodoItem _todo(Map value) => OpenCodeTodoItem(
    id: '${value['id'] ?? ''}',
    content: '${value['content'] ?? ''}',
    status: '${value['status'] ?? 'pending'}',
    priority: '${value['priority'] ?? 'medium'}',
  );

  OpenCodeFileChange _diff(Map value) => OpenCodeFileChange(
    path: '${value['file'] ?? ''}',
    additions: value['additions'] is num
        ? (value['additions'] as num).toInt()
        : 0,
    deletions: value['deletions'] is num
        ? (value['deletions'] as num).toInt()
        : 0,
  );

  OpenCodeCommand _command(Map value) => OpenCodeCommand(
    name: '${value['name'] ?? ''}',
    description: _optionalText(value['description']),
    agent: _optionalText(value['agent']),
    model: _optionalText(value['model']),
    subtask: value['subtask'] == true,
  );

  OpenCodeAgent _agent(Map value) => OpenCodeAgent(
    name: '${value['name'] ?? ''}',
    mode: '${value['mode'] ?? 'all'}',
    builtIn: value['builtIn'] == true,
    description: _optionalText(value['description']),
  );

  OpenCodeSessionEvent? _event(Map value, String sessionId) {
    final type = '${value['type'] ?? ''}';
    final properties = value['properties'];
    if (properties is! Map) return null;
    final part = properties['part'];
    final info = properties['info'];
    final eventSession =
        properties['sessionID'] ??
        (part is Map ? part['sessionID'] : null) ??
        (info is Map ? info['sessionID'] : null);
    if (eventSession != sessionId) return null;
    return switch (type) {
      'message.updated' when info is Map => OpenCodeSessionEvent.messageUpdated(
        '${info['id'] ?? ''}',
        info['role'] == 'user'
            ? OpenCodeMessageRole.user
            : OpenCodeMessageRole.assistant,
      ),
      'message.part.updated' when part is Map => _partEvent(part),
      'message.removed' ||
      'message.part.removed' => const OpenCodeSessionEvent.contentChanged(),
      'session.status' when properties['status'] is Map =>
        OpenCodeSessionEvent.statusChanged(
          _status(properties['status'] as Map),
        ),
      'session.idle' => const OpenCodeSessionEvent.statusChanged(
        OpenCodeSessionStatus.idle(),
      ),
      'todo.updated' when properties['todos'] is List =>
        OpenCodeSessionEvent.todoChanged(
          (properties['todos'] as List)
              .whereType<Map>()
              .map(_todo)
              .toList(growable: false),
        ),
      'session.diff' when properties['diff'] is List =>
        OpenCodeSessionEvent.diffChanged(
          (properties['diff'] as List)
              .whereType<Map>()
              .map(_diff)
              .toList(growable: false),
        ),
      'permission.updated' ||
      'permission.asked' ||
      'permission.v2.asked' => _permissionEvent(properties, sessionId),
      'session.error' => OpenCodeSessionEvent.failed(
        _errorText(properties['error']) ?? 'OpenCodeでエラーが発生しました。',
      ),
      _ => null,
    };
  }

  OpenCodeSessionEvent? _partEvent(Map part) {
    final messageId = '${part['messageID'] ?? ''}';
    if (messageId.isEmpty) return null;
    if (part['type'] == 'text') {
      if (part['ignored'] == true) return null;
      return OpenCodeSessionEvent.textPartUpdated(
        messageId,
        OpenCodeTextPart(
          id: '${part['id'] ?? messageId}',
          text: '${part['text'] ?? ''}',
        ),
      );
    }
    final activity = _activity(part);
    return activity == null
        ? null
        : OpenCodeSessionEvent.activityUpdated(messageId, activity);
  }

  OpenCodeSessionEvent? _permissionEvent(Map properties, String sessionId) {
    final id = '${properties['id'] ?? ''}';
    if (id.isEmpty) return null;
    final patternValues =
        properties['pattern'] ??
        properties['patterns'] ??
        properties['resources'];
    final patterns = patternValues is List
        ? patternValues.map((value) => '$value').toList(growable: false)
        : patternValues == null
        ? const <String>[]
        : ['$patternValues'];
    return OpenCodeSessionEvent.permissionRequested(
      OpenCodePermissionRequest(
        id: id,
        sessionId: sessionId,
        permission:
            _optionalText(properties['title']) ??
            _optionalText(properties['type']) ??
            _optionalText(properties['permission']) ??
            '操作',
        patterns: patterns,
      ),
    );
  }

  String? _optionalText(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  String? _errorText(Object? value) {
    if (value is Map) {
      final data = value['data'];
      if (data is Map) {
        final message = _optionalText(data['message']);
        if (message != null) return message;
      }
      return _optionalText(value['message']) ?? _optionalText(value['name']);
    }
    return _optionalText(value);
  }
}
