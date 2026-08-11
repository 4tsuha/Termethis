import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/font_licenses.dart';
import 'features/connections/application/connection_profiles_controller.dart';
import 'features/connections/domain/connection_profile_repository.dart';
import 'features/connections/domain/credential_vault.dart';
import 'features/connections/domain/remote_desktop_launcher.dart';
import 'features/connections/application/remote_desktop_launcher_provider.dart';
import 'features/settings/application/app_font_controller.dart';
import 'features/settings/application/background_session_coordinator.dart';
import 'features/settings/application/terminal_performance_settings_controller.dart';
import 'features/settings/domain/app_font.dart';
import 'features/settings/domain/app_font_store.dart';
import 'features/settings/domain/background_session_service_controller.dart';
import 'features/settings/domain/display_performance_controller.dart';
import 'features/settings/domain/terminal_performance_settings.dart';
import 'features/settings/domain/terminal_performance_settings_store.dart';
import 'features/terminal/application/session_registry.dart';
import 'features/terminal/application/ssh_tabs_controller.dart';
import 'features/terminal/domain/ssh_tab.dart';
import 'features/terminal/domain/ssh_gateway.dart';
import 'features/wake_on_lan/application/wake_on_lan_provider.dart';
import 'features/wake_on_lan/domain/wake_on_lan.dart';
import 'infrastructure/background/android_background_session_service_controller.dart';
import 'infrastructure/database/app_database.dart';
import 'infrastructure/database/drift_connection_profile_repository.dart';
import 'infrastructure/database/drift_host_key_repository.dart';
import 'infrastructure/display/android_display_performance_controller.dart';
import 'infrastructure/remote_desktop/android_remote_desktop_launcher.dart';
import 'infrastructure/secure_storage/encrypted_file_credential_vault.dart';
import 'infrastructure/settings/shared_preferences_app_font_store.dart';
import 'infrastructure/settings/shared_preferences_ssh_tab_store.dart';
import 'infrastructure/settings/shared_preferences_terminal_performance_settings_store.dart';
import 'infrastructure/wake_on_lan/udp_wake_on_lan_sender.dart';
import 'src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  registerBundledFontLicenses();
  final fontStore = SharedPreferencesAppFontStore();
  final initialFont = await fontStore.read() ?? AppFont.notoSansJp;
  final performanceStore = SharedPreferencesTerminalPerformanceSettingsStore();
  final initialPerformanceSettings =
      await performanceStore.read() ?? const TerminalPerformanceSettings();
  runApp(
    MainApp(
      initialFont: initialFont,
      fontStore: fontStore,
      initialPerformanceSettings: initialPerformanceSettings,
      performanceSettingsStore: performanceStore,
      displayPerformanceController: const AndroidDisplayPerformanceController(),
      backgroundSessionServiceController:
          const AndroidBackgroundSessionServiceController(),
      database: AppDatabase.defaults(),
      credentialVault: EncryptedFileCredentialVault.androidDefaults(),
      wakeOnLanSender: const UdpWakeOnLanSender(),
      remoteDesktopLauncher: const AndroidRemoteDesktopLauncher(),
      sshTabStore: SharedPreferencesSshTabStore(),
    ),
  );
}

class MainApp extends StatefulWidget {
  const MainApp({
    this.initialFont = AppFont.notoSansJp,
    this.fontStore = const EphemeralAppFontStore(),
    this.initialPerformanceSettings = const TerminalPerformanceSettings(
      rendererMode: TerminalRendererMode.flutter,
    ),
    this.performanceSettingsStore =
        const EphemeralTerminalPerformanceSettingsStore(),
    this.displayPerformanceController =
        const NoopDisplayPerformanceController(),
    this.backgroundSessionServiceController =
        const NoopBackgroundSessionServiceController(),
    this.database,
    this.credentialVault,
    this.wakeOnLanSender,
    this.remoteDesktopLauncher = const UnavailableRemoteDesktopLauncher(),
    this.sshTabStore,
    super.key,
  });

  final AppFont initialFont;
  final AppFontStore fontStore;
  final TerminalPerformanceSettings initialPerformanceSettings;
  final TerminalPerformanceSettingsStore performanceSettingsStore;
  final DisplayPerformanceController displayPerformanceController;
  final BackgroundSessionServiceController backgroundSessionServiceController;
  final AppDatabase? database;
  final CredentialVault? credentialVault;
  final WakeOnLanSender? wakeOnLanSender;
  final RemoteDesktopLauncher remoteDesktopLauncher;
  final SshTabStore? sshTabStore;

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  ConnectionProfileRepository? _profiles;
  HostKeyRepository? _hostKeys;

  @override
  void initState() {
    super.initState();
    final database = widget.database;
    if (database != null) {
      _profiles = DriftConnectionProfileRepository(database);
      _hostKeys = DriftHostKeyRepository(database);
    }
  }

  @override
  void dispose() {
    final database = widget.database;
    if (database != null) {
      unawaited(database.close());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        initialAppFontProvider.overrideWithValue(widget.initialFont),
        appFontStoreProvider.overrideWithValue(widget.fontStore),
        initialTerminalPerformanceSettingsProvider.overrideWithValue(
          widget.initialPerformanceSettings,
        ),
        terminalPerformanceSettingsStoreProvider.overrideWithValue(
          widget.performanceSettingsStore,
        ),
        displayPerformanceControllerProvider.overrideWithValue(
          widget.displayPerformanceController,
        ),
        backgroundSessionServiceControllerProvider.overrideWithValue(
          widget.backgroundSessionServiceController,
        ),
        if (_profiles case final profiles?)
          connectionProfileRepositoryProvider.overrideWithValue(profiles),
        if (_hostKeys case final hostKeys?)
          hostKeyRepositoryProvider.overrideWithValue(hostKeys),
        if (widget.credentialVault case final credentialVault?)
          credentialVaultProvider.overrideWithValue(credentialVault),
        if (widget.wakeOnLanSender case final wakeOnLanSender?)
          wakeOnLanSenderProvider.overrideWithValue(wakeOnLanSender),
        remoteDesktopLauncherProvider.overrideWithValue(
          widget.remoteDesktopLauncher,
        ),
        if (widget.sshTabStore case final sshTabStore?)
          sshTabStoreProvider.overrideWithValue(sshTabStore),
      ],
      child: const TermethisApp(),
    );
  }
}
