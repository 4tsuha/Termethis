import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/ftp_gateway.dart';

final sftpTransferManagerProvider =
    NotifierProvider<SftpTransferManager, List<ManagedSftpTransfer>>(
      SftpTransferManager.new,
    );

enum ManagedTransferStatus {
  running,
  readyToSave,
  completed,
  cancelled,
  failed,
}

class ManagedSftpTransfer {
  const ManagedSftpTransfer({
    required this.id,
    required this.tabId,
    required this.name,
    required this.direction,
    required this.status,
    required this.bytesTransferred,
    required this.startedAt,
    this.totalBytes,
    this.localPath,
    this.finishedAt,
    this.errorMessage,
  });

  final String id;
  final String tabId;
  final String name;
  final SftpTransferDirection direction;
  final ManagedTransferStatus status;
  final int bytesTransferred;
  final int? totalBytes;
  final String? localPath;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final String? errorMessage;

  double? get fraction => switch (totalBytes) {
    final total? when total > 0 => (bytesTransferred / total).clamp(0, 1),
    _ => null,
  };

  bool get isActive => status == ManagedTransferStatus.running;
  bool get canRetry => status == ManagedTransferStatus.failed;

  ManagedSftpTransfer copyWith({
    ManagedTransferStatus? status,
    int? bytesTransferred,
    int? totalBytes,
    bool clearTotalBytes = false,
    DateTime? startedAt,
    DateTime? finishedAt,
    bool clearFinishedAt = false,
    String? errorMessage,
    bool clearError = false,
  }) => ManagedSftpTransfer(
    id: id,
    tabId: tabId,
    name: name,
    direction: direction,
    status: status ?? this.status,
    bytesTransferred: bytesTransferred ?? this.bytesTransferred,
    totalBytes: clearTotalBytes ? null : totalBytes ?? this.totalBytes,
    localPath: localPath,
    startedAt: startedAt ?? this.startedAt,
    finishedAt: clearFinishedAt ? null : finishedAt ?? this.finishedAt,
    errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
  );
}

class SftpTransferManager extends Notifier<List<ManagedSftpTransfer>> {
  static const _pollInterval = Duration(milliseconds: 100);
  static const _historyLimit = 30;

  final Map<String, _ManagedTask> _tasks = {};

  @override
  List<ManagedSftpTransfer> build() {
    ref.onDispose(() {
      for (final managed in _tasks.values) {
        unawaited(_cancelAndCleanup(managed));
      }
      _tasks.clear();
    });
    return const [];
  }

  Future<void> _cancelAndCleanup(_ManagedTask managed) async {
    final task = managed.task;
    try {
      if (task != null) {
        try {
          await task.cancel();
          for (var attempt = 0; attempt < 100; attempt++) {
            final progress = await task.progress();
            if (progress.isFinished) break;
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
        } finally {
          await task.dispose();
        }
      }
    } finally {
      await managed.cleanup();
    }
  }

  Future<String> startDownload({
    required String tabId,
    required String name,
    required String localPath,
    required Future<SftpTransferTask> Function() start,
    required Future<void> Function() cleanup,
  }) => _start(
    tabId: tabId,
    name: name,
    direction: SftpTransferDirection.download,
    localPath: localPath,
    start: start,
    cleanup: cleanup,
  );

  Future<String> startUpload({
    required String tabId,
    required String name,
    required Future<SftpTransferTask> Function() start,
    required Future<void> Function() cleanup,
    Future<void> Function()? onCompleted,
  }) => _start(
    tabId: tabId,
    name: name,
    direction: SftpTransferDirection.upload,
    start: start,
    cleanup: cleanup,
    onCompleted: onCompleted,
  );

  Future<void> retry(String id) async {
    final managed = _tasks[id];
    if (managed == null || _find(id)?.canRetry != true) return;
    await managed.task?.dispose();
    managed.task = null;
    _replace(
      id,
      (item) => item.copyWith(
        status: ManagedTransferStatus.running,
        bytesTransferred: 0,
        clearTotalBytes: true,
        startedAt: DateTime.now(),
        clearFinishedAt: true,
        clearError: true,
      ),
    );
    await _launch(id, managed);
  }

  Future<void> cancel(String id) async {
    final managed = _tasks[id];
    if (managed == null || _find(id)?.isActive != true) return;
    await managed.task?.cancel();
  }

  Future<void> cancelForTab(String tabId) async {
    final ids = [
      for (final item in state)
        if (item.tabId == tabId) item.id,
    ];
    for (final id in ids) {
      if (_find(id)?.isActive == true) {
        await cancel(id);
        await _waitUntilFinished(id);
      }
      await remove(id);
    }
  }

  Future<void> markSaved(String id) async {
    final item = _find(id);
    if (item?.status != ManagedTransferStatus.readyToSave) return;
    _replace(
      id,
      (current) => current.copyWith(
        status: ManagedTransferStatus.completed,
        finishedAt: DateTime.now(),
      ),
    );
    await _releaseResources(id);
  }

  Future<void> remove(String id) async {
    final item = _find(id);
    if (item == null) return;
    if (item.isActive) {
      await cancel(id);
      return;
    }
    state = state.where((entry) => entry.id != id).toList(growable: false);
    await _releaseResources(id);
  }

  Future<void> _waitUntilFinished(String id) async {
    for (var attempt = 0; attempt < 100; attempt++) {
      if (_find(id)?.isActive != true) return;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  Future<String> _start({
    required String tabId,
    required String name,
    required SftpTransferDirection direction,
    required Future<SftpTransferTask> Function() start,
    required Future<void> Function() cleanup,
    String? localPath,
    Future<void> Function()? onCompleted,
  }) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final managed = _ManagedTask(
      start: start,
      cleanup: cleanup,
      onCompleted: onCompleted,
    );
    _tasks[id] = managed;
    final retained = [...state];
    final evicted = <ManagedSftpTransfer>[];
    while (retained.length >= _historyLimit) {
      final removable = retained.lastIndexWhere((item) => !item.isActive);
      if (removable < 0) break;
      evicted.add(retained.removeAt(removable));
    }
    state = [
      ManagedSftpTransfer(
        id: id,
        tabId: tabId,
        name: name,
        direction: direction,
        status: ManagedTransferStatus.running,
        bytesTransferred: 0,
        localPath: localPath,
        startedAt: DateTime.now(),
      ),
      ...retained,
    ];
    for (final item in evicted) {
      unawaited(_releaseResources(item.id));
    }
    await _launch(id, managed);
    return id;
  }

  Future<void> _launch(String id, _ManagedTask managed) async {
    try {
      managed.task = await managed.start();
      unawaited(_monitor(id, managed));
    } catch (error) {
      _fail(id, error);
    }
  }

  Future<void> _monitor(String id, _ManagedTask managed) async {
    while (_tasks[id] == managed) {
      try {
        final progress = await managed.task!.progress();
        if (_find(id) == null) return;
        switch (progress.status) {
          case SftpTransferStatus.running:
            _replace(
              id,
              (item) => item.copyWith(
                bytesTransferred: progress.bytesTransferred,
                totalBytes: progress.totalBytes,
                clearTotalBytes: progress.totalBytes == null,
              ),
            );
            await Future<void>.delayed(_pollInterval);
          case SftpTransferStatus.completed:
            if (_find(id)?.direction == SftpTransferDirection.upload) {
              await managed.onCompleted?.call();
              _replace(
                id,
                (item) => item.copyWith(
                  status: ManagedTransferStatus.completed,
                  bytesTransferred: progress.bytesTransferred,
                  totalBytes: progress.totalBytes,
                  finishedAt: DateTime.now(),
                ),
              );
              await _releaseResources(id);
            } else {
              _replace(
                id,
                (item) => item.copyWith(
                  status: ManagedTransferStatus.readyToSave,
                  bytesTransferred: progress.bytesTransferred,
                  totalBytes: progress.totalBytes,
                  finishedAt: DateTime.now(),
                ),
              );
              await managed.task?.dispose();
              managed.task = null;
            }
            return;
          case SftpTransferStatus.cancelled:
            _replace(
              id,
              (item) => item.copyWith(
                status: ManagedTransferStatus.cancelled,
                bytesTransferred: progress.bytesTransferred,
                finishedAt: DateTime.now(),
              ),
            );
            await _releaseResources(id);
            return;
          case SftpTransferStatus.failed:
            _fail(id, progress.errorMessage ?? '転送に失敗しました。');
            await managed.task?.dispose();
            managed.task = null;
            return;
        }
      } catch (error) {
        _fail(id, error);
        await managed.task?.dispose();
        managed.task = null;
        return;
      }
    }
  }

  void _fail(String id, Object error) {
    _replace(
      id,
      (item) => item.copyWith(
        status: ManagedTransferStatus.failed,
        finishedAt: DateTime.now(),
        errorMessage: _safeError(error),
      ),
    );
  }

  String _safeError(Object error) {
    final message = error.toString().replaceFirst('Exception: ', '').trim();
    return message.isEmpty ? '転送に失敗しました。' : message;
  }

  Future<void> _releaseResources(String id) async {
    final managed = _tasks.remove(id);
    if (managed == null) return;
    try {
      await managed.task?.dispose();
    } finally {
      await managed.cleanup();
    }
  }

  ManagedSftpTransfer? _find(String id) {
    for (final item in state) {
      if (item.id == id) return item;
    }
    return null;
  }

  void _replace(
    String id,
    ManagedSftpTransfer Function(ManagedSftpTransfer item) transform,
  ) {
    if (_find(id) == null) return;
    state = [
      for (final item in state)
        if (item.id == id) transform(item) else item,
    ];
  }
}

class _ManagedTask {
  _ManagedTask({required this.start, required this.cleanup, this.onCompleted});

  final Future<SftpTransferTask> Function() start;
  final Future<void> Function() cleanup;
  final Future<void> Function()? onCompleted;
  SftpTransferTask? task;
}
