import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termethis/features/ftp/application/sftp_transfer_manager.dart';
import 'package:termethis/features/ftp/domain/ftp_gateway.dart';

void main() {
  test('アップロード完了後に履歴を残して一時データを解放する', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    var cleaned = false;
    final manager = container.read(sftpTransferManagerProvider.notifier);
    final id = await manager.startUpload(
      tabId: 'tab-1',
      name: 'archive.zip',
      start: () async => _FakeTransferTask(
        const SftpTransferProgress(
          id: 'native-1',
          name: 'archive.zip',
          direction: SftpTransferDirection.upload,
          status: SftpTransferStatus.completed,
          bytesTransferred: 4096,
          totalBytes: 4096,
        ),
      ),
      cleanup: () async => cleaned = true,
    );

    await _waitUntil(
      () =>
          container
              .read(sftpTransferManagerProvider)
              .firstWhere((item) => item.id == id)
              .status ==
          ManagedTransferStatus.completed,
    );
    final transfer = container
        .read(sftpTransferManagerProvider)
        .firstWhere((item) => item.id == id);
    expect(transfer.bytesTransferred, 4096);
    expect(transfer.fraction, 1);
    expect(cleaned, isTrue);
  });

  test('ダウンロードは利用者が保存するまで一時データを維持する', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    var cleaned = false;
    final manager = container.read(sftpTransferManagerProvider.notifier);
    final id = await manager.startDownload(
      tabId: 'tab-1',
      name: 'report.txt',
      localPath: 'cache/report.txt',
      start: () async => _FakeTransferTask(
        const SftpTransferProgress(
          id: 'native-2',
          name: 'report.txt',
          direction: SftpTransferDirection.download,
          status: SftpTransferStatus.completed,
          bytesTransferred: 128,
          totalBytes: 128,
        ),
      ),
      cleanup: () async => cleaned = true,
    );

    await _waitUntil(
      () =>
          container
              .read(sftpTransferManagerProvider)
              .firstWhere((item) => item.id == id)
              .status ==
          ManagedTransferStatus.readyToSave,
    );
    expect(cleaned, isFalse);
    await manager.markSaved(id);
    expect(cleaned, isTrue);
  });
}

class _FakeTransferTask implements SftpTransferTask {
  _FakeTransferTask(this.value);

  final SftpTransferProgress value;

  @override
  String get id => value.id;

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<SftpTransferProgress> progress() async => value;
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw TimeoutException('condition was not reached');
}
