import 'package:flutter/services.dart';

import '../../features/settings/domain/background_session_service_controller.dart';

class AndroidBackgroundSessionServiceController
    implements BackgroundSessionServiceController {
  const AndroidBackgroundSessionServiceController();

  static const _channel = MethodChannel(
    'jp.hgzt23678.ssh_terminal_ja/background_session',
  );

  @override
  Future<void> setRunning(bool running) async {
    try {
      await _channel.invokeMethod<void>('setRunning', {'running': running});
    } on MissingPluginException {
      // Android以外ではForeground Serviceを使用しない。
    }
  }
}
