import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../connections/application/connection_profiles_controller.dart';
import '../../connections/domain/connection_profile.dart';
import '../application/session_registry.dart';
import '../application/ssh_session_controller.dart';
import '../application/ssh_tabs_controller.dart';
import '../domain/ssh_tab.dart';

class TerminalSessionsScreen extends ConsumerWidget {
  const TerminalSessionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final profiles = ref.watch(connectionProfilesProvider).value ?? const [];
    final profileById = {for (final profile in profiles) profile.id: profile};
    final tabs = ref.watch(sshTabsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.terminalSessionsTitle)),
      body: tabs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: OutlinedButton.icon(
            onPressed: () => ref.invalidate(sshTabsProvider),
            icon: const Icon(Icons.refresh),
            label: Text(l10n.retry),
          ),
        ),
        data: (tabs) => tabs.isEmpty
            ? _EmptyTerminalSessions(
                onOpenConnections: () => context.go('/ssh'),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                itemCount: tabs.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final tab = tabs[index];
                  return _TerminalSessionCard(
                    tab: tab,
                    profile: profileById[tab.profileId],
                    controller: ref.read(sessionRegistryProvider).find(tab.id),
                    onOpen: () => context.push(
                      '/terminal/${tab.profileId}?tab=${tab.id}',
                    ),
                    onClose: () async {
                      ref.read(sessionRegistryProvider).remove(tab.id);
                      await ref.read(sshTabsProvider.notifier).close(tab.id);
                    },
                  );
                },
              ),
      ),
      floatingActionButton: tabs.value?.isNotEmpty == true
          ? FloatingActionButton(
              tooltip: l10n.terminalSessionsOpenConnections,
              onPressed: () => context.go('/ssh'),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}

class _EmptyTerminalSessions extends StatelessWidget {
  const _EmptyTerminalSessions({required this.onOpenConnections});

  final VoidCallback onOpenConnections;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.terminal, size: 64, color: colors.outline),
            const SizedBox(height: 16),
            Text(
              l10n.terminalSessionsEmptyTitle,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.terminalSessionsEmptyMessage,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onOpenConnections,
              icon: const Icon(Icons.dns_outlined),
              label: Text(l10n.terminalSessionsOpenConnections),
            ),
          ],
        ),
      ),
    );
  }
}

class _TerminalSessionCard extends StatelessWidget {
  const _TerminalSessionCard({
    required this.tab,
    required this.profile,
    required this.controller,
    required this.onOpen,
    required this.onClose,
  });

  final SshTab tab;
  final ConnectionProfile? profile;
  final SshSessionController? controller;
  final VoidCallback onOpen;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final session = controller;
    if (session == null) return _buildCard(context, null);
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) => _buildCard(context, session),
    );
  }

  Widget _buildCard(BuildContext context, SshSessionController? session) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final connected = session?.isConnected == true;
    final status = tab.restored && session == null
        ? l10n.statusClosed
        : _statusLabel(l10n, session?.status ?? SshSessionStatus.idle);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: connected
          ? Color.alphaBlend(
              colors.primary.withValues(alpha: 0.10),
              colors.surfaceContainerLow,
            )
          : colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: connected ? colors.primary : Colors.transparent,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        leading: CircleAvatar(
          backgroundColor: colors.secondaryContainer,
          foregroundColor: colors.onSecondaryContainer,
          child: Icon(tab.restored ? Icons.history : Icons.terminal),
        ),
        title: Text(tab.title),
        subtitle: Text(
          '${profile?.target ?? l10n.profileNotFound}\n$status',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: true,
        onTap: onOpen,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton.filledTonal(
              tooltip: l10n.connect,
              onPressed: onOpen,
              icon: const Icon(Icons.open_in_new),
            ),
            IconButton(
              tooltip: l10n.closeSessionTab,
              onPressed: onClose,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }
}

String _statusLabel(AppLocalizations l10n, SshSessionStatus status) =>
    switch (status) {
      SshSessionStatus.idle => l10n.statusIdle,
      SshSessionStatus.connecting => l10n.statusConnecting,
      SshSessionStatus.verifyingHost => l10n.statusVerifyingHost,
      SshSessionStatus.authenticating => l10n.statusAuthenticating,
      SshSessionStatus.openingPty => l10n.statusOpeningPty,
      SshSessionStatus.connected => l10n.statusConnected,
      SshSessionStatus.closing => l10n.statusClosing,
      SshSessionStatus.closed => l10n.statusClosed,
      SshSessionStatus.failed => l10n.statusFailed,
      SshSessionStatus.reconnectPrompt => l10n.statusReconnectPrompt,
    };
