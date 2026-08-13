import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/ftp/presentation/ftp_manager_screen.dart';
import '../features/connections/presentation/connection_editor_screen.dart';
import '../features/connections/presentation/connection_list_screen.dart';
import '../features/connections/presentation/connections_workspace_screen.dart';
import '../features/connections/domain/connection_profile.dart';
import '../features/connection_logs/presentation/connection_logs_screen.dart';
import '../features/diagnostics/presentation/logcat_capture_screen.dart';
import '../features/diagnostics/presentation/shizuku_screen.dart';
import '../features/diagnostics/presentation/connection_diagnostics_screen.dart';
import '../features/data_management/presentation/data_and_safety_screen.dart';
import '../features/mcp/presentation/mcp_server_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/settings/presentation/key_management_screen.dart';
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
                path: '/connections',
                builder: (context, state) => ConnectionsWorkspaceScreen(
                  requestedTabId: state.uri.queryParameters['tab'],
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/files',
                builder: (context, state) => const FtpManagerScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsScreen(),
                routes: [
                  GoRoute(
                    path: 'keys',
                    builder: (context, state) => const KeyManagementScreen(),
                  ),
                  GoRoute(
                    path: 'shizuku',
                    builder: (context, state) => const ShizukuScreen(),
                  ),
                  GoRoute(
                    path: 'logcat',
                    builder: (context, state) => const LogcatCaptureScreen(),
                  ),
                  GoRoute(
                    path: 'connection-logs',
                    builder: (context, state) => const ConnectionLogsScreen(),
                  ),
                  GoRoute(
                    path: 'mcp',
                    builder: (context, state) => const McpServerScreen(),
                  ),
                  GoRoute(
                    path: 'data-safety',
                    builder: (context, state) => const DataAndSafetyScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/terminals',
        redirect: (context, state) => Uri(
          path: '/connections',
          queryParameters: {'tab': ?state.uri.queryParameters['tab']},
        ).toString(),
      ),
      GoRoute(path: '/desktop', redirect: (context, state) => '/connections'),
      GoRoute(path: '/ftp', redirect: (context, state) => '/files'),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/connections/new',
        builder: (context, state) {
          final desktopOnly = state.uri.queryParameters['scope'] == 'desktop';
          return ConnectionEditorScreen(
            connectionType: desktopOnly
                ? ConnectionType.rdp
                : ConnectionType.ssh,
            allowedConnectionTypes: desktopOnly
                ? const {ConnectionType.rdp, ConnectionType.vnc}
                : const {
                    ConnectionType.ssh,
                    ConnectionType.mosh,
                    ConnectionType.rdp,
                    ConnectionType.vnc,
                  },
          );
        },
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/connections/:id/edit',
        builder: (context, state) =>
            ConnectionEditorScreen(profileId: state.pathParameters['id']),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/connections/:id/diagnostics',
        builder: (context, state) =>
            ConnectionDiagnosticsScreen(profileId: state.pathParameters['id']!),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
