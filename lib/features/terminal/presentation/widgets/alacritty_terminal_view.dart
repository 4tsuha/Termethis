import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart' as alacritty;
import 'package:xterm/xterm.dart' show TerminalKey;

import '../../../settings/domain/terminal_performance_settings.dart';
import '../../application/ssh_session_controller.dart';

class AlacrittyTerminalView extends StatefulWidget {
  const AlacrittyTerminalView({
    required this.session,
    required this.scrollbackLines,
    required this.terminalFontFamily,
    required this.japaneseFontFamily,
    required this.fontSize,
    required this.hardwareAccelerationMode,
    this.onFatalError,
    super.key,
  });

  final SshSessionController session;
  final int scrollbackLines;
  final String terminalFontFamily;
  final String japaneseFontFamily;
  final double fontSize;
  final HardwareAccelerationMode hardwareAccelerationMode;
  final ValueChanged<String>? onFatalError;

  @override
  State<AlacrittyTerminalView> createState() => AlacrittyTerminalViewState();
}

class AlacrittyTerminalViewState extends State<AlacrittyTerminalView> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'alacritty-terminal');
  late final Future<void> _ready = _initialize();

  alacritty.TerminalEngine? _engine;
  alacritty.TerminalController? _controller;
  StreamSubscription<Uint8List>? _outputSubscription;
  StreamSubscription<String>? _clipboardStoreSubscription;
  StreamSubscription<void>? _clipboardLoadSubscription;
  int _lastSequence = 0;
  bool _active = true;
  bool _disposed = false;
  bool _fatalReported = false;

  @override
  void didUpdateWidget(AlacrittyTerminalView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollbackLines != widget.scrollbackLines ||
        oldWidget.terminalFontFamily != widget.terminalFontFamily ||
        oldWidget.japaneseFontFamily != widget.japaneseFontFamily ||
        oldWidget.fontSize != widget.fontSize) {
      _engine?.reconfigure(_terminalConfig());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    widget.session.removeWebTerminalDataListener(_onTerminalData);
    unawaited(_outputSubscription?.cancel());
    unawaited(_clipboardStoreSubscription?.cancel());
    unawaited(_clipboardLoadSubscription?.cancel());
    _controller?.dispose();
    _engine?.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _ready,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          _reportFatal('Flutter Alacrittyを初期化できませんでした: ${snapshot.error}');
          return const ColoredBox(
            color: Colors.black,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final engine = _engine;
        final controller = _controller;
        if (snapshot.connectionState != ConnectionState.done ||
            engine == null ||
            controller == null) {
          return const ColoredBox(
            color: Colors.black,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final config = _terminalConfig();
        return alacritty.TerminalView(
          engine,
          controller: controller,
          theme: config.theme,
          textStyle: config.style,
          focusNode: _focusNode,
          autofocus: true,
          preferGpuSurface: switch (widget.hardwareAccelerationMode) {
            HardwareAccelerationMode.automatic => null,
            HardwareAccelerationMode.vulkan => true,
            HardwareAccelerationMode.disabled => false,
          },
          onPtyResize: widget.session.resizeTerminal,
        );
      },
    );
  }

  Future<void> focus() async {
    await _ready;
    if (!_disposed) _focusNode.requestFocus();
  }

  Future<void> paste(String text) async {
    await _ready;
    if (_disposed || text.isEmpty) return;
    // The existing xterm model tracks bracketed-paste mode alongside the
    // Alacritty engine and already emits the correct PTY sequence.
    widget.session.paste(text);
  }

  Future<bool> sendKey(
    TerminalKey key, {
    required bool control,
    required bool alt,
  }) async {
    await _ready;
    // TerminalScreen falls back to the shared xterm key encoder. This keeps
    // modifier and application-cursor handling common across every renderer.
    return false;
  }

  Future<void> setActive(bool active) async {
    _active = active;
    if (!active) return;
    try {
      await _ready;
      if (_disposed) return;
      _feedReplay(widget.session.webTerminalReplayAfter(_lastSequence));
    } catch (error) {
      _reportFatal('Flutter Alacrittyを再開できませんでした: $error');
    }
  }

  Future<void> _initialize() async {
    await alacritty.RustLib.init();
    if (_disposed) return;

    final engine = alacritty.TerminalEngine(config: _terminalConfig());
    final controller = alacritty.TerminalController()..attach(engine);
    _engine = engine;
    _controller = controller;
    _outputSubscription = engine.output.listen(
      widget.session.sendInputBytesDirect,
      onError: (Object error, StackTrace _) {
        _reportFatal('Flutter Alacrittyの入力処理に失敗しました: $error');
      },
    );
    _clipboardStoreSubscription = engine.clipboardStore.listen(
      (text) => Clipboard.setData(ClipboardData(text: text)),
    );
    _clipboardLoadSubscription = engine.clipboardLoad.listen((_) async {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (!_disposed) engine.respondClipboardLoad(data?.text ?? '');
    });

    final replay = widget.session.webTerminalReplay;
    _lastSequence = replay.throughSequence;
    if (replay.data.isNotEmpty) engine.feed(replay.data);
    widget.session.addWebTerminalDataListener(_onTerminalData);
    _feedReplay(widget.session.webTerminalReplayAfter(_lastSequence));
  }

  alacritty.TerminalConfig _terminalConfig() {
    final defaults = alacritty.TerminalConfig.defaults();
    return defaults.copyWith(
      font: defaults.font.copyWith(
        family: widget.terminalFontFamily,
        fallback: [
          widget.japaneseFontFamily,
          'NerdSymbolsMono',
          'Noto Color Emoji',
        ],
        size: widget.fontSize,
        lineHeight: 1.2,
      ),
      scrolling: defaults.scrolling.copyWith(history: widget.scrollbackLines),
    );
  }

  void _onTerminalData(WebTerminalDataEvent event) {
    if (_disposed || !_active || event.sequence <= _lastSequence) return;
    _lastSequence = event.sequence;
    try {
      _engine?.feed(event.data);
    } catch (error) {
      _reportFatal('Flutter Alacrittyの出力処理に失敗しました: $error');
    }
  }

  void _feedReplay(WebTerminalReplay replay) {
    if (replay.throughSequence <= _lastSequence && replay.data.isEmpty) return;
    _lastSequence = replay.throughSequence;
    if (replay.data.isEmpty) return;
    try {
      _engine?.feed(
        replay.resetRequired
            ? Uint8List.fromList([0x1b, 0x63, ...replay.data])
            : replay.data,
      );
    } catch (error) {
      _reportFatal('Flutter Alacrittyの履歴復元に失敗しました: $error');
    }
  }

  void _reportFatal(String message) {
    if (_fatalReported || _disposed) return;
    _fatalReported = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) widget.onFatalError?.call(message);
    });
  }
}
