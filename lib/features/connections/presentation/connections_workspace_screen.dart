import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/connection_profiles_controller.dart';
import '../application/connection_tabs_controller.dart';
import '../domain/connection_profile.dart';
import '../domain/connection_tab.dart';
import '../../diagnostics/presentation/shizuku_shell_screen.dart';
import '../../remote_desktop/application/rdp_session_registry.dart';
import '../../remote_desktop/presentation/rdp_screen.dart';
import '../../remote_desktop/presentation/vnc_screen.dart';
import '../../terminal/application/session_registry.dart';
import '../../terminal/presentation/terminal_screen.dart';
import '../../opencode/presentation/opencode_chat_screen.dart';
import '../../../shared/presentation/expressive_scaffold.dart';

class ConnectionsWorkspaceScreen extends ConsumerStatefulWidget {
  const ConnectionsWorkspaceScreen({this.requestedTabId, super.key});

  final String? requestedTabId;

  @override
  ConsumerState<ConnectionsWorkspaceScreen> createState() =>
      _ConnectionsWorkspaceScreenState();
}

class _ConnectionsWorkspaceScreenState
    extends ConsumerState<ConnectionsWorkspaceScreen> {
  @override
  void initState() {
    super.initState();
    _activateRequestedTab(widget.requestedTabId);
  }

  @override
  void didUpdateWidget(covariant ConnectionsWorkspaceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.requestedTabId != widget.requestedTabId) {
      _activateRequestedTab(widget.requestedTabId);
    }
  }

  void _activateRequestedTab(String? tabId) {
    if (tabId == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.requestedTabId != tabId) return;
      final notifier = ref.read(connectionTabsProvider.notifier);
      final requested = notifier.find(tabId);
      final selected = notifier.selectedTab;
      if (requested == null ||
          (selected != null &&
              selected.id != requested.id &&
              selected.lastActivatedAt.isAfter(requested.lastActivatedAt))) {
        return;
      }
      unawaited(notifier.markActive(tabId));
    });
  }

  @override
  Widget build(BuildContext context) {
    final tabs = ref.watch(connectionTabsProvider);
    return tabs.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => Center(
        child: OutlinedButton.icon(
          onPressed: () => ref.invalidate(connectionTabsProvider),
          icon: const Icon(Icons.refresh),
          label: const Text('接続タブを再読み込み'),
        ),
      ),
      data: (items) {
        if (items.isEmpty) return const _EmptyConnectionsWorkspace();
        final active =
            ref.read(connectionTabsProvider.notifier).selectedTab ??
            _selectedTab(items);
        final profiles =
            ref.watch(connectionProfilesProvider).value ?? const [];
        final profile = active.profileId == null
            ? null
            : profiles.where((item) => item.id == active.profileId).firstOrNull;
        return ColoredBox(
          color: Theme.of(context).colorScheme.surface,
          child: Column(
            children: [
              ConnectionTabBar(
                tabs: items,
                activeTabId: active.id,
                onSelect: _select,
                onClose: _requestClose,
                onAdd: _showConnectionPicker,
                onMove: (tabId, index) => ref
                    .read(connectionTabsProvider.notifier)
                    .move(tabId, index),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(20),
                    ),
                    child: _ConnectionContentHost(
                      tab: active,
                      profile: profile,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  ConnectionTab _selectedTab(List<ConnectionTab> tabs) => tabs.reduce(
    (current, next) =>
        next.lastActivatedAt.isAfter(current.lastActivatedAt) ? next : current,
  );

  Future<void> _select(ConnectionTab tab) async {
    await ref.read(connectionTabsProvider.notifier).markActive(tab.id);
    if (!mounted) return;
    context.go(
      Uri(path: '/connections', queryParameters: {'tab': tab.id}).toString(),
    );
  }

  Future<void> _requestClose(ConnectionTab tab) async {
    final sshSession = ref.read(sessionRegistryProvider).find(tab.id);
    final rdpSession = ref.read(rdpSessionRegistryProvider).find(tab.id);
    final active =
        sshSession?.isConnected == true || rdpSession?.isActive == true;
    if (active) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('接続を終了しますか'),
          content: Text('${tab.title}の接続とタブを閉じます。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('終了'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    if (sshSession != null) await sshSession.disconnect();
    ref.read(sessionRegistryProvider).remove(tab.id);
    await ref.read(rdpSessionRegistryProvider).remove(tab.id);
    await ref.read(connectionTabsProvider.notifier).close(tab.id);
    final remaining = ref.read(connectionTabsProvider).value ?? const [];
    if (!mounted) return;
    if (remaining.isEmpty) {
      context.go('/connections');
    } else {
      await _select(remaining.last);
    }
  }

  Future<void> _showConnectionPicker() async {
    final profiles = await ref.read(connectionProfilesProvider.future);
    if (!mounted) return;
    final selected = await showModalBottomSheet<ConnectionProfile>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _ConnectionPicker(profiles: profiles),
    );
    if (selected == null) return;
    final tabId = await ref
        .read(connectionTabsProvider.notifier)
        .open(selected);
    if (!mounted) return;
    context.go(
      Uri(path: '/connections', queryParameters: {'tab': tabId}).toString(),
    );
  }
}

class _ConnectionContentHost extends StatelessWidget {
  const _ConnectionContentHost({required this.tab, required this.profile});

  final ConnectionTab tab;
  final ConnectionProfile? profile;

  @override
  Widget build(BuildContext context) {
    if (tab.protocol == ConnectionProtocol.shizukuShell) {
      return const ShizukuShellScreen(embedded: true);
    }
    final connection = profile;
    if (connection == null) {
      return _MissingConnection(tab: tab);
    }
    return switch (tab.protocol) {
      ConnectionProtocol.ssh => TerminalScreen(
        key: ValueKey('connection-terminal-${tab.id}'),
        profileId: connection.id,
        tabId: tab.id,
        embedded: true,
        showSessionBar: false,
        popWhenEmpty: false,
      ),
      ConnectionProtocol.mosh => TerminalScreen(
        key: ValueKey('connection-mosh-${tab.id}'),
        profileId: connection.id,
        tabId: tab.id,
        embedded: true,
        showSessionBar: false,
        popWhenEmpty: false,
      ),
      ConnectionProtocol.rdp => RdpScreen(
        key: ValueKey('connection-rdp-${tab.id}'),
        profileId: connection.id,
        tabId: tab.id,
        embedded: true,
      ),
      ConnectionProtocol.vnc => VncScreen(
        key: ValueKey('connection-vnc-${tab.id}'),
        profileId: connection.id,
        tabId: tab.id,
      ),
      ConnectionProtocol.opencode => OpenCodeChatScreen(
        key: ValueKey('connection-opencode-${tab.id}'),
        profileId: connection.id,
        tabId: tab.id,
      ),
      ConnectionProtocol.shizukuShell => const SizedBox.shrink(),
    };
  }
}

@visibleForTesting
class ConnectionTabBar extends StatelessWidget {
  const ConnectionTabBar({
    super.key,
    required this.tabs,
    required this.activeTabId,
    required this.onSelect,
    required this.onClose,
    required this.onAdd,
    required this.onMove,
  });

  final List<ConnectionTab> tabs;
  final String activeTabId;
  final ValueChanged<ConnectionTab> onSelect;
  final ValueChanged<ConnectionTab> onClose;
  final VoidCallback onAdd;
  final Future<void> Function(String tabId, int index) onMove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainer,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              Expanded(
                child: ReorderableListView.builder(
                  scrollDirection: Axis.horizontal,
                  buildDefaultDragHandles: false,
                  padding: const EdgeInsets.fromLTRB(8, 8, 0, 0),
                  itemCount: tabs.length,
                  onReorderItem: (oldIndex, newIndex) {
                    unawaited(onMove(tabs[oldIndex].id, newIndex));
                  },
                  itemBuilder: (context, index) {
                    final tab = tabs[index];
                    final selected = tab.id == activeTabId;
                    return ReorderableDragStartListener(
                      key: ValueKey('connection-tab-reorder-${tab.id}'),
                      index: index,
                      child: Semantics(
                        button: true,
                        selected: selected,
                        label: '${_protocolLabel(tab.protocol)}、${tab.title}',
                        child: InkWell(
                          onTap: () => onSelect(tab),
                          child: AnimatedContainer(
                            key: ValueKey('connection-tab-${tab.id}'),
                            duration: const Duration(milliseconds: 140),
                            constraints: const BoxConstraints(
                              minWidth: 104,
                              maxWidth: 320,
                            ),
                            margin: const EdgeInsets.only(right: 4),
                            padding: const EdgeInsets.only(left: 12),
                            decoration: BoxDecoration(
                              color: selected
                                  ? colors.primaryContainer
                                  : colors.surfaceContainerHigh,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(20),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _protocolIcon(tab.protocol),
                                  size: 18,
                                  color: selected
                                      ? colors.onPrimaryContainer
                                      : colors.onSurfaceVariant,
                                ),
                                const SizedBox(width: 7),
                                Flexible(
                                  child: Text(
                                    tab.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                          color: selected
                                              ? colors.onPrimaryContainer
                                              : colors.onSurface,
                                          fontWeight: selected
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                        ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: '${tab.title}を閉じる',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => onClose(tab),
                                  icon: const Icon(Icons.close, size: 17),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              IconButton(
                tooltip: '接続を追加',
                onPressed: onAdd,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectionPicker extends StatefulWidget {
  const _ConnectionPicker({required this.profiles});

  final List<ConnectionProfile> profiles;

  @override
  State<_ConnectionPicker> createState() => _ConnectionPickerState();
}

class _ConnectionPickerState extends State<_ConnectionPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final visible = widget.profiles
        .where(
          (profile) =>
              profile.name.toLowerCase().contains(_query.toLowerCase()) ||
              profile.target.toLowerCase().contains(_query.toLowerCase()),
        )
        .toList(growable: false);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          4,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('接続を追加', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              autofocus: true,
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                hintText: '接続先を検索',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  final profile = visible[index];
                  return ListTile(
                    leading: Icon(
                      _protocolIcon(ConnectionTab.protocolFor(profile)),
                    ),
                    title: Text(profile.name),
                    subtitle: Text(profile.target),
                    trailing: profile.connectionType == ConnectionType.vnc
                        ? const Text('VNC')
                        : null,
                    onTap: () => Navigator.pop(context, profile),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyConnectionsWorkspace extends StatelessWidget {
  const _EmptyConnectionsWorkspace();

  @override
  Widget build(BuildContext context) => ExpressiveEmptyState(
    icon: Icons.lan_outlined,
    title: '接続は開かれていません',
    message: 'ホームから接続先を開くと、SSH・Mosh・RDP・VNC・OpenCodeをここで切り替えられます。',
    action: FilledButton.icon(
      onPressed: () => context.go('/ssh'),
      icon: const Icon(Icons.home_outlined),
      label: const Text('ホームを開く'),
    ),
  );
}

class _MissingConnection extends StatelessWidget {
  const _MissingConnection({required this.tab});
  final ConnectionTab tab;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text('${tab.title}の接続先は削除されています。タブを閉じてください。'),
    ),
  );
}

IconData _protocolIcon(ConnectionProtocol protocol) => switch (protocol) {
  ConnectionProtocol.ssh ||
  ConnectionProtocol.mosh ||
  ConnectionProtocol.shizukuShell => Icons.terminal,
  ConnectionProtocol.rdp => Icons.desktop_windows_outlined,
  ConnectionProtocol.vnc => Icons.monitor_outlined,
  ConnectionProtocol.opencode => Icons.code_rounded,
};

String _protocolLabel(ConnectionProtocol protocol) => switch (protocol) {
  ConnectionProtocol.ssh => 'SSH',
  ConnectionProtocol.mosh => 'Mosh',
  ConnectionProtocol.rdp => 'RDP',
  ConnectionProtocol.vnc => 'VNC',
  ConnectionProtocol.opencode => 'OpenCode',
  ConnectionProtocol.shizukuShell => 'ADBシェル',
};
