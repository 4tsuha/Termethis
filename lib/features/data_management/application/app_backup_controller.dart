import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../command_palette/application/command_palette_controller.dart';
import '../../connections/application/connection_profiles_controller.dart';
import '../../connections/application/connection_tabs_controller.dart';
import '../../connections/application/ssh_routes_controller.dart';
import '../../connections/domain/ssh_route_configuration.dart';
import '../../settings/application/app_font_controller.dart';
import '../../settings/application/terminal_performance_settings_controller.dart';
import '../../terminal/application/session_registry.dart';
import '../domain/app_backup.dart';

final appBackupControllerProvider = Provider<AppBackupController>(
  AppBackupController.new,
);

class AppBackupController {
  AppBackupController(this.ref);

  final Ref ref;

  Future<String> create() async {
    final profiles = await ref
        .read(connectionProfileRepositoryProvider)
        .watchAll()
        .first;
    final backup = AppBackup(
      version: appBackupFormatVersion,
      createdAt: DateTime.now().toUtc(),
      profiles: profiles,
      knownHosts: await ref.read(hostKeyRepositoryProvider).listAll(),
      tabs: await ref.read(connectionTabStoreProvider).load(),
      snippets: await ref.read(commandSnippetStoreProvider).load(),
      routes: await ref.read(sshRouteStoreProvider).load(),
      appFont: ref.read(appFontProvider),
      terminalSettings: ref.read(terminalPerformanceSettingsProvider),
      credentialsToReenter: profiles
          .where((profile) => profile.credentialReference != null)
          .length,
    );
    return const JsonEncoder.withIndent('  ').convert(backup.toJson());
  }

  Future<AppBackupPreview> preview(String encoded) async {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map) throw const FormatException('JSONオブジェクトではありません。');
    final backup = AppBackup.fromJson(
      decoded.map((key, value) => MapEntry('$key', value)),
    );
    _ensureValidRelationships(backup);
    final existing = await ref
        .read(connectionProfileRepositoryProvider)
        .watchAll()
        .first;
    final existingIds = existing.map((profile) => profile.id).toSet();
    final restoredIds = backup.profiles.map((profile) => profile.id).toSet();
    return AppBackupPreview(
      backup: backup,
      newProfiles: backup.profiles
          .where((profile) => !existingIds.contains(profile.id))
          .length,
      updatedProfiles: backup.profiles
          .where((profile) => existingIds.contains(profile.id))
          .length,
      credentialsToReenter: backup.credentialsToReenter,
      skippedTabs: backup.tabs
          .where(
            (tab) =>
                tab.profileId != null && !restoredIds.contains(tab.profileId),
          )
          .length,
    );
  }

  void _ensureValidRelationships(AppBackup backup) {
    final profileIds = backup.profiles.map((profile) => profile.id).toSet();
    if (profileIds.length != backup.profiles.length) {
      throw const FormatException('接続先IDが重複しています。');
    }
    final tabIds = backup.tabs.map((tab) => tab.id).toSet();
    if (tabIds.length != backup.tabs.length) {
      throw const FormatException('タブIDが重複しています。');
    }
    final graph = <String, List<String>>{};
    for (final route in backup.routes) {
      if (!profileIds.contains(route.profileId) ||
          route.jumpProfileIds.any((id) => !profileIds.contains(id))) {
        throw const FormatException('踏み台設定が存在しない接続先を参照しています。');
      }
      graph[route.profileId] = route.jumpProfileIds;
    }
    final visiting = <String>{};
    final visited = <String>{};
    void visit(String id) {
      if (!visiting.add(id)) {
        throw const FormatException('踏み台設定が循環しています。');
      }
      if (!visited.add(id)) {
        visiting.remove(id);
        return;
      }
      for (final next in graph[id] ?? const <String>[]) {
        visit(next);
      }
      visiting.remove(id);
    }

    for (final id in graph.keys) {
      visit(id);
    }
  }

  Future<void> restore(AppBackupPreview preview) async {
    final backup = preview.backup;
    final profiles = ref.read(connectionProfileRepositoryProvider);
    for (final profile in backup.profiles) {
      await profiles.save(profile);
    }
    final hosts = ref.read(hostKeyRepositoryProvider);
    for (final host in backup.knownHosts) {
      await hosts.trust(host);
    }
    final profileIds = backup.profiles.map((profile) => profile.id).toSet();
    await ref.read(connectionTabStoreProvider).save([
      for (final tab in backup.tabs)
        if (tab.profileId == null || profileIds.contains(tab.profileId)) tab,
    ]);
    await ref.read(commandSnippetStoreProvider).save(backup.snippets);
    await ref.read(sshRouteStoreProvider).save([
      for (final route in backup.routes)
        if (profileIds.contains(route.profileId))
          SshRouteConfiguration(
            profileId: route.profileId,
            jumpProfileIds: route.jumpProfileIds
                .where(profileIds.contains)
                .toList(),
          ),
    ]);

    ref.read(appFontProvider.notifier).select(backup.appFont);
    await ref.read(appFontStoreProvider).save(backup.appFont);
    final terminal = ref.read(terminalPerformanceSettingsProvider.notifier);
    final settings = backup.terminalSettings;
    terminal
      ..selectRendererMode(settings.rendererMode)
      ..selectTerminalFont(settings.terminalFont)
      ..selectHardwareAccelerationMode(settings.hardwareAccelerationMode)
      ..selectRefreshRateMode(settings.refreshRateMode)
      ..selectScrollbackLines(settings.scrollbackLines)
      ..setKeepAliveInBackground(settings.keepAliveInBackground)
      ..setShowSearchButton(settings.showSearchButton)
      ..setShowCopyOutputButton(settings.showCopyOutputButton)
      ..selectSearchMode(settings.searchMode)
      ..setKeepScreenAwake(settings.keepScreenAwake)
      ..setMouseInput(settings.mouseInput)
      ..setLongPressRightClick(settings.longPressRightClick)
      ..setTapToMovePromptCursor(settings.tapToMovePromptCursor)
      ..setShowSessionTabBar(settings.showSessionTabBar)
      ..setResizeForKeyboard(settings.resizeForKeyboard);
    await ref.read(terminalPerformanceSettingsStoreProvider).save(settings);

    ref.invalidate(connectionProfilesProvider);
    ref.invalidate(connectionTabsProvider);
    ref.invalidate(commandSnippetsProvider);
    ref.invalidate(sshRoutesProvider);
  }
}
