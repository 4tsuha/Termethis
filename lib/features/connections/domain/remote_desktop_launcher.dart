import 'connection_profile.dart';

enum RemoteDesktopLaunchFailureCode {
  unsupportedType,
  noCompatibleApp,
  endpointUnreachable,
  protocolMismatch,
}

class RemoteDesktopLaunchFailure implements Exception {
  const RemoteDesktopLaunchFailure(this.code);

  final RemoteDesktopLaunchFailureCode code;
}

abstract interface class RemoteDesktopLauncher {
  Future<void> launch(ConnectionProfile profile);
}

class UnavailableRemoteDesktopLauncher implements RemoteDesktopLauncher {
  const UnavailableRemoteDesktopLauncher();

  @override
  Future<void> launch(ConnectionProfile profile) {
    throw const RemoteDesktopLaunchFailure(
      RemoteDesktopLaunchFailureCode.noCompatibleApp,
    );
  }
}
