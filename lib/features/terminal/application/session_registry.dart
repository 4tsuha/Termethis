import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../infrastructure/ssh/dart_ssh_gateway.dart';
import '../../../infrastructure/ssh/in_memory_host_key_repository.dart';
import '../../../infrastructure/terminal/utf8_terminal_codec.dart';
import '../../connections/domain/connection_profile.dart';
import '../../settings/application/background_session_coordinator.dart';
import '../../settings/application/terminal_performance_settings_controller.dart';
import '../../settings/domain/terminal_performance_settings.dart';
import '../domain/ssh_gateway.dart';
import 'ssh_session_controller.dart';

final hostKeyRepositoryProvider = Provider<HostKeyRepository>(
  (ref) => InMemoryHostKeyRepository(),
);

final terminalCodecProvider = Provider<TerminalCodec>(
  (ref) => const Utf8TerminalCodec(),
);

final sshGatewayProvider = Provider<SshGateway>(
  (ref) => DartSshGateway(ref.watch(hostKeyRepositoryProvider)),
);

final sessionRegistryProvider = Provider<SessionRegistry>((ref) {
  final registry = SessionRegistry(
    ref.watch(sshGatewayProvider),
    ref.watch(terminalCodecProvider),
    scrollbackLines: () =>
        ref.read(terminalPerformanceSettingsProvider).scrollbackLines,
    compactFlutterBuffer: () =>
        ref.read(terminalPerformanceSettingsProvider).rendererMode ==
        TerminalRendererMode.webgl,
    backgroundSessions: ref.watch(backgroundSessionCoordinatorProvider),
  );
  ref.onDispose(registry.dispose);
  return registry;
});

class SessionRegistry {
  SessionRegistry(
    this._gateway,
    this._codec, {
    int Function()? scrollbackLines,
    bool Function()? compactFlutterBuffer,
    this._backgroundSessions,
  }) : _scrollbackLines = scrollbackLines ?? _defaultScrollbackLines,
       _compactFlutterBuffer =
           compactFlutterBuffer ?? _defaultCompactFlutterBuffer;

  final SshGateway _gateway;
  final TerminalCodec _codec;
  final int Function() _scrollbackLines;
  final bool Function() _compactFlutterBuffer;
  final BackgroundSessionCoordinator? _backgroundSessions;
  final Map<String, SshSessionController> _sessions = {};

  SshSessionController open(String tabId, ConnectionProfile profile) {
    return _sessions.putIfAbsent(tabId, () {
      final session = SshSessionController(
        _gateway,
        _codec,
        profile: profile,
        maxLines: _scrollbackLines(),
        compactFlutterBuffer: _compactFlutterBuffer(),
      );
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

  static int _defaultScrollbackLines() => 5000;

  static bool _defaultCompactFlutterBuffer() => false;
}
