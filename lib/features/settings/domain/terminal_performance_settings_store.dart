import 'terminal_performance_settings.dart';

abstract interface class TerminalPerformanceSettingsStore {
  Future<TerminalPerformanceSettings?> read();
  Future<void> save(TerminalPerformanceSettings settings);
}

class EphemeralTerminalPerformanceSettingsStore
    implements TerminalPerformanceSettingsStore {
  const EphemeralTerminalPerformanceSettingsStore();

  @override
  Future<TerminalPerformanceSettings?> read() async => null;

  @override
  Future<void> save(TerminalPerformanceSettings settings) async {}
}
