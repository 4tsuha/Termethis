import '../../features/ftp/domain/ftp_gateway.dart';
import '../../features/terminal/domain/ssh_gateway.dart';
import '../../src/rust/api/core.dart' as rust;

class RoutingFtpGateway implements FtpGateway {
  const RoutingFtpGateway(this.ftp, this.sftp);

  final FtpGateway ftp;
  final FtpGateway sftp;

  @override
  Future<FtpConnection> connect(FtpConnectRequest request) {
    return request.securityMode == FtpSecurityMode.sftp
        ? sftp.connect(request)
        : ftp.connect(request);
  }
}

class RustSftpGateway implements FtpGateway {
  RustSftpGateway(this._hostKeys);

  final HostKeyRepository _hostKeys;

  @override
  Future<FtpConnection> connect(FtpConnectRequest request) async {
    final knownHosts = await _hostKeys.find(request.host, request.port);
    var result = await _connect(request, _trustedKeyIdentities(knownHosts));
    if (result.hostKey case final receivedKey?) {
      final received = HostKeyInfo(
        host: request.host,
        port: request.port,
        algorithm: receivedKey.algorithm,
        fingerprintSha256: receivedKey.fingerprintSha256,
      );
      switch (evaluateHostKeyTrust(knownHosts, received)) {
        case HostKeyTrust.mismatch:
          throw StateError('SSH host key mismatch');
        case HostKeyTrust.trusted:
          throw StateError('SSH host key was rejected');
        case HostKeyTrust.unknown:
          final accepted =
              await request.onUnknownHostKey?.call(received) ?? false;
          if (!accepted) throw StateError('SSH host key was rejected');
          await _hostKeys.trust(
            KnownHost(info: received, acceptedAt: DateTime.now()),
          );
          result = await _connect(request, [_hostKeyIdentity(received)]);
      }
    }
    if (result.errorCode != null || result.sessionId == null) {
      throw StateError(result.errorMessage ?? 'SFTP connection failed');
    }
    return RustSftpConnection(result.sessionId!);
  }

  Future<rust.RustSftpConnectResult> _connect(
    FtpConnectRequest request,
    List<String> trustedKeys,
  ) {
    final authentication =
        request.sshAuthentication ??
        SshPasswordAuthentication(request.password);
    return rust.sftpConnect(
      request: rust.RustSftpConnectRequest(
        host: request.host,
        port: request.port,
        username: request.username,
        authKind: authentication is SshPrivateKeyAuthentication
            ? 'private_key'
            : 'password',
        password: authentication is SshPasswordAuthentication
            ? authentication.password
            : '',
        privateKeyPem: authentication is SshPrivateKeyAuthentication
            ? authentication.pem
            : '',
        passphrase: authentication is SshPrivateKeyAuthentication
            ? authentication.passphrase
            : null,
        trustedHostKeys: trustedKeys,
      ),
    );
  }
}

class RustSftpConnection implements SftpFileConnection {
  RustSftpConnection(this._sessionId);

  final int _sessionId;
  bool _closed = false;

  @override
  Future<String> currentDirectory() =>
      rust.sftpCurrentDirectory(sessionId: _sessionId);

  @override
  Future<List<FtpEntryInfo>> listDirectory() async {
    final entries = await rust.sftpListDirectory(sessionId: _sessionId);
    return [
      for (final entry in entries)
        FtpEntryInfo(
          name: entry.name,
          kind: switch (entry.kind) {
            'directory' => FtpEntryKind.directory,
            'file' => FtpEntryKind.file,
            'link' => FtpEntryKind.link,
            _ => FtpEntryKind.unknown,
          },
          size: entry.size,
          modifiedAt: entry.modifiedSeconds == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(
                  entry.modifiedSeconds! * 1000,
                ),
          permissions: entry.permissions,
        ),
    ];
  }

  @override
  Future<void> changeDirectory(String path) =>
      rust.sftpChangeDirectory(sessionId: _sessionId, path: path);

  @override
  Future<void> createDirectory(String name) =>
      rust.sftpCreateDirectory(sessionId: _sessionId, name: name);

  @override
  Future<void> rename(String oldName, String newName) => rust.sftpRename(
    sessionId: _sessionId,
    oldName: oldName,
    newName: newName,
  );

  @override
  Future<void> deleteFile(String name) =>
      rust.sftpDeleteFile(sessionId: _sessionId, name: name);

  @override
  Future<void> deleteEmptyDirectory(String name) =>
      rust.sftpDeleteEmptyDirectory(sessionId: _sessionId, name: name);

  @override
  Future<void> deleteDirectoryRecursive(String name) =>
      rust.sftpDeleteDirectoryRecursive(sessionId: _sessionId, name: name);

  @override
  Future<void> changePermissions(String name, int mode) =>
      rust.sftpSetPermissions(sessionId: _sessionId, name: name, mode: mode);

  @override
  Future<void> downloadFile(String remoteName, String localPath) =>
      rust.sftpDownloadFile(
        sessionId: _sessionId,
        remoteName: remoteName,
        localPath: localPath,
      );

  @override
  Future<void> uploadFile(String localPath, String remoteName) =>
      rust.sftpUploadFile(
        sessionId: _sessionId,
        localPath: localPath,
        remoteName: remoteName,
      );

  @override
  Future<SftpTransferTask> startDownloadFile(
    String remoteName,
    String localPath,
  ) async => _RustSftpTransferTask(
    await rust.sftpStartDownloadFile(
      sessionId: _sessionId,
      remoteName: remoteName,
      localPath: localPath,
    ),
  );

  @override
  Future<SftpTransferTask> startUploadFile(
    String localPath,
    String remoteName,
  ) async => _RustSftpTransferTask(
    await rust.sftpStartUploadFile(
      sessionId: _sessionId,
      localPath: localPath,
      remoteName: remoteName,
    ),
  );

  @override
  Future<SftpTransferTask> startUploadDirectory(
    String localPath,
    String remoteName,
  ) async => _RustSftpTransferTask(
    await rust.sftpStartUploadDirectory(
      sessionId: _sessionId,
      localPath: localPath,
      remoteName: remoteName,
    ),
  );

  @override
  Future<void> uploadDirectory(String localPath, String remoteName) =>
      rust.sftpUploadDirectory(
        sessionId: _sessionId,
        localPath: localPath,
        remoteName: remoteName,
      );

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await rust.sftpClose(sessionId: _sessionId);
  }
}

class _RustSftpTransferTask implements SftpTransferTask {
  const _RustSftpTransferTask(this._transferId);

  final int _transferId;

  @override
  String get id => 'sftp-$_transferId';

  @override
  Future<void> cancel() => rust.sftpCancelTransfer(transferId: _transferId);

  @override
  Future<void> dispose() => rust.sftpForgetTransfer(transferId: _transferId);

  @override
  Future<SftpTransferProgress> progress() async {
    final value = await rust.sftpTransferProgress(transferId: _transferId);
    return SftpTransferProgress(
      id: id,
      name: value.name,
      direction: value.direction == 'download'
          ? SftpTransferDirection.download
          : SftpTransferDirection.upload,
      status: switch (value.state) {
        'completed' => SftpTransferStatus.completed,
        'cancelled' => SftpTransferStatus.cancelled,
        'failed' => SftpTransferStatus.failed,
        _ => SftpTransferStatus.running,
      },
      bytesTransferred: value.bytesTransferred.toInt(),
      totalBytes: value.totalBytes?.toInt(),
      errorMessage: value.errorMessage,
    );
  }
}

List<String> _trustedKeyIdentities(List<KnownHost> knownHosts) => [
  for (final host in knownHosts) _hostKeyIdentity(host.info),
];

String _hostKeyIdentity(HostKeyInfo key) =>
    '${key.algorithm}|${key.fingerprintSha256}';
