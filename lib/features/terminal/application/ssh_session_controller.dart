import 'dart:async';
import 'dart:collection';

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

@immutable
class WebTerminalDataEvent {
  const WebTerminalDataEvent({required this.sequence, required this.data});

  final int sequence;
  final String data;
}

@immutable
class WebTerminalReplay {
  const WebTerminalReplay({
    required this.throughSequence,
    required this.data,
    this.resetRequired = false,
  });

  final int throughSequence;
  final String data;
  final bool resetRequired;
}

class _WebTerminalChunk {
  const _WebTerminalChunk(this.sequence, this.data);

  final int sequence;
  final String data;
}

class SshSessionController extends ChangeNotifier {
  SshSessionController(
    this._gateway,
    this._codec, {
    required this.profile,
    int maxLines = 5000,
    bool compactFlutterBuffer = false,
  }) : terminal = Terminal(maxLines: compactFlutterBuffer ? 200 : maxLines),
       _mirrorToFlutterTerminal = !compactFlutterBuffer {
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
  final Set<VoidCallback> _terminalActivityListeners = {};
  final Set<ValueChanged<String>> _terminalDataListeners = {};
  final Set<ValueChanged<WebTerminalDataEvent>> _webTerminalDataListeners = {};
  final Queue<_WebTerminalChunk> _webTerminalDelta = Queue();
  bool _mirrorToFlutterTerminal;

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
  bool _viewportVisible = false;
  Timer? _terminalWriteTimer;
  StringBuffer _pendingTerminalData = StringBuffer();
  int _pendingTerminalLength = 0;
  int _webTerminalSequence = 0;
  int _webTerminalDeltaLength = 0;
  int _webTerminalSnapshotSequence = 0;
  String _webTerminalSnapshot = '';
  bool _webTerminalDeltaTruncated = false;

  static const _visibleWriteInterval = Duration(milliseconds: 8);
  static const _hiddenWriteInterval = Duration(milliseconds: 16);
  static const _maximumBufferedCharacters = 64 * 1024;
  static const _maximumWebTerminalDeltaCharacters = 1024 * 1024;
  static const _maximumWebTerminalSnapshotCharacters = 4 * 1024 * 1024;

  bool get isConnected => status == SshSessionStatus.connected;

  void reportFailure(SshFailure value) {
    failure = value;
    _setStatus(SshSessionStatus.failed);
  }

  Future<void> connect({
    required SshAuthentication authentication,
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
          authentication: authentication,
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
          .listen(_queueTerminalWrite, onError: _handleStreamError);
      _stderrSubscription = _codec
          .decode(connection.stderr.cast<List<int>>())
          .listen(_queueTerminalWrite, onError: _handleStreamError);
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

  void addTerminalActivityListener(VoidCallback listener) {
    _terminalActivityListeners.add(listener);
  }

  void removeTerminalActivityListener(VoidCallback listener) {
    _terminalActivityListeners.remove(listener);
  }

  void addTerminalDataListener(ValueChanged<String> listener) {
    _terminalDataListeners.add(listener);
  }

  void removeTerminalDataListener(ValueChanged<String> listener) {
    _terminalDataListeners.remove(listener);
  }

  void addWebTerminalDataListener(ValueChanged<WebTerminalDataEvent> listener) {
    _webTerminalDataListeners.add(listener);
  }

  void removeWebTerminalDataListener(
    ValueChanged<WebTerminalDataEvent> listener,
  ) {
    _webTerminalDataListeners.remove(listener);
  }

  WebTerminalReplay get webTerminalReplay {
    final output = StringBuffer();
    if (_webTerminalDeltaTruncated) output.write('\x1bc');
    output.write(_webTerminalSnapshot);
    for (final chunk in _webTerminalDelta) {
      output.write(chunk.data);
    }
    return WebTerminalReplay(
      throughSequence: _webTerminalSequence,
      data: output.toString(),
      resetRequired: _webTerminalDeltaTruncated,
    );
  }

  WebTerminalReplay webTerminalReplayAfter(int sequence) {
    if (sequence < _webTerminalSnapshotSequence ||
        (_webTerminalDeltaTruncated &&
            (_webTerminalDelta.isEmpty ||
                sequence < _webTerminalDelta.first.sequence - 1))) {
      final replay = webTerminalReplay;
      return WebTerminalReplay(
        throughSequence: replay.throughSequence,
        data: replay.data,
        resetRequired: true,
      );
    }

    final output = StringBuffer();
    for (final chunk in _webTerminalDelta) {
      if (chunk.sequence > sequence) output.write(chunk.data);
    }
    return WebTerminalReplay(
      throughSequence: _webTerminalSequence,
      data: output.toString(),
    );
  }

  bool saveWebTerminalSnapshot(String snapshot, int throughSequence) {
    if (snapshot.length > _maximumWebTerminalSnapshotCharacters ||
        throughSequence < _webTerminalSnapshotSequence ||
        throughSequence > _webTerminalSequence) {
      return false;
    }

    _webTerminalSnapshot = snapshot;
    _webTerminalSnapshotSequence = throughSequence;
    while (_webTerminalDelta.isNotEmpty &&
        _webTerminalDelta.first.sequence <= throughSequence) {
      _webTerminalDeltaLength -= _webTerminalDelta.removeFirst().data.length;
    }
    _webTerminalDeltaTruncated = false;
    return true;
  }

  void sendInput(String data) => _handleTerminalOutput(data);

  void resizeTerminal(int width, int height) {
    _handleResize(width, height, 0, 0);
  }

  void setViewportVisible(bool visible) {
    _viewportVisible = visible;
  }

  void enableFlutterTerminalMirror() {
    if (_mirrorToFlutterTerminal || _disposed) return;
    _mirrorToFlutterTerminal = true;
    terminal.write('\x1bc${webTerminalReplay.data}');
  }

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
    _flushTerminalWrites();
    await connection?.close();
  }

  void _queueTerminalWrite(String data) {
    if (data.isEmpty || _disposed) return;
    _pendingTerminalData.write(data);
    _pendingTerminalLength += data.length;
    if (_pendingTerminalLength >= _maximumBufferedCharacters) {
      _flushTerminalWrites();
      return;
    }
    final interval = _viewportVisible
        ? _visibleWriteInterval
        : _hiddenWriteInterval;
    _terminalWriteTimer ??= Timer(interval, _flushTerminalWrites);
  }

  void _flushTerminalWrites() {
    _terminalWriteTimer?.cancel();
    _terminalWriteTimer = null;
    if (_pendingTerminalLength == 0 || _disposed) return;
    final data = _pendingTerminalData.toString();
    _pendingTerminalData = StringBuffer();
    _pendingTerminalLength = 0;
    if (_mirrorToFlutterTerminal) terminal.write(data);
    final event = WebTerminalDataEvent(
      sequence: ++_webTerminalSequence,
      data: data,
    );
    _appendWebTerminalDelta(event);
    for (final listener in List<ValueChanged<String>>.of(
      _terminalDataListeners,
    )) {
      listener(data);
    }
    for (final listener in List<ValueChanged<WebTerminalDataEvent>>.of(
      _webTerminalDataListeners,
    )) {
      listener(event);
    }
    _reportTerminalActivity();
  }

  void _appendWebTerminalDelta(WebTerminalDataEvent event) {
    var data = event.data;
    if (data.length > _maximumWebTerminalDeltaCharacters) {
      var start = data.length - _maximumWebTerminalDeltaCharacters;
      if (start > 0 &&
          _isLowSurrogate(data.codeUnitAt(start)) &&
          _isHighSurrogate(data.codeUnitAt(start - 1))) {
        start--;
      }
      data = data.substring(start);
      _webTerminalDelta.clear();
      _webTerminalDeltaLength = 0;
      _webTerminalDeltaTruncated = true;
    }
    _webTerminalDelta.addLast(_WebTerminalChunk(event.sequence, data));
    _webTerminalDeltaLength += data.length;
    while (_webTerminalDeltaLength > _maximumWebTerminalDeltaCharacters &&
        _webTerminalDelta.isNotEmpty) {
      _webTerminalDeltaLength -= _webTerminalDelta.removeFirst().data.length;
      _webTerminalDeltaTruncated = true;
    }
  }

  static bool _isHighSurrogate(int value) => value >= 0xD800 && value <= 0xDBFF;

  static bool _isLowSurrogate(int value) => value >= 0xDC00 && value <= 0xDFFF;

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
    _reportTerminalActivity();
    connection.write(_codec.encode(output));
  }

  void _reportTerminalActivity() {
    for (final listener in List<VoidCallback>.of(_terminalActivityListeners)) {
      listener();
    }
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
    _flushTerminalWrites();
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
    _terminalWriteTimer?.cancel();
    _terminalWriteTimer = null;
    _terminalActivityListeners.clear();
    _terminalDataListeners.clear();
    _webTerminalDataListeners.clear();
    _webTerminalDelta.clear();
    _webTerminalDeltaLength = 0;
    _webTerminalSnapshot = '';
    terminal.onOutput = null;
    terminal.onResize = null;
    terminal.onTitleChange = null;
    unawaited(_stdoutSubscription?.cancel());
    unawaited(_stderrSubscription?.cancel());
    unawaited(_connection?.close());
    super.dispose();
  }
}
