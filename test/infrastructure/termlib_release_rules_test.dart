import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ReleaseビルドでtermlibのJNI境界名を難読化しない', () {
    final rules = File(
      'third_party/termlib/lib/consumer-rules.pro',
    ).readAsStringSync();

    for (final jniType in [
      'CellRun',
      'TermRect',
      'CursorPosition',
      'ScreenCell',
      r'TerminalProperty$*',
      'TerminalCallbacks',
    ]) {
      expect(
        rules,
        contains('org.connectbot.terminal.$jniType'),
        reason: '$jniTypeはJNIから名前で参照されます。',
      );
    }
    expect(
      rules,
      contains(
        '-keep class * implements org.connectbot.terminal.TerminalCallbacks',
      ),
    );
  });
}
