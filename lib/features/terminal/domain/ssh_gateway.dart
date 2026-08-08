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

abstract interface class HostKeyRepository {
  Future<KnownHost?> find(String host, int port);
  Future<void> trust(KnownHost host);
  Future<void> remove(String host, int port);
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

class SshConnectRequest {
  const SshConnectRequest({
    required this.profile,
    required this.password,
    required this.onUnknownHostKey,
    required this.onInteractivePrompt,
    required this.onAuthenticationStarted,
    required this.onOpeningPty,
    required this.terminalWidth,
    required this.terminalHeight,
  });

  final ConnectionProfile profile;
  final String password;
  final HostKeyApprovalHandler onUnknownHostKey;
  final InteractivePromptHandler onInteractivePrompt;
  final void Function() onAuthenticationStarted;
  final void Function() onOpeningPty;
  final int terminalWidth;
  final int terminalHeight;
}

abstract interface class SshConnection {
  Stream<Uint8List> get stdout;
  Stream<Uint8List> get stderr;
  Future<void> get done;

  void write(Uint8List data);
  void resize(int width, int height, int pixelWidth, int pixelHeight);
  Future<void> close();
}

abstract interface class SshGateway {
  Future<SshConnection> connect(SshConnectRequest request);
}

abstract interface class TerminalCodec {
  Stream<String> decode(Stream<List<int>> source);
  Uint8List encode(String input);
}
