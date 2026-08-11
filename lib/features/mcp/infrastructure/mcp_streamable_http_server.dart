import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../application/mcp_tool_backend.dart';
import '../domain/mcp_server_settings.dart';

class McpStreamableHttpServer {
  McpStreamableHttpServer(this._backend);

  static const protocolVersion = '2025-11-25';
  static const _maxRequestBytes = 64 * 1024;
  static const _maxOutputBytes = 1024 * 1024;
  static const _maxTimeoutSeconds = 120;

  final McpToolBackend _backend;
  HttpServer? _server;
  StreamSubscription<HttpRequest>? _subscription;
  final Map<String, bool> _sessions = {};

  bool get isRunning => _server != null;
  int? get boundPort => _server?.port;
  String? get boundAddress => _server?.address.address;

  Future<void> start(McpServerSettings settings) async {
    if (isRunning) return;
    if (!settings.enabled) {
      throw StateError('MCPサーバーは設定で無効です。');
    }
    if (settings.bearerToken.trim().isEmpty) {
      throw StateError('Bearer tokenを設定してください。');
    }
    if (settings.allowLan && utf8.encode(settings.bearerToken).length < 32) {
      throw StateError('LAN公開には32バイト以上のBearer tokenが必要です。');
    }
    if (settings.port < 1 || settings.port > 65535) {
      throw StateError('ポート番号が範囲外です。');
    }
    final address = settings.allowLan
        ? InternetAddress.anyIPv4
        : InternetAddress.loopbackIPv4;
    final server = await HttpServer.bind(address, settings.port, shared: false);
    _server = server;
    _subscription = server.listen(
      (request) => unawaited(_handle(request, settings.bearerToken)),
    );
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await _subscription?.cancel();
    _subscription = null;
    await server?.close(force: true);
    _sessions.clear();
  }

  Future<void> _handle(HttpRequest request, String token) async {
    try {
      if (request.uri.path != '/mcp') {
        return _httpError(
          request.response,
          HttpStatus.notFound,
          'MCPエンドポイントが見つかりません。',
        );
      }
      if (request.headers.value('Origin') != null) {
        return _httpError(
          request.response,
          HttpStatus.forbidden,
          'Originは許可されていません。',
        );
      }
      if (!_tokenMatches(
        request.headers.value(HttpHeaders.authorizationHeader),
        token,
      )) {
        request.response.headers.set(
          HttpHeaders.wwwAuthenticateHeader,
          'Bearer',
        );
        return _httpError(
          request.response,
          HttpStatus.unauthorized,
          'Bearer tokenが必要です。',
        );
      }
      if (request.method != 'POST') {
        return _httpError(
          request.response,
          HttpStatus.methodNotAllowed,
          'POSTのみ利用できます。',
        );
      }
      if (request.headers.contentType?.mimeType != 'application/json') {
        return _httpError(
          request.response,
          HttpStatus.unsupportedMediaType,
          'Content-Typeはapplication/jsonを指定してください。',
        );
      }
      final bytes = <int>[];
      await for (final chunk in request) {
        bytes.addAll(chunk);
        if (bytes.length > _maxRequestBytes) {
          return _httpError(
            request.response,
            HttpStatus.requestEntityTooLarge,
            'リクエストが大きすぎます。',
          );
        }
      }
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) throw const FormatException('JSONオブジェクトが必要です。');
      final message = decoded.cast<String, Object?>();
      if (message['jsonrpc'] != '2.0' || message['method'] is! String) {
        return _jsonRpcError(
          request.response,
          message['id'],
          -32600,
          'Invalid Request',
        );
      }
      final method = message['method'] as String;
      if (method == 'initialize') {
        final sessionId = _newSessionId();
        _sessions[sessionId] = false;
        request.response.headers.set('MCP-Session-Id', sessionId);
        return _jsonResult(request.response, message['id'], {
          'protocolVersion': protocolVersion,
          'capabilities': const {
            'tools': {'listChanged': false},
          },
          'serverInfo': const {
            'name': 'termethis',
            'title': 'Termethis SSH MCP Server',
            'version': '1.0.0',
          },
        });
      }
      final sessionId = request.headers.value('MCP-Session-Id');
      if (sessionId == null || !_sessions.containsKey(sessionId)) {
        return _httpError(
          request.response,
          HttpStatus.badRequest,
          '有効なMCPセッションが必要です。',
        );
      }
      if (request.headers.value('MCP-Protocol-Version') != protocolVersion) {
        return _httpError(
          request.response,
          HttpStatus.badRequest,
          'MCPプロトコルバージョンが一致しません。',
        );
      }
      if (method == 'notifications/initialized' && !message.containsKey('id')) {
        _sessions[sessionId] = true;
        request.response.statusCode = HttpStatus.accepted;
        return request.response.close();
      }
      if (_sessions[sessionId] != true) {
        return _httpError(
          request.response,
          HttpStatus.badRequest,
          'MCP初期化が完了していません。',
        );
      }
      final id = message['id'];
      if (id == null) {
        return _jsonRpcError(
          request.response,
          null,
          -32600,
          'Request id is required',
        );
      }
      switch (method) {
        case 'tools/list':
          return _jsonResult(request.response, id, {'tools': _tools});
        case 'tools/call':
          return _callTool(request.response, id, message['params']);
        default:
          return _jsonRpcError(
            request.response,
            id,
            -32601,
            'Method not found',
          );
      }
    } on FormatException catch (error) {
      await _jsonRpcError(request.response, null, -32700, error.message);
    } on Object {
      try {
        await _jsonRpcError(request.response, null, -32603, 'Internal error');
      } on Object {
        // クライアント切断後は応答を書き込めない。
      }
    }
  }

  Future<void> _callTool(
    HttpResponse response,
    Object? id,
    Object? rawParams,
  ) async {
    if (rawParams is! Map) {
      return _jsonRpcError(response, id, -32602, 'Invalid params');
    }
    final params = rawParams.cast<String, Object?>();
    final name = params['name'];
    final rawArguments = params['arguments'];
    final arguments = rawArguments is Map
        ? rawArguments.cast<String, Object?>()
        : const <String, Object?>{};
    try {
      final Object data = switch (name) {
        'connections.list' => {
          'connections': (await _backend.listSavedConnections())
              .map((value) => value.toJson())
              .toList(growable: false),
        },
        'sessions.list' => {
          'sessions': (await _backend.listSessions())
              .map((value) => value.toJson())
              .toList(growable: false),
        },
        'ssh.execute' => await _execute(arguments),
        _ => throw const McpToolException('unknown_tool', '指定されたツールはありません。'),
      };
      final structured = data is McpSshExecutionResult ? data.toJson() : data;
      return _jsonResult(response, id, {
        'content': [
          {'type': 'text', 'text': jsonEncode(structured)},
        ],
        'structuredContent': structured,
        'isError': false,
      });
    } on McpToolException catch (error) {
      return _jsonResult(response, id, {
        'content': [
          {'type': 'text', 'text': '${error.code}: ${error.message}'},
        ],
        'isError': true,
      });
    }
  }

  Future<McpSshExecutionResult> _execute(Map<String, Object?> arguments) {
    final profileId = arguments['profileId'];
    final command = arguments['command'];
    if (profileId is! String ||
        profileId.trim().isEmpty ||
        command is! String ||
        command.isEmpty) {
      throw const McpToolException(
        'invalid_arguments',
        'profileIdとcommandが必要です。',
      );
    }
    final timeoutSeconds = (arguments['timeoutSeconds'] as num?)?.toInt() ?? 30;
    final outputLimit =
        (arguments['outputLimitBytes'] as num?)?.toInt() ?? 262144;
    if (timeoutSeconds < 1 || timeoutSeconds > _maxTimeoutSeconds) {
      throw const McpToolException(
        'invalid_timeout',
        'timeoutSecondsは1〜120秒で指定してください。',
      );
    }
    if (outputLimit < 1024 || outputLimit > _maxOutputBytes) {
      throw const McpToolException(
        'invalid_output_limit',
        'outputLimitBytesは1024〜1048576で指定してください。',
      );
    }
    return _backend.executeSavedProfile(
      profileId: profileId,
      command: command,
      timeout: Duration(seconds: timeoutSeconds),
      outputLimitBytes: outputLimit,
    );
  }

  bool _tokenMatches(String? authorization, String expected) {
    const prefix = 'Bearer ';
    if (authorization == null || !authorization.startsWith(prefix)) {
      return false;
    }
    final actualBytes = utf8.encode(authorization.substring(prefix.length));
    final expectedBytes = utf8.encode(expected);
    var difference = actualBytes.length ^ expectedBytes.length;
    for (var i = 0; i < actualBytes.length && i < expectedBytes.length; i++) {
      difference |= actualBytes[i] ^ expectedBytes[i];
    }
    return difference == 0;
  }

  String _newSessionId() {
    final random = Random.secure();
    return List.generate(
      32,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<void> _httpError(HttpResponse response, int status, String message) {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode({'error': message}));
    return response.close();
  }

  Future<void> _jsonRpcError(
    HttpResponse response,
    Object? id,
    int code,
    String message,
  ) => _writeJson(response, {
    'jsonrpc': '2.0',
    'id': id,
    'error': {'code': code, 'message': message},
  });

  Future<void> _jsonResult(HttpResponse response, Object? id, Object result) =>
      _writeJson(response, {'jsonrpc': '2.0', 'id': id, 'result': result});

  Future<void> _writeJson(HttpResponse response, Object body) {
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    return response.close();
  }

  static const _tools = [
    {
      'name': 'connections.list',
      'description': '保存済みSSH接続先の公開可能な情報を一覧表示します。',
      'inputSchema': {'type': 'object', 'additionalProperties': false},
    },
    {
      'name': 'sessions.list',
      'description': 'SSHセッションのID、接続先ID、状態だけを一覧表示します。',
      'inputSchema': {'type': 'object', 'additionalProperties': false},
    },
    {
      'name': 'ssh.execute',
      'description': '保存済みSSH接続先で非対話コマンドを実行します。',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'profileId': {'type': 'string'},
          'command': {'type': 'string'},
          'timeoutSeconds': {'type': 'integer', 'minimum': 1, 'maximum': 120},
          'outputLimitBytes': {
            'type': 'integer',
            'minimum': 1024,
            'maximum': 1048576,
          },
        },
        'required': ['profileId', 'command'],
        'additionalProperties': false,
      },
    },
  ];
}
