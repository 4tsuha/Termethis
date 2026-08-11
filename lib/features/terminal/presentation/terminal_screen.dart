import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:xterm/xterm.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../connections/application/connection_profiles_controller.dart';
import '../../connections/domain/connection_profile.dart';
import '../../connections/domain/credential_vault.dart';
import '../../settings/application/app_font_controller.dart';
import '../../settings/application/terminal_performance_settings_controller.dart';
import '../../settings/domain/terminal_performance_settings.dart';
import '../application/session_registry.dart';
import '../application/ssh_session_controller.dart';
import '../application/ssh_tabs_controller.dart';
import '../domain/ssh_tab.dart';
import '../domain/ssh_failure.dart';
import '../domain/ssh_gateway.dart';
import '../../../infrastructure/display/android_terminal_window_controller.dart';
import 'widgets/xterm_web_terminal.dart';

class TerminalScreen extends ConsumerStatefulWidget {
  const TerminalScreen({
    required this.profileId,
    required this.tabId,
    super.key,
  });

  final String profileId;
  final String tabId;

  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen>
    with WidgetsBindingObserver {
  final _terminalFocusNode = FocusNode();
  final _webTerminalKey = GlobalKey<XtermWebTerminalState>();
  final _windowController = const AndroidTerminalWindowController();
  ConnectionProfile? _profile;
  SshSessionController? _session;
  SessionRegistry? _sessionRegistry;
  Timer? _performancePulseTimer;
  String _webRenderer = '起動中';
  bool _webTerminalFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _profile = ref
        .read(connectionProfilesProvider.notifier)
        .findById(widget.profileId);
    if (_profile case final profile?) {
      _sessionRegistry = ref.read(sessionRegistryProvider);
      _session = _sessionRegistry!.open(widget.tabId, profile);
      if (ref.read(terminalPerformanceSettingsProvider).rendererMode ==
          TerminalRendererMode.flutter) {
        _session!.enableFlutterTerminalMirror();
      }
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
    _performancePulseTimer?.cancel();
    _session?.removeTerminalActivityListener(_pulseHighFrameRate);
    _session?.setViewportVisible(false);
    _terminalFocusNode.dispose();
    unawaited(_windowController.restore());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final visible = state == AppLifecycleState.resumed;
    _session?.setViewportVisible(visible);
    if (visible) {
      _webTerminalKey.currentState?.resume();
    } else {
      unawaited(
        _webTerminalKey.currentState?.suspend() ?? Future<void>.value(),
      );
    }
  }

  Future<void> _initializeTab() async {
    final tabs = await ref.read(sshTabsProvider.future);
    SshTab? tab;
    for (final item in tabs) {
      if (item.id == widget.tabId) tab = item;
    }
    if (!mounted || tab == null || tab.restored) return;
    if (_session?.status == SshSessionStatus.idle) {
      await _startConnection();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final appFont = ref.watch(appFontProvider);
    final performance = ref.watch(terminalPerformanceSettingsProvider);
    ref.listen(terminalPerformanceSettingsProvider, (_, next) {
      if (next.rendererMode == TerminalRendererMode.flutter) {
        _session?.enableFlutterTerminalMirror();
      }
      unawaited(_applyTerminalWindowSettings(next));
    });
    final useWebRenderer =
        performance.rendererMode == TerminalRendererMode.webgl &&
        !_webTerminalFailed;
    final rendererLabel = useWebRenderer
        ? _webRenderer == 'webgl'
              ? 'WebGL'
              : _webRenderer
        : 'Flutter互換';
    final tabs = ref.watch(sshTabsProvider).value ?? const <SshTab>[];
    final session = _session;
    if (_profile == null || session == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.appTitle)),
        body: Center(child: Text(l10n.profileNotFound)),
      );
    }
    return PopScope<void>(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          unawaited(
            _webTerminalKey.currentState?.suspend() ?? Future<void>.value(),
          );
        }
      },
      child: ListenableBuilder(
        listenable: session,
        builder: (context, child) {
          return Scaffold(
            backgroundColor: Colors.black,
            resizeToAvoidBottomInset: performance.resizeForKeyboard,
            appBar: AppBar(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _SessionStatusDot(status: session.status, size: 8),
                      const SizedBox(width: 6),
                      Text(
                        _statusText(l10n, session.status),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      const SizedBox(width: 8),
                      _RendererBadge(label: rendererLabel),
                      if (tabs.length > 1) ...[
                        const SizedBox(width: 8),
                        _TabOverviewButton(
                          label:
                              '${tabs.indexWhere((tab) => tab.id == widget.tabId) + 1}/${tabs.length}',
                          onTap: () => _showTabOverview(tabs),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              actions: [
                if (session.isConnected)
                  IconButton.filledTonal(
                    tooltip: l10n.disconnect,
                    onPressed: session.disconnect,
                    icon: const Icon(Icons.link_off),
                  ),
                IconButton(
                  tooltip: l10n.closeSessionTab,
                  onPressed: _requestClose,
                  icon: const Icon(Icons.close),
                ),
              ],
              bottom: performance.showSessionTabBar
                  ? PreferredSize(
                      preferredSize: const Size.fromHeight(60),
                      child: _TerminalSessionBar(
                        tabs: tabs,
                        currentTabId: widget.tabId,
                        registry: _sessionRegistry,
                        showSearch: performance.showSearchButton,
                        showCopy: performance.showCopyOutputButton,
                        onSelect: (tab) => unawaited(_switchTab(tab)),
                        onSearch: _sendSearchShortcut,
                        onCopy: _copyLastOutput,
                      ),
                    )
                  : null,
            ),
            body: SafeArea(
              top: false,
              child: Column(
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final fontSize = _terminalFontSize(
                          constraints.maxWidth,
                          MediaQuery.textScalerOf(context),
                        );
                        return Stack(
                          children: [
                            Positioned.fill(
                              child: Listener(
                                behavior: HitTestBehavior.translucent,
                                onPointerDown: (_) => _pulseHighFrameRate(),
                                onPointerMove: (_) => _pulseHighFrameRate(),
                                child: useWebRenderer
                                    ? XtermWebTerminal(
                                        key: _webTerminalKey,
                                        session: session,
                                        scrollbackLines:
                                            performance.scrollbackLines,
                                        japaneseFontFamily: appFont.family,
                                        fontSize: fontSize,
                                        mouseInput: performance.mouseInput,
                                        longPressRightClick:
                                            performance.longPressRightClick,
                                        tapToMovePromptCursor:
                                            performance.tapToMovePromptCursor,
                                        onRendererChanged: (renderer) {
                                          if (mounted &&
                                              renderer != _webRenderer) {
                                            setState(
                                              () => _webRenderer = renderer,
                                            );
                                          }
                                        },
                                        onFatalError:
                                            _fallbackToFlutterTerminal,
                                      )
                                    : TerminalView(
                                        session.terminal,
                                        focusNode: _terminalFocusNode,
                                        autofocus: true,
                                        keyboardType: TextInputType.text,
                                        enableSuggestions: true,
                                        textStyle: TerminalStyle(
                                          fontSize: fontSize,
                                          height: 1.15,
                                          fontFamily: 'CascadiaMono',
                                          fontFamilyFallback: [
                                            appFont.family,
                                            'Noto Color Emoji',
                                            'monospace',
                                          ],
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 6,
                                        ),
                                      ),
                              ),
                            ),
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
                        );
                      },
                    ),
                  ),
                  _SpecialKeyBar(
                    session: session,
                    pasteLabel: l10n.paste,
                    onPaste: _paste,
                    onKeySent: _focusTerminal,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _switchTab(SshTab tab) async {
    if (tab.id == widget.tabId) return;
    await (_webTerminalKey.currentState?.suspend() ?? Future<void>.value());
    if (!mounted) return;
    context.pushReplacement('/terminal/${tab.profileId}?tab=${tab.id}');
  }

  Future<void> _showTabOverview(List<SshTab> tabs) async {
    final selected = await showModalBottomSheet<SshTab>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.72,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'SSHセッション',
                      style: Theme.of(sheetContext).textTheme.titleLarge,
                    ),
                  ),
                  Text('${tabs.length}件'),
                ],
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: tabs.length,
                itemBuilder: (context, index) {
                  final tab = tabs[index];
                  final tabSession = _sessionRegistry?.find(tab.id);
                  final status = tabSession?.status ?? SshSessionStatus.closed;
                  final statusLabel = tabSession == null && tab.restored
                      ? '復元済み'
                      : _statusText(AppLocalizations.of(context), status);
                  final selected = tab.id == widget.tabId;
                  return ListTile(
                    leading: _SessionStatusIcon(
                      status: status,
                      restored: tab.restored,
                    ),
                    title: Text(tab.title),
                    subtitle: Text(statusLabel),
                    selected: selected,
                    trailing: selected
                        ? const Icon(Icons.check_circle)
                        : const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pop(context, tab),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (selected != null && mounted) await _switchTab(selected);
  }

  Future<void> _applyTerminalWindowSettings(
    TerminalPerformanceSettings settings,
  ) => _windowController.apply(
    keepScreenAwake: settings.keepScreenAwake,
    resizeForKeyboard: settings.resizeForKeyboard,
  );

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
    if (performance.rendererMode == TerminalRendererMode.webgl &&
        !_webTerminalFailed) {
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
      ).showSnackBar(const SnackBar(content: Text('最後のコマンド出力をコピーしました。')));
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
              '最後の出力コピーとプロンプト内カーソル移動にはOSC 133マーカーが必要です。starship、fish 3.6以降、または対応するbash/zsh設定を使用してください。',
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

  void _fallbackToFlutterTerminal(String _) {
    if (!mounted || _webTerminalFailed) return;
    _session?.enableFlutterTerminalMirror();
    setState(() => _webTerminalFailed = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('WebGL端末を利用できないため互換描画へ切り替えました。')),
    );
  }

  void _pulseHighFrameRate() {
    final mode = ref.read(terminalPerformanceSettingsProvider).refreshRateMode;
    if (mode != RefreshRateMode.balanced || _performancePulseTimer != null) {
      return;
    }
    _performancePulseTimer = Timer(const Duration(milliseconds: 100), () {
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

    await ref.read(sshTabsProvider.notifier).markActive(widget.tabId);

    final authentication = await _resolveAuthentication(profile, session);
    if (!mounted || authentication == null) {
      if (session.status == SshSessionStatus.idle) {
        await _finishAndPop();
      }
      return;
    }

    await session.connect(
      authentication: authentication,
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
      final password = await _askPassword(profile);
      return password == null ? null : SshPasswordAuthentication(password);
    }

    final reference = profile.credentialReference;
    if (reference == null) {
      session.reportFailure(const SshFailure(SshFailureCode.privateKeyInvalid));
      return null;
    }

    try {
      final credential = await ref
          .read(credentialVaultProvider)
          .readPrivateKey(CredentialHandle(reference));
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
    if (renderer == TerminalRendererMode.webgl && !_webTerminalFailed) {
      _webTerminalKey.currentState?.paste(text);
    } else {
      session.paste(text);
    }
    _focusTerminal();
  }

  void _focusTerminal() {
    final renderer = ref.read(terminalPerformanceSettingsProvider).rendererMode;
    if (renderer == TerminalRendererMode.webgl && !_webTerminalFailed) {
      _webTerminalKey.currentState?.focus();
    } else {
      _terminalFocusNode.requestFocus();
    }
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
    _sessionRegistry?.remove(widget.tabId);
    await ref.read(sshTabsProvider.notifier).close(widget.tabId);
    final remaining = ref.read(sshTabsProvider).value ?? const <SshTab>[];
    if (!mounted) return;
    if (remaining.isNotEmpty) {
      final next = remaining.last;
      context.pushReplacement('/terminal/${next.profileId}?tab=${next.id}');
    } else {
      context.pop();
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
    required this.onSearch,
    required this.onCopy,
  });

  final List<SshTab> tabs;
  final String currentTabId;
  final SessionRegistry? registry;
  final bool showSearch;
  final bool showCopy;
  final ValueChanged<SshTab> onSelect;
  final VoidCallback onSearch;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      child: SizedBox(
        height: 60,
        child: Row(
          children: [
            Expanded(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(8, 5, 4, 5),
                itemCount: tabs.length,
                separatorBuilder: (_, _) => const SizedBox(width: 4),
                itemBuilder: (context, index) {
                  final tab = tabs[index];
                  return _SessionTabButton(
                    tab: tab,
                    session: registry?.find(tab.id),
                    selected: tab.id == currentTabId,
                    onTap: () => onSelect(tab),
                  );
                },
              ),
            ),
            if (showSearch || showCopy)
              Container(
                margin: const EdgeInsets.fromLTRB(4, 6, 8, 6),
                padding: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showSearch)
                      IconButton(
                        tooltip: '検索',
                        visualDensity: VisualDensity.compact,
                        onPressed: onSearch,
                        icon: const Icon(Icons.search),
                      ),
                    if (showSearch && showCopy)
                      SizedBox(
                        height: 24,
                        child: VerticalDivider(
                          width: 1,
                          thickness: 1,
                          color: colors.outlineVariant,
                        ),
                      ),
                    if (showCopy)
                      IconButton(
                        tooltip: '最後の出力をコピー',
                        visualDensity: VisualDensity.compact,
                        onPressed: onCopy,
                        icon: const Icon(Icons.content_copy_outlined),
                      ),
                  ],
                ),
              ),
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
  });

  final SshTab tab;
  final SshSessionController? session;
  final bool selected;
  final VoidCallback onTap;

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
        color: selected ? colors.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            constraints: const BoxConstraints(minWidth: 132, maxWidth: 184),
            padding: const EdgeInsets.fromLTRB(10, 5, 12, 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? colors.primary : colors.outlineVariant,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: _sessionStatusColor(
                      colors,
                      effectiveStatus,
                    ).withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    _sessionStatusIcon(effectiveStatus, restored: tab.restored),
                    size: 17,
                    color: _sessionStatusColor(colors, effectiveStatus),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tab.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w600,
                        ),
                      ),
                      Text(
                        statusLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: _sessionStatusColor(colors, effectiveStatus),
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SessionStatusDot extends StatelessWidget {
  const _SessionStatusDot({required this.status, this.size = 8});

  final SshSessionStatus status;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _sessionStatusColor(Theme.of(context).colorScheme, status),
        shape: BoxShape.circle,
      ),
    );
  }
}

class _SessionStatusIcon extends StatelessWidget {
  const _SessionStatusIcon({required this.status, required this.restored});

  final SshSessionStatus status;
  final bool restored;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = _sessionStatusColor(colors, status);
    return CircleAvatar(
      backgroundColor: color.withValues(alpha: 0.14),
      foregroundColor: color,
      child: Icon(_sessionStatusIcon(status, restored: restored), size: 20),
    );
  }
}

class _TabOverviewButton extends StatelessWidget {
  const _TabOverviewButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(5, 1, 3, 1),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelSmall),
              const Icon(Icons.arrow_drop_down, size: 15),
            ],
          ),
        ),
      ),
    );
  }
}

class _RendererBadge extends StatelessWidget {
  const _RendererBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colors.onSurfaceVariant,
            height: 1.2,
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

IconData _sessionStatusIcon(
  SshSessionStatus status, {
  required bool restored,
}) => switch (status) {
  SshSessionStatus.connected => Icons.terminal,
  SshSessionStatus.connecting ||
  SshSessionStatus.verifyingHost ||
  SshSessionStatus.authenticating ||
  SshSessionStatus.openingPty ||
  SshSessionStatus.closing => Icons.sync,
  SshSessionStatus.failed ||
  SshSessionStatus.reconnectPrompt => Icons.error_outline,
  SshSessionStatus.idle ||
  SshSessionStatus.closed => restored ? Icons.history : Icons.terminal_outlined,
};

class _SpecialKeyBar extends StatelessWidget {
  const _SpecialKeyBar({
    required this.session,
    required this.pasteLabel,
    required this.onPaste,
    required this.onKeySent,
  });

  final SshSessionController session;
  final String pasteLabel;
  final VoidCallback onPaste;
  final VoidCallback onKeySent;

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
          ],
        ),
      ),
    );
  }

  Widget _keyButton(String label, TerminalKey key) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: OutlinedButton(
        onPressed: session.isConnected
            ? () {
                session.sendKey(key);
                onKeySent();
              }
            : null,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 36),
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
        child: Text(label),
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
    SshFailureCode.unexpected || null => l10n.failureUnexpected,
  };
}
