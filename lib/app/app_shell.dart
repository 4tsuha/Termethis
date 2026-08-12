import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/connections/application/connection_tabs_controller.dart';
import 'l10n/app_localizations.dart';

class AppShell extends ConsumerWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final connectionCount =
        ref.watch(connectionTabsProvider).value?.length ?? 0;
    final destinations = [
      NavigationDestination(
        icon: const Icon(Icons.home_outlined),
        selectedIcon: const Icon(Icons.home),
        label: l10n.navHome,
      ),
      NavigationDestination(
        icon: _ConnectionNavigationIcon(
          count: connectionCount,
          selected: false,
        ),
        selectedIcon: _ConnectionNavigationIcon(
          count: connectionCount,
          selected: true,
        ),
        label: l10n.navConnections,
      ),
      NavigationDestination(
        icon: const Icon(Icons.folder_outlined),
        selectedIcon: const Icon(Icons.folder),
        label: l10n.navFiles,
      ),
      NavigationDestination(
        icon: const Icon(Icons.settings_outlined),
        selectedIcon: const Icon(Icons.settings),
        label: l10n.navSettings,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final useRail = constraints.maxWidth >= 600;
        if (useRail) {
          return Scaffold(
            body: Row(
              children: [
                RepaintBoundary(
                  child: NavigationRail(
                    selectedIndex: navigationShell.currentIndex,
                    extended: constraints.maxWidth >= 840,
                    labelType: constraints.maxWidth >= 840
                        ? NavigationRailLabelType.none
                        : NavigationRailLabelType.all,
                    onDestinationSelected: _goToBranch,
                    destinations: [
                      for (final destination in destinations)
                        NavigationRailDestination(
                          icon: destination.icon,
                          selectedIcon: destination.selectedIcon,
                          label: Text(destination.label),
                        ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: RepaintBoundary(child: navigationShell)),
              ],
            ),
          );
        }
        return Scaffold(
          body: RepaintBoundary(child: navigationShell),
          bottomNavigationBar: RepaintBoundary(
            child: NavigationBar(
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: _goToBranch,
              destinations: destinations,
            ),
          ),
        );
      },
    );
  }

  void _goToBranch(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }
}

class _ConnectionNavigationIcon extends StatelessWidget {
  const _ConnectionNavigationIcon({
    required this.count,
    required this.selected,
  });

  final int count;
  final bool selected;

  @override
  Widget build(BuildContext context) => Semantics(
    label: count == 0 ? '接続なし' : '接続タブ$count件',
    child: Badge(
      isLabelVisible: count > 0,
      label: Text('$count'),
      child: Icon(selected ? Icons.lan : Icons.lan_outlined),
    ),
  );
}
