import '../../connections/domain/connection_profile.dart';
import '../../settings/domain/credential_settings.dart';
import '../../settings/domain/vault_protection.dart';

enum ConnectionDiagnosticStep { dns, tcp, hostKey, credentials }

enum ConnectionDiagnosticStatus { passed, warning, failed, notApplicable }

class ConnectionDiagnosticItem {
  const ConnectionDiagnosticItem({
    required this.step,
    required this.status,
    required this.title,
    required this.message,
    this.action,
  });

  final ConnectionDiagnosticStep step;
  final ConnectionDiagnosticStatus status;
  final String title;
  final String message;
  final String? action;
}

class ConnectionDiagnosticReport {
  const ConnectionDiagnosticReport({
    required this.profileId,
    required this.completedAt,
    required this.items,
  });

  final String profileId;
  final DateTime completedAt;
  final List<ConnectionDiagnosticItem> items;

  bool get canAttemptConnection =>
      items.every((item) => item.status != ConnectionDiagnosticStatus.failed);
}

class ConnectionSecuritySummary {
  const ConnectionSecuritySummary({
    required this.transport,
    required this.identityVerification,
    required this.credentialProtection,
    required this.warnings,
  });

  final String transport;
  final String identityVerification;
  final String credentialProtection;
  final List<String> warnings;
}

ConnectionSecuritySummary assessConnectionSecurity({
  required ConnectionProfile profile,
  required int knownHostKeys,
  required CredentialSettings credentialSettings,
  required VaultProtectionStatus vaultStatus,
}) {
  final hasSavedCredential = profile.credentialReference != null;
  final credentialProtection = hasSavedCredential
      ? vaultStatus.keyInvalidated
            ? 'Keystore鍵が無効です。認証情報を再登録してください。'
            : vaultStatus.locked
            ? '暗号化Vaultはロックされています。'
            : '保存した認証情報は暗号化Vaultで保護されています。'
      : profile.authenticationType == AuthenticationType.privateKey
      ? '秘密鍵は未登録です。接続先の編集画面で登録してください。'
      : credentialSettings.saveSshPasswords
      ? 'この接続先には保存済みパスワードがありません。'
      : 'パスワードは保存せず、接続時だけ使用します。';
  return switch (profile.connectionType) {
    ConnectionType.ssh || ConnectionType.mosh => ConnectionSecuritySummary(
      transport: profile.connectionType == ConnectionType.ssh
          ? 'SSHで暗号化'
          : 'SSHによる起動後、Moshの暗号化UDP通信',
      identityVerification: knownHostKeys > 0
          ? '保存済みホスト鍵 $knownHostKeys件と照合します。'
          : '初回接続時にホスト鍵の確認が必要です。',
      credentialProtection: credentialProtection,
      warnings: const [],
    ),
    ConnectionType.rdp => ConnectionSecuritySummary(
      transport: 'RDPのTLSセキュリティ層を使用',
      identityVerification: '現在の内蔵RDPはサーバー証明書を検証しません。',
      credentialProtection: credentialProtection,
      warnings: const ['接続先を暗号学的に確認できません。信頼できるVPNまたはSSHトンネル内で使用してください。'],
    ),
    ConnectionType.vnc => ConnectionSecuritySummary(
      transport: 'VNC/RFBの直接接続',
      identityVerification: 'サーバー証明書とホスト鍵の検証はありません。',
      credentialProtection: credentialProtection,
      warnings: const ['通信経路は暗号化されません。VPNまたはSSHトンネル内で使用してください。'],
    ),
    ConnectionType.opencode => ConnectionSecuritySummary(
      transport: 'HTTP接続',
      identityVerification: 'TLS証明書の検証はありません。',
      credentialProtection: credentialProtection,
      warnings: const ['現在のOpenCode接続はHTTP固定です。信頼できるローカルネットワーク内で使用してください。'],
    ),
  };
}

abstract interface class ConnectionReachabilityGateway {
  Future<List<String>> resolve(String host);

  Future<void> connect({
    required String host,
    required int port,
    required Duration timeout,
  });
}
