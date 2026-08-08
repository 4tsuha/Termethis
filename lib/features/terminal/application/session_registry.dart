import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../infrastructure/ssh/dart_ssh_gateway.dart';
import '../../../infrastructure/ssh/in_memory_host_key_repository.dart';
import '../../../infrastructure/terminal/utf8_terminal_codec.dart';
import '../../connections/domain/connection_profile.dart';
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
  );
  ref.onDispose(registry.dispose);
  return registry;
});

class SessionRegistry {
  SessionRegistry(this._gateway, this._codec);

  final SshGateway _gateway;
  final TerminalCodec _codec;
  final Map<String, SshSessionController> _sessions = {};

  SshSessionController open(ConnectionProfile profile) {
    return _sessions.putIfAbsent(
      profile.id,
      () => SshSessionController(_gateway, _codec, profile: profile),
    );
  }

  void remove(String profileId) {
    _sessions.remove(profileId)?.dispose();
  }

  void dispose() {
    for (final session in _sessions.values) {
      session.dispose();
    }
    _sessions.clear();
  }
}
