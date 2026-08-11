import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/display_performance_controller.dart';
import '../domain/terminal_performance_settings.dart';
import '../domain/terminal_performance_settings_store.dart';
import 'background_session_coordinator.dart';

final initialTerminalPerformanceSettingsProvider =
    Provider<TerminalPerformanceSettings>(
      (ref) => const TerminalPerformanceSettings(
        rendererMode: TerminalRendererMode.flutter,
      ),
    );

final terminalPerformanceSettingsStoreProvider =
    Provider<TerminalPerformanceSettingsStore>(
      (ref) => const EphemeralTerminalPerformanceSettingsStore(),
    );

final displayPerformanceControllerProvider =
    Provider<DisplayPerformanceController>(
      (ref) => const NoopDisplayPerformanceController(),
    );

final terminalPerformanceSettingsProvider =
    NotifierProvider<
      TerminalPerformanceSettingsController,
      TerminalPerformanceSettings
    >(TerminalPerformanceSettingsController.new);

class TerminalPerformanceSettingsController
    extends Notifier<TerminalPerformanceSettings> {
  late TerminalPerformanceSettingsStore _store;

  @override
  TerminalPerformanceSettings build() {
    _store = ref.watch(terminalPerformanceSettingsStoreProvider);
    final initial = ref.watch(initialTerminalPerformanceSettingsProvider);
    unawaited(
      ref
          .read(displayPerformanceControllerProvider)
          .setMode(initial.refreshRateMode),
    );
    ref
        .read(backgroundSessionCoordinatorProvider)
        .setEnabled(initial.keepAliveInBackground);
    return initial;
  }

  void selectRefreshRateMode(RefreshRateMode mode) {
    _update(state.copyWith(refreshRateMode: mode));
    unawaited(ref.read(displayPerformanceControllerProvider).setMode(mode));
  }

  void selectRendererMode(TerminalRendererMode mode) {
    _update(state.copyWith(rendererMode: mode));
  }

  void selectScrollbackLines(int lines) {
    if (!TerminalPerformanceSettings.supportedScrollbackLines.contains(lines)) {
      return;
    }
    _update(state.copyWith(scrollbackLines: lines));
  }

  void setKeepAliveInBackground(bool enabled) {
    _update(state.copyWith(keepAliveInBackground: enabled));
    ref.read(backgroundSessionCoordinatorProvider).setEnabled(enabled);
  }

  void setShowSearchButton(bool enabled) =>
      _update(state.copyWith(showSearchButton: enabled));

  void setShowCopyOutputButton(bool enabled) =>
      _update(state.copyWith(showCopyOutputButton: enabled));

  void selectSearchMode(TerminalSearchMode mode) =>
      _update(state.copyWith(searchMode: mode));

  void setKeepScreenAwake(bool enabled) =>
      _update(state.copyWith(keepScreenAwake: enabled));

  void setMouseInput(bool enabled) => _update(
    state.copyWith(
      mouseInput: enabled,
      longPressRightClick: enabled ? state.longPressRightClick : false,
    ),
  );

  void setLongPressRightClick(bool enabled) =>
      _update(state.copyWith(longPressRightClick: enabled));

  void setTapToMovePromptCursor(bool enabled) =>
      _update(state.copyWith(tapToMovePromptCursor: enabled));

  void setShowSessionTabBar(bool enabled) =>
      _update(state.copyWith(showSessionTabBar: enabled));

  void setResizeForKeyboard(bool enabled) =>
      _update(state.copyWith(resizeForKeyboard: enabled));

  void _update(TerminalPerformanceSettings next) {
    state = next;
    unawaited(_store.save(next));
  }
}
