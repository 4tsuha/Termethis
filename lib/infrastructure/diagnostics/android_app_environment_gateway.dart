import 'package:flutter/services.dart';

import '../../features/diagnostics/domain/diagnostic_report.dart';

class AndroidAppEnvironmentGateway implements AppEnvironmentGateway {
  const AndroidAppEnvironmentGateway({
    this.channel = const MethodChannel('jp.yts.termethis/app_environment'),
  });

  final MethodChannel channel;

  @override
  Future<AppEnvironmentInfo> read() async {
    try {
      final value = await channel.invokeMapMethod<String, Object?>('getInfo');
      if (value == null) return _unavailable;
      return AppEnvironmentInfo(
        appVersion: value['appVersion'] as String? ?? 'unknown',
        buildNumber: value['buildNumber'] as String? ?? 'unknown',
        osRelease: value['osRelease'] as String? ?? 'unknown',
        sdkLevel: value['sdkLevel'] as int? ?? 0,
        deviceModel: value['deviceModel'] as String? ?? 'unknown',
      );
    } on MissingPluginException {
      return _unavailable;
    }
  }

  static const _unavailable = AppEnvironmentInfo(
    appVersion: 'unknown',
    buildNumber: 'unknown',
    osRelease: 'unknown',
    sdkLevel: 0,
    deviceModel: 'unknown',
  );
}
