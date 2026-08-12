import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/app_localizations.dart';
import '../application/connection_profiles_controller.dart';
import '../application/connection_tabs_controller.dart';
import '../domain/connection_profile.dart';
import '../domain/remote_desktop_launcher.dart';
import '../../wake_on_lan/application/wake_on_lan_provider.dart';
import '../../terminal/application/session_registry.dart';
import '../../terminal/application/ssh_session_controller.dart';

enum _ConnectionMenuAction { wakeOnLan, edit, delete }

enum ConnectionListMode { all, desktop }

class ConnectionListScreen extends ConsumerStatefulWidget {
  const ConnectionListScreen({this.mode = ConnectionListMode.all, super.key});

  final ConnectionListMode mode;

  @override
  ConsumerState<ConnectionListScreen> createState() =>
      _ConnectionListScreenState();
}

class _ConnectionListScreenState extends ConsumerState<ConnectionListScreen> {
  final Set<String> _wakingProfileIds = {};
  final Set<String> _launchingProfileIds = {};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final profiles = ref.watch(connectionProfilesProvider);
    final connectionTabs = ref.watch(connectionTabsProvider).value ?? const [];
    final sessionRegistry = ref.read(sessionRegistryProvider);
    final desktopOnly = widget.mode == ConnectionListMode.desktop;
    final allowedTypes = desktopOnly
        ? const {ConnectionType.rdp, ConnectionType.vnc}
        : ConnectionType.values.toSet();

    return Scaffold(
      appBar: AppBar(
        title: Text(desktopOnly ? l10n.desktopTitle : l10n.connectionsTitle),
      ),
      body: Column(
        children: [
          Expanded(
            child: profiles.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => _LoadFailure(
                message: l10n.loadConnectionsFailed,
                retryLabel: l10n.retry,
                onRetry: () => ref.invalidate(connectionProfilesProvider),
              ),
              data: (items) {
                final visibleItems = items
                    .where(
                      (profile) =>
                          allowedTypes.contains(profile.connectionType),
                    )
                    .toList(growable: false);
                return visibleItems.isEmpty
                    ? _EmptyConnections(
                        title: desktopOnly
                            ? l10n.desktopEmptyTitle
                            : l10n.emptyConnectionsTitle,
                        message: desktopOnly
                            ? l10n.desktopEmptyMessage
                            : l10n.emptyConnectionsMessage,
                        icon: desktopOnly
                            ? Icons.desktop_windows_outlined
                            : Icons.dns_outlined,
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                        itemCount: visibleItems.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final profile = visibleItems[index];
                          final sessions =
                              [
                                for (final tab in connectionTabs)
                                  if (tab.profileId == profile.id)
                                    sessionRegistry.find(tab.id),
                              ].whereType<SshSessionController>().toList(
                                growable: false,
                              );
                          return _ConnectionProfileCard(
                            profile: profile,
                            typeLabel: _connectionTypeLabel(
                              l10n,
                              profile.connectionType,
                            ),
                            typeIcon: _connectionTypeIcon(
                              profile.connectionType,
                            ),
                            sessions: sessions,
                            isLaunching: _launchingProfileIds.contains(
                              profile.id,
                            ),
                            isWaking: _wakingProfileIds.contains(profile.id),
                            onConnect: () => _openProfile(context, profile),
                            onMenuSelected: (action) =>
                                _handleMenuAction(context, profile, action),
                          );
                        },
                      );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push(
          desktopOnly ? '/connections/new?scope=desktop' : '/connections/new',
        ),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _openProfile(
    BuildContext context,
    ConnectionProfile profile,
  ) async {
    if (_launchingProfileIds.contains(profile.id)) return;
    setState(() => _launchingProfileIds.add(profile.id));
    try {
      if (profile.connectionType.usesSshAuthentication) {
        final tabId = await ref
            .read(connectionTabsProvider.notifier)
            .open(profile);
        if (context.mounted) {
          context.go(
            Uri(
              path: '/connections',
              queryParameters: {'tab': tabId},
            ).toString(),
          );
        }
        return;
      }

      if (profile.connectionType == ConnectionType.rdp ||
          profile.connectionType == ConnectionType.vnc) {
        final tabId = await ref
            .read(connectionTabsProvider.notifier)
            .open(profile);
        if (context.mounted) {
          context.go(
            Uri(
              path: '/connections',
              queryParameters: {'tab': tabId},
            ).toString(),
          );
        }
        return;
      }
      throw StateError('未対応の接続方式です。');
    } on RemoteDesktopLaunchFailure catch (error) {
      if (context.mounted) {
        await _showRemoteDesktopFailure(
          context,
          profile.connectionType,
          error.code,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _launchingProfileIds.remove(profile.id));
      }
    }
  }

  Future<void> _showRemoteDesktopFailure(
    BuildContext context,
    ConnectionType type,
    RemoteDesktopLaunchFailureCode code,
  ) {
    final l10n = AppLocalizations.of(context);
    final (icon, title, message) = switch (code) {
      RemoteDesktopLaunchFailureCode.endpointUnreachable => (
        Icons.cloud_off_outlined,
        l10n.remoteEndpointUnavailableTitle,
        l10n.rdpEndpointUnavailableMessage,
      ),
      RemoteDesktopLaunchFailureCode.protocolMismatch => (
        Icons.warning_amber_rounded,
        l10n.rdpProtocolMismatchTitle,
        l10n.rdpProtocolMismatchMessage,
      ),
      RemoteDesktopLaunchFailureCode.unsupportedType ||
      RemoteDesktopLaunchFailureCode.noCompatibleApp => (
        Icons.install_mobile_outlined,
        l10n.remoteClientUnavailableTitle,
        type == ConnectionType.rdp
            ? l10n.rdpClientUnavailableMessage
            : l10n.vncClientUnavailableMessage,
      ),
    };
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(icon),
        title: Text(title),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.close),
          ),
        ],
      ),
    );
  }

  String _connectionTypeLabel(AppLocalizations l10n, ConnectionType type) =>
      switch (type) {
        ConnectionType.ssh => l10n.connectionTypeSsh,
        ConnectionType.mosh => 'Mosh',
        ConnectionType.rdp => l10n.connectionTypeRdp,
        ConnectionType.vnc => l10n.connectionTypeVnc,
      };

  IconData _connectionTypeIcon(ConnectionType type) => switch (type) {
    ConnectionType.ssh => Icons.terminal,
    ConnectionType.mosh => Icons.swap_horiz,
    ConnectionType.rdp => Icons.desktop_windows_outlined,
    ConnectionType.vnc => Icons.monitor_outlined,
  };

  Future<void> _handleMenuAction(
    BuildContext context,
    ConnectionProfile profile,
    _ConnectionMenuAction action,
  ) async {
    switch (action) {
      case _ConnectionMenuAction.wakeOnLan:
        await _wake(profile);
      case _ConnectionMenuAction.edit:
        await context.push('/connections/${profile.id}/edit');
      case _ConnectionMenuAction.delete:
        final l10n = AppLocalizations.of(context);
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n.deleteConnectionTitle),
            content: Text(l10n.deleteConnectionMessage(profile.name)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l10n.delete),
              ),
            ],
          ),
        );
        if (confirmed == true) {
          final tabs = await ref.read(connectionTabsProvider.future);
          for (final tab in tabs.where((tab) => tab.profileId == profile.id)) {
            ref.read(sessionRegistryProvider).remove(tab.id);
            await ref.read(connectionTabsProvider.notifier).close(tab.id);
          }
          await ref
              .read(connectionProfilesProvider.notifier)
              .delete(profile.id);
        }
    }
  }

  Future<void> _wake(ConnectionProfile profile) async {
    final configuration = profile.wakeOnLan;
    if (configuration == null) {
      return;
    }
    setState(() => _wakingProfileIds.add(profile.id));
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(wakeOnLanSenderProvider).send(configuration);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.wakeOnLanSent(profile.name))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.wakeOnLanFailed)));
      }
    } finally {
      if (mounted) {
        setState(() => _wakingProfileIds.remove(profile.id));
      }
    }
  }
}

class _ConnectionProfileCard extends StatelessWidget {
  const _ConnectionProfileCard({
    required this.profile,
    required this.typeLabel,
    required this.typeIcon,
    required this.sessions,
    required this.isLaunching,
    required this.isWaking,
    required this.onConnect,
    required this.onMenuSelected,
  });

  final ConnectionProfile profile;
  final String typeLabel;
  final IconData typeIcon;
  final List<SshSessionController> sessions;
  final bool isLaunching;
  final bool isWaking;
  final VoidCallback onConnect;
  final ValueChanged<_ConnectionMenuAction> onMenuSelected;

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) return _buildCard(context);
    return ListenableBuilder(
      listenable: Listenable.merge(sessions),
      builder: (context, _) => _buildCard(context),
    );
  }

  Widget _buildCard(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final status = _aggregateStatus();
    final connected = status == SshSessionStatus.connected;
    final busy = isLaunching || isWaking;
    final statusColor = _connectionStatusColor(colors, status);
    final statusLabel = switch (profile.connectionType) {
      ConnectionType.ssh => _connectionStatusText(l10n, status),
      ConnectionType.mosh => 'アプリ内蔵',
      ConnectionType.rdp => 'アプリ内蔵',
      ConnectionType.vnc => 'アプリ内蔵',
    };

    return Card(
      key: ValueKey('connection-card-${profile.id}'),
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
      child: InkWell(
        onTap: busy ? null : onConnect,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.secondaryContainer,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(typeIcon, color: colors.onSecondaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          profile.name,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        _ConnectionTypeBadge(label: typeLabel),
                        _ConnectionStatusLabel(
                          label: statusLabel,
                          color: statusColor,
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      profile.target,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    if (profile.authenticationType ==
                            AuthenticationType.privateKey ||
                        profile.wakeOnLan != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (profile.authenticationType ==
                              AuthenticationType.privateKey)
                            _ConnectionFeatureIcon(
                              icon: Icons.key_outlined,
                              label: profile.privateKeyLabel?.isNotEmpty == true
                                  ? '${l10n.privateKeyAuthentication}: ${profile.privateKeyLabel}'
                                  : l10n.privateKeyAuthentication,
                            ),
                          if (profile.authenticationType ==
                                  AuthenticationType.privateKey &&
                              profile.wakeOnLan != null)
                            const SizedBox(width: 10),
                          if (profile.wakeOnLan != null)
                            _ConnectionFeatureIcon(
                              icon: Icons.power_settings_new,
                              label: l10n.wakeOnLanTitle,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (busy)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    IconButton.filledTonal(
                      tooltip: l10n.connect,
                      onPressed: onConnect,
                      icon: const Icon(Icons.login_rounded),
                    ),
                  PopupMenuButton<_ConnectionMenuAction>(
                    tooltip: MaterialLocalizations.of(context).showMenuTooltip,
                    onSelected: onMenuSelected,
                    itemBuilder: (context) => [
                      if (profile.wakeOnLan != null)
                        PopupMenuItem(
                          value: _ConnectionMenuAction.wakeOnLan,
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.power_settings_new),
                            title: Text(l10n.wakeOnLanSend),
                          ),
                        ),
                      PopupMenuItem(
                        value: _ConnectionMenuAction.edit,
                        child: Text(l10n.edit),
                      ),
                      PopupMenuItem(
                        value: _ConnectionMenuAction.delete,
                        child: Text(l10n.delete),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  SshSessionStatus _aggregateStatus() {
    if (sessions.any(
      (session) => session.status == SshSessionStatus.connected,
    )) {
      return SshSessionStatus.connected;
    }
    const activeStatuses = {
      SshSessionStatus.connecting,
      SshSessionStatus.verifyingHost,
      SshSessionStatus.authenticating,
      SshSessionStatus.openingPty,
      SshSessionStatus.closing,
    };
    for (final session in sessions.reversed) {
      if (activeStatuses.contains(session.status)) return session.status;
    }
    if (sessions.any(
      (session) =>
          session.status == SshSessionStatus.failed ||
          session.status == SshSessionStatus.reconnectPrompt,
    )) {
      return SshSessionStatus.failed;
    }
    return sessions.isEmpty ? SshSessionStatus.idle : sessions.last.status;
  }
}

class _ConnectionStatusLabel extends StatelessWidget {
  const _ConnectionStatusLabel({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: color),
        ),
      ],
    );
  }
}

class _ConnectionFeatureIcon extends StatelessWidget {
  const _ConnectionFeatureIcon({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}

class _ConnectionTypeBadge extends StatelessWidget {
  const _ConnectionTypeBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colors.onSecondaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

String _connectionStatusText(AppLocalizations l10n, SshSessionStatus status) =>
    switch (status) {
      SshSessionStatus.idle => l10n.statusIdle,
      SshSessionStatus.connecting => l10n.statusConnecting,
      SshSessionStatus.verifyingHost => l10n.statusVerifyingHost,
      SshSessionStatus.authenticating => l10n.statusAuthenticating,
      SshSessionStatus.openingPty => l10n.statusOpeningPty,
      SshSessionStatus.connected => l10n.statusConnected,
      SshSessionStatus.reconnectPrompt => l10n.statusReconnectPrompt,
      SshSessionStatus.closing => l10n.statusClosing,
      SshSessionStatus.closed => l10n.statusClosed,
      SshSessionStatus.failed => l10n.statusFailed,
    };

Color _connectionStatusColor(ColorScheme colors, SshSessionStatus status) =>
    switch (status) {
      SshSessionStatus.connected => const Color(0xff2e7d32),
      SshSessionStatus.connecting ||
      SshSessionStatus.verifyingHost ||
      SshSessionStatus.authenticating ||
      SshSessionStatus.openingPty ||
      SshSessionStatus.closing => colors.tertiary,
      SshSessionStatus.failed ||
      SshSessionStatus.reconnectPrompt => colors.error,
      SshSessionStatus.idle || SshSessionStatus.closed => colors.outline,
    };

class _LoadFailure extends StatelessWidget {
  const _LoadFailure({
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });

  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: Text(retryLabel)),
          ],
        ),
      ),
    );
  }
}

class _EmptyConnections extends StatelessWidget {
  const _EmptyConnections({
    required this.title,
    required this.message,
    required this.icon,
  });

  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
