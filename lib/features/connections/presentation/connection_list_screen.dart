import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/app_localizations.dart';
import '../application/connection_profiles_controller.dart';
import '../domain/connection_profile.dart';
import '../../wake_on_lan/application/wake_on_lan_provider.dart';
import '../../terminal/application/ssh_tabs_controller.dart';
import '../../terminal/application/session_registry.dart';

enum _ConnectionMenuAction { wakeOnLan, edit, delete }

class ConnectionListScreen extends ConsumerStatefulWidget {
  const ConnectionListScreen({super.key});

  @override
  ConsumerState<ConnectionListScreen> createState() =>
      _ConnectionListScreenState();
}

class _ConnectionListScreenState extends ConsumerState<ConnectionListScreen> {
  final Set<String> _wakingProfileIds = {};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final profiles = ref.watch(connectionProfilesProvider);
    final sshTabs = ref.watch(sshTabsProvider).value ?? const [];

    return Scaffold(
      appBar: AppBar(title: Text(l10n.connectionsTitle)),
      body: Column(
        children: [
          MaterialBanner(
            content: Text(l10n.stageOneNotice),
            leading: const Icon(Icons.info_outline),
            actions: const [SizedBox.shrink()],
          ),
          if (sshTabs.isNotEmpty)
            SizedBox(
              height: 56,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                itemCount: sshTabs.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final tab = sshTabs[index];
                  return InputChip(
                    avatar: Icon(
                      tab.restored ? Icons.history : Icons.terminal,
                      size: 18,
                    ),
                    label: Text(tab.title),
                    onPressed: () => context.push(
                      '/terminal/${tab.profileId}?tab=${tab.id}',
                    ),
                    onDeleted: () async {
                      ref.read(sessionRegistryProvider).remove(tab.id);
                      await ref.read(sshTabsProvider.notifier).close(tab.id);
                    },
                  );
                },
              ),
            ),
          Expanded(
            child: profiles.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => _LoadFailure(
                message: l10n.loadConnectionsFailed,
                retryLabel: l10n.retry,
                onRetry: () => ref.invalidate(connectionProfilesProvider),
              ),
              data: (items) => items.isEmpty
                  ? _EmptyConnections(l10n: l10n)
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: items.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1, indent: 72),
                      itemBuilder: (context, index) {
                        final profile = items[index];
                        return ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.terminal),
                          ),
                          title: Text(profile.name),
                          subtitle: Text(profile.target),
                          onTap: () async {
                            final tabId = await ref
                                .read(sshTabsProvider.notifier)
                                .open(profile);
                            if (context.mounted) {
                              context.push(
                                '/terminal/${profile.id}?tab=$tabId',
                              );
                            }
                          },
                          trailing: _wakingProfileIds.contains(profile.id)
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox.square(
                                    dimension: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : PopupMenuButton<_ConnectionMenuAction>(
                                  onSelected: (action) => _handleMenuAction(
                                    context,
                                    profile,
                                    action,
                                  ),
                                  itemBuilder: (context) => [
                                    if (profile.wakeOnLan != null)
                                      PopupMenuItem(
                                        value: _ConnectionMenuAction.wakeOnLan,
                                        child: ListTile(
                                          contentPadding: EdgeInsets.zero,
                                          leading: const Icon(
                                            Icons.power_settings_new,
                                          ),
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
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/connections/new'),
        icon: const Icon(Icons.add),
        label: Text(l10n.addConnection),
      ),
    );
  }

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
          final tabs = await ref.read(sshTabsProvider.future);
          for (final tab in tabs.where((tab) => tab.profileId == profile.id)) {
            ref.read(sessionRegistryProvider).remove(tab.id);
            await ref.read(sshTabsProvider.notifier).close(tab.id);
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
  const _EmptyConnections({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.dns_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.emptyConnectionsTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(l10n.emptyConnectionsMessage, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
