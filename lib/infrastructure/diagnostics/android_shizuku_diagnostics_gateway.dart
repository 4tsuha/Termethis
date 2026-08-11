import 'package:flutter/services.dart';

import '../../features/diagnostics/domain/shizuku_diagnostics_gateway.dart';

class AndroidShizukuDiagnosticsGateway implements ShizukuDiagnosticsGateway {
  const AndroidShizukuDiagnosticsGateway();

  static const _channel = MethodChannel('jp.yts.termethis/shizuku_diagnostics');

  @override
  Future<ShizukuStatus> getStatus() async {
    try {
      return _statusFromMap(
        await _channel.invokeMapMethod<String, Object?>('getStatus'),
      );
    } on MissingPluginException {
      return const ShizukuStatus.unavailable();
    }
  }

  @override
  Future<ShizukuStatus> requestPermission() async => _statusFromMap(
    await _channel.invokeMapMethod<String, Object?>('requestPermission'),
  );

  @override
  Future<bool> startLogcatCapture({int maxLines = 2000}) async =>
      await _channel.invokeMethod<bool>('startLogcatCapture', {
        'maxLines': maxLines,
      }) ??
      false;

  @override
  Future<bool> stopLogcatCapture() async =>
      await _channel.invokeMethod<bool>('stopLogcatCapture') ?? false;

  @override
  Future<bool> isLogcatCapturing() async =>
      await _channel.invokeMethod<bool>('isLogcatCapturing') ?? false;

  @override
  Future<List<String>> getRecentLogcatLines({int limit = 200}) async {
    final lines = await _channel.invokeListMethod<String>(
      'getRecentLogcatLines',
      {'limit': limit},
    );
    return lines ?? const [];
  }

  @override
  Future<bool> clearLogcatCapture() async =>
      await _channel.invokeMethod<bool>('clearLogcatCapture') ?? false;

  @override
  Future<bool> startShell() async =>
      await _channel.invokeMethod<bool>('startShell') ?? false;

  @override
  Future<bool> writeShellInput(Uint8List input) async =>
      await _channel.invokeMethod<bool>('writeShellInput', {'input': input}) ??
      false;

  @override
  Future<Uint8List> readShellOutput({int maxBytes = 64 * 1024}) async =>
      await _channel.invokeMethod<Uint8List>('readShellOutput', {
        'maxBytes': maxBytes,
      }) ??
      Uint8List(0);

  @override
  Future<bool> isShellRunning() async =>
      await _channel.invokeMethod<bool>('isShellRunning') ?? false;

  @override
  Future<bool> stopShell() async =>
      await _channel.invokeMethod<bool>('stopShell') ?? false;

  ShizukuStatus _statusFromMap(Map<String, Object?>? value) {
    if (value == null) return const ShizukuStatus.unavailable();
    final permissionName = value['permission'] as String?;
    return ShizukuStatus(
      isBinderReady: value['binderReady'] == true,
      permission: ShizukuPermissionState.values.firstWhere(
        (state) => state.name == permissionName,
        orElse: () => ShizukuPermissionState.unavailable,
      ),
      isUserServiceConnected: value['userServiceConnected'] == true,
      isShellPtySupported: value['shellPtySupported'] == true,
      shellTransport: value['shellTransport'] as String? ?? 'pipes',
      serverVersion: value['serverVersion'] as int?,
      serverUid: value['serverUid'] as int?,
    );
  }
}
