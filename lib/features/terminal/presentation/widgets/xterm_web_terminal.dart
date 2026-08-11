import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../application/ssh_session_controller.dart';

class XtermWebTerminal extends StatefulWidget {
  const XtermWebTerminal({
    required this.session,
    required this.scrollbackLines,
    required this.japaneseFontFamily,
    required this.fontSize,
    required this.mouseInput,
    required this.longPressRightClick,
    required this.tapToMovePromptCursor,
    this.onRendererChanged,
    this.onFatalError,
    super.key,
  });

  final SshSessionController session;
  final int scrollbackLines;
  final String japaneseFontFamily;
  final double fontSize;
  final bool mouseInput;
  final bool longPressRightClick;
  final bool tapToMovePromptCursor;
  final ValueChanged<String>? onRendererChanged;
  final ValueChanged<String>? onFatalError;

  @override
  State<XtermWebTerminal> createState() => XtermWebTerminalState();
}

class XtermWebTerminalState extends State<XtermWebTerminal> {
  static const _maximumPendingCharacters = 256 * 1024;
  static const _pauseOutputAtCharacters = 192 * 1024;
  static const _resumeOutputAtCharacters = 64 * 1024;
  static const _maximumWriteCharacters = 32 * 1024;
  static const _readyTimeout = Duration(seconds: 12);
  static const _snapshotTimeout = Duration(seconds: 3);
  static const _writeAckTimeout = Duration(seconds: 10);

  late final WebViewController _controller;
  final Queue<String> _pendingScripts = Queue<String>();
  final Queue<_QueuedOutputChunk> _pendingOutput = Queue<_QueuedOutputChunk>();
  final Map<int, Completer<_SnapshotResult>> _snapshotRequests = {};
  final Map<int, Completer<void>> _writeAckRequests = {};
  Timer? _readyTimer;
  Future<void>? _drainFuture;
  Future<void>? _suspendFuture;
  Future<bool>? _checkpointFuture;
  var _pendingOutputCharacters = 0;
  var _lastQueuedSequence = 0;
  var _lastSentSequence = 0;
  var _snapshotRequestId = 0;
  var _writeRequestId = 0;
  var _ready = false;
  var _active = true;
  var _listenerAttached = false;
  var _disposed = false;
  var _fatalReported = false;
  var _resumeRequested = false;
  var _resetOnResume = false;
  var _outputBackpressured = false;

  @override
  void initState() {
    super.initState();
    _synchronizeFromSession(reset: true);
    _attachSessionListener();
    _readyTimer = Timer(
      _readyTimeout,
      () => _reportFatal('xterm.jsの初期化がタイムアウトしました。'),
    );
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (!request.isMainFrame) return NavigationDecision.navigate;
            return request.url.contains('/assets/web_terminal/')
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame != false) {
              _reportFatal('端末アセットを読み込めませんでした。');
            }
          },
        ),
      )
      ..addJavaScriptChannel(
        'Termethis',
        onMessageReceived: _handleJavaScriptMessage,
      )
      ..loadFlutterAsset('assets/web_terminal/index.html');
  }

  @override
  void didUpdateWidget(XtermWebTerminal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session.removeWebTerminalDataListener(_handleTerminalData);
      oldWidget.session.setOutputBackpressure(false);
      _outputBackpressured = false;
      _listenerAttached = false;
      _pendingOutput.clear();
      _pendingOutputCharacters = 0;
      _lastQueuedSequence = 0;
      _lastSentSequence = 0;
      if (_active) {
        _synchronizeFromSession(reset: true);
        _attachSessionListener();
      } else {
        _resetOnResume = true;
      }
    }
    if (_ready &&
        (oldWidget.scrollbackLines != widget.scrollbackLines ||
            oldWidget.japaneseFontFamily != widget.japaneseFontFamily ||
            oldWidget.fontSize != widget.fontSize ||
            oldWidget.mouseInput != widget.mouseInput ||
            oldWidget.longPressRightClick != widget.longPressRightClick ||
            oldWidget.tapToMovePromptCursor != widget.tapToMovePromptCursor)) {
      _configure();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _readyTimer?.cancel();
    _detachSessionListener();
    for (final completer in _snapshotRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Terminal disposed'));
      }
    }
    _snapshotRequests.clear();
    for (final completer in _writeAckRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Terminal disposed'));
      }
    }
    _writeAckRequests.clear();
    _pendingOutput.clear();
    _pendingOutputCharacters = 0;
    _setOutputBackpressure(false);
    _pendingScripts.clear();
    unawaited(
      _controller
          .runJavaScript('window.termethisTerminal?.dispose();')
          .catchError((_) {}),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: WebViewWidget(controller: _controller),
    );
  }

  void focus() {
    if (_ready && _active) {
      _enqueueScript('window.termethisTerminal.focus();');
    }
  }

  void paste(String text) {
    if (!_ready || !_active || text.isEmpty) return;
    final encoded = base64Encode(utf8.encode(text));
    _enqueueScript("window.termethisTerminal.pasteBase64('$encoded');");
  }

  Future<String?> copyLastCommandOutput() async {
    if (!_ready || !_active || _disposed) return null;
    await _waitForDrain();
    final result = await _controller.runJavaScriptReturningResult(
      'window.termethisTerminal.copyLastOutputBase64();',
    );
    var encoded = result.toString();
    if (encoded.startsWith('"') && encoded.endsWith('"')) {
      encoded = jsonDecode(encoded) as String;
    }
    if (encoded.isEmpty) return null;
    return utf8.decode(base64Decode(encoded));
  }

  Future<void> suspend() async {
    _resumeRequested = false;
    if (_disposed || !_active) return;
    final current = _suspendFuture;
    if (current != null) return current;
    final operation = _performSuspend();
    _suspendFuture = operation;
    try {
      await operation;
    } finally {
      if (identical(_suspendFuture, operation)) _suspendFuture = null;
    }
  }

  Future<void> _performSuspend() async {
    _detachSessionListener();
    await _waitForDrain();

    if (_ready && !_fatalReported) {
      try {
        final snapshot = await _requestSnapshot();
        widget.session.saveWebTerminalSnapshot(
          snapshot.data,
          snapshot.throughSequence,
        );
      } catch (_) {
        // The session delta remains available when a platform view disappears
        // before the snapshot response arrives.
      }
      if (_resumeRequested) {
        _synchronizeFromSession(reset: false);
        _attachSessionListener();
        return;
      }
      _enqueueScript('window.termethisTerminal.setActive(false);');
      await _waitForDrain();
    }
    _active = false;
  }

  void resume() {
    if (_disposed) return;
    _resumeRequested = true;
    final suspending = _suspendFuture;
    if (suspending != null) {
      unawaited(suspending.whenComplete(_resumeAfterSuspension));
      return;
    }
    _resumeAfterSuspension();
  }

  void _resumeAfterSuspension() {
    if (_disposed || !_resumeRequested) return;
    if (_active) {
      _attachSessionListener();
      return;
    }
    _active = true;
    if (_ready) {
      _enqueueScript('window.termethisTerminal.setActive(true);');
    }
    _synchronizeFromSession(reset: _resetOnResume);
    _resetOnResume = false;
    _attachSessionListener();
    _scheduleDrain();
  }

  void _attachSessionListener() {
    if (_listenerAttached) return;
    widget.session.addWebTerminalDataListener(_handleTerminalData);
    _listenerAttached = true;
  }

  void _detachSessionListener() {
    if (!_listenerAttached) return;
    widget.session.removeWebTerminalDataListener(_handleTerminalData);
    _listenerAttached = false;
  }

  void _handleTerminalData(WebTerminalDataEvent event) {
    if (_disposed || !_active || event.sequence <= _lastQueuedSequence) return;
    _queueOutput(event.data, event.sequence);
    _scheduleCheckpoint();
  }

  void _scheduleCheckpoint() {
    if (_disposed ||
        !_ready ||
        !_active ||
        !widget.session.webTerminalCheckpointNeeded ||
        _checkpointFuture != null) {
      return;
    }

    final session = widget.session;
    final operation = _checkpointAfterDrain(session);
    _checkpointFuture = operation;
    unawaited(
      operation.then((saved) {
        if (identical(_checkpointFuture, operation)) {
          _checkpointFuture = null;
        }
        if (saved && identical(widget.session, session)) {
          _scheduleCheckpoint();
        }
      }),
    );
  }

  Future<bool> _checkpointAfterDrain(SshSessionController session) async {
    try {
      await _waitForDrain();
      if (_disposed ||
          !_ready ||
          !_active ||
          !identical(widget.session, session) ||
          !session.webTerminalCheckpointNeeded) {
        return false;
      }

      final snapshot = await _requestSnapshot();
      return session.saveWebTerminalSnapshot(
        snapshot.data,
        snapshot.throughSequence,
      );
    } catch (_) {
      return false;
    }
  }

  void _synchronizeFromSession({required bool reset}) {
    final replay = reset
        ? widget.session.webTerminalReplay
        : widget.session.webTerminalReplayAfter(_lastSentSequence);
    _queueOutput(
      replay.data,
      replay.throughSequence,
      reset: reset || replay.resetRequired,
    );
    _scheduleCheckpoint();
  }

  void _queueOutput(String data, int throughSequence, {bool reset = false}) {
    _lastQueuedSequence = throughSequence;
    if (reset) {
      _pendingOutput.clear();
      _pendingOutputCharacters = 0;
    }
    _appendOutputChunks(data, throughSequence, reset: reset);
    if (_pendingOutputCharacters >= _pauseOutputAtCharacters) {
      _setOutputBackpressure(true);
    }

    if (_pendingOutputCharacters > _maximumPendingCharacters) {
      final replay = widget.session.webTerminalReplay;
      _pendingOutput.clear();
      _pendingOutputCharacters = 0;
      _appendOutputChunks(replay.data, replay.throughSequence, reset: true);
      _lastQueuedSequence = replay.throughSequence;
    }
    _scheduleDrain();
  }

  void _appendOutputChunks(
    String data,
    int throughSequence, {
    required bool reset,
  }) {
    if (data.isEmpty) {
      if (reset) {
        _pendingOutput.addLast(
          _QueuedOutputChunk('', throughSequence, reset: true),
        );
      }
      return;
    }

    var offset = 0;
    var first = true;
    while (offset < data.length) {
      var end = offset + _maximumWriteCharacters;
      if (end > data.length) end = data.length;
      if (end < data.length &&
          _isLowSurrogate(data.codeUnitAt(end)) &&
          _isHighSurrogate(data.codeUnitAt(end - 1))) {
        end--;
      }
      final isLast = end == data.length;
      final chunk = data.substring(offset, end);
      _pendingOutput.addLast(
        _QueuedOutputChunk(
          chunk,
          isLast ? throughSequence : 0,
          reset: reset && first,
        ),
      );
      _pendingOutputCharacters += chunk.length;
      first = false;
      offset = end;
    }
  }

  void _handleJavaScriptMessage(JavaScriptMessage message) {
    if (_disposed) return;
    final Object? decoded;
    try {
      decoded = jsonDecode(message.message);
    } on FormatException {
      return;
    }
    if (decoded is! Map<String, dynamic>) return;
    switch (decoded['type']) {
      case 'ready':
        _readyTimer?.cancel();
        _ready = true;
        _configure();
        _enqueueScript('window.termethisTerminal.setActive($_active);');
        _scheduleDrain();
        _scheduleCheckpoint();
        widget.onRendererChanged?.call(decoded['renderer'] as String? ?? 'dom');
      case 'renderer':
        widget.onRendererChanged?.call(decoded['renderer'] as String? ?? 'dom');
      case 'rendererError':
        widget.onRendererChanged?.call('dom');
      case 'input':
        final data = decoded['data'];
        if (_active && data is String) widget.session.sendInput(data);
      case 'resize':
        final columns = decoded['cols'];
        final rows = decoded['rows'];
        if (columns is num && rows is num && columns > 0 && rows > 0) {
          widget.session.resizeTerminal(columns.toInt(), rows.toInt());
        }
      case 'snapshot':
        _completeSnapshot(decoded);
      case 'snapshotError':
        final id = decoded['id'];
        if (id is num) {
          _snapshotRequests
              .remove(id.toInt())
              ?.completeError(StateError('Snapshot failed'));
        }
      case 'writeAck':
        final id = decoded['id'];
        if (id is num) {
          final completer = _writeAckRequests.remove(id.toInt());
          if (completer != null && !completer.isCompleted) {
            completer.complete();
          }
        }
      case 'fatal':
        _reportFatal(decoded['message'] as String? ?? 'xterm.js error');
    }
  }

  void _completeSnapshot(Map<String, dynamic> message) {
    final id = message['id'];
    final sequence = message['throughSequence'];
    final encoded = message['data'];
    if (id is! num || sequence is! num || encoded is! String) return;
    final completer = _snapshotRequests.remove(id.toInt());
    if (completer == null || completer.isCompleted) return;
    try {
      completer.complete(
        _SnapshotResult(utf8.decode(base64Decode(encoded)), sequence.toInt()),
      );
    } on FormatException catch (error) {
      completer.completeError(error);
    }
  }

  void _configure() {
    final options = jsonEncode({
      'scrollback': widget.scrollbackLines,
      'fontFamily':
          'CascadiaMono, ${widget.japaneseFontFamily}, Mejiro, Koruri, monospace',
      'fontSize': widget.fontSize,
      'mouseInput': widget.mouseInput,
      'longPressRightClick': widget.longPressRightClick,
      'tapToMovePromptCursor': widget.tapToMovePromptCursor,
    });
    _enqueueScript('window.termethisTerminal.setOptions($options);');
  }

  Future<_SnapshotResult> _requestSnapshot() async {
    final id = ++_snapshotRequestId;
    final completer = Completer<_SnapshotResult>();
    _snapshotRequests[id] = completer;
    _enqueueScript(
      'window.termethisTerminal.requestSnapshot('
      '$id, $_lastSentSequence, ${widget.scrollbackLines});',
    );
    await _waitForDrain();
    return completer.future.timeout(
      _snapshotTimeout,
      onTimeout: () {
        _snapshotRequests.remove(id);
        throw TimeoutException('Terminal snapshot timed out');
      },
    );
  }

  void _enqueueScript(String script) {
    if (_disposed) return;
    _pendingScripts.addLast(script);
    _scheduleDrain();
  }

  void _scheduleDrain() {
    if (_disposed || _drainFuture != null) return;
    _drainFuture = _drainOperations().whenComplete(() {
      _drainFuture = null;
      if (!_disposed &&
          (_pendingScripts.isNotEmpty ||
              (_ready && _active && _pendingOutput.isNotEmpty))) {
        _scheduleDrain();
      }
    });
  }

  Future<void> _drainOperations() async {
    while (!_disposed) {
      String? script;
      var outputSequence = 0;
      if (_pendingScripts.isNotEmpty) {
        script = _pendingScripts.removeFirst();
      } else if (_ready && _active && _pendingOutput.isNotEmpty) {
        final output = _pendingOutput.removeFirst();
        _pendingOutputCharacters -= output.data.length;
        if (_pendingOutputCharacters <= _resumeOutputAtCharacters) {
          _setOutputBackpressure(false);
        }
        outputSequence = output.throughSequence;
        final requestId = ++_writeRequestId;
        final acknowledgement = Completer<void>();
        _writeAckRequests[requestId] = acknowledgement;
        final encoded = base64Encode(utf8.encode(output.data));
        script =
            "window.termethisTerminal.writeBase64("
            "'$encoded', ${output.reset}, $requestId);";

        try {
          await _controller.runJavaScript(script);
          await acknowledgement.future.timeout(_writeAckTimeout);
          if (outputSequence > _lastSentSequence) {
            _lastSentSequence = outputSequence;
          }
        } catch (error) {
          _writeAckRequests.remove(requestId);
          if (!_disposed) _reportFatal('WebViewとの通信に失敗しました。');
          return;
        }
        continue;
      } else {
        return;
      }

      try {
        await _controller.runJavaScript(script);
        if (outputSequence > _lastSentSequence) {
          _lastSentSequence = outputSequence;
        }
      } catch (error) {
        if (!_disposed) _reportFatal('WebViewとの通信に失敗しました。');
        return;
      }
    }
  }

  Future<void> _waitForDrain() async {
    _scheduleDrain();
    while (true) {
      final draining = _drainFuture;
      if (draining == null) return;
      await draining;
    }
  }

  void _reportFatal(String message) {
    if (_disposed || _fatalReported) return;
    _fatalReported = true;
    _readyTimer?.cancel();
    for (final completer in _writeAckRequests.values) {
      if (!completer.isCompleted) completer.completeError(StateError(message));
    }
    _writeAckRequests.clear();
    _setOutputBackpressure(false);
    widget.onFatalError?.call(message);
  }

  void _setOutputBackpressure(bool paused) {
    if (_outputBackpressured == paused) return;
    _outputBackpressured = paused;
    widget.session.setOutputBackpressure(paused);
  }

  static bool _isHighSurrogate(int value) => value >= 0xD800 && value <= 0xDBFF;

  static bool _isLowSurrogate(int value) => value >= 0xDC00 && value <= 0xDFFF;
}

class _QueuedOutputChunk {
  const _QueuedOutputChunk(
    this.data,
    this.throughSequence, {
    required this.reset,
  });

  final String data;
  final int throughSequence;
  final bool reset;
}

class _SnapshotResult {
  const _SnapshotResult(this.data, this.throughSequence);

  final String data;
  final int throughSequence;
}
