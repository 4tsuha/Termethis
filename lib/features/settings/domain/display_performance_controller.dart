import 'terminal_performance_settings.dart';

abstract interface class DisplayPerformanceController {
  Future<void> setMode(RefreshRateMode mode);
  Future<void> pulseHigh();
}

class NoopDisplayPerformanceController implements DisplayPerformanceController {
  const NoopDisplayPerformanceController();

  @override
  Future<void> pulseHigh() async {}

  @override
  Future<void> setMode(RefreshRateMode mode) async {}
}
