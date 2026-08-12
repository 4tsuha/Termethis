import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('xterm.js uses a wide PTY unless Agent mode is enabled', () {
    final source = File('tool/web_terminal/src/terminal.js').readAsStringSync();
    final page = File('assets/web_terminal/index.html').readAsStringSync();

    expect(source, contains('const WIDE_TERMINAL_COLUMNS = 160;'));
    expect(source, contains('!agentMode &&'));
    expect(source, contains('visibleDimensions.cols < WIDE_TERMINAL_COLUMNS'));
    expect(source, contains('agentMode = options.agentMode === true;'));
    expect(source, contains('resizeObserver.observe(viewport);'));
    expect(page, contains('id="terminal-scroll"'));
    expect(page, contains('overflow-x: auto;'));
  });
}
