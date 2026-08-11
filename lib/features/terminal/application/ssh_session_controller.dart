import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

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
  final Uint8List data;
}

@immutable
class WebTerminalReplay {
  const WebTerminalReplay({
    required this.throughSequence,
    required this.data,
    this.resetRequired = false,
  });

  final int throughSequence;
  final Uint8List data;
  final bool resetRequired;
}

class _WebTerminalChunk {
  const _WebTerminalChunk(this.sequence, this.data);

  final int sequence;
  final Uint8List data;
}

class SshSessionController extends ChangeNotifier {
  SshSessionController(this._gateway, this._codec, {required this.profile})
    : terminal = Terminal(maxLines: 50) {
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

  SshSessionStatus status = SshSessionStatus.idle;
  SshFailure? failure;
  late String title = profile.name;
  bool controlArmed = false;
  bool altArmed = false;

  SshConnection? _connection;
  StreamSubscription<Uint8List>? _stdoutSubscription;
  StreamSubscription<Uint8List>? _stderrSubscription;
  bool _closing = false;
  bool _disposed = false;
  bool _viewportVisible = false;
  Timer? _terminalWriteTimer;
  BytesBuilder _pendingTerminalData = BytesBuilder(copy: false);
  int _pendingTerminalLength = 0;
  int _webTerminalSequence = 0;
  int _webTerminalDeltaLength = 0;
  int _webTerminalSnapshotSequence = 0;
  Uint8List _webTerminalSnapshot = Uint8List(0);
  bool _webTerminalDeltaTruncated = false;
  bool _rendererOutputBackpressured = false;
  bool _outputSubscriptionsPaused = false;

  static const _visibleWriteInterval = Duration(milliseconds: 8);
  static const _hiddenWriteInterval = Duration(milliseconds: 32);
  static const _maximumBufferedBytes = 128 * 1024;
  static const _webTerminalCheckpointBytes = 1024 * 1024;
  static const _maximumWebTerminalDeltaBytes = 2 * 1024 * 1024;
  static const _maximumWebTerminalSnapshotBytes = 8 * 1024 * 1024;

  bool get isConnected => status == SshSessionStatus.connected;

  bool get webTerminalCheckpointNeeded =>
      _webTerminalDeltaLength >= _webTerminalCheckpointBytes;

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
      _stdoutSubscription = connection.stdout.listen(
        _queueTerminalWrite,
        onError: _handleStreamError,
      );
      _stderrSubscription = connection.stderr.listen(
        _queueTerminalWrite,
        onError: _handleStreamError,
      );
      _applyOutputBackpressure();
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
    final modifiers = consumeArmedModifiers();
    sendKeyWithModifiers(key, control: modifiers.control, alt: modifiers.alt);
  }

  void sendKeyWithModifiers(
    TerminalKey key, {
    required bool control,
    required bool alt,
  }) {
    terminal.keyInput(key, ctrl: control, alt: alt);
  }

  ({bool control, bool alt}) consumeArmedModifiers() {
    final modifiers = (control: controlArmed, alt: altArmed);
    _clearModifiers();
    return modifiers;
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
    final output = BytesBuilder(copy: false);
    if (_webTerminalDeltaTruncated) output.add(const [0x1b, 0x63]);
    output.add(_webTerminalSnapshot);
    for (final chunk in _webTerminalDelta) {
      output.add(chunk.data);
    }
    return WebTerminalReplay(
      throughSequence: _webTerminalSequence,
      data: output.takeBytes(),
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

    final output = BytesBuilder(copy: false);
    for (final chunk in _webTerminalDelta) {
      if (chunk.sequence > sequence) output.add(chunk.data);
    }
    return WebTerminalReplay(
      throughSequence: _webTerminalSequence,
      data: output.takeBytes(),
    );
  }

  bool saveWebTerminalSnapshot(String snapshot, int throughSequence) {
    final encoded = utf8.encode(snapshot);
    if (encoded.length > _maximumWebTerminalSnapshotBytes ||
        throughSequence < _webTerminalSnapshotSequence ||
        throughSequence > _webTerminalSequence) {
      return false;
    }

    _webTerminalSnapshot = Uint8List.fromList(encoded);
    _webTerminalSnapshotSequence = throughSequence;
    while (_webTerminalDelta.isNotEmpty &&
        _webTerminalDelta.first.sequence <= throughSequence) {
      _webTerminalDeltaLength -= _webTerminalDelta.removeFirst().data.length;
    }
    _webTerminalDeltaTruncated = false;
    return true;
  }

  void sendInput(String data) => _handleTerminalOutput(data);

  void sendInputDirect(String data) {
    final connection = _connection;
    if (connection == null || status != SshSessionStatus.connected) return;
    _reportTerminalActivity();
    connection.write(_codec.encode(data));
  }

  void sendInputBytes(Uint8List data) {
    final connection = _connection;
    if (connection == null || status != SshSessionStatus.connected) return;
    var output = data;
    if (controlArmed && data.length == 1) {
      var value = data.single;
      if (value >= 65 && value <= 90) value += 32;
      if (value >= 97 && value <= 122) {
        output = Uint8List.fromList([value - 96]);
      }
    }
    if (altArmed) {
      output = Uint8List.fromList([0x1b, ...output]);
    }
    _clearModifiers();
    _reportTerminalActivity();
    connection.write(output);
  }

  void sendInputBytesDirect(Uint8List data) {
    final connection = _connection;
    if (connection == null || status != SshSessionStatus.connected) return;
    _reportTerminalActivity();
    connection.write(data);
  }

  void resizeTerminal(int width, int height) {
    _handleResize(width, height, 0, 0);
  }

  void setViewportVisible(bool visible) {
    _viewportVisible = visible;
  }

  void setOutputBackpressure(bool paused) {
    if (_disposed) return;
    if (_rendererOutputBackpressured == paused) return;
    _rendererOutputBackpressured = paused;
    _applyOutputBackpressure();
  }

  void _applyOutputBackpressure() {
    final shouldPause = _rendererOutputBackpressured;
    if (_outputSubscriptionsPaused == shouldPause) return;
    _outputSubscriptionsPaused = shouldPause;
    if (shouldPause) {
      _stdoutSubscription?.pause();
      _stderrSubscription?.pause();
    } else {
      _stdoutSubscription?.resume();
      _stderrSubscription?.resume();
    }
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
    _outputSubscriptionsPaused = false;
    _flushTerminalWrites();
    await connection?.close();
  }

  void _queueTerminalWrite(Uint8List data) {
    if (data.isEmpty || _disposed) return;
    _pendingTerminalData.add(data);
    _pendingTerminalLength += data.length;
    if (_pendingTerminalLength >= _maximumBufferedBytes) {
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
    final data = _pendingTerminalData.takeBytes();
    _pendingTerminalData = BytesBuilder(copy: false);
    _pendingTerminalLength = 0;
    final event = WebTerminalDataEvent(
      sequence: ++_webTerminalSequence,
      data: data,
    );
    _appendWebTerminalDelta(event);
    if (_terminalDataListeners.isNotEmpty) {
      final decoded = utf8.decode(data, allowMalformed: true);
      for (final listener in List<ValueChanged<String>>.of(
        _terminalDataListeners,
      )) {
        listener(decoded);
      }
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
    if (data.length > _maximumWebTerminalDeltaBytes) {
      var start = data.length - _maximumWebTerminalDeltaBytes;
      while (start < data.length && _isUtf8ContinuationByte(data[start])) {
        start++;
      }
      data = Uint8List.sublistView(data, start);
      _webTerminalDelta.clear();
      _webTerminalDeltaLength = 0;
      _webTerminalDeltaTruncated = true;
    }
    _webTerminalDelta.addLast(_WebTerminalChunk(event.sequence, data));
    _webTerminalDeltaLength += data.length;
    while (_webTerminalDeltaLength > _maximumWebTerminalDeltaBytes &&
        _webTerminalDelta.isNotEmpty) {
      _webTerminalDeltaLength -= _webTerminalDelta.removeFirst().data.length;
      _webTerminalDeltaTruncated = true;
    }
  }

  static bool _isUtf8ContinuationByte(int value) => value & 0xC0 == 0x80;

  void _handleTerminalOutput(String data) {
    final connection = _connection;
    if (connection == null || status != SshSessionStatus.connected) {
      return;
    }

    var output = data;
    if (controlArmed && data.length == 1) {
      var value = data.codeUnitAt(0);
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
    setOutputBackpressure(false);
    _webTerminalDelta.clear();
    _webTerminalDeltaLength = 0;
    _webTerminalSnapshot = Uint8List(0);
    terminal.onOutput = null;
    terminal.onResize = null;
    terminal.onTitleChange = null;
    unawaited(_stdoutSubscription?.cancel());
    unawaited(_stderrSubscription?.cancel());
    unawaited(_connection?.close());
    super.dispose();
  }
}
