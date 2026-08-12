import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:xterm/xterm.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../connections/application/connection_profiles_controller.dart';
import '../../connections/application/connection_tabs_controller.dart';
import '../../connections/application/ssh_routes_controller.dart';
import '../../connections/domain/connection_profile.dart';
import '../../connections/domain/connection_tab.dart';
import '../../connections/domain/credential_vault.dart';
import '../../command_palette/presentation/command_palette_sheet.dart';
import '../../settings/application/app_font_controller.dart';
import '../../settings/application/credential_settings_controller.dart';
import '../../settings/application/terminal_performance_settings_controller.dart';
import '../../settings/domain/terminal_performance_settings.dart';
import '../../settings/domain/vault_protection.dart';
import '../application/session_registry.dart';
import '../application/ssh_session_controller.dart';
import '../domain/ssh_failure.dart';
import '../domain/ssh_gateway.dart';
import '../../../infrastructure/display/android_terminal_window_controller.dart';
import 'widgets/alacritty_terminal_view.dart';
import 'widgets/native_terminal_view.dart';
import 'widgets/xterm_web_terminal.dart';

class TerminalScreen extends ConsumerStatefulWidget {
  const TerminalScreen({
    required this.profileId,
    required this.tabId,
    this.popWhenEmpty = true,
    this.embedded = false,
    this.showSessionBar = true,
    super.key,
  });

  final String profileId;
  final String tabId;
  final bool popWhenEmpty;
  final bool embedded;
  final bool showSessionBar;

  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen>
    with WidgetsBindingObserver {
  var _webTerminalKey = GlobalKey<XtermWebTerminalState>();
  var _nativeTerminalKey = GlobalKey<NativeTerminalViewState>();
  var _alacrittyTerminalKey = GlobalKey<AlacrittyTerminalViewState>();
  final _windowController = const AndroidTerminalWindowController();
  ConnectionProfile? _profile;
  SshSessionController? _session;
  SessionRegistry? _sessionRegistry;
  Timer? _performancePulseTimer;
  late String _activeTabId;
  bool _webTerminalFailed = false;
  bool _nativeTerminalFailed = false;
  bool _alacrittyTerminalFailed = false;
  bool _switchingTab = false;
  final List<SshTunnelStatus> _tunnels = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _activeTabId = widget.tabId;
    _profile = ref
        .read(connectionProfilesProvider.notifier)
        .findById(widget.profileId);
    if (_profile case final profile?
        when profile.connectionType == ConnectionType.ssh) {
      _sessionRegistry = ref.read(sessionRegistryProvider);
      _session = _sessionRegistry!.open(_activeTabId, profile);
      _session!.setViewportVisible(true);
      _session!.addTerminalActivityListener(_pulseHighFrameRate);
      WidgetsBinding.instance.addPostFrameCallback((_) => _initializeTab());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _applyTerminalWindowSettings(
          ref.read(terminalPerformanceSettingsProvider),
        );
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_webTerminalKey.currentState?.suspend() ?? Future<void>.value());
    unawaited(_nativeTerminalKey.currentState?.setActive(false));
    unawaited(_alacrittyTerminalKey.currentState?.setActive(false));
    _performancePulseTimer?.cancel();
    _session?.removeTerminalActivityListener(_pulseHighFrameRate);
    _session?.setViewportVisible(false);
    unawaited(_windowController.restore());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final visible = state == AppLifecycleState.resumed;
    _session?.setViewportVisible(visible);
    if (visible) {
      _webTerminalKey.currentState?.resume();
      unawaited(_nativeTerminalKey.currentState?.setActive(true));
      unawaited(_alacrittyTerminalKey.currentState?.setActive(true));
    } else {
      unawaited(
        _webTerminalKey.currentState?.suspend() ?? Future<void>.value(),
      );
      unawaited(_nativeTerminalKey.currentState?.setActive(false));
      unawaited(_alacrittyTerminalKey.currentState?.setActive(false));
    }
  }

  Future<void> _initializeTab() async {
    final expectedTabId = _activeTabId;
    final tabs = await ref.read(connectionTabsProvider.future);
    ConnectionTab? tab;
    for (final item in tabs) {
      if (item.id == expectedTabId) tab = item;
    }
    if (!mounted ||
        _activeTabId != expectedTabId ||
        tab == null ||
        tab.restored) {
      return;
    }
    if (_session?.status == SshSessionStatus.idle) {
      await _startConnection();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final appFont = ref.watch(appFontProvider);
    final performance = ref.watch(terminalPerformanceSettingsProvider);
    ref.listen(terminalPerformanceSettingsProvider, (previous, next) {
      if (previous?.rendererMode != next.rendererMode && mounted) {
        setState(() {
          _webTerminalFailed = false;
          _nativeTerminalFailed = false;
          _alacrittyTerminalFailed = false;
          _webTerminalKey = GlobalKey<XtermWebTerminalState>();
          _nativeTerminalKey = GlobalKey<NativeTerminalViewState>();
          _alacrittyTerminalKey = GlobalKey<AlacrittyTerminalViewState>();
        });
      }
      unawaited(_applyTerminalWindowSettings(next));
    });
    final useWebRenderer = _usesWebRenderer(performance.rendererMode);
    final useAlacrittyRenderer = _usesAlacrittyRenderer(
      performance.rendererMode,
    );
    final tabs =
        ref.watch(connectionTabsProvider).value ?? const <ConnectionTab>[];
    final session = _session;
    if (_profile == null || session == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.appTitle)),
        body: Center(child: Text(l10n.profileNotFound)),
      );
    }
    final content = Column(
      children: [
        if (widget.showSessionBar)
          _TerminalSessionBar(
            tabs: tabs.where((tab) => tab.isTerminal).toList(growable: false),
            currentTabId: _activeTabId,
            registry: _sessionRegistry,
            showSearch: performance.showSearchButton,
            showCopy: performance.showCopyOutputButton,
            onSelect: (tab) => unawaited(_switchTab(tab)),
            onClose: _requestClose,
            onSearch: _sendSearchShortcut,
            onCopy: _copyLastOutput,
            onCommandPalette: _openCommandPalette,
            onTunnels: _manageTunnels,
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final fontSize = _terminalFontSize(
                constraints.maxWidth,
                MediaQuery.textScalerOf(context),
              );
              final renderer = RepaintBoundary(
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (_) => _pulseHighFrameRate(),
                  onPointerMove: (_) => _pulseHighFrameRate(),
                  child: useAlacrittyRenderer
                      ? AlacrittyTerminalView(
                          key: _alacrittyTerminalKey,
                          session: session,
                          scrollbackLines: performance.scrollbackLines,
                          terminalFontFamily: performance.terminalFont.family,
                          japaneseFontFamily: appFont.family,
                          fontSize: fontSize,
                          hardwareAccelerationMode:
                              performance.hardwareAccelerationMode,
                          onFatalError: _fallbackFromAlacrittyTerminal,
                        )
                      : useWebRenderer
                      ? XtermWebTerminal(
                          key: _webTerminalKey,
                          session: session,
                          scrollbackLines: performance.scrollbackLines,
                          terminalFontFamily: performance.terminalFont.family,
                          japaneseFontFamily: appFont.family,
                          fontSize: fontSize,
                          mouseInput: performance.mouseInput,
                          longPressRightClick: performance.longPressRightClick,
                          tapToMovePromptCursor:
                              performance.tapToMovePromptCursor,
                          onFatalError: _fallbackToNativeTerminal,
                        )
                      : NativeTerminalView(
                          key: _nativeTerminalKey,
                          session: session,
                          rendererMode: performance.rendererMode,
                          scrollbackLines: performance.scrollbackLines,
                          terminalFontFamily: performance.terminalFont.family,
                          japaneseFontFamily: appFont.family,
                          fontSize: fontSize,
                          mouseInput: performance.mouseInput,
                          longPressRightClick: performance.longPressRightClick,
                          tapToMovePromptCursor:
                              performance.tapToMovePromptCursor,
                          resizeForKeyboard: performance.resizeForKeyboard,
                          onFatalError: _fallbackToWebTerminal,
                        ),
                ),
              );
              return ListenableBuilder(
                listenable: session,
                child: renderer,
                builder: (context, renderer) => Stack(
                  children: [
                    Positioned.fill(child: renderer!),
                    if ({
                      SshSessionStatus.idle,
                      SshSessionStatus.closed,
                      SshSessionStatus.failed,
                      SshSessionStatus.reconnectPrompt,
                    }.contains(session.status))
                      Positioned.fill(
                        child: _FailurePanel(
                          message: session.failure == null
                              ? l10n.sessionRestoredMessage
                              : _failureText(l10n, session.failure),
                          retryLabel: l10n.retry,
                          onRetry: _startConnection,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        ListenableBuilder(
          listenable: session,
          builder: (context, _) => _SpecialKeyBar(
            session: session,
            pasteLabel: l10n.paste,
            onPaste: _paste,
            onKey: _sendSpecialKey,
            onCommandPalette: _openCommandPalette,
            onTunnels: _manageTunnels,
          ),
        ),
      ],
    );
    if (widget.embedded) {
      return ColoredBox(color: Colors.black, child: content);
    }
    return PopScope<void>(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          unawaited(
            _webTerminalKey.currentState?.suspend() ?? Future<void>.value(),
          );
          unawaited(_alacrittyTerminalKey.currentState?.setActive(false));
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: true,
        body: SafeArea(child: content),
      ),
    );
  }

  Future<void> _switchTab(ConnectionTab tab) async {
    if (tab.profileId == null || !tab.isTerminal) return;
    if (tab.id == _activeTabId || _switchingTab) return;
    final profile = ref
        .read(connectionProfilesProvider.notifier)
        .findById(tab.profileId!);
    if (profile == null) return;

    _switchingTab = true;
    try {
      await (_webTerminalKey.currentState?.suspend() ?? Future<void>.value());
      await _nativeTerminalKey.currentState?.setActive(false);
      await _alacrittyTerminalKey.currentState?.setActive(false);
      if (!mounted) return;
      _session?.removeTerminalActivityListener(_pulseHighFrameRate);
      _session?.setViewportVisible(false);
      _activateTab(tab, profile);
      await ref.read(connectionTabsProvider.notifier).markActive(tab.id);
      if (!mounted || _activeTabId != tab.id) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _activeTabId != tab.id) return;
        _webTerminalKey.currentState?.resume();
        unawaited(_nativeTerminalKey.currentState?.setActive(true));
        unawaited(_alacrittyTerminalKey.currentState?.setActive(true));
        _focusTerminal();
      });
    } finally {
      _switchingTab = false;
    }
  }

  void _activateTab(ConnectionTab tab, ConnectionProfile profile) {
    final session = _sessionRegistry!.open(tab.id, profile);
    session.setViewportVisible(true);
    session.addTerminalActivityListener(_pulseHighFrameRate);
    setState(() {
      _activeTabId = tab.id;
      _profile = profile;
      _session = session;
      _webTerminalKey = GlobalKey<XtermWebTerminalState>();
      _nativeTerminalKey = GlobalKey<NativeTerminalViewState>();
      _alacrittyTerminalKey = GlobalKey<AlacrittyTerminalViewState>();
      _webTerminalFailed = false;
      _nativeTerminalFailed = false;
      _alacrittyTerminalFailed = false;
    });
  }

  Future<void> _applyTerminalWindowSettings(
    TerminalPerformanceSettings settings,
  ) => _windowController.apply(keepScreenAwake: settings.keepScreenAwake);

  void _sendSearchShortcut() {
    final session = _session;
    if (session == null || !session.isConnected) return;
    final mode = ref.read(terminalPerformanceSettingsProvider).searchMode;
    session.sendInput(terminalSearchSequence(mode));
    _focusTerminal();
  }

  Future<void> _copyLastOutput() async {
    final performance = ref.read(terminalPerformanceSettingsProvider);
    String? output;
    if (_usesWebRenderer(performance.rendererMode)) {
      output = await _webTerminalKey.currentState?.copyLastCommandOutput();
    }
    if (!mounted) return;
    if (output == null || output.isEmpty) {
      await _showShellIntegrationHelp();
      return;
    }
    await Clipboard.setData(ClipboardData(text: output));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('直前のコマンド出力をコピーしました。')));
    }
  }

  Future<void> _openCommandPalette() async {
    final session = _session;
    final profile = _profile;
    if (session == null || profile == null || !session.isConnected) return;
    final command = await showCommandPalette(context, profileId: profile.id);
    if (command == null || command.isEmpty || !mounted) return;
    session.sendInputDirect(command);
    _focusTerminal();
  }

  Future<void> _manageTunnels() async {
    final session = _session;
    if (session == null || !session.isConnected) return;
    final action = await showModalBottomSheet<_TunnelSheetAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => _TunnelManagerSheet(tunnels: _tunnels),
    );
    if (action == null || !mounted) return;
    try {
      if (action.stopId case final id?) {
        await session.stopTunnel(id);
        setState(() => _tunnels.removeWhere((tunnel) => tunnel.id == id));
        return;
      }
      final request = action.request;
      if (request == null) return;
      final status = await session.startTunnel(request);
      if (mounted) setState(() => _tunnels.add(status));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('トンネルを更新できませんでした: $error')));
      }
    }
  }

  Future<void> _showShellIntegrationHelp() {
    const markerTest = "printf '\\e]133;A\\aPrompt\\e]133;B\\a'";
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'シェル統合が必要です',
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            const Text(
              'Termethisが直前の出力とプロンプト位置を認識するには、OSC 133対応のシェル設定が必要です。starship、fish 3.6以降、または対応するbash/zsh設定を使用してください。',
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(const ClipboardData(text: markerTest));
                if (sheetContext.mounted) Navigator.pop(sheetContext);
              },
              icon: const Icon(Icons.copy),
              label: const Text('確認コマンドをコピー'),
            ),
          ],
        ),
      ),
    );
  }

  void _fallbackToNativeTerminal(String _) {
    if (!mounted || _webTerminalFailed) return;
    setState(() => _webTerminalFailed = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('WebGL端末を利用できないためConnectBot描画へ切り替えました。')),
    );
  }

  void _fallbackToWebTerminal(String _) {
    if (!mounted || _nativeTerminalFailed) return;
    setState(() => _nativeTerminalFailed = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('選択したネイティブ端末を利用できないためWebGL描画へ切り替えました。')),
    );
  }

  void _fallbackFromAlacrittyTerminal(String _) {
    if (!mounted || _alacrittyTerminalFailed) return;
    setState(() => _alacrittyTerminalFailed = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Flutter Alacrittyを利用できないためxterm.js WebGLへ切り替えました。'),
      ),
    );
  }

  bool _usesAlacrittyRenderer(TerminalRendererMode renderer) =>
      renderer == TerminalRendererMode.alacritty && !_alacrittyTerminalFailed;

  bool _usesWebRenderer(TerminalRendererMode renderer) =>
      !_webTerminalFailed &&
      (renderer == TerminalRendererMode.webgl ||
          renderer == TerminalRendererMode.alacritty &&
              _alacrittyTerminalFailed ||
          _nativeTerminalFailed);

  void _pulseHighFrameRate() {
    final mode = ref.read(terminalPerformanceSettingsProvider).refreshRateMode;
    if (mode == RefreshRateMode.maximum || _performancePulseTimer != null) {
      return;
    }
    _performancePulseTimer = Timer(const Duration(milliseconds: 80), () {
      _performancePulseTimer = null;
    });
    unawaited(ref.read(displayPerformanceControllerProvider).pulseHigh());
  }

  Future<void> _startConnection() async {
    final session = _session;
    final profile = _profile;
    if (!mounted || session == null || profile == null) {
      return;
    }

    await ref.read(connectionTabsProvider.notifier).markActive(_activeTabId);

    final authentication = await _resolveAuthentication(profile, session);
    if (!mounted || authentication == null) {
      if (session.status == SshSessionStatus.idle) {
        await _finishAndPop();
      }
      return;
    }
    final jumpHosts = <SshJumpHost>[];
    final routes = await ref.read(sshRoutesProvider.future);
    final route = routes
        .where((route) => route.profileId == profile.id)
        .firstOrNull;
    for (final jumpProfileId in route?.jumpProfileIds ?? const <String>[]) {
      final jumpProfile = ref
          .read(connectionProfilesProvider.notifier)
          .findById(jumpProfileId);
      if (jumpProfile == null) {
        session.reportFailure(
          const SshFailure(SshFailureCode.jumpHostConnectionFailed),
        );
        return;
      }
      final jumpAuthentication = await _resolveAuthentication(
        jumpProfile,
        session,
      );
      if (!mounted || jumpAuthentication == null) return;
      jumpHosts.add(
        SshJumpHost(profile: jumpProfile, authentication: jumpAuthentication),
      );
    }

    await session.connect(
      authentication: authentication,
      jumpHosts: jumpHosts,
      onUnknownHostKey: _approveHostKey,
      onInteractivePrompt: _answerInteractivePrompt,
    );
    if (mounted && session.isConnected) {
      _focusTerminal();
    }
  }

  Future<String?> _askPassword(ConnectionProfile profile) async {
    final l10n = AppLocalizations.of(context);
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _SecretDialog(
        title: l10n.passwordDialogTitle,
        message: l10n.passwordDialogMessage(profile.target),
        label: l10n.password,
      ),
    );
  }

  Future<SshAuthentication?> _resolveAuthentication(
    ConnectionProfile profile,
    SshSessionController session,
  ) async {
    if (profile.authenticationType ==
        AuthenticationType.passwordOrInteractive) {
      final reference = profile.credentialReference;
      final passwordStorageEnabled = ref
          .read(credentialSettingsProvider)
          .saveSshPasswords;
      if (passwordStorageEnabled && reference != null) {
        try {
          final saved = await _readSavedPassword(reference);
          if (saved != null) return SshPasswordAuthentication(saved.password);
        } on CredentialVaultFailure {
          session.reportFailure(
            const SshFailure(SshFailureCode.authenticationFailed),
          );
          return null;
        }
      }
      final password = await _askPassword(profile);
      return password == null ? null : SshPasswordAuthentication(password);
    }

    final reference = profile.credentialReference;
    if (reference == null) {
      session.reportFailure(const SshFailure(SshFailureCode.privateKeyInvalid));
      return null;
    }

    try {
      final credential = await _readSavedPrivateKey(reference);
      if (credential == null) {
        session.reportFailure(
          const SshFailure(SshFailureCode.privateKeyInvalid),
        );
        return null;
      }

      var passphrase = credential.passphrase;
      if (credential.isEncrypted &&
          (passphrase == null || passphrase.isEmpty)) {
        passphrase = await _askKeyPassphrase(credential.label);
        if (passphrase == null) {
          return null;
        }
      }
      return SshPrivateKeyAuthentication(
        pem: credential.pem,
        passphrase: passphrase,
      );
    } on CredentialVaultFailure {
      session.reportFailure(const SshFailure(SshFailureCode.privateKeyInvalid));
      return null;
    }
  }

  Future<PasswordCredential?> _readSavedPassword(String reference) async {
    final vault = ref.read(credentialVaultProvider);
    try {
      return await vault.readPassword(CredentialHandle(reference));
    } on CredentialVaultFailure catch (failure) {
      if (failure.code != CredentialVaultFailureCode.vaultLocked) rethrow;
      if (!await _unlockVaultForForegroundUse()) rethrow;
      return vault.readPassword(CredentialHandle(reference));
    }
  }

  Future<PrivateKeyCredential?> _readSavedPrivateKey(String reference) async {
    final vault = ref.read(credentialVaultProvider);
    try {
      return await vault.readPrivateKey(CredentialHandle(reference));
    } on CredentialVaultFailure catch (failure) {
      if (failure.code != CredentialVaultFailureCode.vaultLocked) rethrow;
      if (!await _unlockVaultForForegroundUse()) rethrow;
      return vault.readPrivateKey(CredentialHandle(reference));
    }
  }

  Future<bool> _unlockVaultForForegroundUse() async {
    if (!mounted) return false;
    final result = await ref
        .read(credentialSettingsProvider.notifier)
        .unlockVault();
    if (!mounted || result == VaultAuthenticationResult.unlocked) {
      return result == VaultAuthenticationResult.unlocked;
    }
    final message = switch (result) {
      VaultAuthenticationResult.canceled => 'Vaultの解錠をキャンセルしました。',
      VaultAuthenticationResult.keyInvalidated =>
        'Keystore鍵が無効です。設定からVault保護を再設定してください。',
      VaultAuthenticationResult.backgroundDenied => 'アプリを表示してからVaultを解錠してください。',
      VaultAuthenticationResult.unavailable => 'この端末ではVaultの認証を利用できません。',
      VaultAuthenticationResult.unlocked => '',
    };
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
    return false;
  }

  Future<String?> _askKeyPassphrase(String label) {
    final l10n = AppLocalizations.of(context);
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _SecretDialog(
        title: l10n.keyPassphraseTitle,
        message: l10n.keyPassphraseMessage(label),
        label: l10n.keyPassphrase,
      ),
    );
  }

  Future<bool> _approveHostKey(HostKeyInfo info) async {
    if (!mounted) {
      return false;
    }
    final l10n = AppLocalizations.of(context);
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            icon: const Icon(Icons.security),
            title: Text(l10n.hostKeyDialogTitle),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.hostKeyDialogMessage),
                  const SizedBox(height: 16),
                  Text('${info.host}:${info.port}'),
                  const SizedBox(height: 12),
                  Text(
                    l10n.hostKeyAlgorithm,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  SelectableText(info.algorithm),
                  const SizedBox(height: 12),
                  Text(
                    l10n.hostKeyFingerprint,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  SelectableText(info.fingerprintSha256),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.reject),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l10n.trustAndConnect),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<List<String>?> _answerInteractivePrompt(
    InteractiveRequest request,
  ) async {
    if (!mounted) {
      return null;
    }
    return showDialog<List<String>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _InteractivePromptDialog(request: request),
    );
  }

  Future<void> _paste() async {
    final session = _session;
    if (session == null) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (!mounted) {
      return;
    }
    if (text == null || text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.nothingToPaste)));
      return;
    }

    if (text.length > 200 || text.contains('\n') || text.contains('\r')) {
      final preview = text.length > 400 ? '${text.substring(0, 400)}…' : text;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.pasteConfirmationTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.pasteConfirmationMessage),
                const SizedBox(height: 12),
                Container(
                  width: double.maxFinite,
                  padding: const EdgeInsets.all(12),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: SelectableText(preview),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.paste),
            ),
          ],
        ),
      );
      if (confirmed != true) {
        return;
      }
    }

    final renderer = ref.read(terminalPerformanceSettingsProvider).rendererMode;
    if (_usesWebRenderer(renderer)) {
      _webTerminalKey.currentState?.paste(text);
    } else if (_usesAlacrittyRenderer(renderer)) {
      await _alacrittyTerminalKey.currentState?.paste(text);
    } else {
      await _nativeTerminalKey.currentState?.paste(text);
    }
    _focusTerminal();
  }

  void _focusTerminal() {
    final renderer = ref.read(terminalPerformanceSettingsProvider).rendererMode;
    if (_usesWebRenderer(renderer)) {
      _webTerminalKey.currentState?.focus();
    } else if (_usesAlacrittyRenderer(renderer)) {
      unawaited(_alacrittyTerminalKey.currentState?.focus());
    } else {
      unawaited(_nativeTerminalKey.currentState?.focus());
    }
  }

  Future<void> _sendSpecialKey(TerminalKey key, int repeat) async {
    final session = _session;
    if (session == null || !session.isConnected) return;
    final modifiers = session.consumeArmedModifiers();
    final renderer = ref.read(terminalPerformanceSettingsProvider).rendererMode;

    var handled = false;
    for (var index = 0; index < repeat; index++) {
      if (_usesWebRenderer(renderer)) {
        handled =
            _webTerminalKey.currentState?.sendKey(
              key,
              control: modifiers.control,
              alt: modifiers.alt,
            ) ??
            false;
      } else if (_usesAlacrittyRenderer(renderer)) {
        handled =
            await _alacrittyTerminalKey.currentState?.sendKey(
              key,
              control: modifiers.control,
              alt: modifiers.alt,
            ) ??
            false;
      } else {
        handled =
            await _nativeTerminalKey.currentState?.sendKey(
              key,
              control: modifiers.control,
              alt: modifiers.alt,
            ) ??
            false;
      }
      if (!handled) {
        session.sendKeyWithModifiers(
          key,
          control: modifiers.control,
          alt: modifiers.alt,
        );
      }
    }
    _focusTerminal();
  }

  Future<void> _requestClose() async {
    final session = _session;
    if (session == null) {
      await _finishAndPop();
      return;
    }
    final active = !{
      SshSessionStatus.idle,
      SshSessionStatus.closed,
      SshSessionStatus.failed,
    }.contains(session.status);
    if (active) {
      final l10n = AppLocalizations.of(context);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.closeSessionTitle),
          content: Text(l10n.closeSessionMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.disconnect),
            ),
          ],
        ),
      );
      if (confirmed != true) {
        return;
      }
      await session.disconnect();
    }
    await (_webTerminalKey.currentState?.suspend() ?? Future<void>.value());
    await _alacrittyTerminalKey.currentState?.setActive(false);
    session.removeTerminalActivityListener(_pulseHighFrameRate);
    session.setViewportVisible(false);
    final closingTabId = _activeTabId;
    _sessionRegistry?.remove(closingTabId);
    await ref.read(connectionTabsProvider.notifier).close(closingTabId);
    final remaining =
        ref.read(connectionTabsProvider).value ?? const <ConnectionTab>[];
    if (!mounted) return;
    if (remaining.isNotEmpty) {
      final next = remaining.last;
      final profile = ref
          .read(connectionProfilesProvider.notifier)
          .findById(next.profileId ?? '');
      if (profile == null) {
        context.pop();
        return;
      }
      _activateTab(next, profile);
      await ref.read(connectionTabsProvider.notifier).markActive(next.id);
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _activeTabId != next.id) return;
        _webTerminalKey.currentState?.resume();
        unawaited(_alacrittyTerminalKey.currentState?.setActive(true));
        _focusTerminal();
      });
    } else {
      if (widget.popWhenEmpty) context.pop();
    }
  }

  Future<void> _finishAndPop() async {
    if (mounted) context.pop();
  }
}

class _SecretDialog extends StatefulWidget {
  const _SecretDialog({
    required this.title,
    required this.message,
    required this.label,
  });

  final String title;
  final String message;
  final String label;

  @override
  State<_SecretDialog> createState() => _SecretDialogState();
}

class _SecretDialogState extends State<_SecretDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.message),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: widget.label,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (value) => Navigator.pop(context, value),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(l10n.connect),
        ),
      ],
    );
  }
}

class _InteractivePromptDialog extends StatefulWidget {
  const _InteractivePromptDialog({required this.request});

  final InteractiveRequest request;

  @override
  State<_InteractivePromptDialog> createState() =>
      _InteractivePromptDialogState();
}

class _InteractivePromptDialogState extends State<_InteractivePromptDialog> {
  late final List<TextEditingController> _controllers = widget.request.prompts
      .map((prompt) => TextEditingController())
      .toList(growable: false);

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(
        widget.request.name.isEmpty
            ? l10n.interactiveAuthenticationTitle
            : widget.request.name,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.request.instruction.isEmpty
                  ? l10n.interactiveAuthenticationMessage
                  : widget.request.instruction,
            ),
            const SizedBox(height: 12),
            for (var index = 0; index < widget.request.prompts.length; index++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: _controllers[index],
                  autofocus: index == 0,
                  obscureText: !widget.request.prompts[index].echo,
                  enableSuggestions: widget.request.prompts[index].echo,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: widget.request.prompts[index].text,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _controllers.map((controller) => controller.text).toList(),
          ),
          child: Text(l10n.submit),
        ),
      ],
    );
  }
}

class _TerminalSessionBar extends StatelessWidget {
  const _TerminalSessionBar({
    required this.tabs,
    required this.currentTabId,
    required this.registry,
    required this.showSearch,
    required this.showCopy,
    required this.onSelect,
    required this.onClose,
    required this.onSearch,
    required this.onCopy,
    required this.onCommandPalette,
    required this.onTunnels,
  });

  final List<ConnectionTab> tabs;
  final String currentTabId;
  final SessionRegistry? registry;
  final bool showSearch;
  final bool showCopy;
  final ValueChanged<ConnectionTab> onSelect;
  final VoidCallback onClose;
  final VoidCallback onSearch;
  final VoidCallback onCopy;
  final VoidCallback onCommandPalette;
  final VoidCallback onTunnels;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        border: const Border(bottom: BorderSide(color: Colors.black)),
      ),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            Expanded(
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(left: 4, top: 4),
                itemCount: tabs.length,
                itemBuilder: (context, index) {
                  final tab = tabs[index];
                  return _SessionTabButton(
                    tab: tab,
                    session: registry?.find(tab.id),
                    selected: tab.id == currentTabId,
                    onTap: () => onSelect(tab),
                    onClose: tab.id == currentTabId ? onClose : null,
                  );
                },
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showSearch)
                  IconButton(
                    tooltip: '検索',
                    visualDensity: VisualDensity.compact,
                    onPressed: onSearch,
                    icon: const Icon(Icons.search),
                  ),
                if (showCopy)
                  IconButton(
                    tooltip: '直前のコマンド出力をコピー',
                    visualDensity: VisualDensity.compact,
                    onPressed: onCopy,
                    icon: const Icon(Icons.content_copy_outlined),
                  ),
                IconButton(
                  tooltip: 'コマンドパレット',
                  visualDensity: VisualDensity.compact,
                  onPressed: onCommandPalette,
                  icon: const Icon(Icons.terminal_outlined),
                ),
              ],
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

class _SessionTabButton extends StatelessWidget {
  const _SessionTabButton({
    required this.tab,
    required this.session,
    required this.selected,
    required this.onTap,
    required this.onClose,
  });

  final ConnectionTab tab;
  final SshSessionController? session;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final listenable = session;
    if (listenable == null) return _buildButton(context, null);
    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) => _buildButton(context, listenable.status),
    );
  }

  Widget _buildButton(BuildContext context, SshSessionStatus? status) {
    final colors = Theme.of(context).colorScheme;
    final effectiveStatus = status ?? SshSessionStatus.closed;
    final statusLabel = status == null && tab.restored
        ? '復元済み'
        : _statusText(AppLocalizations.of(context), effectiveStatus);
    return Semantics(
      button: true,
      selected: selected,
      label: '${tab.title}、$statusLabel',
      child: Material(
        color: Colors.transparent,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: AnimatedContainer(
            key: ValueKey('terminal-tab-${tab.id}'),
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            constraints: const BoxConstraints(minWidth: 112, maxWidth: 176),
            margin: const EdgeInsets.only(right: 2),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: selected ? Colors.black : colors.surfaceContainerHighest,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(8),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _sessionStatusColor(colors, effectiveStatus),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    tab.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: selected ? Colors.white : colors.onSurface,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                ),
                if (onClose != null) ...[
                  const SizedBox(width: 4),
                  Tooltip(
                    message: AppLocalizations.of(context).closeSessionTab,
                    child: InkResponse(
                      onTap: onClose,
                      radius: 14,
                      child: const Padding(
                        padding: EdgeInsets.all(3),
                        child: Icon(Icons.close, size: 16),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Color _sessionStatusColor(ColorScheme colors, SshSessionStatus status) =>
    switch (status) {
      SshSessionStatus.connected => const Color(0xff2e7d32),
      SshSessionStatus.connecting ||
      SshSessionStatus.verifyingHost ||
      SshSessionStatus.authenticating ||
      SshSessionStatus.openingPty ||
      SshSessionStatus.closing => colors.tertiary,
      SshSessionStatus.failed ||
      SshSessionStatus.reconnectPrompt => colors.error,
      SshSessionStatus.idle || SshSessionStatus.closed => colors.outline,
    };

class _SpecialKeyBar extends StatelessWidget {
  const _SpecialKeyBar({
    required this.session,
    required this.pasteLabel,
    required this.onPaste,
    required this.onKey,
    required this.onCommandPalette,
    required this.onTunnels,
  });

  final SshSessionController session;
  final String pasteLabel;
  final VoidCallback onPaste;
  final void Function(TerminalKey key, int repeat) onKey;
  final VoidCallback onCommandPalette;
  final VoidCallback onTunnels;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: SizedBox(
        height: 52,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          children: [
            FilterChip(
              label: const Text('Ctrl'),
              selected: session.controlArmed,
              onSelected: (_) => session.toggleControl(),
            ),
            const SizedBox(width: 4),
            FilterChip(
              label: const Text('Alt'),
              selected: session.altArmed,
              onSelected: (_) => session.toggleAlt(),
            ),
            const SizedBox(width: 4),
            _keyButton('Esc', TerminalKey.escape),
            _keyButton('Tab', TerminalKey.tab),
            _keyButton('↵', TerminalKey.enter),
            _keyButton('↑', TerminalKey.arrowUp),
            _keyButton('↓', TerminalKey.arrowDown),
            _keyButton('←', TerminalKey.arrowLeft),
            _keyButton('→', TerminalKey.arrowRight),
            const SizedBox(width: 4),
            TextButton.icon(
              onPressed: session.isConnected ? onPaste : null,
              icon: const Icon(Icons.content_paste, size: 18),
              label: Text(pasteLabel),
            ),
            IconButton(
              tooltip: 'コマンドパレット',
              onPressed: session.isConnected ? onCommandPalette : null,
              icon: const Icon(Icons.terminal_outlined),
            ),
            IconButton(
              tooltip: 'SSHトンネル',
              onPressed: session.isConnected ? onTunnels : null,
              icon: const Icon(Icons.route_outlined),
            ),
          ],
        ),
      ),
    );
  }

  Widget _keyButton(String label, TerminalKey key) {
    final button = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: OutlinedButton(
        onPressed: session.isConnected ? () => onKey(key, 1) : null,
        onLongPress: session.isConnected && key == TerminalKey.tab
            ? () => onKey(key, 2)
            : null,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 36),
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
        child: Text(label),
      ),
    );
    if (key != TerminalKey.tab) return button;
    return Tooltip(message: 'タップで補完、長押しで候補一覧', child: button);
  }
}

class _TunnelSheetAction {
  const _TunnelSheetAction.start(this.request) : stopId = null;
  const _TunnelSheetAction.stop(this.stopId) : request = null;

  final SshTunnelRequest? request;
  final int? stopId;
}

class _TunnelManagerSheet extends StatefulWidget {
  const _TunnelManagerSheet({required this.tunnels});
  final List<SshTunnelStatus> tunnels;

  @override
  State<_TunnelManagerSheet> createState() => _TunnelManagerSheetState();
}

class _TunnelManagerSheetState extends State<_TunnelManagerSheet> {
  final _bindPort = TextEditingController(text: '0');
  final _targetHost = TextEditingController(text: '127.0.0.1');
  final _targetPort = TextEditingController(text: '80');
  SshTunnelKind _kind = SshTunnelKind.local;
  bool _allowLan = false;

  @override
  void dispose() {
    _bindPort.dispose();
    _targetHost.dispose();
    _targetPort.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SSHトンネル', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            for (final tunnel in widget.tunnels)
              ListTile(
                leading: const Icon(Icons.route),
                title: Text('${tunnel.bindHost}:${tunnel.bindPort}'),
                subtitle: Text(
                  '${tunnel.kind == SshTunnelKind.socks5 ? 'SOCKS5' : 'ローカル転送'} ・ ↑${tunnel.bytesUp} ↓${tunnel.bytesDown} bytes',
                ),
                trailing: IconButton(
                  tooltip: '停止',
                  onPressed: () => Navigator.pop(
                    context,
                    _TunnelSheetAction.stop(tunnel.id),
                  ),
                  icon: const Icon(Icons.stop_circle_outlined),
                ),
              ),
            SegmentedButton<SshTunnelKind>(
              segments: const [
                ButtonSegment(value: SshTunnelKind.local, label: Text('ローカル')),
                ButtonSegment(
                  value: SshTunnelKind.socks5,
                  label: Text('SOCKS5'),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: (value) =>
                  setState(() => _kind = value.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bindPort,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'ローカルポート（0は自動）',
                border: OutlineInputBorder(),
              ),
            ),
            if (_kind == SshTunnelKind.local) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _targetHost,
                decoration: const InputDecoration(
                  labelText: '転送先ホスト',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _targetPort,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '転送先ポート',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('LANへ公開'),
              subtitle: const Text(
                '同じネットワークの端末から接続可能になります。信頼できる環境だけで有効にしてください。',
              ),
              value: _allowLan,
              onChanged: (value) => setState(() => _allowLan = value),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _start,
                icon: const Icon(Icons.play_arrow),
                label: const Text('開始'),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  void _start() {
    final bindPort = int.tryParse(_bindPort.text);
    final targetPort = int.tryParse(_targetPort.text);
    if (bindPort == null || bindPort < 0 || bindPort > 65535) return;
    if (_kind == SshTunnelKind.local &&
        (targetPort == null || targetPort < 1 || targetPort > 65535)) {
      return;
    }
    Navigator.pop(
      context,
      _TunnelSheetAction.start(
        SshTunnelRequest(
          kind: _kind,
          bindHost: _allowLan ? '0.0.0.0' : '127.0.0.1',
          bindPort: bindPort,
          targetHost: _targetHost.text.trim(),
          targetPort: targetPort ?? 0,
          allowLan: _allowLan,
        ),
      ),
    );
  }
}

class _FailurePanel extends StatelessWidget {
  const _FailurePanel({
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });

  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.72),
      child: Center(
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 40),
                const SizedBox(height: 12),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: Text(retryLabel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _statusText(AppLocalizations l10n, SshSessionStatus status) {
  return switch (status) {
    SshSessionStatus.idle => l10n.statusIdle,
    SshSessionStatus.connecting => l10n.statusConnecting,
    SshSessionStatus.verifyingHost => l10n.statusVerifyingHost,
    SshSessionStatus.authenticating => l10n.statusAuthenticating,
    SshSessionStatus.openingPty => l10n.statusOpeningPty,
    SshSessionStatus.connected => l10n.statusConnected,
    SshSessionStatus.reconnectPrompt => l10n.statusReconnectPrompt,
    SshSessionStatus.closing => l10n.statusClosing,
    SshSessionStatus.closed => l10n.statusClosed,
    SshSessionStatus.failed => l10n.statusFailed,
  };
}

double _terminalFontSize(double width, TextScaler textScaler) {
  final baseSize = switch (width) {
    < 400 => 12.0,
    < 600 => 13.0,
    _ => 14.0,
  };
  return textScaler.scale(baseSize).clamp(baseSize, 18.0);
}

String _failureText(AppLocalizations l10n, SshFailure? failure) {
  return switch (failure?.code) {
    SshFailureCode.dnsLookupFailed => l10n.failureDnsLookup,
    SshFailureCode.connectionRefused => l10n.failureConnectionRefused,
    SshFailureCode.connectionTimedOut => l10n.failureConnectionTimeout,
    SshFailureCode.hostKeyRejected => l10n.failureHostKeyRejected,
    SshFailureCode.hostKeyMismatch => l10n.failureHostKeyMismatch,
    SshFailureCode.authenticationFailed => l10n.failureAuthentication,
    SshFailureCode.privateKeyInvalid => l10n.failurePrivateKey,
    SshFailureCode.keyPassphraseRequired => l10n.failureKeyPassphraseRequired,
    SshFailureCode.ptyRejected => l10n.failurePty,
    SshFailureCode.remoteClosed => l10n.failureRemoteClosed,
    SshFailureCode.networkLost => l10n.failureNetwork,
    SshFailureCode.jumpHostConnectionFailed => '踏み台へ接続できませんでした。接続経路を確認してください。',
    SshFailureCode.jumpHostAuthenticationFailed =>
      '踏み台の認証に失敗しました。踏み台ごとの資格情報を確認してください。',
    SshFailureCode.jumpHostKeyRejected =>
      '踏み台のホスト鍵を確認できません。先に踏み台へ直接接続して鍵を確認してください。',
    SshFailureCode.vaultLocked => 'Vaultがロックされています。認証してから再試行してください。',
    SshFailureCode.biometricUnavailable => '端末認証を利用できません。Vault保護設定を確認してください。',
    SshFailureCode.biometricCanceled => '端末認証をキャンセルしました。',
    SshFailureCode.keystoreKeyInvalidated =>
      'Keystore鍵が無効です。Vault保護を再設定してください。',
    SshFailureCode.tunnelBindFailed => 'トンネルのポートを開けませんでした。',
    SshFailureCode.tunnelRemoteRejected => '接続先がトンネル要求を拒否しました。',
    SshFailureCode.socksProtocolError => 'SOCKS5要求を処理できませんでした。',
    SshFailureCode.moshServerMissing => '接続先にmosh-serverがありません。',
    SshFailureCode.moshUdpUnreachable => 'MoshのUDPポートへ到達できません。',
    SshFailureCode.moshProtocolMismatch => 'Moshプロトコルに互換性がありません。',
    SshFailureCode.simdUnavailable => 'この端末では指定したSIMD経路を利用できません。',
    SshFailureCode.keyDecodeFailed => l10n.failurePrivateKey,
    SshFailureCode.sessionProfileMissing => '接続先が削除されています。',
    SshFailureCode.remoteDesktopDisconnected => 'リモートデスクトップ接続が終了しました。',
    SshFailureCode.unexpected || null => l10n.failureUnexpected,
  };
}
