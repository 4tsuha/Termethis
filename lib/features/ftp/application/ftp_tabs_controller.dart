import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../infrastructure/ftp/ftp_connect_gateway.dart';
import '../../../infrastructure/ftp/rust_sftp_gateway.dart';
import '../../terminal/application/session_registry.dart';
import '../domain/ftp_gateway.dart';
import 'sftp_transfer_manager.dart';

final ftpGatewayProvider = Provider<FtpGateway>(
  (ref) => RoutingFtpGateway(
    const FtpConnectGateway(),
    RustSftpGateway(ref.watch(hostKeyRepositoryProvider)),
  ),
);

final ftpTabsProvider = NotifierProvider<FtpTabsController, List<FtpTabState>>(
  FtpTabsController.new,
);

enum FtpTabStatus { connecting, connected, failed }

class FtpTabState {
  const FtpTabState({
    required this.id,
    required this.request,
    required this.status,
    required this.path,
    required this.entries,
    required this.isBusy,
    this.connection,
    this.hasOperationError = false,
  });

  final String id;
  final FtpConnectRequest request;
  final FtpTabStatus status;
  final String path;
  final List<FtpEntryInfo> entries;
  final bool isBusy;
  final FtpConnection? connection;
  final bool hasOperationError;

  FtpTabState copyWith({
    FtpTabStatus? status,
    String? path,
    List<FtpEntryInfo>? entries,
    bool? isBusy,
    FtpConnection? connection,
    bool clearConnection = false,
    bool? hasOperationError,
  }) {
    return FtpTabState(
      id: id,
      request: request,
      status: status ?? this.status,
      path: path ?? this.path,
      entries: entries ?? this.entries,
      isBusy: isBusy ?? this.isBusy,
      connection: clearConnection ? null : connection ?? this.connection,
      hasOperationError: hasOperationError ?? this.hasOperationError,
    );
  }
}

class FtpTabsController extends Notifier<List<FtpTabState>> {
  late FtpGateway _gateway;
  final Set<FtpConnection> _openConnections = {};

  @override
  List<FtpTabState> build() {
    _gateway = ref.watch(ftpGatewayProvider);
    ref.onDispose(() {
      for (final connection in _openConnections) {
        unawaited(connection.close());
      }
      _openConnections.clear();
    });
    return const [];
  }

  String openTab(FtpConnectRequest request) {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    state = [
      ...state,
      FtpTabState(
        id: id,
        request: request,
        status: FtpTabStatus.connecting,
        path: '/',
        entries: const [],
        isBusy: true,
      ),
    ];
    unawaited(_connect(id));
    return id;
  }

  Future<void> retry(String id) async {
    final oldConnection = _find(id)?.connection;
    if (oldConnection != null) {
      _openConnections.remove(oldConnection);
      await oldConnection.close();
    }
    _replace(
      id,
      (tab) => tab.copyWith(
        status: FtpTabStatus.connecting,
        isBusy: true,
        clearConnection: true,
        hasOperationError: false,
      ),
    );
    await _connect(id);
  }

  Future<void> closeTab(String id) async {
    final tab = _find(id);
    await ref.read(sftpTransferManagerProvider.notifier).cancelForTab(id);
    state = state.where((item) => item.id != id).toList(growable: false);
    final connection = tab?.connection;
    if (connection != null) {
      _openConnections.remove(connection);
      await connection.close();
    }
  }

  Future<void> refresh(String id) => _loadDirectory(id);

  Future<void> enterDirectory(String id, String name) async {
    await _runOperation(id, (connection) => connection.changeDirectory(name));
  }

  Future<void> goToDirectory(String id, String path) async {
    await _runOperation(id, (connection) => connection.changeDirectory(path));
  }

  Future<void> createDirectory(String id, String name) async {
    await _runOperation(id, (connection) => connection.createDirectory(name));
  }

  Future<void> renameEntry(String id, String oldName, String newName) async {
    await _runOperation(
      id,
      (connection) => connection.rename(oldName, newName),
    );
  }

  Future<void> deleteEntry(String id, FtpEntryInfo entry) async {
    await _runOperation(
      id,
      (connection) => entry.isDirectory
          ? connection is SftpFileConnection
                ? connection.deleteDirectoryRecursive(entry.name)
                : connection.deleteEmptyDirectory(entry.name)
          : connection.deleteFile(entry.name),
    );
  }

  Future<void> changePermissions(String id, String name, int mode) =>
      _runSftpOperation(
        id,
        (connection) => connection.changePermissions(name, mode),
      );

  Future<void> downloadFile(String id, String remoteName, String localPath) =>
      _runSftpOperation(
        id,
        (connection) => connection.downloadFile(remoteName, localPath),
        refreshDirectory: false,
      );

  Future<void> uploadFile(String id, String localPath, String remoteName) =>
      _runSftpOperation(
        id,
        (connection) => connection.uploadFile(localPath, remoteName),
      );

  Future<void> uploadDirectory(
    String id,
    String localPath,
    String remoteName,
  ) => _runSftpOperation(
    id,
    (connection) => connection.uploadDirectory(localPath, remoteName),
  );

  Future<String?> startDownloadFile({
    required String id,
    required String remoteName,
    required String localPath,
    required Future<void> Function() cleanup,
  }) async {
    final connection = _find(id)?.connection;
    if (connection is! SftpFileConnection) return null;
    return ref
        .read(sftpTransferManagerProvider.notifier)
        .startDownload(
          tabId: id,
          name: remoteName,
          localPath: localPath,
          start: () => connection.startDownloadFile(remoteName, localPath),
          cleanup: cleanup,
        );
  }

  Future<String?> startUploadFile({
    required String id,
    required String localPath,
    required String remoteName,
    required Future<void> Function() cleanup,
  }) async {
    final connection = _find(id)?.connection;
    if (connection is! SftpFileConnection) return null;
    return ref
        .read(sftpTransferManagerProvider.notifier)
        .startUpload(
          tabId: id,
          name: remoteName,
          start: () => connection.startUploadFile(localPath, remoteName),
          cleanup: cleanup,
          onCompleted: () => _loadDirectory(id),
        );
  }

  Future<String?> startUploadDirectory({
    required String id,
    required String localPath,
    required String remoteName,
    required Future<void> Function() cleanup,
  }) async {
    final connection = _find(id)?.connection;
    if (connection is! SftpFileConnection) return null;
    return ref
        .read(sftpTransferManagerProvider.notifier)
        .startUpload(
          tabId: id,
          name: remoteName,
          start: () => connection.startUploadDirectory(localPath, remoteName),
          cleanup: cleanup,
          onCompleted: () => _loadDirectory(id),
        );
  }

  void clearOperationError(String id) {
    _replace(id, (tab) => tab.copyWith(hasOperationError: false));
  }

  Future<void> _connect(String id) async {
    final tab = _find(id);
    if (tab == null) return;
    try {
      final connection = await _gateway.connect(tab.request);
      if (_find(id) == null) {
        await connection.close();
        return;
      }
      _openConnections.add(connection);
      _replace(
        id,
        (current) => current.copyWith(
          connection: connection,
          status: FtpTabStatus.connected,
          hasOperationError: false,
        ),
      );
      await _loadDirectory(id);
    } catch (_) {
      _replace(
        id,
        (current) => current.copyWith(
          status: FtpTabStatus.failed,
          isBusy: false,
          clearConnection: true,
        ),
      );
    }
  }

  Future<void> _runOperation(
    String id,
    Future<void> Function(FtpConnection connection) operation,
  ) async {
    final connection = _find(id)?.connection;
    if (connection == null) return;
    _replace(id, (tab) => tab.copyWith(isBusy: true, hasOperationError: false));
    try {
      await operation(connection);
      await _loadDirectory(id, markBusy: false);
    } catch (_) {
      _replace(
        id,
        (tab) => tab.copyWith(isBusy: false, hasOperationError: true),
      );
    }
  }

  Future<void> _runSftpOperation(
    String id,
    Future<void> Function(SftpFileConnection connection) operation, {
    bool refreshDirectory = true,
  }) async {
    final connection = _find(id)?.connection;
    if (connection is! SftpFileConnection) return;
    _replace(id, (tab) => tab.copyWith(isBusy: true, hasOperationError: false));
    try {
      await operation(connection);
      if (refreshDirectory) {
        await _loadDirectory(id, markBusy: false);
      } else {
        _replace(id, (tab) => tab.copyWith(isBusy: false));
      }
    } catch (_) {
      _replace(
        id,
        (tab) => tab.copyWith(isBusy: false, hasOperationError: true),
      );
    }
  }

  Future<void> _loadDirectory(String id, {bool markBusy = true}) async {
    final connection = _find(id)?.connection;
    if (connection == null) return;
    if (markBusy) {
      _replace(
        id,
        (tab) => tab.copyWith(isBusy: true, hasOperationError: false),
      );
    }
    try {
      final path = await connection.currentDirectory();
      final entries = [...await connection.listDirectory()];
      entries.sort(_compareEntries);
      _replace(
        id,
        (tab) => tab.copyWith(
          path: path,
          entries: entries,
          status: FtpTabStatus.connected,
          isBusy: false,
          hasOperationError: false,
        ),
      );
    } catch (_) {
      _replace(
        id,
        (tab) => tab.copyWith(isBusy: false, hasOperationError: true),
      );
    }
  }

  int _compareEntries(FtpEntryInfo left, FtpEntryInfo right) {
    if (left.isDirectory != right.isDirectory) {
      return left.isDirectory ? -1 : 1;
    }
    return left.name.toLowerCase().compareTo(right.name.toLowerCase());
  }

  FtpTabState? _find(String id) {
    for (final tab in state) {
      if (tab.id == id) return tab;
    }
    return null;
  }

  void _replace(String id, FtpTabState Function(FtpTabState tab) transform) {
    if (_find(id) == null) return;
    state = [
      for (final tab in state)
        if (tab.id == id) transform(tab) else tab,
    ];
  }
}
