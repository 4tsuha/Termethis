import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

import '../../connections/domain/connection_profile.dart';
import '../domain/ssh_failure.dart';
import '../domain/ssh_gateway.dart';

enum SshSessionStatus {
  idle,
  connecting,
  verifyingHost,
  authenticating,
  openingPty,
  connected,
  reconnectPrompt,
  closing,
  closed,
  failed,
}

class SshSessionController extends ChangeNotifier {
  SshSessionController(this._gateway, this._codec, {required this.profile})
    : terminal = Terminal(maxLines: 10000) {
    terminal.onOutput = _handleTerminalOutput;
    terminal.onResize = _handleResize;
    terminal.onTitleChange = (value) {
      title = value.isEmpty ? profile.name : value;
      _notify();
    };
  }

  final ConnectionProfile profile;
  final SshGateway _gateway;
  final TerminalCodec _codec;
  final Terminal terminal;

  SshSessionStatus status = SshSessionStatus.idle;
  SshFailure? failure;
  late String title = profile.name;
  bool controlArmed = false;
  bool altArmed = false;

  SshConnection? _connection;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  bool _closing = false;
  bool _disposed = false;

  bool get isConnected => status == SshSessionStatus.connected;

  Future<void> connect({
    required String password,
    required HostKeyApprovalHandler onUnknownHostKey,
    required InteractivePromptHandler onInteractivePrompt,
  }) async {
    if ({
      SshSessionStatus.connecting,
      SshSessionStatus.verifyingHost,
      SshSessionStatus.authenticating,
      SshSessionStatus.openingPty,
      SshSessionStatus.connected,
      SshSessionStatus.closing,
    }.contains(status)) {
      return;
    }

    _closing = true;
    await _releaseConnection();
    _closing = false;
    failure = null;
    _setStatus(SshSessionStatus.connecting);

    try {
      final connection = await _gateway.connect(
        SshConnectRequest(
          profile: profile,
          password: password,
          onUnknownHostKey: (info) async {
            _setStatus(SshSessionStatus.verifyingHost);
            return onUnknownHostKey(info);
          },
          onInteractivePrompt: onInteractivePrompt,
          onAuthenticationStarted: () {
            _setStatus(SshSessionStatus.authenticating);
          },
          onOpeningPty: () {
            _setStatus(SshSessionStatus.openingPty);
          },
          terminalWidth: terminal.viewWidth,
          terminalHeight: terminal.viewHeight,
        ),
      );
      if (_closing || _disposed) {
        await connection.close();
        return;
      }

      _connection = connection;
      _stdoutSubscription = _codec
          .decode(connection.stdout.cast<List<int>>())
          .listen(terminal.write, onError: _handleStreamError);
      _stderrSubscription = _codec
          .decode(connection.stderr.cast<List<int>>())
          .listen(terminal.write, onError: _handleStreamError);
      unawaited(
        connection.done.then(
          (_) => _handleRemoteDone(),
          onError: (Object error, StackTrace stackTrace) {
            _handleStreamError(error, stackTrace);
          },
        ),
      );
      _setStatus(SshSessionStatus.connected);
    } on SshFailure catch (error) {
      failure = error;
      _setStatus(SshSessionStatus.failed);
    } catch (error) {
      failure = SshFailure(SshFailureCode.unexpected, error);
      _setStatus(SshSessionStatus.failed);
    }
  }

  void toggleControl() {
    controlArmed = !controlArmed;
    _notify();
  }

  void toggleAlt() {
    altArmed = !altArmed;
    _notify();
  }

  void sendKey(TerminalKey key) {
    final control = controlArmed;
    final alt = altArmed;
    _clearModifiers();
    terminal.keyInput(key, ctrl: control, alt: alt);
  }

  void paste(String text) => terminal.paste(text);

  Future<void> disconnect() async {
    if (_closing || status == SshSessionStatus.closed) {
      return;
    }
    _closing = true;
    _setStatus(SshSessionStatus.closing);

    await _releaseConnection();
    _setStatus(SshSessionStatus.closed);
  }

  Future<void> _releaseConnection() async {
    final connection = _connection;
    _connection = null;
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription = null;
    await connection?.close();
  }

  void _handleTerminalOutput(String data) {
    final connection = _connection;
    if (connection == null || status != SshSessionStatus.connected) {
      return;
    }

    var output = data;
    final runes = data.runes.toList(growable: false);
    if (controlArmed && runes.length == 1) {
      var value = runes.single;
      if (value >= 65 && value <= 90) {
        value += 32;
      }
      if (value >= 97 && value <= 122) {
        output = String.fromCharCode(value - 96);
      }
    }
    if (altArmed) {
      output = '\x1b$output';
    }
    _clearModifiers();
    connection.write(_codec.encode(output));
  }

  void _handleResize(int width, int height, int pixelWidth, int pixelHeight) {
    if (status == SshSessionStatus.connected) {
      _connection?.resize(width, height, pixelWidth, pixelHeight);
    }
  }

  void _handleStreamError(Object error, StackTrace stackTrace) {
    if (_closing || _disposed) {
      return;
    }
    failure = SshFailure(SshFailureCode.networkLost, error);
    _setStatus(SshSessionStatus.reconnectPrompt);
  }

  void _handleRemoteDone() {
    if (_closing || _disposed) {
      return;
    }
    failure = const SshFailure(SshFailureCode.remoteClosed);
    _setStatus(SshSessionStatus.reconnectPrompt);
  }

  void _clearModifiers() {
    final changed = controlArmed || altArmed;
    controlArmed = false;
    altArmed = false;
    if (changed) {
      _notify();
    }
  }

  void _setStatus(SshSessionStatus next) {
    status = next;
    _notify();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _closing = true;
    terminal.onOutput = null;
    terminal.onResize = null;
    terminal.onTitleChange = null;
    unawaited(_stdoutSubscription?.cancel());
    unawaited(_stderrSubscription?.cancel());
    unawaited(_connection?.close());
    super.dispose();
  }
}
