import 'package:flutter/services.dart';

import '../../features/settings/domain/display_performance_controller.dart';
import '../../features/settings/domain/terminal_performance_settings.dart';

class AndroidDisplayPerformanceController
    implements DisplayPerformanceController {
  const AndroidDisplayPerformanceController();

  static const _channel = MethodChannel(
    'jp.hgzt23678.ssh_terminal_ja/display_performance',
  );

  @override
  Future<void> pulseHigh() => _invoke('pulseHigh');

  @override
  Future<void> setMode(RefreshRateMode mode) {
    return _invoke('setMode', {'mode': mode.name});
  }

  Future<void> _invoke(String method, [Object? arguments]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // Android以外ではOS側の表示制御を行わない。
    }
  }
}
