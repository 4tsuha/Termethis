import 'dart:async';

import 'package:dartssh2/dartssh2.dart';

import '../../features/ftp/domain/ftp_gateway.dart';
import '../../features/terminal/domain/ssh_gateway.dart';

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

class DartSftpGateway implements FtpGateway {
  DartSftpGateway(this._hostKeys);

  final HostKeyRepository _hostKeys;

  @override
  Future<FtpConnection> connect(FtpConnectRequest request) async {
    SSHSocket? socket;
    SSHClient? client;
    try {
      final (connectedSocket, knownHosts) = await (
        SSHSocket.connect(
          request.host,
          request.port,
          timeout: const Duration(seconds: 15),
        ),
        _hostKeys.find(request.host, request.port),
      ).wait;
      socket = connectedSocket;
      final authentication =
          request.sshAuthentication ??
          SshPasswordAuthentication(request.password);
      final password = authentication is SshPasswordAuthentication
          ? authentication.password
          : null;
      final identities = authentication is SshPrivateKeyAuthentication
          ? _parseIdentities(authentication)
          : null;
      client = SSHClient(
        socket,
        username: request.username,
        handshakeTimeout: const Duration(seconds: 15),
        authTimeout: const Duration(seconds: 20),
        identities: identities,
        onPasswordRequest: password == null ? null : () => password,
        onUserInfoRequest: password == null
            ? null
            : (prompt) async => [for (final _ in prompt.prompts) password],
        onVerifyHostKey: (algorithm, fingerprintBytes) async {
          final received = HostKeyInfo(
            host: request.host,
            port: request.port,
            algorithm: algorithm,
            fingerprintSha256: String.fromCharCodes(fingerprintBytes),
          );
          final trust = evaluateHostKeyTrust(knownHosts, received);
          if (trust == HostKeyTrust.trusted) return true;
          if (trust == HostKeyTrust.mismatch) return false;
          final accepted =
              await request.onUnknownHostKey?.call(received) ?? false;
          if (accepted) {
            await _hostKeys.trust(
              KnownHost(info: received, acceptedAt: DateTime.now()),
            );
          }
          return accepted;
        },
      );
      final sftp = await client.sftp();
      await sftp.handshake;
      final homePath = await sftp.absolute('.');
      return _DartSftpConnection(client, sftp, homePath);
    } catch (_) {
      client?.close();
      if (client == null && socket != null) await socket.close();
      rethrow;
    }
  }

  List<SSHKeyPair> _parseIdentities(
    SshPrivateKeyAuthentication authentication,
  ) {
    final encrypted = SSHKeyPair.isEncryptedPem(authentication.pem);
    return SSHKeyPair.fromPem(
      authentication.pem,
      encrypted ? authentication.passphrase : null,
    );
  }
}

class _DartSftpConnection implements FtpConnection {
  _DartSftpConnection(this._client, this._sftp, this._path);

  final SSHClient _client;
  final SftpClient _sftp;
  String _path;
  bool _closed = false;

  @override
  Future<void> changeDirectory(String path) async {
    final target = await _sftp.absolute(_resolve(path));
    final attributes = await _sftp.stat(target);
    if (!attributes.isDirectory) throw StateError('Not a directory');
    _path = target;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _sftp.close();
    _client.close();
  }

  @override
  Future<void> createDirectory(String name) => _sftp.mkdir(_resolve(name));

  @override
  Future<String> currentDirectory() async => _path;

  @override
  Future<void> deleteEmptyDirectory(String name) => _sftp.rmdir(_resolve(name));

  @override
  Future<void> deleteFile(String name) => _sftp.remove(_resolve(name));

  @override
  Future<List<FtpEntryInfo>> listDirectory() async {
    final names = await _sftp.listdir(_path);
    return names
        .where((entry) => entry.filename != '.' && entry.filename != '..')
        .map(
          (entry) => FtpEntryInfo(
            name: entry.filename,
            kind: switch (entry.attr.mode?.type) {
              SftpFileType.directory => FtpEntryKind.directory,
              SftpFileType.regularFile => FtpEntryKind.file,
              SftpFileType.symbolicLink => FtpEntryKind.link,
              _ => FtpEntryKind.unknown,
            },
            size: entry.attr.size,
            modifiedAt: entry.attr.modifyTime == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(
                    entry.attr.modifyTime! * 1000,
                  ),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> rename(String oldName, String newName) =>
      _sftp.rename(_resolve(oldName), _resolve(newName));

  String _resolve(String value) {
    if (value.startsWith('/')) return value;
    return _path == '/' ? '/$value' : '$_path/$value';
  }
}
