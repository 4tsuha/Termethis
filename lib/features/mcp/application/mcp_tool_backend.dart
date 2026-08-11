class McpConnectionSummary {
  const McpConnectionSummary({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.username,
  });

  final String id;
  final String name;
  final String host;
  final int port;
  final String username;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'host': host,
    'port': port,
    'username': username,
  };
}

class McpSessionSummary {
  const McpSessionSummary({
    required this.id,
    required this.profileId,
    required this.state,
  });

  final String id;
  final String profileId;
  final String state;

  Map<String, Object?> toJson() => {
    'id': id,
    'profileId': profileId,
    'state': state,
  };
}

class McpSshExecutionResult {
  const McpSshExecutionResult({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
    required this.timedOut,
    required this.truncated,
  });

  final String stdout;
  final String stderr;
  final int? exitCode;
  final bool timedOut;
  final bool truncated;

  Map<String, Object?> toJson() => {
    'stdout': stdout,
    'stderr': stderr,
    'exitCode': exitCode,
    'timedOut': timedOut,
    'truncated': truncated,
  };
}

/// Adapter boundary for the existing profile repository, CredentialVault and
/// SshGateway. Implementations must reject unknown/non-SSH profile IDs and must
/// not answer interactive authentication or host-key prompts automatically.
abstract interface class McpToolBackend {
  Future<List<McpConnectionSummary>> listSavedConnections();
  Future<List<McpSessionSummary>> listSessions();
  Future<McpSshExecutionResult> executeSavedProfile({
    required String profileId,
    required String command,
    required Duration timeout,
    required int outputLimitBytes,
  });
}

class McpToolException implements Exception {
  const McpToolException(this.code, this.message);
  final String code;
  final String message;
}
