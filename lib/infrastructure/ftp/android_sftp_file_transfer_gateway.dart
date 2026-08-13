import 'package:flutter/services.dart';

class LocalTransferFile {
  const LocalTransferFile({required this.name, required this.path});

  final String name;
  final String path;

  factory LocalTransferFile.fromMap(Object? value) {
    final map = Map<Object?, Object?>.from(value! as Map);
    return LocalTransferFile(
      name: map['name']! as String,
      path: map['path']! as String,
    );
  }
}

class AndroidSftpFileTransferGateway {
  const AndroidSftpFileTransferGateway({
    this._channel = const MethodChannel('jp.yts.termethis/sftp_file_transfer'),
  });

  final MethodChannel _channel;

  Future<List<LocalTransferFile>> pickFiles() async {
    final values = await _channel.invokeListMethod<Object?>('pickFiles');
    return values?.map(LocalTransferFile.fromMap).toList(growable: false) ??
        const [];
  }

  Future<LocalTransferFile?> pickDirectory() async {
    final value = await _channel.invokeMethod<Object?>('pickDirectory');
    return value == null ? null : LocalTransferFile.fromMap(value);
  }

  Future<bool> exportFile({
    required String localPath,
    required String fileName,
    String mimeType = 'application/octet-stream',
  }) async =>
      await _channel.invokeMethod<bool>('exportFile', {
        'localPath': localPath,
        'fileName': fileName,
        'mimeType': mimeType,
      }) ??
      false;
}
