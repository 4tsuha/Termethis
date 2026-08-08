enum FtpSecurityMode { ftp, ftpes, ftps }

class FtpConnectRequest {
  const FtpConnectRequest({
    required this.tabName,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.securityMode,
  });

  final String tabName;
  final String host;
  final int port;
  final String username;
  final String password;
  final FtpSecurityMode securityMode;

  String get target => '$username@$host:$port';
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
