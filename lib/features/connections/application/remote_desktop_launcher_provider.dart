import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/remote_desktop_launcher.dart';

final remoteDesktopLauncherProvider = Provider<RemoteDesktopLauncher>(
  (ref) => const UnavailableRemoteDesktopLauncher(),
);
