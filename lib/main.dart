import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/font_licenses.dart';
import 'features/connections/application/connection_profiles_controller.dart';
import 'features/connections/domain/connection_profile_repository.dart';
import 'features/connections/domain/credential_vault.dart';
import 'features/settings/application/app_font_controller.dart';
import 'features/settings/domain/app_font.dart';
import 'features/settings/domain/app_font_store.dart';
import 'features/terminal/application/session_registry.dart';
import 'features/terminal/domain/ssh_gateway.dart';
import 'features/wake_on_lan/application/wake_on_lan_provider.dart';
import 'features/wake_on_lan/domain/wake_on_lan.dart';
import 'infrastructure/database/app_database.dart';
import 'infrastructure/database/drift_connection_profile_repository.dart';
import 'infrastructure/database/drift_host_key_repository.dart';
import 'infrastructure/secure_storage/encrypted_file_credential_vault.dart';
import 'infrastructure/settings/shared_preferences_app_font_store.dart';
import 'infrastructure/wake_on_lan/udp_wake_on_lan_sender.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerBundledFontLicenses();
  final fontStore = SharedPreferencesAppFontStore();
  final initialFont = await fontStore.read() ?? AppFont.notoSansJp;
  runApp(
    MainApp(
      initialFont: initialFont,
      fontStore: fontStore,
      database: AppDatabase.defaults(),
      credentialVault: EncryptedFileCredentialVault.androidDefaults(),
      wakeOnLanSender: const UdpWakeOnLanSender(),
    ),
  );
}

class MainApp extends StatefulWidget {
  const MainApp({
    this.initialFont = AppFont.notoSansJp,
    this.fontStore = const EphemeralAppFontStore(),
    this.database,
    this.credentialVault,
    this.wakeOnLanSender,
    super.key,
  });

  final AppFont initialFont;
  final AppFontStore fontStore;
  final AppDatabase? database;
  final CredentialVault? credentialVault;
  final WakeOnLanSender? wakeOnLanSender;

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
        if (_profiles case final profiles?)
          connectionProfileRepositoryProvider.overrideWithValue(profiles),
        if (_hostKeys case final hostKeys?)
          hostKeyRepositoryProvider.overrideWithValue(hostKeys),
        if (widget.credentialVault case final credentialVault?)
          credentialVaultProvider.overrideWithValue(credentialVault),
        if (widget.wakeOnLanSender case final wakeOnLanSender?)
          wakeOnLanSenderProvider.overrideWithValue(wakeOnLanSender),
      ],
      child: const SshTerminalApp(),
    );
  }
}
