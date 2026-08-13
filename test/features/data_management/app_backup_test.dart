import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termethis/features/connections/application/connection_profiles_controller.dart';
import 'package:termethis/features/connections/domain/connection_profile.dart';
import 'package:termethis/features/connections/domain/connection_profile_repository.dart';
import 'package:termethis/features/connections/domain/ssh_route_configuration.dart';
import 'package:termethis/features/data_management/application/app_backup_controller.dart';
import 'package:termethis/features/data_management/domain/app_backup.dart';
import 'package:termethis/features/settings/domain/app_font.dart';
import 'package:termethis/features/settings/domain/terminal_performance_settings.dart';

void main() {
  test('バックアップへCredential Vaultの参照を含めない', () {
    final backup = AppBackup(
      version: appBackupFormatVersion,
      createdAt: DateTime.utc(2026, 8, 14),
      profiles: const [
        ConnectionProfile(
          id: 'server-1',
          name: '開発サーバー',
          host: 'example.local',
          port: 22,
          username: 'alice',
          authenticationType: AuthenticationType.privateKey,
          credentialReference: 'vault-secret-handle',
          privateKeyLabel: 'id_ed25519',
        ),
      ],
      knownHosts: const [],
      tabs: const [],
      snippets: const [],
      routes: const [],
      appFont: AppFont.notoSansJp,
      terminalSettings: const TerminalPerformanceSettings(),
      credentialsToReenter: 1,
    );

    final encoded = jsonEncode(backup.toJson());
    expect(encoded, isNot(contains('vault-secret-handle')));
    expect(encoded, isNot(contains('id_ed25519')));
    expect(jsonDecode(encoded)['containsCredentials'], isFalse);

    final restored = AppBackup.fromJson(
      jsonDecode(encoded) as Map<String, dynamic>,
    );
    expect(restored.profiles.single.credentialReference, isNull);
    expect(restored.profiles.single.privateKeyLabel, isNull);
    expect(restored.credentialsToReenter, 1);
  });

  test('循環する踏み台設定を復元前に拒否する', () async {
    final repository = EphemeralConnectionProfileRepository();
    addTearDown(repository.close);
    final container = ProviderContainer(
      overrides: [
        connectionProfileRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    final backup = AppBackup(
      version: appBackupFormatVersion,
      createdAt: DateTime.utc(2026, 8, 14),
      profiles: const [
        ConnectionProfile(
          id: 'a',
          name: 'A',
          host: 'a.local',
          port: 22,
          username: 'a',
        ),
        ConnectionProfile(
          id: 'b',
          name: 'B',
          host: 'b.local',
          port: 22,
          username: 'b',
        ),
      ],
      knownHosts: const [],
      tabs: const [],
      snippets: const [],
      routes: const [
        SshRouteConfiguration(profileId: 'a', jumpProfileIds: ['b']),
        SshRouteConfiguration(profileId: 'b', jumpProfileIds: ['a']),
      ],
      appFont: AppFont.notoSansJp,
      terminalSettings: const TerminalPerformanceSettings(),
    );

    expect(
      () => container
          .read(appBackupControllerProvider)
          .preview(jsonEncode(backup.toJson())),
      throwsA(isA<FormatException>()),
    );
  });
}
