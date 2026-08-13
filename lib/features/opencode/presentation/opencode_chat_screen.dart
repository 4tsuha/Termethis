import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  Timer? _refreshTimer;
  OpenCodeConnection? _connection;
  StreamSubscription<OpenCodeSessionEvent>? _eventSubscription;
  List<OpenCodeRemoteSession> _sessions = const [];
  List<OpenCodeChatMessage> _messages = const [];
  String? _sessionId;
  String? _serverVersion;
  String? _error;
  ConnectionProfile? _profile;
  bool _loading = true;
  bool _sending = false;
  final Set<String> _shownPermissionIds = {};

  @override
  void initState() {
    super.initState();
    unawaited(_connect());
  }

  @override
  void dispose() {
    _composer.dispose();
    _scrollController.dispose();
    _refreshTimer?.cancel();
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
      final connection = ref
          .read(openCodeGatewayProvider)
          .connect(
            OpenCodeConnectRequest(
              host: profile.host,
              port: profile.port,
              username: profile.username.isEmpty
                  ? 'opencode'
                  : profile.username,
              password: password,
              directory: profile.remotePath,
            ),
          );
      pendingConnection = connection;
      final health = await connection.health();
      final sessions = await connection.listSessions();
      if (!mounted) {
        await connection.close();
        return;
      }
      _connection = connection;
      pendingConnection = null;
      _serverVersion = health.version;
      _sessions = sessions;
      final selected = sessions.firstOrNull;
      if (selected != null) await _selectSession(selected.id);
    } on OpenCodeGatewayFailure catch (error) {
      await pendingConnection?.close();
      if (error.code == 'unauthorized' && mounted) {
        final password = await _askPassword();
        if (password != null && mounted) {
          await _connectWithPassword(password);
          return;
        }
      }
      if (mounted) setState(() => _error = _errorText(error));
    } catch (_) {
      await pendingConnection?.close();
      if (mounted) setState(() => _error = 'OpenCode Serveへ接続できませんでした。');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _connectWithPassword(String password) async {
    final profile = _profile;
    if (profile == null) return;
    OpenCodeConnection? pendingConnection;
    try {
      final connection = ref
          .read(openCodeGatewayProvider)
          .connect(
            OpenCodeConnectRequest(
              host: profile.host,
              port: profile.port,
              username: profile.username.isEmpty
                  ? 'opencode'
                  : profile.username,
              password: password,
              directory: profile.remotePath,
            ),
          );
      pendingConnection = connection;
      final health = await connection.health();
      final sessions = await connection.listSessions();
      if (!mounted) {
        await connection.close();
        return;
      }
      _connection = connection;
      pendingConnection = null;
      setState(() {
        _serverVersion = health.version;
        _sessions = sessions;
        _error = null;
      });
      if (sessions.firstOrNull case final session?) {
        await _selectSession(session.id);
      }
    } on OpenCodeGatewayFailure catch (error) {
      await pendingConnection?.close();
      if (mounted) setState(() => _error = _errorText(error));
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
    if (connection == null) return;
    await _eventSubscription?.cancel();
    try {
      final messages = await connection.listMessages(id);
      if (!mounted) return;
      setState(() {
        _sessionId = id;
        _messages = messages;
        _error = null;
      });
      _eventSubscription = connection
          .watchSession(id)
          .listen(_handleSessionEvent, onError: (_) {});
      _scrollToEnd();
    } on OpenCodeGatewayFailure catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    }
  }

  void _handleSessionEvent(OpenCodeSessionEvent event) {
    final permission = event.permission;
    if (event.type == OpenCodeSessionEventType.permissionRequested &&
        permission != null) {
      unawaited(_showPermissionRequest(permission));
      return;
    }
    if (_refreshTimer?.isActive == true) return;
    _refreshTimer = Timer(
      const Duration(milliseconds: 120),
      () => unawaited(_refreshMessages()),
    );
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
    } on OpenCodeGatewayFailure catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    } finally {
      _shownPermissionIds.remove(request.id);
    }
  }

  Future<void> _createSession() async {
    final connection = _connection;
    if (connection == null) return;
    final session = await connection.createSession(title: 'Termethis');
    if (!mounted) return;
    setState(() => _sessions = [session, ..._sessions]);
    await _selectSession(session.id);
  }

  Future<void> _refreshMessages() async {
    final connection = _connection;
    final sessionId = _sessionId;
    if (connection == null || sessionId == null) return;
    try {
      final messages = await connection.listMessages(sessionId);
      if (!mounted || _sessionId != sessionId) return;
      setState(() => _messages = messages);
      _scrollToEnd();
    } catch (_) {}
  }

  Future<void> _send() async {
    final connection = _connection;
    var sessionId = _sessionId;
    final text = _composer.text.trim();
    if (connection == null || text.isEmpty || _sending) return;
    try {
      if (sessionId == null) {
        final session = await connection.createSession(title: _titleFor(text));
        if (!mounted) return;
        setState(() => _sessions = [session, ..._sessions]);
        await _selectSession(session.id);
        sessionId = session.id;
        if (!mounted) return;
      }
    } on OpenCodeGatewayFailure catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
      return;
    }
    _composer.clear();
    setState(() {
      _sending = true;
      _error = null;
      _messages = [
        ..._messages,
        OpenCodeChatMessage(
          id: 'local-${DateTime.now().microsecondsSinceEpoch}',
          role: OpenCodeMessageRole.user,
          text: text,
        ),
      ];
    });
    _scrollToEnd();
    try {
      await connection.sendMessage(sessionId, text);
      await _refreshMessages();
    } on OpenCodeGatewayFailure catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _abort() async {
    final sessionId = _sessionId;
    if (sessionId == null) return;
    await _connection?.abort(sessionId);
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _connection == null) {
      return _ConnectionFailure(message: _error!, onRetry: _connect);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final conversations = _SessionPane(
          sessions: _sessions,
          selectedId: _sessionId,
          version: _serverVersion,
          onSelect: _selectSession,
          onCreate: _createSession,
        );
        final chat = Column(
          children: [
            if (!wide)
              _CompactHeader(
                sessions: _sessions,
                selectedId: _sessionId,
                onSelect: _selectSession,
                onCreate: _createSession,
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
              child: _messages.isEmpty
                  ? const _EmptyChat()
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) =>
                          _MessageBubble(message: _messages[index]),
                    ),
            ),
            _Composer(
              controller: _composer,
              sending: _sending,
              enabled: _connection != null,
              onSend: _send,
              onAbort: _abort,
            ),
          ],
        );
        return ColoredBox(
          color: colors.surface,
          child: wide
              ? Row(
                  children: [
                    SizedBox(width: 280, child: conversations),
                    VerticalDivider(width: 1, color: colors.outlineVariant),
                    Expanded(child: chat),
                  ],
                )
              : chat,
        );
      },
    );
  }

  void _scrollToEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  });

  String _titleFor(String text) =>
      text.length > 40 ? '${text.substring(0, 40)}…' : text;

  String _errorText(OpenCodeGatewayFailure error) => switch (error.code) {
    'unauthorized' => '認証に失敗しました。接続先のユーザー名とパスワードを確認してください。',
    'timeout' => 'OpenCode Serveから応答がありません。',
    'unreachable' => 'OpenCode Serveへ到達できません。ホストとポートを確認してください。',
    _ => error.message,
  };
}

class _SessionPane extends StatelessWidget {
  const _SessionPane({
    required this.sessions,
    required this.selectedId,
    required this.version,
    required this.onSelect,
    required this.onCreate,
  });
  final List<OpenCodeRemoteSession> sessions;
  final String? selectedId;
  final String? version;
  final ValueChanged<String> onSelect;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
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
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                tooltip: '新しいセッション',
                onPressed: onCreate,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: sessions.length,
            itemBuilder: (context, index) {
              final session = sessions[index];
              return Material(
                type: MaterialType.transparency,
                child: ListTile(
                  selected: session.id == selectedId,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  leading: const Icon(Icons.chat_bubble_outline),
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
    required this.onSelect,
    required this.onCreate,
  });
  final List<OpenCodeRemoteSession> sessions;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 8, 0),
    child: Row(
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
            ),
            items: [
              for (final session in sessions)
                DropdownMenuItem(
                  value: session.id,
                  child: Text(session.title, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (value) {
              if (value != null) onSelect(value);
            },
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          onPressed: onCreate,
          icon: const Icon(Icons.add),
        ),
      ],
    ),
  );
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});
  final OpenCodeChatMessage message;

  @override
  Widget build(BuildContext context) {
    final user = message.role == OpenCodeMessageRole.user;
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 720),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: user ? colors.primaryContainer : colors.surfaceContainerHigh,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(24),
            topRight: const Radius.circular(24),
            bottomLeft: Radius.circular(user ? 24 : 6),
            bottomRight: Radius.circular(user ? 6 : 24),
          ),
        ),
        child: SelectableText(message.text),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.enabled,
    required this.onSend,
    required this.onAbort,
  });
  final TextEditingController controller;
  final bool sending;
  final bool enabled;
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
          padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('opencode-composer'),
                  controller: controller,
                  enabled: enabled && !sending,
                  minLines: 1,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    hintText: 'OpenCodeへメッセージ',
                    border: InputBorder.none,
                  ),
                  onSubmitted: (_) => onSend(),
                ),
              ),
              IconButton.filled(
                tooltip: sending ? '停止' : '送信',
                onPressed: enabled ? (sending ? onAbort : onSend) : null,
                icon: Icon(
                  sending ? Icons.stop_rounded : Icons.arrow_upward_rounded,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat();
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.code_rounded,
            size: 64,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text('何を作りますか？', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text(
            'リモートのOpenCodeセッションへ、実装や調査を依頼できます。',
            textAlign: TextAlign.center,
          ),
        ],
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
