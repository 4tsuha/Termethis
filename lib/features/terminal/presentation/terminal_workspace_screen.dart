import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../connections/application/connection_profiles_controller.dart';
import '../../connections/domain/connection_profile.dart';
import '../../diagnostics/presentation/shizuku_shell_screen.dart';
import '../application/ssh_tabs_controller.dart';
import '../domain/ssh_tab.dart';
import 'terminal_screen.dart';

class TerminalWorkspaceScreen extends ConsumerWidget {
  const TerminalWorkspaceScreen({
    this.requestedTabId,
    this.openShizukuShell = false,
    super.key,
  });

  final String? requestedTabId;
  final bool openShizukuShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (openShizukuShell) return const ShizukuShellScreen();
    final tabs = ref.watch(sshTabsProvider);
    return tabs.when(
      loading: () => const _TerminalLoadingView(),
      error: (_, _) =>
          _TerminalErrorView(onRetry: () => ref.invalidate(sshTabsProvider)),
      data: (items) {
        if (items.isEmpty) return const _EmptyTerminalView();
        final selectedTab = _selectTab(items, requestedTabId);
        final profiles = ref.watch(connectionProfilesProvider);
        return profiles.when(
          loading: () => const _TerminalLoadingView(),
          error: (_, _) => _TerminalErrorView(
            onRetry: () => ref.invalidate(connectionProfilesProvider),
          ),
          data: (profiles) {
            final profile = _findProfile(profiles, selectedTab.profileId);
            if (profile == null) {
              return _MissingProfileView(
                tab: selectedTab,
                onClose: () =>
                    ref.read(sshTabsProvider.notifier).close(selectedTab.id),
              );
            }
            return TerminalScreen(
              key: ValueKey('terminal-workspace-${selectedTab.id}'),
              profileId: profile.id,
              tabId: selectedTab.id,
              popWhenEmpty: false,
            );
          },
        );
      },
    );
  }
}

SshTab _selectTab(List<SshTab> tabs, String? requestedTabId) {
  for (final tab in tabs) {
    if (tab.id == requestedTabId) return tab;
  }
  return tabs.last;
}

ConnectionProfile? _findProfile(
  List<ConnectionProfile> profiles,
  String profileId,
) {
  for (final profile in profiles) {
    if (profile.id == profileId) return profile;
  }
  return null;
}

class _TerminalLoadingView extends StatelessWidget {
  const _TerminalLoadingView();

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: Colors.black,
    child: Center(child: CircularProgressIndicator()),
  );
}

class _TerminalErrorView extends StatelessWidget {
  const _TerminalErrorView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: Text(l10n.retry),
        ),
      ),
    );
  }
}

class _EmptyTerminalView extends StatelessWidget {
  const _EmptyTerminalView();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.terminal_outlined,
                size: 48,
                color: Colors.white70,
              ),
              const SizedBox(height: 12),
              Text(
                l10n.terminalSessionsEmptyTitle,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.terminalSessionsEmptyMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () => context.go('/ssh'),
                icon: const Icon(Icons.home_outlined),
                label: Text(l10n.terminalSessionsOpenConnections),
              ),
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: () => context.go('/terminals?mode=shizuku'),
                icon: const Icon(Icons.admin_panel_settings_outlined),
                label: const Text('Shizuku ADBシェル'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MissingProfileView extends StatelessWidget {
  const _MissingProfileView({required this.tab, required this.onClose});

  final SshTab tab;
  final Future<void> Function() onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(color: colors.surfaceContainer),
          child: SizedBox(
            height: 48,
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Container(
                height: 44,
                constraints: const BoxConstraints(minWidth: 144, maxWidth: 220),
                margin: const EdgeInsets.only(left: 4),
                padding: const EdgeInsets.only(left: 12),
                decoration: const BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.history, size: 16, color: colors.outline),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tab.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.closeSessionTab,
                      onPressed: () async => onClose(),
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 17,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: ColoredBox(
            color: Colors.black,
            child: Center(
              child: Text(
                l10n.profileNotFound,
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
