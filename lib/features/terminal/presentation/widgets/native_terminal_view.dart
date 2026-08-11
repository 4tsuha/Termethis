import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import '../../../settings/domain/terminal_performance_settings.dart';
import '../../application/ssh_session_controller.dart';

class NativeTerminalView extends StatefulWidget {
  const NativeTerminalView({
    required this.session,
    required this.rendererMode,
    required this.scrollbackLines,
    required this.terminalFontFamily,
    required this.japaneseFontFamily,
    required this.fontSize,
    required this.mouseInput,
    required this.longPressRightClick,
    required this.tapToMovePromptCursor,
    required this.resizeForKeyboard,
    this.onRendererReady,
    this.onFatalError,
    super.key,
  });

  final SshSessionController session;
  final TerminalRendererMode rendererMode;
  final int scrollbackLines;
  final String terminalFontFamily;
  final String japaneseFontFamily;
  final double fontSize;
  final bool mouseInput;
  final bool longPressRightClick;
  final bool tapToMovePromptCursor;
  final bool resizeForKeyboard;
  final ValueChanged<String>? onRendererReady;
  final ValueChanged<String>? onFatalError;

  @override
  State<NativeTerminalView> createState() => NativeTerminalViewState();
}

class NativeTerminalViewState extends State<NativeTerminalView> {
  static const _connectBotViewType = 'jp.yts.termethis/native_terminal';
  static const _termuxViewType = 'jp.yts.termethis/termux_terminal';
  static const _backpressureThreshold = 512 * 1024;

  MethodChannel? _channel;
  final List<WebTerminalDataEvent> _pendingEvents = [];
  Future<void> _writeChain = Future<void>.value();
  bool _ready = false;
  bool _active = true;
  bool _disposed = false;
  int _lastSequence = 0;
  int _pendingBytes = 0;

  String get _viewType => switch (widget.rendererMode) {
    TerminalRendererMode.termux => _termuxViewType,
    _ => _connectBotViewType,
  };

  @override
  void initState() {
    super.initState();
    widget.session.addWebTerminalDataListener(_onTerminalData);
  }

  @override
  void didUpdateWidget(NativeTerminalView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.session, widget.session)) {
      oldWidget.session.removeWebTerminalDataListener(_onTerminalData);
      widget.session.addWebTerminalDataListener(_onTerminalData);
    }
    if (_channel != null && _optionsChanged(oldWidget)) {
      unawaited(_channel!.invokeMethod<void>('setOptions', _creationParams));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    widget.session.removeWebTerminalDataListener(_onTerminalData);
    widget.session.setOutputBackpressure(false);
    _channel?.setMethodCallHandler(null);
    unawaited(_channel?.invokeMethod<void>('setActive', false));
    _pendingEvents.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Text(
            'ネイティブ端末はAndroidでのみ利用できます。',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }
    return AndroidView(
      viewType: _viewType,
      creationParams: _creationParams,
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: _onPlatformViewCreated,
    );
  }

  Future<void> focus() async {
    await _channel?.invokeMethod<void>('focus');
  }

  Future<void> paste(String text) async {
    await _channel?.invokeMethod<void>('paste', text);
  }

  Future<bool> sendKey(
    TerminalKey key, {
    required bool control,
    required bool alt,
  }) async {
    final channel = _channel;
    if (channel == null || _disposed) return false;
    final name = switch (key) {
      TerminalKey.escape => 'escape',
      TerminalKey.tab => 'tab',
      TerminalKey.enter => 'enter',
      TerminalKey.arrowUp => 'arrowUp',
      TerminalKey.arrowDown => 'arrowDown',
      TerminalKey.arrowLeft => 'arrowLeft',
      TerminalKey.arrowRight => 'arrowRight',
      _ => null,
    };
    if (name == null) return false;
    await channel.invokeMethod<void>('sendKey', {
      'key': name,
      'control': control,
      'alt': alt,
    });
    return true;
  }

  Future<void> setActive(bool active) async {
    if (_disposed || _active == active) return;
    _active = active;
    await _channel?.invokeMethod<void>('setActive', active);
    if (!active) {
      widget.session.setOutputBackpressure(false);
      return;
    }
    final replay = widget.session.webTerminalReplayAfter(_lastSequence);
    _lastSequence = replay.throughSequence;
    _enqueueWrite(replay.data, reset: replay.resetRequired);
  }

  Map<String, Object> get _creationParams => {
    'scrollbackLines': widget.scrollbackLines,
    'terminalFontFamily': widget.terminalFontFamily,
    'japaneseFontFamily': widget.japaneseFontFamily,
    'fontSize': widget.fontSize,
    'mouseInput': widget.mouseInput,
    'longPressRightClick': widget.longPressRightClick,
    'tapToMovePromptCursor': widget.tapToMovePromptCursor,
    'resizeForKeyboard': widget.resizeForKeyboard,
  };

  Future<void> _onPlatformViewCreated(int viewId) async {
    final channel = MethodChannel('$_viewType/$viewId');
    _channel = channel;
    channel.setMethodCallHandler(_onNativeCall);
    try {
      final result = await channel.invokeMapMethod<String, Object?>(
        'initialize',
      );
      if (_disposed) return;
      await _restoreAndDrain();
      if (_disposed) return;
      widget.onRendererReady?.call(
        result?['renderer'] as String? ?? widget.rendererMode.name,
      );
    } catch (error) {
      _reportFatal('ネイティブ端末を初期化できませんでした: $error');
    }
  }

  Future<Object?> _onNativeCall(MethodCall call) async {
    if (_disposed) return null;
    switch (call.method) {
      case 'input':
        final bytes = call.arguments;
        if (bytes is Uint8List) widget.session.sendInputBytes(bytes);
      case 'directInput':
        final bytes = call.arguments;
        if (bytes is Uint8List) widget.session.sendInputBytesDirect(bytes);
      case 'resize':
        final dimensions = call.arguments;
        if (dimensions is Map) {
          final columns = dimensions['columns'];
          final rows = dimensions['rows'];
          if (columns is int && rows is int) {
            widget.session.resizeTerminal(columns, rows);
          }
        }
      case 'openLink':
        final uri = call.arguments;
        if (uri is String && uri.isNotEmpty) {
          await Clipboard.setData(ClipboardData(text: uri));
        }
    }
    return null;
  }

  void _onTerminalData(WebTerminalDataEvent event) {
    if (_disposed || !_active || event.sequence <= _lastSequence) return;
    if (!_ready) {
      _pendingEvents.add(event);
      return;
    }
    _lastSequence = event.sequence;
    _enqueueWrite(event.data);
  }

  Future<void> _restoreAndDrain() async {
    final replay = widget.session.webTerminalReplay;
    _lastSequence = replay.throughSequence;
    await _write(replay.data, reset: true);

    while (!_disposed) {
      final next =
          _pendingEvents
              .where((event) => event.sequence > _lastSequence)
              .toList(growable: false)
            ..sort((a, b) => a.sequence.compareTo(b.sequence));
      _pendingEvents.clear();
      if (next.isEmpty) {
        _ready = true;
        return;
      }
      for (final event in next) {
        _lastSequence = event.sequence;
        await _write(event.data);
      }
    }
  }

  void _enqueueWrite(Uint8List data, {bool reset = false}) {
    _pendingBytes += data.length;
    if (_pendingBytes >= _backpressureThreshold) {
      widget.session.setOutputBackpressure(true);
    }
    _writeChain = _writeChain
        .then((_) => _write(data, reset: reset))
        .whenComplete(() {
          _pendingBytes -= data.length;
          if (_pendingBytes < _backpressureThreshold ~/ 2) {
            widget.session.setOutputBackpressure(false);
          }
        })
        .catchError((Object error, StackTrace stackTrace) {
          _reportFatal('ネイティブ端末への出力に失敗しました: $error');
        });
  }

  Future<void> _write(Uint8List data, {bool reset = false}) async {
    if (_disposed || data.isEmpty && !reset) return;
    await _channel?.invokeMethod<void>('write', {'data': data, 'reset': reset});
  }

  bool _optionsChanged(NativeTerminalView oldWidget) =>
      oldWidget.terminalFontFamily != widget.terminalFontFamily ||
      oldWidget.japaneseFontFamily != widget.japaneseFontFamily ||
      oldWidget.fontSize != widget.fontSize ||
      oldWidget.mouseInput != widget.mouseInput ||
      oldWidget.longPressRightClick != widget.longPressRightClick ||
      oldWidget.tapToMovePromptCursor != widget.tapToMovePromptCursor ||
      oldWidget.resizeForKeyboard != widget.resizeForKeyboard;

  void _reportFatal(String message) {
    if (_disposed) return;
    widget.session.setOutputBackpressure(false);
    widget.onFatalError?.call(message);
  }
}
