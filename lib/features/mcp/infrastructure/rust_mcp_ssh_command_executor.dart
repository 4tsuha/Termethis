import 'dart:async';
import 'dart:convert';

import '../../../src/rust/api/core.dart' as rust;
import '../application/mcp_tool_backend.dart';

class McpSshCommandRequest {
  const McpSshCommandRequest({
    required this.host,
    required this.port,
    required this.username,
    required this.authKind,
    required this.password,
    required this.privateKeyPem,
    required this.passphrase,
    required this.trustedHostKeys,
    required this.command,
    required this.timeout,
    required this.outputLimitBytes,
  });

  final String host;
  final int port;
  final String username;
  final String authKind;
  final String password;
  final String privateKeyPem;
  final String? passphrase;
  final List<String> trustedHostKeys;
  final String command;
  final Duration timeout;
  final int outputLimitBytes;
}

abstract interface class McpSshCommandExecutor {
  Future<McpSshExecutionResult> execute(McpSshCommandRequest request);
}

class RustMcpSshCommandExecutor implements McpSshCommandExecutor {
  int _nextExecutionId = DateTime.now().microsecondsSinceEpoch;

  @override
  Future<McpSshExecutionResult> execute(McpSshCommandRequest request) async {
    final executionId = _nextExecutionId++;
    try {
      final result = await rust
          .sshExecute(
            request: rust.RustSshExecRequest(
              executionId: executionId,
              host: request.host,
              port: request.port,
              username: request.username,
              authKind: request.authKind,
              password: request.password,
              privateKeyPem: request.privateKeyPem,
              passphrase: request.passphrase,
              trustedHostKeys: request.trustedHostKeys,
              command: request.command,
              timeoutMillis: request.timeout.inMilliseconds,
              outputLimitBytes: request.outputLimitBytes,
            ),
          )
          .timeout(request.timeout + const Duration(seconds: 2));
      if (result.errorCode != null && !result.timedOut) {
        throw McpToolException(
          result.errorCode!,
          result.errorMessage ?? 'SSHコマンドを実行できませんでした。',
        );
      }
      return McpSshExecutionResult(
        stdout: utf8.decode(result.stdout, allowMalformed: true),
        stderr: utf8.decode(result.stderr, allowMalformed: true),
        exitCode: result.exitStatus,
        timedOut: result.timedOut,
        truncated: result.truncated,
      );
    } on TimeoutException {
      await rust.sshCancelExecution(executionId: executionId);
      throw const McpToolException('timeout', 'SSHコマンドがタイムアウトしました。');
    }
  }
}
