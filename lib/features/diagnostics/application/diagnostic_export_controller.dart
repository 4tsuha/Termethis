import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../connection_logs/application/connection_logs_controller.dart';
import '../../connection_logs/domain/connection_log_entry.dart';
import '../../connections/application/connection_profiles_controller.dart';
import '../../connections/application/connection_tabs_controller.dart';
import '../../settings/application/terminal_performance_settings_controller.dart';
import '../../../infrastructure/diagnostics/android_app_environment_gateway.dart';
import '../domain/diagnostic_report.dart';

final appEnvironmentGatewayProvider = Provider<AppEnvironmentGateway>(
  (ref) => const AndroidAppEnvironmentGateway(),
);

final diagnosticExportControllerProvider = Provider<DiagnosticExportController>(
  DiagnosticExportController.new,
);

class DiagnosticExportController {
  DiagnosticExportController(this.ref);

  final Ref ref;

  Future<String> create({required bool includeConnectionLogs}) async {
    final profiles = await ref
        .read(connectionProfileRepositoryProvider)
        .watchAll()
        .first;
    final tabs = await ref.read(connectionTabStoreProvider).load();
    final List<ConnectionLogEntry> logs = includeConnectionLogs
        ? await ref.read(connectionLogsProvider.notifier).list()
        : const <ConnectionLogEntry>[];
    final environment = await ref.read(appEnvironmentGatewayProvider).read();
    final hardware = await ref.read(
      hardwareAccelerationCapabilitiesProvider.future,
    );
    return const DiagnosticReportBuilder().build(
      generatedAt: DateTime.now(),
      environment: environment,
      terminalSettings: ref.read(terminalPerformanceSettingsProvider),
      hardware: hardware,
      savedConnectionCount: profiles.length,
      openTabCount: tabs.length,
      includeConnectionLogs: includeConnectionLogs,
      connectionLogs: logs,
    );
  }
}
