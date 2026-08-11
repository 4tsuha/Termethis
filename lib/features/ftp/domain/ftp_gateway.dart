import '../../terminal/domain/ssh_gateway.dart';
import '../../connections/domain/connection_profile.dart';

enum FtpSecurityMode { ftp, ftpes, ftps, sftp }

class FtpConnectRequest {
  const FtpConnectRequest({
    required this.tabName,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.securityMode,
    this.onUnknownHostKey,
    this.sshProfile,
    this.sshAuthentication,
  });

  final String tabName;
  final String host;
  final int port;
  final String username;
  final String password;
  final FtpSecurityMode securityMode;
  final HostKeyApprovalHandler? onUnknownHostKey;
  final ConnectionProfile? sshProfile;
  final SshAuthentication? sshAuthentication;

  String get target => '$username@$host:$port';

  FtpConnectRequest withHostKeyApproval(HostKeyApprovalHandler handler) {
    return FtpConnectRequest(
      tabName: tabName,
      host: host,
      port: port,
      username: username,
      password: password,
      securityMode: securityMode,
      onUnknownHostKey: handler,
      sshProfile: sshProfile,
      sshAuthentication: sshAuthentication,
    );
  }

  FtpConnectRequest withSshAuthentication(SshAuthentication authentication) {
    return FtpConnectRequest(
      tabName: tabName,
      host: host,
      port: port,
      username: username,
      password: password,
      securityMode: securityMode,
      onUnknownHostKey: onUnknownHostKey,
      sshProfile: sshProfile,
      sshAuthentication: authentication,
    );
  }
}

enum FtpEntryKind { directory, file, link, unknown }

class FtpEntryInfo {
  const FtpEntryInfo({
    required this.name,
    required this.kind,
    this.size,
    this.modifiedAt,
  });

  final String name;
  final FtpEntryKind kind;
  final int? size;
  final DateTime? modifiedAt;

  bool get isDirectory => kind == FtpEntryKind.directory;
}

abstract interface class FtpGateway {
  Future<FtpConnection> connect(FtpConnectRequest request);
}

abstract interface class FtpConnection {
  Future<String> currentDirectory();
  Future<List<FtpEntryInfo>> listDirectory();
  Future<void> changeDirectory(String path);
  Future<void> createDirectory(String name);
  Future<void> rename(String oldName, String newName);
  Future<void> deleteFile(String name);
  Future<void> deleteEmptyDirectory(String name);
  Future<void> close();
}
