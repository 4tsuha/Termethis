import 'package:shared_preferences/shared_preferences.dart';

import '../../features/settings/domain/terminal_performance_settings.dart';
import '../../features/settings/domain/terminal_performance_settings_store.dart';

TerminalRendererMode selectRendererAfterNativeSurfaceMigration({
  required TerminalRendererMode? savedRenderer,
  required bool migrationCompleted,
}) {
  if (!migrationCompleted && savedRenderer == TerminalRendererMode.webgl) {
    return TerminalRendererMode.connectBot;
  }
  return savedRenderer ?? TerminalRendererMode.connectBot;
}

class SharedPreferencesTerminalPerformanceSettingsStore
    implements TerminalPerformanceSettingsStore {
  SharedPreferencesTerminalPerformanceSettingsStore({
    SharedPreferencesAsync? preferences,
  }) : _preferences = preferences ?? SharedPreferencesAsync();

  static const _refreshRateModeKey = 'settings.refresh_rate_mode';
  static const _rendererModeKey = 'settings.terminal_renderer_mode';
  static const _nativeSurfaceMigrationKey =
      'settings.native_surface_renderer_migrated';
  static const _terminalFontKey = 'settings.terminal_font';
  static const _hardwareAccelerationModeKey =
      'settings.hardware_acceleration_mode';
  static const _scrollbackLinesKey = 'settings.scrollback_lines';
  static const _keepAliveKey = 'settings.keep_alive_in_background';
  static const _showSearchButtonKey = 'settings.show_search_button';
  static const _showCopyOutputButtonKey = 'settings.show_copy_output_button';
  static const _searchModeKey = 'settings.search_mode';
  static const _keepScreenAwakeKey = 'settings.keep_screen_awake';
  static const _mouseInputKey = 'settings.mouse_input';
  static const _longPressRightClickKey = 'settings.long_press_right_click';
  static const _tapToMovePromptCursorKey = 'settings.tap_to_move_prompt_cursor';
  static const _showSessionTabBarKey = 'settings.show_session_tab_bar';
  static const _resizeForKeyboardKey = 'settings.resize_for_keyboard';

  final SharedPreferencesAsync _preferences;

  @override
  Future<TerminalPerformanceSettings?> read() async {
    final savedRenderer = await _preferences.getString(_rendererModeKey);
    final savedTerminalFont = await _preferences.getString(_terminalFontKey);
    final savedMode = await _preferences.getString(_refreshRateModeKey);
    final savedHardwareAccelerationMode = await _preferences.getString(
      _hardwareAccelerationModeKey,
    );
    final savedLines = await _preferences.getInt(_scrollbackLinesKey);
    final savedKeepAlive = await _preferences.getBool(_keepAliveKey);
    final savedSearchMode = await _preferences.getString(_searchModeKey);
    final mode = RefreshRateMode.values
        .where((value) => value.name == savedMode)
        .firstOrNull;
    var renderer = savedRenderer == 'flutter' || savedRenderer == 'native'
        ? TerminalRendererMode.connectBot
        : TerminalRendererMode.values
              .where((value) => value.name == savedRenderer)
              .firstOrNull;
    final nativeSurfaceMigrated =
        await _preferences.getBool(_nativeSurfaceMigrationKey) ?? false;
    renderer = selectRendererAfterNativeSurfaceMigration(
      savedRenderer: renderer,
      migrationCompleted: nativeSurfaceMigrated,
    );
    if (!nativeSurfaceMigrated) {
      await _preferences.setBool(_nativeSurfaceMigrationKey, true);
    }
    final terminalFont = TerminalFont.values
        .where((value) => value.name == savedTerminalFont)
        .firstOrNull;
    final searchMode = TerminalSearchMode.values
        .where((value) => value.name == savedSearchMode)
        .firstOrNull;
    final hardwareAccelerationMode = HardwareAccelerationMode.values
        .where((value) => value.name == savedHardwareAccelerationMode)
        .firstOrNull;
    final lines =
        TerminalPerformanceSettings.supportedScrollbackLines.contains(
          savedLines,
        )
        ? savedLines!
        : 2000;
    return TerminalPerformanceSettings(
      rendererMode: renderer,
      terminalFont: terminalFont ?? TerminalFont.cascadiaMono,
      hardwareAccelerationMode:
          hardwareAccelerationMode ?? HardwareAccelerationMode.automatic,
      refreshRateMode: mode ?? RefreshRateMode.adaptive,
      scrollbackLines: lines,
      keepAliveInBackground: savedKeepAlive ?? false,
      showSearchButton:
          await _preferences.getBool(_showSearchButtonKey) ?? true,
      showCopyOutputButton:
          await _preferences.getBool(_showCopyOutputButtonKey) ?? true,
      searchMode: searchMode ?? TerminalSearchMode.shell,
      keepScreenAwake: await _preferences.getBool(_keepScreenAwakeKey) ?? false,
      mouseInput: await _preferences.getBool(_mouseInputKey) ?? false,
      longPressRightClick:
          await _preferences.getBool(_longPressRightClickKey) ?? false,
      tapToMovePromptCursor:
          await _preferences.getBool(_tapToMovePromptCursorKey) ?? false,
      showSessionTabBar:
          await _preferences.getBool(_showSessionTabBarKey) ?? true,
      resizeForKeyboard:
          await _preferences.getBool(_resizeForKeyboardKey) ?? false,
    );
  }

  @override
  Future<void> save(TerminalPerformanceSettings settings) async {
    await Future.wait([
      _preferences.setString(_rendererModeKey, settings.rendererMode.name),
      _preferences.setString(_terminalFontKey, settings.terminalFont.name),
      _preferences.setString(
        _hardwareAccelerationModeKey,
        settings.hardwareAccelerationMode.name,
      ),
      _preferences.setString(
        _refreshRateModeKey,
        settings.refreshRateMode.name,
      ),
      _preferences.setInt(_scrollbackLinesKey, settings.scrollbackLines),
      _preferences.setBool(_keepAliveKey, settings.keepAliveInBackground),
      _preferences.setBool(_showSearchButtonKey, settings.showSearchButton),
      _preferences.setBool(
        _showCopyOutputButtonKey,
        settings.showCopyOutputButton,
      ),
      _preferences.setString(_searchModeKey, settings.searchMode.name),
      _preferences.setBool(_keepScreenAwakeKey, settings.keepScreenAwake),
      _preferences.setBool(_mouseInputKey, settings.mouseInput),
      _preferences.setBool(
        _longPressRightClickKey,
        settings.longPressRightClick,
      ),
      _preferences.setBool(
        _tapToMovePromptCursorKey,
        settings.tapToMovePromptCursor,
      ),
      _preferences.setBool(_showSessionTabBarKey, settings.showSessionTabBar),
      _preferences.setBool(_resizeForKeyboardKey, settings.resizeForKeyboard),
    ]);
  }
}
