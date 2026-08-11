enum RefreshRateMode { adaptive, balanced, maximum }

enum TerminalRendererMode { webgl, alacritty, connectBot, termux }

enum TerminalFont { cascadiaMono, jetBrainsMono }

extension TerminalFontFamily on TerminalFont {
  String get family => switch (this) {
    TerminalFont.cascadiaMono => 'CascadiaMono',
    TerminalFont.jetBrainsMono => 'JetBrainsMono',
  };
}

enum HardwareAccelerationMode { automatic, vulkan, disabled }

enum TerminalSearchMode { shell, tmux, zellij, screen }

String terminalSearchSequence(TerminalSearchMode mode) => switch (mode) {
  TerminalSearchMode.shell => '\x12',
  TerminalSearchMode.tmux => '\x02[/',
  TerminalSearchMode.zellij => '\x13s',
  TerminalSearchMode.screen => '\x01[/',
};

class TerminalPerformanceSettings {
  const TerminalPerformanceSettings({
    this.rendererMode = TerminalRendererMode.webgl,
    this.terminalFont = TerminalFont.cascadiaMono,
    this.hardwareAccelerationMode = HardwareAccelerationMode.automatic,
    this.refreshRateMode = RefreshRateMode.adaptive,
    this.scrollbackLines = 2000,
    this.keepAliveInBackground = false,
    this.showSearchButton = true,
    this.showCopyOutputButton = true,
    this.searchMode = TerminalSearchMode.shell,
    this.keepScreenAwake = false,
    this.mouseInput = false,
    this.longPressRightClick = false,
    this.tapToMovePromptCursor = false,
    this.showSessionTabBar = true,
    this.resizeForKeyboard = false,
  });

  static const supportedScrollbackLines = [
    2000,
    5000,
    10000,
    25000,
    50000,
    100000,
  ];

  final TerminalRendererMode rendererMode;
  final TerminalFont terminalFont;
  final HardwareAccelerationMode hardwareAccelerationMode;
  final RefreshRateMode refreshRateMode;
  final int scrollbackLines;
  final bool keepAliveInBackground;
  final bool showSearchButton;
  final bool showCopyOutputButton;
  final TerminalSearchMode searchMode;
  final bool keepScreenAwake;
  final bool mouseInput;
  final bool longPressRightClick;
  final bool tapToMovePromptCursor;
  final bool showSessionTabBar;
  final bool resizeForKeyboard;

  TerminalPerformanceSettings copyWith({
    TerminalRendererMode? rendererMode,
    TerminalFont? terminalFont,
    HardwareAccelerationMode? hardwareAccelerationMode,
    RefreshRateMode? refreshRateMode,
    int? scrollbackLines,
    bool? keepAliveInBackground,
    bool? showSearchButton,
    bool? showCopyOutputButton,
    TerminalSearchMode? searchMode,
    bool? keepScreenAwake,
    bool? mouseInput,
    bool? longPressRightClick,
    bool? tapToMovePromptCursor,
    bool? showSessionTabBar,
    bool? resizeForKeyboard,
  }) {
    return TerminalPerformanceSettings(
      rendererMode: rendererMode ?? this.rendererMode,
      terminalFont: terminalFont ?? this.terminalFont,
      hardwareAccelerationMode:
          hardwareAccelerationMode ?? this.hardwareAccelerationMode,
      refreshRateMode: refreshRateMode ?? this.refreshRateMode,
      scrollbackLines: scrollbackLines ?? this.scrollbackLines,
      keepAliveInBackground:
          keepAliveInBackground ?? this.keepAliveInBackground,
      showSearchButton: showSearchButton ?? this.showSearchButton,
      showCopyOutputButton: showCopyOutputButton ?? this.showCopyOutputButton,
      searchMode: searchMode ?? this.searchMode,
      keepScreenAwake: keepScreenAwake ?? this.keepScreenAwake,
      mouseInput: mouseInput ?? this.mouseInput,
      longPressRightClick: longPressRightClick ?? this.longPressRightClick,
      tapToMovePromptCursor:
          tapToMovePromptCursor ?? this.tapToMovePromptCursor,
      showSessionTabBar: showSessionTabBar ?? this.showSessionTabBar,
      resizeForKeyboard: resizeForKeyboard ?? this.resizeForKeyboard,
    );
  }
}
