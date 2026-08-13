class OpenCodeServerInfo {
  const OpenCodeServerInfo({required this.version});
  final String version;
}

class OpenCodeRemoteSession {
  const OpenCodeRemoteSession({required this.id, required this.title});
  final String id;
  final String title;
}

enum OpenCodeMessageRole { user, assistant }

class OpenCodeChatMessage {
  const OpenCodeChatMessage({
    required this.id,
    required this.role,
    required this.text,
    this.createdAt,
  });

  final String id;
  final OpenCodeMessageRole role;
  final String text;
  final DateTime? createdAt;
}

class OpenCodePermissionRequest {
  const OpenCodePermissionRequest({
    required this.id,
    required this.sessionId,
    required this.permission,
    this.patterns = const [],
  });

  final String id;
  final String sessionId;
  final String permission;
  final List<String> patterns;
}

enum OpenCodeSessionEventType { contentChanged, permissionRequested }

class OpenCodeSessionEvent {
  const OpenCodeSessionEvent.contentChanged()
    : type = OpenCodeSessionEventType.contentChanged,
      permission = null;

  const OpenCodeSessionEvent.permissionRequested(this.permission)
    : type = OpenCodeSessionEventType.permissionRequested;

  final OpenCodeSessionEventType type;
  final OpenCodePermissionRequest? permission;
}

enum OpenCodePermissionResponse { once, always, reject }

class OpenCodeConnectRequest {
  const OpenCodeConnectRequest({
    required this.host,
    required this.port,
    required this.username,
    this.password,
    this.directory,
  });

  final String host;
  final int port;
  final String username;
  final String? password;
  final String? directory;
}

class OpenCodeGatewayFailure implements Exception {
  const OpenCodeGatewayFailure(this.code, this.message);
  final String code;
  final String message;

  @override
  String toString() => 'OpenCodeGatewayFailure($code)';
}

abstract interface class OpenCodeConnection {
  Future<OpenCodeServerInfo> health();
  Future<List<OpenCodeRemoteSession>> listSessions();
  Future<OpenCodeRemoteSession> createSession({required String title});
  Future<List<OpenCodeChatMessage>> listMessages(String sessionId);
  Future<OpenCodeChatMessage> sendMessage(String sessionId, String text);
  Future<void> abort(String sessionId);
  Future<void> replyPermission(
    String sessionId,
    String permissionId,
    OpenCodePermissionResponse response,
  );
  Stream<OpenCodeSessionEvent> watchSession(String sessionId);
  Future<void> close();
}

abstract interface class OpenCodeGateway {
  OpenCodeConnection connect(OpenCodeConnectRequest request);
}
