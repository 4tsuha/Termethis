import 'dart:io';

import 'package:flutter/services.dart';

class AndroidTerminalWindowController {
  const AndroidTerminalWindowController();

  static const _channel = MethodChannel('jp.yts.termethis/terminal_window');

  Future<void> apply({required bool keepScreenAwake}) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('apply', {
      'keepScreenAwake': keepScreenAwake,
    });
  }

  Future<void> restore() => apply(keepScreenAwake: false);
}
