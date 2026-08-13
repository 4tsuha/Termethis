import 'dart:async';
import 'dart:typed_data';

import '../../features/terminal/domain/ssh_failure.dart';
import '../../features/terminal/domain/ssh_gateway.dart';
import '../../src/rust/api/core.dart' as rust;

typedef RustConnect =
    Future<rust.RustSshConnectResult> Function({
      required rust.RustSshConnectRequest request,
    });
typedef RustContinueHostKey =
    Future<rust.RustSshConnectResult> Function({
      required int pendingHostKeyId,
      required bool approved,
    });
typedef RustConnectionFactory = SshConnection Function(int sessionId);

class RustSshGateway implements SshGateway {
  RustSshGateway(
    this._hostKeys, {
    RustConnect connect = rust.sshConnect,
    RustContinueHostKey continueHostKey = rust.sshContinueHostKey,
    this._connectionFactory = RustSshConnection.new,
  }) : _rustConnect = connect,
       _rustContinueHostKey = continueHostKey;

  final HostKeyRepository _hostKeys;
  final RustConnect _rustConnect;
  final RustContinueHostKey _rustContinueHostKey;
  final RustConnectionFactory _connectionFactory;

  @override
  Future<SshConnection> connect(SshConnectRequest request) async {
    final knownHosts = await _hostKeys.find(
      request.profile.host,
      request.profile.port,
    );
    var trustedKeys = _trustedKeyIdentities(knownHosts);
    if (trustedKeys.isNotEmpty) request.onAuthenticationStarted();

    var result = await _connect(request, trustedKeys);
    if (result.hostKey case final receivedKey?) {
      final jumpIndex = _jumpHostIndex(result.errorCode);
      if (jumpIndex != null && jumpIndex < request.jumpHosts.length) {
        final jump = request.jumpHosts[jumpIndex].profile;
        final received = HostKeyInfo(
          host: jump.host,
          port: jump.port,
          algorithm: receivedKey.algorithm,
          fingerprintSha256: receivedKey.fingerprintSha256,
        );
        final knownJumpHosts = await _hostKeys.find(jump.host, jump.port);
        if (evaluateHostKeyTrust(knownJumpHosts, received) ==
            HostKeyTrust.mismatch) {
          throw const SshFailure(SshFailureCode.jumpHostKeyRejected);
        }
        if (!await request.onUnknownHostKey(received)) {
          throw const SshFailure(SshFailureCode.jumpHostKeyRejected);
        }
        await _hostKeys.trust(
          KnownHost(info: received, acceptedAt: DateTime.now()),
        );
        result = await _connect(request, trustedKeys);
      }
    }
    if (result.hostKey case final receivedKey?) {
      final received = HostKeyInfo(
        host: request.profile.host,
        port: request.profile.port,
        algorithm: receivedKey.algorithm,
        fingerprintSha256: receivedKey.fingerprintSha256,
      );
      switch (evaluateHostKeyTrust(knownHosts, received)) {
        case HostKeyTrust.mismatch:
          throw const SshFailure(SshFailureCode.hostKeyMismatch);
        case HostKeyTrust.trusted:
          throw const SshFailure(SshFailureCode.hostKeyRejected);
        case HostKeyTrust.unknown:
          final pendingHostKeyId = result.pendingHostKeyId;
          var approved = false;
          try {
            final userApproved = await request.onUnknownHostKey(received);
            if (userApproved) {
              await _hostKeys.trust(
                KnownHost(info: received, acceptedAt: DateTime.now()),
              );
              approved = true;
              request.onAuthenticationStarted();
            }
          } finally {
            if (pendingHostKeyId != null) {
              result = await _rustContinueHostKey(
                pendingHostKeyId: pendingHostKeyId,
                approved: approved,
              );
            }
          }
          if (!approved) {
            throw const SshFailure(SshFailureCode.hostKeyRejected);
          }
          if (pendingHostKeyId == null) {
            trustedKeys = [_hostKeyIdentity(received)];
            result = await _connect(request, trustedKeys);
          }
      }
    }

    while (true) {
      final challenge = result.challenge;
      if (challenge == null) break;
      final pendingId = result.pendingAuthId;
      if (pendingId == null) {
        throw const SshFailure(SshFailureCode.authenticationFailed);
      }
      final responses = await request.onInteractivePrompt(
        InteractiveRequest(
          name: challenge.name,
          instruction: challenge.instruction,
          prompts: [
            for (final prompt in challenge.prompts)
              InteractivePrompt(text: prompt.text, echo: prompt.echo),
          ],
        ),
      );
      if (responses == null) {
        throw const SshFailure(SshFailureCode.authenticationFailed);
      }
      result = await rust.sshContinueAuthentication(
        pendingAuthId: pendingId,
        responses: responses,
      );
    }

    if (result.errorCode != null || result.sessionId == null) {
      throw _mapRustFailure(result.errorCode, result.errorMessage);
    }
    request.onOpeningPty();
    return _connectionFactory(result.sessionId!);
  }

  Future<rust.RustSshConnectResult> _connect(
    SshConnectRequest request,
    List<String> trustedKeys,
  ) async {
    final authentication = request.authentication;
    return _rustConnect(
      request: rust.RustSshConnectRequest(
        host: request.profile.host,
        port: request.profile.port,
        username: request.profile.username,
        authKind: authentication is SshPrivateKeyAuthentication
            ? 'private_key'
            : 'password',
        password: authentication is SshPasswordAuthentication
            ? authentication.password
            : '',
        privateKeyPem: authentication is SshPrivateKeyAuthentication
            ? authentication.pem
            : '',
        passphrase: authentication is SshPrivateKeyAuthentication
            ? authentication.passphrase
            : null,
        trustedHostKeys: trustedKeys,
        terminalWidth: request.terminalWidth,
        terminalHeight: request.terminalHeight,
        jumpHosts: await Future.wait([
          for (final jump in request.jumpHosts) _jumpHost(jump),
        ]),
      ),
    );
  }

  Future<rust.RustSshJumpHost> _jumpHost(SshJumpHost jump) async {
    final knownHosts = await _hostKeys.find(
      jump.profile.host,
      jump.profile.port,
    );
    final authentication = jump.authentication;
    return rust.RustSshJumpHost(
      host: jump.profile.host,
      port: jump.profile.port,
      username: jump.profile.username,
      authKind: authentication is SshPrivateKeyAuthentication
          ? 'private_key'
          : 'password',
      password: authentication is SshPasswordAuthentication
          ? authentication.password
          : '',
      privateKeyPem: authentication is SshPrivateKeyAuthentication
          ? authentication.pem
          : '',
      passphrase: authentication is SshPrivateKeyAuthentication
          ? authentication.passphrase
          : null,
      trustedHostKeys: _trustedKeyIdentities(knownHosts),
    );
  }
}

int? _jumpHostIndex(String? errorCode) {
  if (errorCode == null || !errorCode.startsWith('jump_host_key_rejected:')) {
    return null;
  }
  return int.tryParse(errorCode.substring(errorCode.lastIndexOf(':') + 1));
}

class RustSshConnection implements TunnelCapableSshConnection {
  RustSshConnection(this._sessionId) {
    _stdout = StreamController<Uint8List>(
      onPause: () => _setConsumerPaused(stdout: true),
      onResume: () => _setConsumerPaused(stdout: false),
      onCancel: () => _setConsumerPaused(stdout: false),
    );
    _stderr = StreamController<Uint8List>(
      onPause: () => _setConsumerPaused(stderr: true),
      onResume: () => _setConsumerPaused(stderr: false),
      onCancel: () => _setConsumerPaused(stderr: false),
    );
    _pumpFuture = _pump();
  }

  final int _sessionId;
  late final StreamController<Uint8List> _stdout;
  late final StreamController<Uint8List> _stderr;
  final _done = Completer<void>();
  late final Future<void> _pumpFuture;
  Future<void> _writeChain = Future<void>.value();
  Completer<void>? _consumerResumed;
  bool _stdoutPaused = false;
  bool _stderrPaused = false;
  bool _closing = false;
  final Set<int> _tunnelIds = {};

  @override
  Stream<Uint8List> get stdout => _stdout.stream;

  @override
  Stream<Uint8List> get stderr => _stderr.stream;

  @override
  Future<void> get done => _done.future;

  @override
  void write(Uint8List data) {
    if (_closing || data.isEmpty) return;
    final packet = Uint8List.fromList(data);
    _writeChain = _writeChain
        .then((_) {
          return rust.sshWrite(sessionId: _sessionId, data: packet);
        })
        .catchError(_reportAsyncError);
  }

  @override
  void resize(int width, int height, int pixelWidth, int pixelHeight) {
    if (_closing) return;
    unawaited(
      rust
          .sshResize(
            sessionId: _sessionId,
            width: width,
            height: height,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
          )
          .catchError(_reportAsyncError),
    );
  }

  @override
  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    for (final tunnelId in _tunnelIds.toList(growable: false)) {
      await rust.sshStopTunnel(tunnelId: tunnelId);
    }
    _tunnelIds.clear();
    await _writeChain;
    _setConsumerPaused(stdout: false, stderr: false);
    await rust.sshClose(sessionId: _sessionId);
    await _pumpFuture;
  }

  @override
  Future<SshTunnelStatus> startTunnel(SshTunnelRequest request) async {
    final status = await rust.sshStartTunnel(
      request: rust.RustSshTunnelStartRequest(
        sessionId: _sessionId,
        kind: request.kind.name,
        bindHost: request.bindHost,
        bindPort: request.bindPort,
        targetHost: request.targetHost,
        targetPort: request.targetPort,
        allowLan: request.allowLan,
      ),
    );
    _tunnelIds.add(status.tunnelId);
    return _tunnelStatus(status);
  }

  @override
  Future<SshTunnelStatus> tunnelStatus(int tunnelId) async =>
      _tunnelStatus(await rust.sshTunnelStatus(tunnelId: tunnelId));

  @override
  Future<void> stopTunnel(int tunnelId) async {
    await rust.sshStopTunnel(tunnelId: tunnelId);
    _tunnelIds.remove(tunnelId);
  }

  SshTunnelStatus _tunnelStatus(rust.RustSshTunnelStatus status) =>
      SshTunnelStatus(
        id: status.tunnelId,
        kind: SshTunnelKind.values.firstWhere(
          (value) => value.name == status.kind,
        ),
        bindHost: status.bindHost,
        bindPort: status.bindPort,
        bytesUp: status.bytesUp.toInt(),
        bytesDown: status.bytesDown.toInt(),
        active: status.active,
        errorMessage: status.errorMessage,
      );

  Future<void> _pump() async {
    Object? terminalError;
    try {
      while (!_closing) {
        await _waitForConsumers();
        if (_closing) break;
        final output = await rust.sshRead(
          sessionId: _sessionId,
          maxBytes: 128 * 1024,
          waitMillis: 250,
        );
        if (output.stdout.isNotEmpty) _stdout.add(output.stdout);
        if (output.stderr.isNotEmpty) _stderr.add(output.stderr);
        if (output.errorMessage case final message?) {
          terminalError = StateError(message);
          break;
        }
        if (output.closed) break;
      }
    } catch (error, stackTrace) {
      if (!_closing) {
        terminalError = error;
        _stdout.addError(error, stackTrace);
        _stderr.addError(error, stackTrace);
      }
    } finally {
      await _stdout.close();
      await _stderr.close();
      if (!_done.isCompleted) {
        if (terminalError == null || _closing) {
          _done.complete();
        } else {
          _done.completeError(terminalError);
        }
      }
    }
  }

  Future<void> _reportAsyncError(Object error) async {
    if (!_closing) {
      _stdout.addError(error);
      _stderr.addError(error);
    }
  }

  void _setConsumerPaused({bool? stdout, bool? stderr}) {
    if (stdout != null) _stdoutPaused = stdout;
    if (stderr != null) _stderrPaused = stderr;
    if (!_stdoutPaused && !_stderrPaused) {
      final resumed = _consumerResumed;
      _consumerResumed = null;
      if (resumed != null && !resumed.isCompleted) resumed.complete();
    }
  }

  Future<void> _waitForConsumers() {
    if (!_stdoutPaused && !_stderrPaused) return Future<void>.value();
    return (_consumerResumed ??= Completer<void>()).future;
  }
}

List<String> _trustedKeyIdentities(List<KnownHost> knownHosts) => [
  for (final host in knownHosts) _hostKeyIdentity(host.info),
];

String _hostKeyIdentity(HostKeyInfo key) =>
    '${key.algorithm}|${key.fingerprintSha256}';

SshFailure _mapRustFailure(String? code, String? message) {
  final detail = message == null ? null : StateError(message);
  if (code == 'authentication_failed') {
    return SshFailure(SshFailureCode.authenticationFailed, detail);
  }
  if (code?.startsWith('jump_host_key_rejected:') == true) {
    return SshFailure(SshFailureCode.jumpHostKeyRejected, detail);
  }
  if (code?.startsWith('jump_host_authentication_failed:') == true) {
    return SshFailure(SshFailureCode.jumpHostAuthenticationFailed, detail);
  }
  if (code?.startsWith('jump_host_connection_failed:') == true) {
    return SshFailure(SshFailureCode.jumpHostConnectionFailed, detail);
  }
  final normalized = message?.toLowerCase() ?? '';
  if (normalized.contains('timed out')) {
    return SshFailure(SshFailureCode.connectionTimedOut, detail);
  }
  if (normalized.contains('refused')) {
    return SshFailure(SshFailureCode.connectionRefused, detail);
  }
  if (normalized.contains('lookup') || normalized.contains('name or service')) {
    return SshFailure(SshFailureCode.dnsLookupFailed, detail);
  }
  if (normalized.contains('pty')) {
    return SshFailure(SshFailureCode.ptyRejected, detail);
  }
  return SshFailure(SshFailureCode.networkLost, detail);
}
