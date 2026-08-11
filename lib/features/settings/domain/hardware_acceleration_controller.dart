import 'terminal_performance_settings.dart';

class HardwareAccelerationCapabilities {
  const HardwareAccelerationCapabilities({
    required this.isVulkanSupported,
    this.vulkanVersion,
    this.vulkanHardwareLevel,
    this.isAndroidHardwareAccelerated = false,
    this.appliedMode = HardwareAccelerationMode.automatic,
    this.requiresRestart = false,
  });

  const HardwareAccelerationCapabilities.unavailable()
    : isVulkanSupported = false,
      vulkanVersion = null,
      vulkanHardwareLevel = null,
      isAndroidHardwareAccelerated = false,
      appliedMode = HardwareAccelerationMode.automatic,
      requiresRestart = false;

  final bool isVulkanSupported;
  final String? vulkanVersion;
  final int? vulkanHardwareLevel;
  final bool isAndroidHardwareAccelerated;
  final HardwareAccelerationMode appliedMode;
  final bool requiresRestart;
}

abstract interface class HardwareAccelerationController {
  Future<HardwareAccelerationCapabilities> getCapabilities();

  Future<void> setMode(HardwareAccelerationMode mode);
}

class NoopHardwareAccelerationController
    implements HardwareAccelerationController {
  const NoopHardwareAccelerationController();

  @override
  Future<HardwareAccelerationCapabilities> getCapabilities() async =>
      const HardwareAccelerationCapabilities.unavailable();

  @override
  Future<void> setMode(HardwareAccelerationMode mode) async {}
}
