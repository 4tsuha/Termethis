import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'l10n/app_localizations.dart';

class AppShell extends StatelessWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.terminal_outlined),
            selectedIcon: const Icon(Icons.terminal),
            label: l10n.navSsh,
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
        ],
      ),
    );
  }
}
