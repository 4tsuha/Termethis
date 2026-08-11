import 'dart:io';

import 'package:flutter/services.dart';

class AndroidTerminalWindowController {
  const AndroidTerminalWindowController();

  static const _channel = MethodChannel(
    'jp.hgzt23678.ssh_terminal_ja/terminal_window',
  );

  Future<void> apply({
    required bool keepScreenAwake,
    required bool resizeForKeyboard,
  }) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('apply', {
      'keepScreenAwake': keepScreenAwake,
      'resizeForKeyboard': resizeForKeyboard,
    });
  }

  Future<void> restore() =>
      apply(keepScreenAwake: false, resizeForKeyboard: true);
}
