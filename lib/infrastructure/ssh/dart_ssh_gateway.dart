import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../../features/terminal/domain/ssh_failure.dart';
import '../../features/terminal/domain/ssh_gateway.dart';

class DartSshGateway implements SshGateway {
  DartSshGateway(this._hostKeys);

  final HostKeyRepository _hostKeys;

  @override
  Future<SshConnection> connect(SshConnectRequest request) async {
    SSHSocket? socket;
    SSHClient? client;
    SshFailure? verificationFailure;

    try {
      final identities = _parseIdentities(request.authentication);
      final (connectedSocket, knownHosts) = await (
        SSHSocket.connect(
          request.profile.host,
          request.profile.port,
          timeout: const Duration(seconds: 15),
        ),
        _hostKeys.find(request.profile.host, request.profile.port),
      ).wait;
      socket = connectedSocket;
      final passwordAuthentication =
          request.authentication is SshPasswordAuthentication
          ? request.authentication as SshPasswordAuthentication
          : null;

      client = SSHClient(
        socket,
        username: request.profile.username,
        handshakeTimeout: const Duration(seconds: 15),
        authTimeout: const Duration(seconds: 20),
        onVerifyHostKey: (algorithm, fingerprintBytes) async {
          final received = HostKeyInfo(
            host: request.profile.host,
            port: request.profile.port,
            algorithm: algorithm,
            fingerprintSha256: utf8.decode(fingerprintBytes),
          );
          final trust = evaluateHostKeyTrust(knownHosts, received);
          if (trust == HostKeyTrust.trusted) {
            request.onAuthenticationStarted();
            return true;
          }
          if (trust == HostKeyTrust.mismatch) {
            verificationFailure = const SshFailure(
              SshFailureCode.hostKeyMismatch,
            );
            return false;
          }

          final accepted = await request.onUnknownHostKey(received);
          if (!accepted) {
            verificationFailure = const SshFailure(
              SshFailureCode.hostKeyRejected,
            );
            return false;
          }

          await _hostKeys.trust(
            KnownHost(info: received, acceptedAt: DateTime.now()),
          );
          request.onAuthenticationStarted();
          return true;
        },
        identities: identities,
        onPasswordRequest: passwordAuthentication != null
            ? () => passwordAuthentication.password
            : null,
        onUserInfoRequest: passwordAuthentication != null
            ? (sshRequest) {
                return request.onInteractivePrompt(
                  InteractiveRequest(
                    name: sshRequest.name,
                    instruction: sshRequest.instruction,
                    prompts: sshRequest.prompts
                        .map(
                          (prompt) => InteractivePrompt(
                            text: prompt.promptText,
                            echo: prompt.echo,
                          ),
                        )
                        .toList(growable: false),
                  ),
                );
              }
            : null,
        onAuthenticated: request.onOpeningPty,
      );

      final session = await client.shell(
        pty: SSHPtyConfig(
          type: 'xterm-256color',
          width: request.terminalWidth,
          height: request.terminalHeight,
        ),
        pipelinePtyAndShellRequests: true,
      );
      return DartSshConnection(client, session);
    } catch (error) {
      client?.close();
      if (client == null && socket != null) {
        await socket.close();
      }
      if (verificationFailure case final failure?) {
        throw failure;
      }
      if (error is SshFailure) {
        rethrow;
      }
      throw _mapFailure(error);
    }
  }

  List<SSHKeyPair>? _parseIdentities(SshAuthentication authentication) {
    if (authentication is! SshPrivateKeyAuthentication) {
      return null;
    }
    try {
      final encrypted = SSHKeyPair.isEncryptedPem(authentication.pem);
      if (encrypted &&
          (authentication.passphrase == null ||
              authentication.passphrase!.isEmpty)) {
        throw const SshFailure(SshFailureCode.keyPassphraseRequired);
      }
      return SSHKeyPair.fromPem(
        authentication.pem,
        encrypted ? authentication.passphrase : null,
      );
    } on SshFailure {
      rethrow;
    } on SSHKeyDecryptError catch (error) {
      throw SshFailure(SshFailureCode.privateKeyInvalid, error);
    } catch (error) {
      throw SshFailure(SshFailureCode.privateKeyInvalid, error);
    }
  }

  SshFailure _mapFailure(Object error) {
    if (error is TimeoutException) {
      return SshFailure(SshFailureCode.connectionTimedOut, error);
    }
    if (error is SocketException) {
      final message = error.message.toLowerCase();
      if (message.contains('failed host lookup') ||
          message.contains('name or service') ||
          message.contains('no address')) {
        return SshFailure(SshFailureCode.dnsLookupFailed, error);
      }
      if (message.contains('refused')) {
        return SshFailure(SshFailureCode.connectionRefused, error);
      }
      if (message.contains('timed out')) {
        return SshFailure(SshFailureCode.connectionTimedOut, error);
      }
      return SshFailure(SshFailureCode.networkLost, error);
    }
    if (error is SSHSocketError) {
      return _mapFailure(error.error);
    }
    if (error is SSHAuthError) {
      return SshFailure(SshFailureCode.authenticationFailed, error);
    }
    if (error is SSHHostkeyError) {
      return SshFailure(SshFailureCode.hostKeyRejected, error);
    }
    if (error is SSHChannelRequestError || error is SSHChannelOpenError) {
      return SshFailure(SshFailureCode.ptyRejected, error);
    }
    return SshFailure(SshFailureCode.unexpected, error);
  }
}

class DartSshConnection implements SshConnection {
  DartSshConnection(this._client, this._session);

  final SSHClient _client;
  final SSHSession _session;
  bool _closed = false;

  @override
  Stream<Uint8List> get stdout => _session.stdout;

  @override
  Stream<Uint8List> get stderr => _session.stderr;

  @override
  Future<void> get done => _client.done;

  @override
  void write(Uint8List data) => _session.write(data);

  @override
  void resize(int width, int height, int pixelWidth, int pixelHeight) {
    _session.resizeTerminal(width, height, pixelWidth, pixelHeight);
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _session.close();
    _client.close();
    try {
      await _client.done.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      return;
    }
  }
}
