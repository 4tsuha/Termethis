import 'package:flutter/services.dart';

import '../../features/connections/domain/connection_profile.dart';
import '../../features/connections/domain/remote_desktop_launcher.dart';

class AndroidRemoteDesktopLauncher implements RemoteDesktopLauncher {
  const AndroidRemoteDesktopLauncher();

  static const _channel = MethodChannel('jp.yts.termethis/remote_desktop');

  @override
  Future<void> launch(ConnectionProfile profile) async {
    if (profile.connectionType == ConnectionType.ssh) {
      throw const RemoteDesktopLaunchFailure(
        RemoteDesktopLaunchFailureCode.unsupportedType,
      );
    }
    try {
      await _channel.invokeMethod<void>('launch', {
        'type': profile.connectionType.name,
        'host': profile.host,
        'port': profile.port,
        'username': profile.username,
      });
    } on PlatformException catch (error) {
      final failureCode = switch (error.code) {
        'no_compatible_app' => RemoteDesktopLaunchFailureCode.noCompatibleApp,
        'endpoint_unreachable' =>
          RemoteDesktopLaunchFailureCode.endpointUnreachable,
        'rdp_protocol_mismatch' =>
          RemoteDesktopLaunchFailureCode.protocolMismatch,
        _ => null,
      };
      if (failureCode == null) rethrow;
      throw RemoteDesktopLaunchFailure(failureCode);
    }
  }
}
