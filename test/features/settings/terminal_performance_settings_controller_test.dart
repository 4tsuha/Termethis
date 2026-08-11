import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_terminal_ja/features/settings/application/background_session_coordinator.dart';
import 'package:ssh_terminal_ja/features/settings/application/terminal_performance_settings_controller.dart';
import 'package:ssh_terminal_ja/features/settings/domain/background_session_service_controller.dart';
import 'package:ssh_terminal_ja/features/settings/domain/display_performance_controller.dart';
import 'package:ssh_terminal_ja/features/settings/domain/terminal_performance_settings.dart';
import 'package:ssh_terminal_ja/features/settings/domain/terminal_performance_settings_store.dart';

void main() {
  test('表示モードとスクロールバック行数を適用して保存する', () async {
    final display = _RecordingDisplayController();
    final store = _RecordingSettingsStore();
    final container = ProviderContainer(
      overrides: [
        displayPerformanceControllerProvider.overrideWithValue(display),
        terminalPerformanceSettingsStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(
      terminalPerformanceSettingsProvider.notifier,
    );
    notifier.selectRendererMode(TerminalRendererMode.flutter);
    notifier.selectRefreshRateMode(RefreshRateMode.balanced);
    notifier.selectScrollbackLines(2000);
    notifier.selectScrollbackLines(1234);
    notifier.setShowSearchButton(false);
    notifier.setShowCopyOutputButton(false);
    notifier.selectSearchMode(TerminalSearchMode.tmux);
    notifier.setKeepScreenAwake(true);
    notifier.setMouseInput(true);
    notifier.setLongPressRightClick(true);
    notifier.setTapToMovePromptCursor(true);
    notifier.setShowSessionTabBar(false);
    notifier.setResizeForKeyboard(true);
    await Future<void>.delayed(Duration.zero);

    final settings = container.read(terminalPerformanceSettingsProvider);
    expect(settings.rendererMode, TerminalRendererMode.flutter);
    expect(settings.refreshRateMode, RefreshRateMode.balanced);
    expect(settings.scrollbackLines, 2000);
    expect(settings.showSearchButton, isFalse);
    expect(settings.showCopyOutputButton, isFalse);
    expect(settings.searchMode, TerminalSearchMode.tmux);
    expect(settings.keepScreenAwake, isTrue);
    expect(settings.mouseInput, isTrue);
    expect(settings.longPressRightClick, isTrue);
    expect(settings.tapToMovePromptCursor, isTrue);
    expect(settings.showSessionTabBar, isFalse);
    expect(settings.resizeForKeyboard, isTrue);
    expect(display.modes, [RefreshRateMode.adaptive, RefreshRateMode.balanced]);
    expect(store.saved.last.scrollbackLines, 2000);
  });

  test('検索モードを端末キーシーケンスへ変換する', () {
    expect(terminalSearchSequence(TerminalSearchMode.shell), '\x12');
    expect(terminalSearchSequence(TerminalSearchMode.tmux), '\x02[/');
    expect(terminalSearchSequence(TerminalSearchMode.zellij), '\x13s');
    expect(terminalSearchSequence(TerminalSearchMode.screen), '\x01[/');
  });

  test('常駐サービスは利用者設定と接続中セッションが揃った時だけ動く', () async {
    final service = _RecordingBackgroundService();
    final coordinator = BackgroundSessionCoordinator(service);
    addTearDown(coordinator.dispose);

    coordinator.setEnabled(true);
    coordinator.setHasActiveSession(true);
    await Future<void>.delayed(Duration.zero);
    coordinator.setHasActiveSession(false);
    await Future<void>.delayed(Duration.zero);

    expect(service.states, [true, false]);
  });

  test('常駐サービスの開始失敗後は状態変化で再試行できる', () async {
    final service = _FailOnceBackgroundService();
    final coordinator = BackgroundSessionCoordinator(service);
    addTearDown(coordinator.dispose);

    coordinator.setEnabled(true);
    coordinator.setHasActiveSession(true);
    await Future<void>.delayed(Duration.zero);
    coordinator.setHasActiveSession(true);
    await Future<void>.delayed(Duration.zero);

    expect(service.attempts, 2);
  });
}

class _RecordingDisplayController implements DisplayPerformanceController {
  final List<RefreshRateMode> modes = [];

  @override
  Future<void> pulseHigh() async {}

  @override
  Future<void> setMode(RefreshRateMode mode) async => modes.add(mode);
}

class _RecordingSettingsStore implements TerminalPerformanceSettingsStore {
  final List<TerminalPerformanceSettings> saved = [];

  @override
  Future<TerminalPerformanceSettings?> read() async => null;

  @override
  Future<void> save(TerminalPerformanceSettings settings) async {
    saved.add(settings);
  }
}

class _RecordingBackgroundService
    implements BackgroundSessionServiceController {
  final List<bool> states = [];

  @override
  Future<void> setRunning(bool running) async => states.add(running);
}

class _FailOnceBackgroundService implements BackgroundSessionServiceController {
  int attempts = 0;

  @override
  Future<void> setRunning(bool running) async {
    attempts++;
    if (attempts == 1) throw StateError('permission denied');
  }
}
