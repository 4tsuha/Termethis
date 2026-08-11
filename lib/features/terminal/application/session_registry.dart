import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../infrastructure/ssh/in_memory_host_key_repository.dart';
import '../../../infrastructure/ssh/rust_ssh_gateway.dart';
import '../../../infrastructure/terminal/utf8_terminal_codec.dart';
import '../../connections/domain/connection_profile.dart';
import '../../settings/application/background_session_coordinator.dart';
import '../domain/ssh_gateway.dart';
import 'ssh_session_controller.dart';

final hostKeyRepositoryProvider = Provider<HostKeyRepository>(
  (ref) => InMemoryHostKeyRepository(),
);

final terminalCodecProvider = Provider<TerminalCodec>(
  (ref) => const Utf8TerminalCodec(),
);

final sshGatewayProvider = Provider<SshGateway>(
  (ref) => RustSshGateway(ref.watch(hostKeyRepositoryProvider)),
);

final sessionRegistryProvider = Provider<SessionRegistry>((ref) {
  final registry = SessionRegistry(
    ref.watch(sshGatewayProvider),
    ref.watch(terminalCodecProvider),
    backgroundSessions: ref.watch(backgroundSessionCoordinatorProvider),
  );
  ref.onDispose(registry.dispose);
  return registry;
});

class SessionRegistry {
  SessionRegistry(this._gateway, this._codec, {this._backgroundSessions});

  final SshGateway _gateway;
  final TerminalCodec _codec;
  final BackgroundSessionCoordinator? _backgroundSessions;
  final Map<String, SshSessionController> _sessions = {};

  SshSessionController open(String tabId, ConnectionProfile profile) {
    return _sessions.putIfAbsent(tabId, () {
      final session = SshSessionController(_gateway, _codec, profile: profile);
      session.addListener(_syncBackgroundSessions);
      return session;
    });
  }

  SshSessionController? find(String tabId) => _sessions[tabId];

  void remove(String tabId) {
    final session = _sessions.remove(tabId);
    session?.removeListener(_syncBackgroundSessions);
    session?.dispose();
    _syncBackgroundSessions();
  }

  void dispose() {
    for (final session in _sessions.values) {
      session.removeListener(_syncBackgroundSessions);
      session.dispose();
    }
    _sessions.clear();
    _backgroundSessions?.setHasActiveSession(false);
  }

  void _syncBackgroundSessions() {
    _backgroundSessions?.setHasActiveSession(
      _sessions.values.any((session) => session.isConnected),
    );
  }
}
