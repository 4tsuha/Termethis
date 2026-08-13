import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../connections/application/connection_profiles_controller.dart';
import '../../connections/domain/connection_profile.dart';
import '../../settings/application/credential_settings_controller.dart';
import '../../terminal/application/session_registry.dart';
import '../../terminal/domain/ssh_gateway.dart';
import '../../../infrastructure/diagnostics/socket_connection_reachability_gateway.dart';
import '../domain/connection_diagnostics.dart';

final connectionReachabilityGatewayProvider =
    Provider<ConnectionReachabilityGateway>(
      (ref) => const SocketConnectionReachabilityGateway(),
    );

final connectionDiagnosticProvider = FutureProvider.autoDispose
    .family<ConnectionDiagnosticReport, String>((ref, profileId) async {
      final profile = await ref
          .watch(connectionProfileRepositoryProvider)
          .findById(profileId);
      if (profile == null) {
        throw StateError('接続先が削除されています。');
      }
      final gateway = ref.watch(connectionReachabilityGatewayProvider);
      final items = <ConnectionDiagnosticItem>[];
      try {
        final addresses = await gateway.resolve(profile.host);
        if (addresses.isEmpty) throw StateError('No address');
        items.add(
          ConnectionDiagnosticItem(
            step: ConnectionDiagnosticStep.dns,
            status: ConnectionDiagnosticStatus.passed,
            title: '名前解決',
            message: addresses.take(3).join(' / '),
          ),
        );
      } catch (_) {
        items.add(
          const ConnectionDiagnosticItem(
            step: ConnectionDiagnosticStep.dns,
            status: ConnectionDiagnosticStatus.failed,
            title: '名前解決',
            message: 'ホスト名をIPアドレスへ変換できませんでした。',
            action: 'ホスト名、DNS、ネットワーク接続を確認してください。',
          ),
        );
        return ConnectionDiagnosticReport(
          profileId: profile.id,
          completedAt: DateTime.now(),
          items: items,
        );
      }

      try {
        await gateway.connect(
          host: profile.host,
          port: profile.port,
          timeout: const Duration(seconds: 5),
        );
        items.add(
          ConnectionDiagnosticItem(
            step: ConnectionDiagnosticStep.tcp,
            status: ConnectionDiagnosticStatus.passed,
            title: 'ポート到達性',
            message: '${profile.host}:${profile.port}へ接続できます。',
          ),
        );
      } catch (_) {
        items.add(
          ConnectionDiagnosticItem(
            step: ConnectionDiagnosticStep.tcp,
            status: ConnectionDiagnosticStatus.failed,
            title: 'ポート到達性',
            message: '${profile.host}:${profile.port}へ接続できません。',
            action: '接続先の起動状態、ポート番号、ファイアウォールを確認してください。',
          ),
        );
      }

      final usesHostKey = profile.connectionType.usesSshAuthentication;
      final knownHosts = usesHostKey
          ? await ref
                .watch(hostKeyRepositoryProvider)
                .find(profile.host, profile.port)
          : const <KnownHost>[];
      items.add(
        ConnectionDiagnosticItem(
          step: ConnectionDiagnosticStep.hostKey,
          status: !usesHostKey
              ? ConnectionDiagnosticStatus.notApplicable
              : knownHosts.isEmpty
              ? ConnectionDiagnosticStatus.warning
              : ConnectionDiagnosticStatus.passed,
          title: '接続先の本人確認',
          message: !usesHostKey
              ? 'この方式ではSSHホスト鍵を使用しません。'
              : knownHosts.isEmpty
              ? '保存済みホスト鍵がありません。初回接続時に確認します。'
              : '保存済みホスト鍵 ${knownHosts.length}件を接続時に照合します。',
          action: usesHostKey && knownHosts.isEmpty
              ? '表示されるフィンガープリントを管理者へ確認してください。'
              : null,
        ),
      );

      final vault = await ref.watch(vaultProtectionStatusProvider.future);
      final hasCredential = profile.credentialReference != null;
      final missingRequiredKey =
          profile.authenticationType == AuthenticationType.privateKey &&
          !hasCredential;
      items.add(
        ConnectionDiagnosticItem(
          step: ConnectionDiagnosticStep.credentials,
          status: missingRequiredKey
              ? ConnectionDiagnosticStatus.failed
              : !hasCredential
              ? ConnectionDiagnosticStatus.warning
              : vault.keyInvalidated
              ? ConnectionDiagnosticStatus.failed
              : vault.locked
              ? ConnectionDiagnosticStatus.warning
              : ConnectionDiagnosticStatus.passed,
          title: '認証情報',
          message: missingRequiredKey
              ? '秘密鍵が登録されていません。'
              : !hasCredential
              ? '保存済み認証情報はありません。接続時に入力が必要です。'
              : vault.keyInvalidated
              ? 'Keystore鍵が無効になっています。'
              : vault.locked
              ? 'Vaultはロックされています。'
              : '保存済み認証情報を利用できます。',
          action: missingRequiredKey
              ? '接続先の編集画面で秘密鍵を登録してください。'
              : vault.keyInvalidated
              ? '接続先の編集画面で認証情報を再登録してください。'
              : vault.locked
              ? '接続時に端末認証でVaultを解錠してください。'
              : null,
        ),
      );
      return ConnectionDiagnosticReport(
        profileId: profile.id,
        completedAt: DateTime.now(),
        items: items,
      );
    });

final connectionSecurityProvider = FutureProvider.autoDispose
    .family<ConnectionSecuritySummary, String>((ref, profileId) async {
      final profile = await ref
          .watch(connectionProfileRepositoryProvider)
          .findById(profileId);
      if (profile == null) throw StateError('接続先が削除されています。');
      final knownHosts = profile.connectionType.usesSshAuthentication
          ? await ref
                .watch(hostKeyRepositoryProvider)
                .find(profile.host, profile.port)
          : const <KnownHost>[];
      return assessConnectionSecurity(
        profile: profile,
        knownHostKeys: knownHosts.length,
        credentialSettings: ref.watch(credentialSettingsProvider),
        vaultStatus: await ref.watch(vaultProtectionStatusProvider.future),
      );
    });
