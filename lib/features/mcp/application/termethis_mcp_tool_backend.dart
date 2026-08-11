import 'dart:convert';

import '../../connections/domain/connection_profile.dart';
import '../../connections/domain/connection_profile_repository.dart';
import '../../connections/domain/credential_vault.dart';
import '../../terminal/domain/ssh_gateway.dart';
import '../infrastructure/rust_mcp_ssh_command_executor.dart';
import 'mcp_tool_backend.dart';

abstract interface class McpSessionSource {
  List<McpSessionSummary> listSessions();
}

class TermethisMcpToolBackend implements McpToolBackend {
  TermethisMcpToolBackend(
    this._profiles,
    this._credentials,
    this._hostKeys,
    this._executor,
    this._sessions,
    this._passwordStorageEnabled,
  );

  final ConnectionProfileRepository _profiles;
  final CredentialVault _credentials;
  final HostKeyRepository _hostKeys;
  final McpSshCommandExecutor _executor;
  final McpSessionSource _sessions;
  final bool _passwordStorageEnabled;

  @override
  Future<List<McpConnectionSummary>> listSavedConnections() async {
    final profiles = await _profiles.watchAll().first;
    return [
      for (final profile in profiles)
        if (profile.connectionType == ConnectionType.ssh)
          McpConnectionSummary(
            id: profile.id,
            name: profile.name,
            host: profile.host,
            port: profile.port,
            username: profile.username,
          ),
    ];
  }

  @override
  Future<List<McpSessionSummary>> listSessions() async =>
      _sessions.listSessions();

  @override
  Future<McpSshExecutionResult> executeSavedProfile({
    required String profileId,
    required String command,
    required Duration timeout,
    required int outputLimitBytes,
  }) async {
    final profile = await _profiles.findById(profileId);
    if (profile == null || profile.connectionType != ConnectionType.ssh) {
      throw const McpToolException('profile_not_found', '保存済みSSH接続先が見つかりません。');
    }
    final knownHosts = await _hostKeys.find(profile.host, profile.port);
    if (knownHosts.isEmpty) {
      throw const McpToolException(
        'host_key_untrusted',
        '接続先のホスト鍵が信頼済みではありません。',
      );
    }
    final reference = profile.credentialReference;
    if (reference == null) {
      throw const McpToolException('credential_missing', '保存済み認証情報がありません。');
    }

    var authKind = 'password';
    var password = '';
    var privateKeyPem = '';
    String? passphrase;
    final handle = CredentialHandle(reference);
    if (profile.authenticationType == AuthenticationType.privateKey) {
      final key = await _credentials.readPrivateKey(handle);
      if (key == null) {
        throw const McpToolException('credential_missing', '保存済み秘密鍵を読み取れません。');
      }
      authKind = 'private_key';
      privateKeyPem = key.pem;
      passphrase = key.passphrase;
    } else {
      if (!_passwordStorageEnabled) {
        throw const McpToolException(
          'password_storage_disabled',
          '設定でSSHパスワード保存が無効です。MCP実行には秘密鍵を使用するか、保存を有効にしてください。',
        );
      }
      final savedPassword = await _credentials.readPassword(handle);
      if (savedPassword == null) {
        throw const McpToolException(
          'credential_missing',
          '保存済みパスワードを読み取れません。',
        );
      }
      password = savedPassword.password;
    }

    final result = await _executor.execute(
      McpSshCommandRequest(
        host: profile.host,
        port: profile.port,
        username: profile.username,
        authKind: authKind,
        password: password,
        privateKeyPem: privateKeyPem,
        passphrase: passphrase,
        trustedHostKeys: [
          for (final host in knownHosts)
            '${host.info.algorithm}|${host.info.fingerprintSha256}',
        ],
        command: command,
        timeout: timeout,
        outputLimitBytes: outputLimitBytes,
      ),
    );
    if (utf8.encode(result.stdout).length + utf8.encode(result.stderr).length >
        outputLimitBytes) {
      throw const McpToolException('output_limit', 'SSH出力が設定上限を超えました。');
    }
    return result;
  }
}
