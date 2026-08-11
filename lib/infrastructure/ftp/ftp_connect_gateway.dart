import 'package:ftpconnect/ftpconnect.dart';

import '../../features/ftp/domain/ftp_gateway.dart';

class FtpConnectGateway implements FtpGateway {
  const FtpConnectGateway();

  @override
  Future<FtpConnection> connect(FtpConnectRequest request) async {
    final client = FTPConnect(
      request.host,
      port: request.port,
      user: request.username,
      pass: request.password,
      securityType: _securityType(request.securityMode),
      timeout: 15,
    );

    final connected = await client.connect();
    if (!connected) {
      throw const FtpConnectionException();
    }
    return _FtpConnectConnection(client);
  }
}

class FtpConnectionException implements Exception {
  const FtpConnectionException();
}

SecurityType _securityType(FtpSecurityMode mode) => switch (mode) {
  FtpSecurityMode.ftp => SecurityType.ftp,
  FtpSecurityMode.ftpes => SecurityType.ftpes,
  FtpSecurityMode.ftps => SecurityType.ftps,
  FtpSecurityMode.sftp => throw UnsupportedError('SFTP uses DartSftpGateway'),
};

class _FtpConnectConnection implements FtpConnection {
  _FtpConnectConnection(this._client);

  final FTPConnect _client;
  bool _closed = false;

  @override
  Future<void> changeDirectory(String path) async {
    if (!await _client.changeDirectory(path)) {
      throw const FtpConnectionException();
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _client.disconnect();
  }

  @override
  Future<void> createDirectory(String name) async {
    if (!await _client.makeDirectory(name)) {
      throw const FtpConnectionException();
    }
  }

  @override
  Future<String> currentDirectory() => _client.currentDirectory();

  @override
  Future<void> deleteEmptyDirectory(String name) async {
    if (!await _client.deleteEmptyDirectory(name)) {
      throw const FtpConnectionException();
    }
  }

  @override
  Future<void> deleteFile(String name) async {
    if (!await _client.deleteFile(name)) {
      throw const FtpConnectionException();
    }
  }

  @override
  Future<List<FtpEntryInfo>> listDirectory() async {
    final entries = await _client.listDirectoryContent();
    return entries
        .where((entry) => entry.name != '.' && entry.name != '..')
        .map(
          (entry) => FtpEntryInfo(
            name: entry.name,
            kind: switch (entry.type) {
              FTPEntryType.dir => FtpEntryKind.directory,
              FTPEntryType.file => FtpEntryKind.file,
              FTPEntryType.link => FtpEntryKind.link,
              FTPEntryType.unknown => FtpEntryKind.unknown,
            },
            size: entry.size,
            modifiedAt: entry.modifyTime,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> rename(String oldName, String newName) async {
    if (!await _client.rename(oldName, newName)) {
      throw const FtpConnectionException();
    }
  }
}
