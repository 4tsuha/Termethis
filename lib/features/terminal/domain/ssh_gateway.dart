import 'dart:typed_data';

import '../../connections/domain/connection_profile.dart';

class HostKeyInfo {
  const HostKeyInfo({
    required this.host,
    required this.port,
    required this.algorithm,
    required this.fingerprintSha256,
  });

  final String host;
  final int port;
  final String algorithm;
  final String fingerprintSha256;
}

class KnownHost {
  const KnownHost({required this.info, required this.acceptedAt});

  final HostKeyInfo info;
  final DateTime acceptedAt;
}

enum HostKeyTrust { unknown, trusted, mismatch }

HostKeyTrust evaluateHostKeyTrust(
  List<KnownHost> knownHosts,
  HostKeyInfo received,
) {
  if (knownHosts.isEmpty) {
    return HostKeyTrust.unknown;
  }
  final matches = knownHosts.any(
    (knownHost) =>
        knownHost.info.algorithm == received.algorithm &&
        knownHost.info.fingerprintSha256 == received.fingerprintSha256,
  );
  return matches ? HostKeyTrust.trusted : HostKeyTrust.mismatch;
}

abstract interface class HostKeyRepository {
  Future<List<KnownHost>> listAll();
  Future<List<KnownHost>> find(String host, int port);
  Future<void> trust(KnownHost host);
  Future<void> remove(String host, int port);
}

String normalizeSshHost(String host) {
  var normalized = host.trim().toLowerCase();
  while (normalized.endsWith('.')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

class InteractivePrompt {
  const InteractivePrompt({required this.text, required this.echo});

  final String text;
  final bool echo;
}

class InteractiveRequest {
  const InteractiveRequest({
    required this.name,
    required this.instruction,
    required this.prompts,
  });

  final String name;
  final String instruction;
  final List<InteractivePrompt> prompts;
}

typedef HostKeyApprovalHandler = Future<bool> Function(HostKeyInfo info);
typedef InteractivePromptHandler =
    Future<List<String>?> Function(InteractiveRequest request);

sealed class SshAuthentication {
  const SshAuthentication();
}

class SshPasswordAuthentication extends SshAuthentication {
  const SshPasswordAuthentication(this.password);

  final String password;
}

class SshPrivateKeyAuthentication extends SshAuthentication {
  const SshPrivateKeyAuthentication({required this.pem, this.passphrase});

  final String pem;
  final String? passphrase;
}

class SshConnectRequest {
  const SshConnectRequest({
    required this.profile,
    required this.authentication,
    required this.onUnknownHostKey,
    required this.onInteractivePrompt,
    required this.onAuthenticationStarted,
    required this.onOpeningPty,
    required this.terminalWidth,
    required this.terminalHeight,
    this.jumpHosts = const [],
  });

  final ConnectionProfile profile;
  final SshAuthentication authentication;
  final HostKeyApprovalHandler onUnknownHostKey;
  final InteractivePromptHandler onInteractivePrompt;
  final void Function() onAuthenticationStarted;
  final void Function() onOpeningPty;
  final int terminalWidth;
  final int terminalHeight;
  final List<SshJumpHost> jumpHosts;
}

class SshJumpHost {
  const SshJumpHost({required this.profile, required this.authentication});

  final ConnectionProfile profile;
  final SshAuthentication authentication;
}

abstract interface class SshConnection {
  Stream<Uint8List> get stdout;
  Stream<Uint8List> get stderr;
  Future<void> get done;

  void write(Uint8List data);
  void resize(int width, int height, int pixelWidth, int pixelHeight);
  Future<void> close();
}

enum SshTunnelKind { local, remote, socks5 }

class SshTunnelRequest {
  const SshTunnelRequest({
    required this.kind,
    this.bindHost = '127.0.0.1',
    required this.bindPort,
    this.targetHost = '',
    this.targetPort = 0,
    this.allowLan = false,
  });

  final SshTunnelKind kind;
  final String bindHost;
  final int bindPort;
  final String targetHost;
  final int targetPort;
  final bool allowLan;
}

class SshTunnelStatus {
  const SshTunnelStatus({
    required this.id,
    required this.kind,
    required this.bindHost,
    required this.bindPort,
    required this.bytesUp,
    required this.bytesDown,
    required this.active,
    this.errorMessage,
  });

  final int id;
  final SshTunnelKind kind;
  final String bindHost;
  final int bindPort;
  final int bytesUp;
  final int bytesDown;
  final bool active;
  final String? errorMessage;
}

abstract interface class TunnelCapableSshConnection implements SshConnection {
  Future<SshTunnelStatus> startTunnel(SshTunnelRequest request);
  Future<SshTunnelStatus> tunnelStatus(int tunnelId);
  Future<void> stopTunnel(int tunnelId);
}

abstract interface class SshGateway {
  Future<SshConnection> connect(SshConnectRequest request);
}

abstract interface class TerminalCodec {
  Stream<String> decode(Stream<List<int>> source);
  Uint8List encode(String input);
}
