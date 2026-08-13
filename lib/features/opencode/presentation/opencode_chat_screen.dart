import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/scheduler.dart';

import '../../connections/application/connection_profiles_controller.dart';
import '../../connections/domain/connection_profile.dart';
import '../../connections/domain/credential_vault.dart';
import '../application/opencode_providers.dart';
import '../domain/opencode_gateway.dart';

class OpenCodeChatScreen extends ConsumerStatefulWidget {
  const OpenCodeChatScreen({
    required this.profileId,
    required this.tabId,
    super.key,
  });

  final String profileId;
  final String tabId;

  @override
  ConsumerState<OpenCodeChatScreen> createState() => _OpenCodeChatScreenState();
}

class _OpenCodeChatScreenState extends ConsumerState<OpenCodeChatScreen> {
  final _composer = TextEditingController();
  final _scrollController = ScrollController();
  OpenCodeConnection? _connection;
  StreamSubscription<OpenCodeSessionEvent>? _eventSubscription;
  List<OpenCodeRemoteSession> _sessions = const [];
  List<OpenCodeChatMessage> _messages = const [];
  List<OpenCodeTodoItem> _todos = const [];
  List<OpenCodeFileChange> _diff = const [];
  List<OpenCodeCommand> _commands = const [];
  List<OpenCodeAgent> _agents = const [];
  String? _sessionId;
  String? _serverVersion;
  String? _selectedAgent;
  String? _error;
  ConnectionProfile? _profile;
  OpenCodeSessionStatus _status = const OpenCodeSessionStatus.idle();
  bool _loading = true;
  bool _sending = false;
  final Set<String> _shownPermissionIds = {};
  final List<OpenCodeSessionEvent> _pendingEvents = [];
  bool _eventFlushScheduled = false;
  List<OpenCodeChatMessage> _visibleMessages = const [];

  bool get _working =>
      _sending ||
      _status.state == OpenCodeRunState.busy ||
      _status.state == OpenCodeRunState.retry;

  @override
  void initState() {
    super.initState();
    unawaited(_connect());
  }

  @override
  void dispose() {
    _pendingEvents.clear();
    _composer.dispose();
    _scrollController.dispose();
    unawaited(_eventSubscription?.cancel());
    unawaited(_connection?.close());
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    OpenCodeConnection? pendingConnection;
    try {
      final profile = await ref
          .read(connectionProfilesProvider.notifier)
          .loadById(widget.profileId);
      if (profile == null ||
          profile.connectionType != ConnectionType.opencode) {
        throw const OpenCodeGatewayFailure('profile_missing', '接続先が見つかりません。');
      }
      _profile = profile;
      String? password;
      if (profile.credentialReference case final reference?) {
        password =
            (await ref
                    .read(credentialVaultProvider)
                    .readPassword(CredentialHandle(reference)))
                ?.password;
      }
      pendingConnection = _newConnection(profile, password);
      await _finishConnection(pendingConnection);
      pendingConnection = null;
    } on OpenCodeGatewayFailure catch (failure) {
      await pendingConnection?.close();
      if (failure.code == 'unauthorized' && mounted) {
        final password = await _askPassword();
        if (password != null && mounted) {
          await _connectWithPassword(password);
          return;
        }
      }
      if (mounted) setState(() => _error = _errorText(failure));
    } catch (_) {
      await pendingConnection?.close();
      if (mounted) setState(() => _error = 'OpenCode Serveへ接続できませんでした。');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  OpenCodeConnection _newConnection(
    ConnectionProfile profile,
    String? password,
  ) => ref
      .read(openCodeGatewayProvider)
      .connect(
        OpenCodeConnectRequest(
          host: profile.host,
          port: profile.port,
          username: profile.username.isEmpty ? 'opencode' : profile.username,
          password: password,
          directory: profile.remotePath,
        ),
      );

  Future<void> _finishConnection(OpenCodeConnection connection) async {
    final results = await Future.wait<Object>([
      connection.health(),
      connection.listSessions(),
      connection.listCommands(),
      connection.listAgents(),
    ]);
    if (!mounted) {
      await connection.close();
      return;
    }
    _connection = connection;
    setState(() {
      _serverVersion = (results[0] as OpenCodeServerInfo).version;
      _sessions = results[1] as List<OpenCodeRemoteSession>;
      _commands = results[2] as List<OpenCodeCommand>;
      _agents = results[3] as List<OpenCodeAgent>;
      _error = null;
    });
    if (_sessions.firstOrNull case final session?) {
      await _selectSession(session.id);
    }
  }

  Future<void> _connectWithPassword(String password) async {
    final profile = _profile;
    if (profile == null) return;
    OpenCodeConnection? pendingConnection;
    try {
      pendingConnection = _newConnection(profile, password);
      await _finishConnection(pendingConnection);
      pendingConnection = null;
    } on OpenCodeGatewayFailure catch (failure) {
      await pendingConnection?.close();
      if (mounted) setState(() => _error = _errorText(failure));
    } catch (_) {
      await pendingConnection?.close();
      if (mounted) setState(() => _error = 'OpenCode Serveへ接続できませんでした。');
    }
  }

  Future<String?> _askPassword() async {
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.lock_outline),
          title: const Text('OpenCode Serveへ認証'),
          content: TextField(
            controller: controller,
            autofocus: true,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'パスワード',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (value) => Navigator.pop(context, value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('接続'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _selectSession(String id) async {
    final connection = _connection;
    if (connection == null || id == _sessionId) return;
    await _eventSubscription?.cancel();
    try {
      final result = await Future.wait<Object>([
        connection.listMessages(id),
        connection.sessionStatus(id),
        connection.listTodos(id),
        connection.listDiff(id),
      ]);
      if (!mounted) return;
      setState(() {
        _sessionId = id;
        _messages = result[0] as List<OpenCodeChatMessage>;
        _visibleMessages = _onlyVisible(_messages);
        _status = result[1] as OpenCodeSessionStatus;
        _todos = result[2] as List<OpenCodeTodoItem>;
        _diff = result[3] as List<OpenCodeFileChange>;
        _error = null;
      });
      _eventSubscription = connection
          .watchSession(id)
          .listen(_handleSessionEvent, onError: _handleEventFailure);
      _jumpToEnd();
    } on OpenCodeGatewayFailure catch (failure) {
      if (mounted) setState(() => _error = _errorText(failure));
    }
  }

  void _handleSessionEvent(OpenCodeSessionEvent event) {
    if (!mounted) return;
    final permission = event.permission;
    if (permission != null) {
      unawaited(_showPermissionRequest(permission));
      return;
    }
    _pendingEvents.add(event);
    if (_eventFlushScheduled) return;
    _eventFlushScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) => _flushEvents());
  }

  void _handleEventFailure(Object _) {
    if (mounted) {
      setState(() => _error = '更新ストリームが切断されました。セッションを開き直してください。');
    }
  }

  void _flushEvents() {
    _eventFlushScheduled = false;
    if (!mounted || _pendingEvents.isEmpty) return;
    final events = List<OpenCodeSessionEvent>.of(_pendingEvents);
    _pendingEvents.clear();
    final order = _messages.map((message) => message.id).toList();
    final messages = {for (final message in _messages) message.id: message};
    var status = _status;
    var sending = _sending;
    var todos = _todos;
    var diff = _diff;
    var error = _error;
    var refresh = false;
    var scroll = false;
    for (final event in events) {
      switch (event.type) {
        case OpenCodeSessionEventType.messageUpdated:
          final id = event.messageId;
          final role = event.role;
          if (id == null || id.isEmpty || role == null) continue;
          if (!messages.containsKey(id)) order.add(id);
          messages[id] ??= OpenCodeChatMessage(id: id, role: role);
        case OpenCodeSessionEventType.textPartUpdated:
          final id = event.messageId;
          final part = event.textPart;
          if (id == null || id.isEmpty || part == null) continue;
          if (!messages.containsKey(id)) order.add(id);
          messages[id] =
              (messages[id] ??
                      OpenCodeChatMessage(
                        id: id,
                        role: OpenCodeMessageRole.assistant,
                      ))
                  .updateTextPart(part);
          scroll = true;
        case OpenCodeSessionEventType.activityUpdated:
          final id = event.messageId;
          final activity = event.activity;
          if (id == null || id.isEmpty || activity == null) continue;
          if (!messages.containsKey(id)) order.add(id);
          messages[id] =
              (messages[id] ??
                      OpenCodeChatMessage(
                        id: id,
                        role: OpenCodeMessageRole.assistant,
                      ))
                  .updateActivity(activity);
        case OpenCodeSessionEventType.statusChanged:
          if (event.status case final nextStatus?) {
            status = nextStatus;
            if (nextStatus.state == OpenCodeRunState.idle) sending = false;
          }
        case OpenCodeSessionEventType.todoChanged:
          if (event.todos case final nextTodos?) todos = nextTodos;
        case OpenCodeSessionEventType.diffChanged:
          if (event.diff case final nextDiff?) diff = nextDiff;
        case OpenCodeSessionEventType.failed:
          sending = false;
          status = const OpenCodeSessionStatus.idle();
          error = event.errorMessage ?? 'OpenCodeでエラーが発生しました。';
        case OpenCodeSessionEventType.contentChanged:
          refresh = true;
        case OpenCodeSessionEventType.permissionRequested:
          break;
      }
    }
    setState(() {
      _messages = [for (final id in order) ?messages[id]];
      _visibleMessages = _onlyVisible(_messages);
      _status = status;
      _sending = sending;
      _todos = todos;
      _diff = diff;
      _error = error;
    });
    if (scroll) _jumpToEnd();
    if (refresh) unawaited(_refreshMessages());
  }

  Future<void> _showPermissionRequest(OpenCodePermissionRequest request) async {
    if (!_shownPermissionIds.add(request.id) || !mounted) return;
    final response = await showDialog<OpenCodePermissionResponse>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.shield_outlined),
        title: const Text('操作の許可'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('OpenCodeが「${request.permission}」を実行しようとしています。'),
              if (request.patterns.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  request.patterns.join('\n'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(context, OpenCodePermissionResponse.reject),
            child: const Text('拒否'),
          ),
          FilledButton.tonal(
            onPressed: () =>
                Navigator.pop(context, OpenCodePermissionResponse.once),
            child: const Text('今回のみ許可'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, OpenCodePermissionResponse.always),
            child: const Text('常に許可'),
          ),
        ],
      ),
    );
    try {
      await _connection?.replyPermission(
        request.sessionId,
        request.id,
        response ?? OpenCodePermissionResponse.reject,
      );
    } on OpenCodeGatewayFailure catch (failure) {
      if (mounted) setState(() => _error = _errorText(failure));
    } finally {
      _shownPermissionIds.remove(request.id);
    }
  }

  Future<void> _createSession() async {
    final connection = _connection;
    if (connection == null) return;
    try {
      final session = await connection.createSession(title: 'Termethis');
      if (!mounted) return;
      setState(() => _sessions = [session, ..._sessions]);
      await _selectSession(session.id);
    } on OpenCodeGatewayFailure catch (failure) {
      if (mounted) setState(() => _error = _errorText(failure));
    }
  }

  Future<void> _refreshMessages() async {
    final connection = _connection;
    final sessionId = _sessionId;
    if (connection == null || sessionId == null) return;
    try {
      final messages = await connection.listMessages(sessionId);
      if (!mounted || _sessionId != sessionId) return;
      setState(() {
        _messages = messages;
        _visibleMessages = _onlyVisible(messages);
      });
      _jumpToEnd();
    } catch (_) {}
  }

  Future<void> _send() async {
    final connection = _connection;
    var sessionId = _sessionId;
    final text = _composer.text.trim();
    if (connection == null || text.isEmpty || _working) return;
    try {
      if (sessionId == null) {
        final session = await connection.createSession(title: _titleFor(text));
        if (!mounted) return;
        setState(() => _sessions = [session, ..._sessions]);
        await _selectSession(session.id);
        sessionId = session.id;
        if (!mounted) return;
      }
      _composer.clear();
      final localId = 'local-${DateTime.now().microsecondsSinceEpoch}';
      setState(() {
        _sending = true;
        _status = const OpenCodeSessionStatus(state: OpenCodeRunState.busy);
        _error = null;
        _messages = [
          ..._messages,
          OpenCodeChatMessage(
            id: localId,
            role: OpenCodeMessageRole.user,
            text: text,
          ),
        ];
        _visibleMessages = _onlyVisible(_messages);
      });
      _jumpToEnd();
      await connection.sendMessage(sessionId, text, agent: _selectedAgent);
    } on OpenCodeGatewayFailure catch (failure) {
      if (mounted) {
        setState(() {
          _sending = false;
          _status = const OpenCodeSessionStatus.idle();
          _error = _errorText(failure);
        });
      }
    }
  }

  Future<void> _executeCommand(OpenCodeCommand command) async {
    final connection = _connection;
    final sessionId = _sessionId;
    if (connection == null || sessionId == null || _working) return;
    final arguments = await _askCommandArguments(command);
    if (arguments == null || !mounted) return;
    try {
      setState(() {
        _sending = true;
        _status = const OpenCodeSessionStatus(state: OpenCodeRunState.busy);
        _error = null;
      });
      await connection.executeCommand(
        sessionId,
        command.name,
        arguments,
        agent: _selectedAgent,
      );
    } on OpenCodeGatewayFailure catch (failure) {
      if (mounted) {
        setState(() {
          _sending = false;
          _status = const OpenCodeSessionStatus.idle();
          _error = _errorText(failure);
        });
      }
    }
  }

  Future<String?> _askCommandArguments(OpenCodeCommand command) async {
    var arguments = '';
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.terminal_rounded),
        title: Text('/${command.name}'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (command.description case final description?) ...[
                Text(description),
                const SizedBox(height: 16),
              ],
              TextField(
                key: const ValueKey('opencode-command-arguments'),
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '引数（任意）',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => arguments = value,
                onSubmitted: (value) => Navigator.pop(context, value.trim()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, arguments.trim()),
            child: const Text('実行'),
          ),
        ],
      ),
    );
  }

  Future<void> _showCommands() async {
    if (_commands.isEmpty || _working || _sessionId == null) return;
    final command = await showModalBottomSheet<OpenCodeCommand>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => _CommandSheet(commands: _commands),
    );
    if (command != null && mounted) await _executeCommand(command);
  }

  Future<void> _showWorkDetails() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) => FractionallySizedBox(
      heightFactor: 0.78,
      child: _WorkDetails(todos: _todos, diff: _diff),
    ),
  );

  Future<void> _abort() async {
    final sessionId = _sessionId;
    if (sessionId == null) return;
    try {
      await _connection?.abort(sessionId);
      if (mounted) {
        setState(() {
          _sending = false;
          _status = const OpenCodeSessionStatus.idle();
        });
      }
    } on OpenCodeGatewayFailure catch (failure) {
      if (mounted) setState(() => _error = _errorText(failure));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _connection == null) {
      return _ConnectionFailure(message: _error!, onRetry: _connect);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final expanded = constraints.maxWidth >= 840;
        final medium = constraints.maxWidth >= 600;
        final sessions = _SessionPane(
          sessions: _sessions,
          selectedId: _sessionId,
          version: _serverVersion,
          status: _status,
          onSelect: _selectSession,
          onCreate: _createSession,
        );
        final chat = Column(
          children: [
            if (!expanded)
              _CompactHeader(
                sessions: _sessions,
                selectedId: _sessionId,
                status: _status,
                agent: _selectedAgent,
                agents: _agents,
                diffCount: _diff.length,
                onSelect: _selectSession,
                onCreate: _createSession,
                onAgentChanged: (agent) =>
                    setState(() => _selectedAgent = agent),
                onCommands: _showCommands,
                onWorkDetails: _showWorkDetails,
              ),
            if (expanded)
              _AgentToolbar(
                status: _status,
                agent: _selectedAgent,
                agents: _agents,
                diffCount: _diff.length,
                onAgentChanged: (agent) =>
                    setState(() => _selectedAgent = agent),
                onCommands: _showCommands,
                onWorkDetails: _showWorkDetails,
              ),
            if (_error case final error?)
              MaterialBanner(
                content: Text(error),
                actions: [
                  TextButton(
                    onPressed: _refreshMessages,
                    child: const Text('再試行'),
                  ),
                ],
              ),
            Expanded(
              child: _visibleMessages.isEmpty
                  ? const _EmptyChat()
                  : ListView.builder(
                      controller: _scrollController,
                      padding: EdgeInsets.fromLTRB(
                        medium ? 24 : 16,
                        20,
                        medium ? 24 : 16,
                        12,
                      ),
                      itemCount: _visibleMessages.length + (_working ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _visibleMessages.length) {
                          return const _AgentWorkingIndicator();
                        }
                        return RepaintBoundary(
                          child: _MessageBubble(
                            key: ValueKey(_visibleMessages[index].id),
                            message: _visibleMessages[index],
                          ),
                        );
                      },
                    ),
            ),
            _Composer(
              controller: _composer,
              working: _working,
              enabled: _connection != null,
              commandsEnabled: _commands.isNotEmpty && _sessionId != null,
              onCommands: _showCommands,
              onSend: _send,
              onAbort: _abort,
            ),
          ],
        );
        return ColoredBox(
          color: colors.surface,
          child: expanded
              ? Row(
                  children: [
                    SizedBox(width: 296, child: sessions),
                    VerticalDivider(width: 1, color: colors.outlineVariant),
                    Expanded(child: chat),
                    SizedBox(
                      width: 320,
                      child: _WorkDetails(todos: _todos, diff: _diff),
                    ),
                  ],
                )
              : chat,
        );
      },
    );
  }

  List<OpenCodeChatMessage> _onlyVisible(List<OpenCodeChatMessage> messages) =>
      messages.where((message) => message.isVisible).toList(growable: false);

  void _jumpToEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
  });

  String _titleFor(String text) =>
      text.length > 40 ? '${text.substring(0, 40)}…' : text;

  String _errorText(OpenCodeGatewayFailure failure) => switch (failure.code) {
    'unauthorized' => '認証に失敗しました。接続先のユーザー名とパスワードを確認してください。',
    'timeout' => 'OpenCode Serveから応答がありません。',
    'unreachable' => 'OpenCode Serveへ到達できません。ホストとポートを確認してください。',
    _ => failure.message,
  };
}

class _SessionPane extends StatelessWidget {
  const _SessionPane({
    required this.sessions,
    required this.selectedId,
    required this.version,
    required this.status,
    required this.onSelect,
    required this.onCreate,
  });

  final List<OpenCodeRemoteSession> sessions;
  final String? selectedId;
  final String? version;
  final OpenCodeSessionStatus status;
  final ValueChanged<String> onSelect;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'OpenCode',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (version?.isNotEmpty == true)
                      Text(
                        'Serve $version',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                      ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                tooltip: '新しいセッション',
                onPressed: onCreate,
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: sessions.length,
            itemBuilder: (context, index) {
              final session = sessions[index];
              final selected = session.id == selectedId;
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: ListTile(
                  selected: selected,
                  selectedTileColor: Theme.of(
                    context,
                  ).colorScheme.secondaryContainer,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  leading: Icon(
                    selected && status.state == OpenCodeRunState.busy
                        ? Icons.sync_rounded
                        : Icons.chat_bubble_outline_rounded,
                  ),
                  title: Text(
                    session.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => onSelect(session.id),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

class _CompactHeader extends StatelessWidget {
  const _CompactHeader({
    required this.sessions,
    required this.selectedId,
    required this.status,
    required this.agent,
    required this.agents,
    required this.diffCount,
    required this.onSelect,
    required this.onCreate,
    required this.onAgentChanged,
    required this.onCommands,
    required this.onWorkDetails,
  });

  final List<OpenCodeRemoteSession> sessions;
  final String? selectedId;
  final OpenCodeSessionStatus status;
  final String? agent;
  final List<OpenCodeAgent> agents;
  final int diffCount;
  final ValueChanged<String> onSelect;
  final VoidCallback onCreate;
  final ValueChanged<String?> onAgentChanged;
  final VoidCallback onCommands;
  final VoidCallback onWorkDetails;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: sessions.any((item) => item.id == selectedId)
                        ? selectedId
                        : null,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.chat_outlined),
                      labelText: 'セッション',
                      isDense: true,
                    ),
                    items: [
                      for (final session in sessions)
                        DropdownMenuItem(
                          value: session.id,
                          child: Text(
                            session.title,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) onSelect(value);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: '新しいセッション',
                  onPressed: onCreate,
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _AgentToolbar(
              compact: constraints.maxWidth < 380,
              status: status,
              agent: agent,
              agents: agents,
              diffCount: diffCount,
              onAgentChanged: onAgentChanged,
              onCommands: onCommands,
              onWorkDetails: onWorkDetails,
            ),
          ],
        ),
      ),
    ),
  );
}

class _AgentToolbar extends StatelessWidget {
  const _AgentToolbar({
    this.compact = false,
    required this.status,
    required this.agent,
    required this.agents,
    required this.diffCount,
    required this.onAgentChanged,
    required this.onCommands,
    required this.onWorkDetails,
  });

  final OpenCodeSessionStatus status;
  final bool compact;
  final String? agent;
  final List<OpenCodeAgent> agents;
  final int diffCount;
  final ValueChanged<String?> onAgentChanged;
  final VoidCallback onCommands;
  final VoidCallback onWorkDetails;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final actions = [
      IconButton(
        tooltip: 'リモートコマンド',
        onPressed: onCommands,
        icon: const Icon(Icons.terminal_rounded),
      ),
      Badge.count(
        count: diffCount,
        isLabelVisible: diffCount > 0,
        child: IconButton(
          tooltip: '作業の進捗と変更ファイル',
          onPressed: onWorkDetails,
          icon: const Icon(Icons.difference_outlined),
        ),
      ),
    ];
    return Material(
      color: colors.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: compact
            ? Column(
                children: [
                  Row(
                    children: [
                      _StatusChip(status: status),
                      const Spacer(),
                      ...actions,
                    ],
                  ),
                  _AgentDropdown(
                    agent: agent,
                    agents: agents,
                    onChanged: onAgentChanged,
                  ),
                ],
              )
            : Row(
                children: [
                  _StatusChip(status: status),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _AgentDropdown(
                      agent: agent,
                      agents: agents,
                      onChanged: onAgentChanged,
                    ),
                  ),
                  ...actions,
                ],
              ),
      ),
    );
  }
}

class _AgentDropdown extends StatelessWidget {
  const _AgentDropdown({
    required this.agent,
    required this.agents,
    required this.onChanged,
  });

  final String? agent;
  final List<OpenCodeAgent> agents;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonHideUnderline(
    child: DropdownButton<String?>(
      value: agents.any((item) => item.name == agent) ? agent : null,
      isExpanded: true,
      hint: const Text('既定のエージェント'),
      icon: const Icon(Icons.expand_more_rounded),
      items: [
        const DropdownMenuItem<String?>(child: Text('既定のエージェント')),
        for (final item in agents.where(
          (item) => item.mode == 'primary' || item.mode == 'all',
        ))
          DropdownMenuItem<String?>(
            value: item.name,
            child: Text(item.name, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
    ),
  );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final OpenCodeSessionStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, icon) = switch (status.state) {
      OpenCodeRunState.busy => ('実行中', Icons.sync_rounded),
      OpenCodeRunState.retry => ('再試行', Icons.refresh_rounded),
      OpenCodeRunState.idle => ('待機中', Icons.check_circle_outline_rounded),
    };
    return Semantics(
      label: 'OpenCodeの状態: $label',
      child: Chip(
        avatar: Icon(icon, size: 18),
        label: Text(label),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, super.key});

  final OpenCodeChatMessage message;

  @override
  Widget build(BuildContext context) {
    final user = message.role == OpenCodeMessageRole.user;
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 760),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: user ? colors.primaryContainer : colors.surfaceContainerHigh,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(24),
            topRight: const Radius.circular(24),
            bottomLeft: Radius.circular(user ? 24 : 8),
            bottomRight: Radius.circular(user ? 8 : 24),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.displayText.isNotEmpty)
              SelectableText(message.displayText),
            if (message.displayText.isNotEmpty && message.activities.isNotEmpty)
              const SizedBox(height: 12),
            for (final activity in message.activities)
              _ActivityRow(activity: activity),
          ],
        ),
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.activity});

  final OpenCodeMessageActivity activity;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final icon = switch (activity.status) {
      OpenCodeActivityStatus.pending => Icons.schedule_rounded,
      OpenCodeActivityStatus.running => Icons.sync_rounded,
      OpenCodeActivityStatus.completed => Icons.check_circle_outline_rounded,
      OpenCodeActivityStatus.error => Icons.error_outline_rounded,
      OpenCodeActivityStatus.info => Icons.bolt_rounded,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colors.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activity.label,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                if (activity.detail case final detail?)
                  Text(
                    detail,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AgentWorkingIndicator extends StatelessWidget {
  const _AgentWorkingIndicator();

  @override
  Widget build(BuildContext context) => const Align(
    alignment: Alignment.centerLeft,
    child: Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: Chip(
        avatar: SizedBox.square(
          dimension: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        label: Text('エージェントが作業しています'),
      ),
    ),
  );
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.working,
    required this.enabled,
    required this.commandsEnabled,
    required this.onCommands,
    required this.onSend,
    required this.onAbort,
  });

  final TextEditingController controller;
  final bool working;
  final bool enabled;
  final bool commandsEnabled;
  final VoidCallback onCommands;
  final VoidCallback onSend;
  final VoidCallback onAbort;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                tooltip: 'リモートコマンド',
                onPressed: commandsEnabled && !working ? onCommands : null,
                icon: const Icon(Icons.terminal_rounded),
              ),
              Expanded(
                child: TextField(
                  key: const ValueKey('opencode-composer'),
                  controller: controller,
                  enabled: enabled && !working,
                  minLines: 1,
                  maxLines: 6,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    hintText: 'OpenCodeへ依頼',
                    border: InputBorder.none,
                  ),
                ),
              ),
              IconButton.filled(
                tooltip: working ? '停止' : '送信',
                onPressed: enabled ? (working ? onAbort : onSend) : null,
                icon: Icon(
                  working ? Icons.stop_rounded : Icons.arrow_upward_rounded,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _WorkDetails extends StatelessWidget {
  const _WorkDetails({required this.todos, required this.diff});

  final List<OpenCodeTodoItem> todos;
  final List<OpenCodeFileChange> diff;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Text(
                '作業の内訳',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ),
          if (todos.isNotEmpty) ...[
            const _SectionHeader(icon: Icons.checklist_rounded, label: '進捗'),
            SliverList.builder(
              itemCount: todos.length,
              itemBuilder: (context, index) => _TodoTile(todo: todos[index]),
            ),
          ],
          const _SectionHeader(
            icon: Icons.difference_outlined,
            label: '変更されたファイル',
          ),
          if (diff.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Text('変更はまだありません。'),
              ),
            )
          else
            SliverList.builder(
              itemCount: diff.length,
              itemBuilder: (context, index) =>
                  _FileChangeTile(change: diff[index]),
            ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Text(label, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    ),
  );
}

class _TodoTile extends StatelessWidget {
  const _TodoTile({required this.todo});

  final OpenCodeTodoItem todo;

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    leading: Icon(switch (todo.status) {
      'completed' => Icons.check_circle_rounded,
      'in_progress' => Icons.sync_rounded,
      'cancelled' => Icons.cancel_outlined,
      _ => Icons.radio_button_unchecked_rounded,
    }),
    title: Text(todo.content),
    subtitle: Text(_todoStatusLabel(todo.status)),
  );
}

String _todoStatusLabel(String status) => switch (status) {
  'completed' => '完了',
  'in_progress' => '実行中',
  'cancelled' => '中止',
  _ => '未着手',
};

class _FileChangeTile extends StatelessWidget {
  const _FileChangeTile({required this.change});

  final OpenCodeFileChange change;

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    leading: const Icon(Icons.insert_drive_file_outlined),
    title: Text(change.path, maxLines: 2, overflow: TextOverflow.ellipsis),
    subtitle: Wrap(
      spacing: 12,
      children: [
        Text(
          '+${change.additions}',
          style: TextStyle(color: Theme.of(context).colorScheme.primary),
        ),
        Text(
          '-${change.deletions}',
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ],
    ),
  );
}

class _CommandSheet extends StatefulWidget {
  const _CommandSheet({required this.commands});

  final List<OpenCodeCommand> commands;

  @override
  State<_CommandSheet> createState() => _CommandSheetState();
}

class _CommandSheetState extends State<_CommandSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.toLowerCase();
    final commands = widget.commands
        .where(
          (command) =>
              command.name.toLowerCase().contains(query) ||
              (command.description?.toLowerCase().contains(query) ?? false),
        )
        .toList(growable: false);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Text(
              'リモートコマンド',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SearchBar(
              hintText: 'コマンドを検索',
              leading: const Icon(Icons.search_rounded),
              onChanged: (value) => setState(() => _query = value.trim()),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: commands.length,
              itemBuilder: (context, index) {
                final command = commands[index];
                return ListTile(
                  leading: const Icon(Icons.terminal_rounded),
                  title: Text('/${command.name}'),
                  subtitle: command.description == null
                      ? null
                      : Text(
                          command.description!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                  trailing: command.subtask
                      ? const Chip(label: Text('サブエージェント'))
                      : null,
                  onTap: () => Navigator.pop(context, command),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat();

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome_rounded,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text('エージェントへ依頼', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text(
              'リモートのOpenCodeセッションへ実装や調査を依頼し、進捗と変更ファイルを確認できます。',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ),
  );
}

class _ConnectionFailure extends StatelessWidget {
  const _ConnectionFailure({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 56,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('再接続'),
          ),
        ],
      ),
    ),
  );
}
