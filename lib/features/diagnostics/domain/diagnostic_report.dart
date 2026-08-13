import 'dart:convert';

import '../../connection_logs/domain/connection_log_entry.dart';
import '../../settings/domain/hardware_acceleration_controller.dart';
import '../../settings/domain/terminal_performance_settings.dart';

const diagnosticReportFormatVersion = 1;

class AppEnvironmentInfo {
  const AppEnvironmentInfo({
    required this.appVersion,
    required this.buildNumber,
    required this.osRelease,
    required this.sdkLevel,
    required this.deviceModel,
  });

  final String appVersion;
  final String buildNumber;
  final String osRelease;
  final int sdkLevel;
  final String deviceModel;
}

abstract interface class AppEnvironmentGateway {
  Future<AppEnvironmentInfo> read();
}

class DiagnosticReportBuilder {
  const DiagnosticReportBuilder();

  String build({
    required DateTime generatedAt,
    required AppEnvironmentInfo environment,
    required TerminalPerformanceSettings terminalSettings,
    required HardwareAccelerationCapabilities hardware,
    required int savedConnectionCount,
    required int openTabCount,
    required bool includeConnectionLogs,
    required List<ConnectionLogEntry> connectionLogs,
  }) {
    final aliases = <String, String>{};
    String alias(String profileId) => aliases.putIfAbsent(
      profileId,
      () => 'connection-${aliases.length + 1}',
    );
    final json = <String, Object?>{
      'format': 'termethis-diagnostics',
      'version': diagnosticReportFormatVersion,
      'generatedAt': generatedAt.toUtc().toIso8601String(),
      'containsCredentials': false,
      'containsHostNames': false,
      'environment': {
        'appVersion': environment.appVersion,
        'buildNumber': environment.buildNumber,
        'os': 'Android ${environment.osRelease}',
        'sdkLevel': environment.sdkLevel,
        'deviceModel': environment.deviceModel,
      },
      'renderer': {
        'terminalEmulator': terminalSettings.rendererMode.name,
        'hardwareAcceleration': terminalSettings.hardwareAccelerationMode.name,
        'refreshRateMode': terminalSettings.refreshRateMode.name,
        'vulkanSupported': hardware.isVulkanSupported,
        'vulkanVersion': hardware.vulkanVersion,
        'androidHardwareAccelerated': hardware.isAndroidHardwareAccelerated,
        'scrollbackLines': terminalSettings.scrollbackLines,
      },
      'counts': {
        'savedConnections': savedConnectionCount,
        'openTabs': openTabCount,
        'connectionLogs': includeConnectionLogs ? connectionLogs.length : 0,
      },
      'connectionLogsIncluded': includeConnectionLogs,
      if (includeConnectionLogs)
        'connectionLogs': [
          for (final entry in connectionLogs)
            {
              'timestamp': entry.timestamp.toUtc().toIso8601String(),
              'connection': alias(entry.profileId),
              'state': entry.state.name,
              'failureCode': entry.failureCode?.name,
            },
        ],
    };
    return const JsonEncoder.withIndent('  ').convert(json);
  }
}
