import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'l10n/app_localizations.dart';

class AppShell extends StatelessWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final destinations = [
      NavigationDestination(
        icon: const Icon(Icons.home_outlined),
        selectedIcon: const Icon(Icons.home),
        label: l10n.navHome,
      ),
      NavigationDestination(
        icon: const Icon(Icons.terminal_outlined),
        selectedIcon: const Icon(Icons.terminal),
        label: l10n.navTerminal,
      ),
      NavigationDestination(
        icon: const Icon(Icons.desktop_windows_outlined),
        selectedIcon: const Icon(Icons.desktop_windows),
        label: l10n.navDesktop,
      ),
      NavigationDestination(
        icon: const Icon(Icons.folder_copy_outlined),
        selectedIcon: const Icon(Icons.folder_copy),
        label: l10n.navFtp,
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
