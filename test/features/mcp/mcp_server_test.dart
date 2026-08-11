import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:termethis/features/mcp/application/mcp_server_controller.dart';
import 'package:termethis/features/mcp/application/mcp_tool_backend.dart';
import 'package:termethis/features/mcp/application/termethis_mcp_tool_backend.dart';
import 'package:termethis/features/mcp/infrastructure/rust_mcp_ssh_command_executor.dart';
import 'package:termethis/features/connections/domain/connection_profile.dart';
import 'package:termethis/features/connections/domain/connection_profile_repository.dart';
import 'package:termethis/features/connections/domain/credential_vault.dart';
import 'package:termethis/features/terminal/domain/ssh_gateway.dart';
import 'package:termethis/infrastructure/ssh/in_memory_host_key_repository.dart';
import 'package:termethis/features/mcp/domain/mcp_server_settings.dart';
import 'package:termethis/features/mcp/infrastructure/mcp_streamable_http_server.dart';
import 'package:termethis/features/mcp/infrastructure/shared_preferences_mcp_server_settings_store.dart';
import 'package:termethis/infrastructure/secure_storage/secure_value_store.dart';

void main() {
  test('サーバーは停止が既定で、設定を永続化できる', () async {
    final preferences = _MemoryPreferences();
    final store = SharedPreferencesMcpServerSettingsStore(
      preferences: preferences,
      secureStore: _MemorySecureStore(),
    );
    expect((await store.read()).enabled, isFalse);

    const settings = McpServerSettings(
      enabled: true,
      allowLan: true,
      port: 9876,
      bearerToken: 'secret',
    );
    await store.save(settings);
    final restored = await store.read();
    expect(restored.allowLan, isTrue);
    expect(restored.bindAddress, '0.0.0.0');
    expect(restored.bearerToken, 'secret');
  });

  test('Bearer認証後にinitializeと安全なツール一覧を返す', () async {
    final port = await _freePort();
    final server = McpStreamableHttpServer(_FakeBackend());
    final store = _MemorySettingsStore(
      McpServerSettings(enabled: true, port: port, bearerToken: 'token'),
    );
    final controller = McpServerController(store, server);
    await controller.load();
    await controller.start();
    addTearDown(controller.stop);

    final unauthorized = await _post(port, {
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'initialize',
      'params': <String, Object?>{},
    });
    expect(unauthorized.statusCode, HttpStatus.unauthorized);

    final initialized = await _post(port, {
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'initialize',
      'params': <String, Object?>{},
    }, token: 'token');
    expect(initialized.json['result']['protocolVersion'], '2025-11-25');
    final sessionId = initialized.sessionId!;
    final ready = await _post(
      port,
      {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
      token: 'token',
      sessionId: sessionId,
    );
    expect(ready.statusCode, HttpStatus.accepted);

    final tools = await _post(
      port,
      {
        'jsonrpc': '2.0',
        'id': 2,
        'method': 'tools/list',
        'params': <String, Object?>{},
      },
      token: 'token',
      sessionId: sessionId,
    );
    final encoded = jsonEncode(tools.json);
    expect(encoded, contains('connections.list'));
    expect(encoded, contains('ssh.execute'));
    expect(encoded, contains('sessions.list'));
    expect(encoded, isNot(contains('credentialRef')));
    expect(encoded, isNot(contains('password')));
    expect(controller.status.state, McpServerState.running);
  });

  test('ssh.executeはprofileIdと上限を検証してバックエンドへ渡す', () async {
    final port = await _freePort();
    final backend = _FakeBackend();
    final server = McpStreamableHttpServer(backend);
    await server.start(
      McpServerSettings(enabled: true, port: port, bearerToken: 'token'),
    );
    addTearDown(server.stop);
    final initialized = await _post(port, {
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'initialize',
      'params': <String, Object?>{},
    }, token: 'token');
    final sessionId = initialized.sessionId!;
    await _post(
      port,
      {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
      token: 'token',
      sessionId: sessionId,
    );

    final response = await _post(
      port,
      {
        'jsonrpc': '2.0',
        'id': 3,
        'method': 'tools/call',
        'params': {
          'name': 'ssh.execute',
          'arguments': {
            'profileId': 'saved-1',
            'command': 'uname -a',
            'timeoutSeconds': 5,
            'outputLimitBytes': 4096,
          },
        },
      },
      token: 'token',
      sessionId: sessionId,
    );
    expect(backend.lastProfileId, 'saved-1');
    expect(backend.lastTimeout, const Duration(seconds: 5));
    expect(backend.lastOutputLimit, 4096);
    expect(jsonEncode(response.json), isNot(contains('private-key')));
  });

  test('保存済み秘密鍵と信頼済みホスト鍵だけをexecへ渡す', () async {
    final profiles = EphemeralConnectionProfileRepository();
    final vault = EphemeralCredentialVault();
    final handle = await vault.putPrivateKey(
      const PrivateKeyCredential(
        pem: 'private-key',
        label: 'key',
        isEncrypted: false,
      ),
    );
    await profiles.save(
      ConnectionProfile(
        id: 'saved',
        name: 'Saved',
        host: 'example.com',
        port: 22,
        username: 'user',
        authenticationType: AuthenticationType.privateKey,
        credentialReference: handle.value,
      ),
    );
    final hostKeys = InMemoryHostKeyRepository();
    await hostKeys.trust(
      KnownHost(
        info: const HostKeyInfo(
          host: 'example.com',
          port: 22,
          algorithm: 'ssh-ed25519',
          fingerprintSha256: 'SHA256:test',
        ),
        acceptedAt: DateTime(2026),
      ),
    );
    final executor = _FakeCommandExecutor();
    final backend = TermethisMcpToolBackend(
      profiles,
      vault,
      hostKeys,
      executor,
      const _EmptySessionSource(),
      true,
    );

    final result = await backend.executeSavedProfile(
      profileId: 'saved',
      command: 'id',
      timeout: const Duration(seconds: 4),
      outputLimitBytes: 4096,
    );
    expect(result.stdout, 'ok');
    expect(executor.request!.authKind, 'private_key');
    expect(executor.request!.privateKeyPem, 'private-key');
    expect(executor.request!.trustedHostKeys, ['ssh-ed25519|SHA256:test']);
  });
}

Future<int> _freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

Future<_Response> _post(
  int port,
  Map<String, Object?> body, {
  String? token,
  String? sessionId,
}) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(
      Uri.parse('http://127.0.0.1:$port/mcp'),
    );
    request.headers.contentType = ContentType.json;
    request.headers.set(
      HttpHeaders.acceptHeader,
      'application/json, text/event-stream',
    );
    if (token != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    if (sessionId != null) {
      request.headers.set('MCP-Session-Id', sessionId);
      request.headers.set('MCP-Protocol-Version', '2025-11-25');
    }
    request.write(jsonEncode(body));
    final response = await request.close();
    final text = await utf8.decoder.bind(response).join();
    return _Response(
      response.statusCode,
      text.isEmpty ? const {} : jsonDecode(text) as Map,
      response.headers.value('MCP-Session-Id'),
    );
  } finally {
    client.close(force: true);
  }
}

class _Response {
  const _Response(this.statusCode, this.json, this.sessionId);
  final int statusCode;
  final Map json;
  final String? sessionId;
}

class _FakeBackend implements McpToolBackend {
  String? lastProfileId;
  Duration? lastTimeout;
  int? lastOutputLimit;

  @override
  Future<McpSshExecutionResult> executeSavedProfile({
    required String profileId,
    required String command,
    required Duration timeout,
    required int outputLimitBytes,
  }) async {
    lastProfileId = profileId;
    lastTimeout = timeout;
    lastOutputLimit = outputLimitBytes;
    return const McpSshExecutionResult(
      stdout: 'Linux',
      stderr: '',
      exitCode: 0,
      timedOut: false,
      truncated: false,
    );
  }

  @override
  Future<List<McpConnectionSummary>> listSavedConnections() async => const [
    McpConnectionSummary(
      id: 'saved-1',
      name: 'Server',
      host: 'example.com',
      port: 22,
      username: 'user',
    ),
  ];

  @override
  Future<List<McpSessionSummary>> listSessions() async => const [];
}

class _MemoryPreferences implements McpSettingsPreferences {
  final Map<String, String> values = {};
  @override
  Future<String?> getString(String key) async => values[key];
  @override
  Future<void> setString(String key, String value) async => values[key] = value;
}

class _MemorySettingsStore implements McpServerSettingsStore {
  _MemorySettingsStore(this.settings);
  McpServerSettings settings;
  @override
  Future<McpServerSettings> read() async => settings;
  @override
  Future<void> save(McpServerSettings value) async => settings = value;
}

class _MemorySecureStore implements SecureValueStore {
  final Map<String, String> values = {};
  @override
  Future<void> delete(String key) async => values.remove(key);
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _FakeCommandExecutor implements McpSshCommandExecutor {
  McpSshCommandRequest? request;
  @override
  Future<McpSshExecutionResult> execute(McpSshCommandRequest request) async {
    this.request = request;
    return const McpSshExecutionResult(
      stdout: 'ok',
      stderr: '',
      exitCode: 0,
      timedOut: false,
      truncated: false,
    );
  }
}

class _EmptySessionSource implements McpSessionSource {
  const _EmptySessionSource();
  @override
  List<McpSessionSummary> listSessions() => const [];
}
