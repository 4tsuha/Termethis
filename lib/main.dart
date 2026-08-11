import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/font_licenses.dart';
import 'features/connections/application/connection_profiles_controller.dart';
import 'features/connection_logs/application/connection_logs_controller.dart';
import 'features/connection_logs/domain/connection_log_repository.dart';
import 'features/connections/domain/connection_profile_repository.dart';
import 'features/connections/domain/credential_vault.dart';
import 'features/connections/domain/remote_desktop_launcher.dart';
import 'features/connections/application/remote_desktop_launcher_provider.dart';
import 'features/diagnostics/application/shizuku_diagnostics_controller.dart';
import 'features/diagnostics/domain/shizuku_diagnostics_gateway.dart';
import 'features/settings/application/app_font_controller.dart';
import 'features/settings/application/background_session_coordinator.dart';
import 'features/settings/application/credential_settings_controller.dart';
import 'features/settings/application/terminal_performance_settings_controller.dart';
import 'features/settings/domain/app_font.dart';
import 'features/settings/domain/app_font_store.dart';
import 'features/settings/domain/background_session_service_controller.dart';
import 'features/settings/domain/display_performance_controller.dart';
import 'features/settings/domain/credential_settings.dart';
import 'features/settings/domain/hardware_acceleration_controller.dart';
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
import 'infrastructure/display/android_hardware_acceleration_controller.dart';
import 'infrastructure/diagnostics/android_shizuku_diagnostics_gateway.dart';
import 'infrastructure/remote_desktop/android_remote_desktop_launcher.dart';
import 'infrastructure/secure_storage/encrypted_file_credential_vault.dart';
import 'infrastructure/settings/shared_preferences_app_font_store.dart';
import 'infrastructure/settings/shared_preferences_connection_log_repository.dart';
import 'infrastructure/settings/shared_preferences_credential_settings_store.dart';
import 'infrastructure/settings/shared_preferences_ssh_tab_store.dart';
import 'infrastructure/settings/shared_preferences_terminal_performance_settings_store.dart';
import 'infrastructure/wake_on_lan/udp_wake_on_lan_sender.dart';
import 'src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  registerBundledLicenses();
  final fontStore = SharedPreferencesAppFontStore();
  final initialFont = await fontStore.read() ?? AppFont.notoSansJp;
  final performanceStore = SharedPreferencesTerminalPerformanceSettingsStore();
  final initialPerformanceSettings =
      await performanceStore.read() ?? const TerminalPerformanceSettings();
  final credentialSettingsStore = SharedPreferencesCredentialSettingsStore();
  final initialCredentialSettings =
      await credentialSettingsStore.read() ?? const CredentialSettings();
  runApp(
    MainApp(
      initialFont: initialFont,
      fontStore: fontStore,
      initialPerformanceSettings: initialPerformanceSettings,
      performanceSettingsStore: performanceStore,
      initialCredentialSettings: initialCredentialSettings,
      credentialSettingsStore: credentialSettingsStore,
      displayPerformanceController: const AndroidDisplayPerformanceController(),
      hardwareAccelerationController:
          const AndroidHardwareAccelerationController(),
      backgroundSessionServiceController:
          const AndroidBackgroundSessionServiceController(),
      database: AppDatabase.defaults(),
      credentialVault: EncryptedFileCredentialVault.androidDefaults(),
      wakeOnLanSender: const UdpWakeOnLanSender(),
      remoteDesktopLauncher: const AndroidRemoteDesktopLauncher(),
      sshTabStore: SharedPreferencesSshTabStore(),
      connectionLogRepository: SharedPreferencesConnectionLogRepository(),
      shizukuDiagnosticsGateway: const AndroidShizukuDiagnosticsGateway(),
    ),
  );
}

class MainApp extends StatefulWidget {
  const MainApp({
    this.initialFont = AppFont.notoSansJp,
    this.fontStore = const EphemeralAppFontStore(),
    this.initialPerformanceSettings = const TerminalPerformanceSettings(
      rendererMode: TerminalRendererMode.webgl,
    ),
    this.performanceSettingsStore =
        const EphemeralTerminalPerformanceSettingsStore(),
    this.initialCredentialSettings = const CredentialSettings(),
    this.credentialSettingsStore = const EphemeralCredentialSettingsStore(),
    this.displayPerformanceController =
        const NoopDisplayPerformanceController(),
    this.hardwareAccelerationController =
        const NoopHardwareAccelerationController(),
    this.backgroundSessionServiceController =
        const NoopBackgroundSessionServiceController(),
    this.database,
    this.credentialVault,
    this.wakeOnLanSender,
    this.remoteDesktopLauncher = const UnavailableRemoteDesktopLauncher(),
    this.sshTabStore,
    this.connectionLogRepository,
    this.shizukuDiagnosticsGateway =
        const UnavailableShizukuDiagnosticsGateway(),
    super.key,
  });

  final AppFont initialFont;
  final AppFontStore fontStore;
  final TerminalPerformanceSettings initialPerformanceSettings;
  final TerminalPerformanceSettingsStore performanceSettingsStore;
  final CredentialSettings initialCredentialSettings;
  final CredentialSettingsStore credentialSettingsStore;
  final DisplayPerformanceController displayPerformanceController;
  final HardwareAccelerationController hardwareAccelerationController;
  final BackgroundSessionServiceController backgroundSessionServiceController;
  final AppDatabase? database;
  final CredentialVault? credentialVault;
  final WakeOnLanSender? wakeOnLanSender;
  final RemoteDesktopLauncher remoteDesktopLauncher;
  final SshTabStore? sshTabStore;
  final ConnectionLogRepository? connectionLogRepository;
  final ShizukuDiagnosticsGateway shizukuDiagnosticsGateway;

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
        initialCredentialSettingsProvider.overrideWithValue(
          widget.initialCredentialSettings,
        ),
        credentialSettingsStoreProvider.overrideWithValue(
          widget.credentialSettingsStore,
        ),
        displayPerformanceControllerProvider.overrideWithValue(
          widget.displayPerformanceController,
        ),
        hardwareAccelerationControllerProvider.overrideWithValue(
          widget.hardwareAccelerationController,
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
        if (widget.connectionLogRepository case final connectionLogRepository?)
          connectionLogRepositoryProvider.overrideWithValue(
            connectionLogRepository,
          ),
        shizukuDiagnosticsGatewayProvider.overrideWithValue(
          widget.shizukuDiagnosticsGateway,
        ),
      ],
      child: const TermethisApp(),
    );
  }
}
