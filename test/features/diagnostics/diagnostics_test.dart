import 'package:flutter_test/flutter_test.dart';
import 'package:termethis/features/connection_logs/domain/connection_log_entry.dart';
import 'package:termethis/features/connections/domain/connection_profile.dart';
import 'package:termethis/features/diagnostics/domain/connection_diagnostics.dart';
import 'package:termethis/features/diagnostics/domain/diagnostic_report.dart';
import 'package:termethis/features/settings/domain/credential_settings.dart';
import 'package:termethis/features/settings/domain/hardware_acceleration_controller.dart';
import 'package:termethis/features/settings/domain/terminal_performance_settings.dart';
import 'package:termethis/features/settings/domain/vault_protection.dart';

void main() {
  const vault = VaultProtectionStatus(
    available: true,
    deviceCredentialAvailable: true,
    strongBiometricAvailable: true,
    locked: false,
  );

  test('SSHはホスト鍵照合を安全性表示へ反映する', () {
    final summary = assessConnectionSecurity(
      profile: const ConnectionProfile(
        id: 'ssh',
        name: 'SSH',
        host: 'server.local',
        port: 22,
        username: 'alice',
      ),
      knownHostKeys: 1,
      credentialSettings: const CredentialSettings(),
      vaultStatus: vault,
    );

    expect(summary.transport, contains('SSH'));
    expect(summary.identityVerification, contains('1件'));
    expect(summary.warnings, isEmpty);
  });

  test('VNCとRDPの未検証条件を警告する', () {
    for (final type in [ConnectionType.vnc, ConnectionType.rdp]) {
      final summary = assessConnectionSecurity(
        profile: ConnectionProfile(
          id: type.name,
          name: type.name,
          host: 'desktop.local',
          port: type.defaultPort,
          username: 'user',
          connectionType: type,
        ),
        knownHostKeys: 0,
        credentialSettings: const CredentialSettings(),
        vaultStatus: vault,
      );
      expect(summary.warnings, isNotEmpty);
    }
  });

  test('診断出力から接続先と利用者データを除外する', () {
    final output = const DiagnosticReportBuilder().build(
      generatedAt: DateTime.utc(2026, 8, 14),
      environment: const AppEnvironmentInfo(
        appVersion: '0.8.0-alpha7',
        buildNumber: '14',
        osRelease: '16',
        sdkLevel: 36,
        deviceModel: 'Generic Device',
      ),
      terminalSettings: const TerminalPerformanceSettings(),
      hardware: const HardwareAccelerationCapabilities.unavailable(),
      savedConnectionCount: 1,
      openTabCount: 1,
      includeConnectionLogs: true,
      connectionLogs: [
        ConnectionLogEntry(
          timestamp: DateTime.utc(2026, 8, 14),
          profileId: 'private-profile-id',
          profileName: '本番サーバー',
          target: 'root@secret.example:22',
          tabId: 'private-tab-id',
          state: ConnectionLogState.failed,
        ),
      ],
    );

    expect(output, contains('connection-1'));
    expect(output, isNot(contains('private-profile-id')));
    expect(output, isNot(contains('private-tab-id')));
    expect(output, isNot(contains('本番サーバー')));
    expect(output, isNot(contains('root@secret.example')));
  });
}
