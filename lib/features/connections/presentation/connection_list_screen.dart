import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/app_localizations.dart';
import '../application/connection_profiles_controller.dart';
import '../domain/connection_profile.dart';

enum _ConnectionMenuAction { edit, delete }

class ConnectionListScreen extends ConsumerWidget {
  const ConnectionListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final profiles = ref.watch(connectionProfilesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.connectionsTitle)),
      body: Column(
        children: [
          MaterialBanner(
            content: Text(l10n.stageOneNotice),
            leading: const Icon(Icons.info_outline),
            actions: const [SizedBox.shrink()],
          ),
          Expanded(
            child: profiles.isEmpty
                ? _EmptyConnections(l10n: l10n)
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: profiles.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1, indent: 72),
                    itemBuilder: (context, index) {
                      final profile = profiles[index];
                      return ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.terminal),
                        ),
                        title: Text(profile.name),
                        subtitle: Text(profile.target),
                        onTap: () => context.push('/terminal/${profile.id}'),
                        trailing: PopupMenuButton<_ConnectionMenuAction>(
                          onSelected: (action) =>
                              _handleMenuAction(context, ref, profile, action),
                          itemBuilder: (context) => [
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
    WidgetRef ref,
    ConnectionProfile profile,
    _ConnectionMenuAction action,
  ) async {
    switch (action) {
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
          ref.read(connectionProfilesProvider.notifier).delete(profile.id);
        }
    }
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
