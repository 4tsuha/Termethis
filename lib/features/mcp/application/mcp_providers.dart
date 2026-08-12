import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../connections/application/connection_profiles_controller.dart';
import '../../connections/application/connection_tabs_controller.dart';
import '../../connections/domain/connection_tab.dart';
import '../../settings/application/credential_settings_controller.dart';
import '../../terminal/application/session_registry.dart';
import '../domain/mcp_server_settings.dart';
import '../infrastructure/mcp_streamable_http_server.dart';
import '../infrastructure/rust_mcp_ssh_command_executor.dart';
import '../infrastructure/shared_preferences_mcp_server_settings_store.dart';
import 'mcp_server_controller.dart';
import 'mcp_tool_backend.dart';
import 'termethis_mcp_tool_backend.dart';

final mcpServerSettingsStoreProvider = Provider<McpServerSettingsStore>(
  (ref) => SharedPreferencesMcpServerSettingsStore(),
);

final mcpSshCommandExecutorProvider = Provider<McpSshCommandExecutor>(
  (ref) => RustMcpSshCommandExecutor(),
);

final mcpSessionSourceProvider = Provider<McpSessionSource>((ref) {
  return _RegistryMcpSessionSource(
    () => ref.read(connectionTabsProvider).value ?? const <ConnectionTab>[],
    ref.watch(sessionRegistryProvider),
  );
});

final mcpToolBackendProvider = Provider<McpToolBackend>((ref) {
  return TermethisMcpToolBackend(
    ref.watch(connectionProfileRepositoryProvider),
    ref.watch(credentialVaultProvider),
    ref.watch(hostKeyRepositoryProvider),
    ref.watch(mcpSshCommandExecutorProvider),
    ref.watch(mcpSessionSourceProvider),
    ref.watch(credentialSettingsProvider).saveSshPasswords,
  );
});

final mcpHttpServerProvider = Provider<McpStreamableHttpServer>((ref) {
  final server = McpStreamableHttpServer(ref.watch(mcpToolBackendProvider));
  ref.onDispose(() => unawaited(server.stop()));
  return server;
});

final mcpServerControllerProvider = FutureProvider<McpServerController>((
  ref,
) async {
  final controller = McpServerController(
    ref.watch(mcpServerSettingsStoreProvider),
    ref.watch(mcpHttpServerProvider),
  );
  await controller.load();
  return controller;
});

class _RegistryMcpSessionSource implements McpSessionSource {
  const _RegistryMcpSessionSource(this._readTabs, this._registry);
  final List<ConnectionTab> Function() _readTabs;
  final SessionRegistry _registry;

  @override
  List<McpSessionSummary> listSessions() {
    final sessions = <McpSessionSummary>[];
    for (final tab in _readTabs()) {
      if (tab.protocol != ConnectionProtocol.ssh || tab.profileId == null) {
        continue;
      }
      final session = _registry.find(tab.id);
      if (session != null) {
        sessions.add(
          McpSessionSummary(
            id: tab.id,
            profileId: tab.profileId!,
            state: session.status.name,
          ),
        );
      }
    }
    return sessions;
  }
}
