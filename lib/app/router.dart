import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/ftp/presentation/ftp_manager_screen.dart';
import '../features/connections/presentation/connection_editor_screen.dart';
import '../features/connections/presentation/connection_list_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/terminal/presentation/terminal_screen.dart';
import 'app_shell.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final rootNavigatorKey = GlobalKey<NavigatorState>();
  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/ssh',
    routes: [
      GoRoute(path: '/', redirect: (context, state) => '/ssh'),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/ssh',
                builder: (context, state) => const ConnectionListScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/ftp',
                builder: (context, state) => const FtpManagerScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/connections/new',
        builder: (context, state) => const ConnectionEditorScreen(),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/connections/:id/edit',
        builder: (context, state) =>
            ConnectionEditorScreen(profileId: state.pathParameters['id']),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/terminal/:id',
        builder: (context, state) => TerminalScreen(
          profileId: state.pathParameters['id']!,
          tabId:
              state.uri.queryParameters['tab'] ?? state.pathParameters['id']!,
        ),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
