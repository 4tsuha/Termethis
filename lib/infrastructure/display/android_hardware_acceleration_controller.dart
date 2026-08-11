import 'package:flutter/services.dart';

import '../../features/settings/domain/hardware_acceleration_controller.dart';
import '../../features/settings/domain/terminal_performance_settings.dart';

class AndroidHardwareAccelerationController
    implements HardwareAccelerationController {
  const AndroidHardwareAccelerationController();

  static const _channel = MethodChannel(
    'jp.yts.termethis/hardware_acceleration',
  );

  @override
  Future<HardwareAccelerationCapabilities> getCapabilities() async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'getCapabilities',
      );
      if (result == null) {
        return const HardwareAccelerationCapabilities.unavailable();
      }
      return HardwareAccelerationCapabilities(
        isVulkanSupported: result['vulkanSupported'] == true,
        vulkanVersion: result['vulkanVersion'] as String?,
        vulkanHardwareLevel: result['vulkanHardwareLevel'] as int?,
        isAndroidHardwareAccelerated:
            result['androidHardwareAccelerated'] == true,
        appliedMode: HardwareAccelerationMode.values.firstWhere(
          (mode) => mode.name == result['appliedMode'],
          orElse: () => HardwareAccelerationMode.automatic,
        ),
        requiresRestart: result['requiresRestart'] == true,
      );
    } on MissingPluginException {
      return const HardwareAccelerationCapabilities.unavailable();
    }
  }

  @override
  Future<void> setMode(HardwareAccelerationMode mode) async {
    try {
      await _channel.invokeMethod<void>('setMode', {'mode': mode.name});
    } on MissingPluginException {
      // Android以外では起動時の描画バックエンドを変更しない。
    }
  }
}
