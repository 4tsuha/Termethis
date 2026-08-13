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

class OpenCodeTextPart {
  const OpenCodeTextPart({required this.id, required this.text});

  final String id;
  final String text;
}

enum OpenCodeActivityStatus { pending, running, completed, error, info }

class OpenCodeMessageActivity {
  const OpenCodeMessageActivity({
    required this.id,
    required this.label,
    this.detail,
    this.status = OpenCodeActivityStatus.info,
  });

  final String id;
  final String label;
  final String? detail;
  final OpenCodeActivityStatus status;
}

class OpenCodeChatMessage {
  const OpenCodeChatMessage({
    required this.id,
    required this.role,
    this.text = '',
    this.textParts = const [],
    this.activities = const [],
    this.createdAt,
  });

  final String id;
  final OpenCodeMessageRole role;
  final String text;
  final List<OpenCodeTextPart> textParts;
  final List<OpenCodeMessageActivity> activities;
  final DateTime? createdAt;

  String get displayText {
    final joined = textParts
        .map((part) => part.text.trim())
        .where((part) => part.isNotEmpty)
        .join('\n\n');
    return joined.isEmpty ? text.trim() : joined;
  }

  bool get isVisible => displayText.isNotEmpty || activities.isNotEmpty;

  OpenCodeChatMessage copyWith({
    OpenCodeMessageRole? role,
    List<OpenCodeTextPart>? textParts,
    List<OpenCodeMessageActivity>? activities,
  }) => OpenCodeChatMessage(
    id: id,
    role: role ?? this.role,
    text: text,
    textParts: textParts ?? this.textParts,
    activities: activities ?? this.activities,
    createdAt: createdAt,
  );

  OpenCodeChatMessage updateTextPart(OpenCodeTextPart part) {
    final index = textParts.indexWhere((item) => item.id == part.id);
    if (index < 0) return copyWith(textParts: [...textParts, part]);
    final updated = [...textParts]..[index] = part;
    return copyWith(textParts: updated);
  }

  OpenCodeChatMessage updateActivity(OpenCodeMessageActivity activity) {
    final index = activities.indexWhere((item) => item.id == activity.id);
    if (index < 0) return copyWith(activities: [...activities, activity]);
    final updated = [...activities]..[index] = activity;
    return copyWith(activities: updated);
  }
}

enum OpenCodeRunState { idle, busy, retry }

class OpenCodeSessionStatus {
  const OpenCodeSessionStatus({
    required this.state,
    this.attempt,
    this.message,
    this.nextRetryAt,
  });

  const OpenCodeSessionStatus.idle() : this(state: OpenCodeRunState.idle);

  final OpenCodeRunState state;
  final int? attempt;
  final String? message;
  final DateTime? nextRetryAt;
}

class OpenCodeTodoItem {
  const OpenCodeTodoItem({
    required this.id,
    required this.content,
    required this.status,
    required this.priority,
  });

  final String id;
  final String content;
  final String status;
  final String priority;
}

class OpenCodeFileChange {
  const OpenCodeFileChange({
    required this.path,
    required this.additions,
    required this.deletions,
  });

  final String path;
  final int additions;
  final int deletions;
}

class OpenCodeCommand {
  const OpenCodeCommand({
    required this.name,
    this.description,
    this.agent,
    this.model,
    this.subtask = false,
  });

  final String name;
  final String? description;
  final String? agent;
  final String? model;
  final bool subtask;
}

class OpenCodeAgent {
  const OpenCodeAgent({
    required this.name,
    required this.mode,
    required this.builtIn,
    this.description,
  });

  final String name;
  final String mode;
  final bool builtIn;
  final String? description;
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

enum OpenCodeSessionEventType {
  messageUpdated,
  textPartUpdated,
  activityUpdated,
  contentChanged,
  statusChanged,
  todoChanged,
  diffChanged,
  permissionRequested,
  failed,
}

class OpenCodeSessionEvent {
  const OpenCodeSessionEvent._({
    required this.type,
    this.messageId,
    this.role,
    this.textPart,
    this.activity,
    this.status,
    this.todos,
    this.diff,
    this.permission,
    this.errorMessage,
  });

  const OpenCodeSessionEvent.messageUpdated(
    String messageId,
    OpenCodeMessageRole role,
  ) : this._(
        type: OpenCodeSessionEventType.messageUpdated,
        messageId: messageId,
        role: role,
      );

  const OpenCodeSessionEvent.textPartUpdated(
    String messageId,
    OpenCodeTextPart textPart,
  ) : this._(
        type: OpenCodeSessionEventType.textPartUpdated,
        messageId: messageId,
        textPart: textPart,
      );

  const OpenCodeSessionEvent.activityUpdated(
    String messageId,
    OpenCodeMessageActivity activity,
  ) : this._(
        type: OpenCodeSessionEventType.activityUpdated,
        messageId: messageId,
        activity: activity,
      );

  const OpenCodeSessionEvent.contentChanged()
    : this._(type: OpenCodeSessionEventType.contentChanged);

  const OpenCodeSessionEvent.statusChanged(OpenCodeSessionStatus status)
    : this._(type: OpenCodeSessionEventType.statusChanged, status: status);

  const OpenCodeSessionEvent.todoChanged(List<OpenCodeTodoItem> todos)
    : this._(type: OpenCodeSessionEventType.todoChanged, todos: todos);

  const OpenCodeSessionEvent.diffChanged(List<OpenCodeFileChange> diff)
    : this._(type: OpenCodeSessionEventType.diffChanged, diff: diff);

  const OpenCodeSessionEvent.permissionRequested(
    OpenCodePermissionRequest permission,
  ) : this._(
        type: OpenCodeSessionEventType.permissionRequested,
        permission: permission,
      );

  const OpenCodeSessionEvent.failed(String message)
    : this._(type: OpenCodeSessionEventType.failed, errorMessage: message);

  final OpenCodeSessionEventType type;
  final String? messageId;
  final OpenCodeMessageRole? role;
  final OpenCodeTextPart? textPart;
  final OpenCodeMessageActivity? activity;
  final OpenCodeSessionStatus? status;
  final List<OpenCodeTodoItem>? todos;
  final List<OpenCodeFileChange>? diff;
  final OpenCodePermissionRequest? permission;
  final String? errorMessage;
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
  Future<List<OpenCodeChatMessage>> listMessages(
    String sessionId, {
    int limit = 200,
  });
  Future<OpenCodeSessionStatus> sessionStatus(String sessionId);
  Future<List<OpenCodeTodoItem>> listTodos(String sessionId);
  Future<List<OpenCodeFileChange>> listDiff(String sessionId);
  Future<List<OpenCodeCommand>> listCommands();
  Future<List<OpenCodeAgent>> listAgents();
  Future<void> sendMessage(String sessionId, String text, {String? agent});
  Future<void> executeCommand(
    String sessionId,
    String command,
    String arguments, {
    String? agent,
  });
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
