import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../../application/ssh_session_controller.dart';

class XtermDartTerminal extends StatefulWidget {
  const XtermDartTerminal({
    required this.session,
    required this.scrollbackLines,
    required this.terminalFontFamily,
    required this.japaneseFontFamily,
    required this.fontSize,
    super.key,
  });

  final SshSessionController session;
  final int scrollbackLines;
  final String terminalFontFamily;
  final String japaneseFontFamily;
  final double fontSize;

  @override
  State<XtermDartTerminal> createState() => XtermDartTerminalState();
}

class XtermDartTerminalState extends State<XtermDartTerminal> {
  final _terminalViewKey = GlobalKey<TerminalViewState>();
  final _focusNode = FocusNode(debugLabel: 'xterm-dart-terminal');
  late Terminal _terminal;
  late ByteConversionSink _utf8Sink;
  int _lastSequence = 0;
  bool _active = true;

  @override
  void initState() {
    super.initState();
    _createTerminal();
    widget.session.addWebTerminalDataListener(_onTerminalData);
    _restore(widget.session.webTerminalReplay);
  }

  @override
  void didUpdateWidget(XtermDartTerminal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.session, widget.session) ||
        oldWidget.scrollbackLines != widget.scrollbackLines) {
      oldWidget.session.removeWebTerminalDataListener(_onTerminalData);
      _utf8Sink.close();
      _createTerminal();
      widget.session.addWebTerminalDataListener(_onTerminalData);
      _restore(widget.session.webTerminalReplay);
    }
  }

  @override
  void dispose() {
    widget.session.removeWebTerminalDataListener(_onTerminalData);
    _utf8Sink.close();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: TerminalView(
        _terminal,
        key: _terminalViewKey,
        focusNode: _focusNode,
        autofocus: true,
        keyboardType: TextInputType.text,
        enableSuggestions: true,
        deleteDetection: false,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        textStyle: TerminalStyle(
          fontFamily: widget.terminalFontFamily,
          fontFamilyFallback: [
            widget.japaneseFontFamily,
            'NerdSymbolsMono',
            'Noto Color Emoji',
          ],
          fontSize: widget.fontSize,
          height: 1.2,
        ),
      ),
    );
  }

  void focus() {
    _focusNode.requestFocus();
    _terminalViewKey.currentState?.requestKeyboard();
  }

  void paste(String text) {
    if (text.isNotEmpty) _terminal.paste(text);
  }

  bool sendKey(TerminalKey key, {required bool control, required bool alt}) {
    _terminal.keyInput(key, ctrl: control, alt: alt);
    return true;
  }

  void setActive(bool active) {
    if (_active == active) return;
    _active = active;
    if (!active) {
      _focusNode.unfocus();
      return;
    }
    _restore(widget.session.webTerminalReplayAfter(_lastSequence));
  }

  void _createTerminal() {
    _terminal = Terminal(
      maxLines: widget.scrollbackLines,
      onOutput: widget.session.sendInput,
      onResize: (width, height, _, _) {
        widget.session.resizeTerminal(width, height);
      },
    );
    _utf8Sink = const Utf8Decoder(allowMalformed: true).startChunkedConversion(
      StringConversionSink.fromStringSink(_TerminalStringSink(_terminal)),
    );
    _lastSequence = 0;
  }

  void _onTerminalData(WebTerminalDataEvent event) {
    if (!_active || event.sequence <= _lastSequence) return;
    _lastSequence = event.sequence;
    _utf8Sink.add(event.data);
  }

  void _restore(WebTerminalReplay replay) {
    if (replay.throughSequence <= _lastSequence && replay.data.isEmpty) return;
    if (replay.resetRequired) _terminal.write('\x1bc');
    _lastSequence = replay.throughSequence;
    if (replay.data.isNotEmpty) _utf8Sink.add(replay.data);
  }
}

class _TerminalStringSink implements StringSink {
  const _TerminalStringSink(this.terminal);

  final Terminal terminal;

  @override
  void write(Object? object) => terminal.write(object?.toString() ?? '');

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      write(objects.join(separator));

  @override
  void writeCharCode(int charCode) => terminal.writeChar(charCode);

  @override
  void writeln([Object? object = '']) => write('${object ?? ''}\n');
}
