import 'dart:typed_data';

enum ShizukuPermissionState {
  unavailable,
  unsupported,
  denied,
  deniedPermanently,
  granted,
}

class ShizukuStatus {
  const ShizukuStatus({
    required this.isBinderReady,
    required this.permission,
    required this.isUserServiceConnected,
    required this.isShellPtySupported,
    required this.shellTransport,
    this.serverVersion,
    this.serverUid,
  });

  const ShizukuStatus.unavailable()
    : isBinderReady = false,
      permission = ShizukuPermissionState.unavailable,
      isUserServiceConnected = false,
      isShellPtySupported = false,
      shellTransport = 'pipes',
      serverVersion = null,
      serverUid = null;

  final bool isBinderReady;
  final ShizukuPermissionState permission;
  final bool isUserServiceConnected;
  final bool isShellPtySupported;
  final String shellTransport;
  final int? serverVersion;
  final int? serverUid;

  bool get canUsePrivilegedFeatures =>
      isBinderReady && permission == ShizukuPermissionState.granted;
}

abstract interface class ShizukuDiagnosticsGateway {
  Future<ShizukuStatus> getStatus();

  Future<ShizukuStatus> requestPermission();

  Future<bool> startLogcatCapture({int maxLines = 2000});

  Future<bool> stopLogcatCapture();

  Future<bool> isLogcatCapturing();

  Future<List<String>> getRecentLogcatLines({int limit = 200});

  Future<bool> clearLogcatCapture();

  /// Starts an ADB-shell-equivalent interactive process through Shizuku.
  ///
  /// The current transport uses stdin/stdout pipes rather than a PTY. Programs
  /// that require terminal ioctls or full-screen ncurses behavior are limited.
  Future<bool> startShell();

  Future<bool> writeShellInput(Uint8List input);

  Future<Uint8List> readShellOutput({int maxBytes = 64 * 1024});

  Future<bool> isShellRunning();

  Future<bool> stopShell();
}

class UnavailableShizukuDiagnosticsGateway
    implements ShizukuDiagnosticsGateway {
  const UnavailableShizukuDiagnosticsGateway();

  @override
  Future<ShizukuStatus> getStatus() async => const ShizukuStatus.unavailable();

  @override
  Future<ShizukuStatus> requestPermission() async =>
      const ShizukuStatus.unavailable();

  @override
  Future<bool> startLogcatCapture({int maxLines = 2000}) async => false;

  @override
  Future<bool> stopLogcatCapture() async => false;

  @override
  Future<bool> isLogcatCapturing() async => false;

  @override
  Future<List<String>> getRecentLogcatLines({int limit = 200}) async =>
      const [];

  @override
  Future<bool> clearLogcatCapture() async => false;

  @override
  Future<bool> startShell() async => false;

  @override
  Future<bool> writeShellInput(Uint8List input) async => false;

  @override
  Future<Uint8List> readShellOutput({int maxBytes = 64 * 1024}) async =>
      Uint8List(0);

  @override
  Future<bool> isShellRunning() async => false;

  @override
  Future<bool> stopShell() async => false;
}
