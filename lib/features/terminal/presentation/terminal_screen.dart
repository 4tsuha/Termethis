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
import '../application/session_registry.dart';
import '../application/ssh_session_controller.dart';
import '../domain/ssh_failure.dart';
import '../domain/ssh_gateway.dart';

class TerminalScreen extends ConsumerStatefulWidget {
  const TerminalScreen({required this.profileId, super.key});

  final String profileId;

  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen> {
  final _terminalFocusNode = FocusNode();
  ConnectionProfile? _profile;
  SshSessionController? _session;
  SessionRegistry? _sessionRegistry;
  bool _allowPop = false;

  @override
  void initState() {
    super.initState();
    _profile = ref
        .read(connectionProfilesProvider.notifier)
        .findById(widget.profileId);
    if (_profile case final profile?) {
      _sessionRegistry = ref.read(sessionRegistryProvider);
      _session = _sessionRegistry!.open(profile);
      WidgetsBinding.instance.addPostFrameCallback((_) => _startConnection());
    }
  }

  @override
  void dispose() {
    _terminalFocusNode.dispose();
    if (_session != null) {
      _sessionRegistry?.remove(widget.profileId);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final appFont = ref.watch(appFontProvider);
    final session = _session;
    if (_profile == null || session == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.appTitle)),
        body: Center(child: Text(l10n.profileNotFound)),
      );
    }

    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _requestClose();
        }
      },
      child: ListenableBuilder(
        listenable: session,
        builder: (context, child) {
          return Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(session.title, maxLines: 1),
                  Text(
                    _statusText(l10n, session.status),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
              actions: [
                if (session.isConnected)
                  IconButton(
                    tooltip: l10n.disconnect,
                    onPressed: _requestClose,
                    icon: const Icon(Icons.link_off),
                  ),
              ],
            ),
            body: SafeArea(
              top: false,
              child: Column(
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: TerminalView(
                            session.terminal,
                            focusNode: _terminalFocusNode,
                            autofocus: true,
                            keyboardType: TextInputType.text,
                            enableSuggestions: true,
                            textStyle: TerminalStyle(
                              fontSize: 14,
                              height: 1.15,
                              fontFamily: 'CascadiaMono',
                              fontFamilyFallback: [
                                appFont.family,
                                'Noto Color Emoji',
                                'monospace',
                              ],
                            ),
                            padding: const EdgeInsets.all(8),
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: _StatusBadge(
                            status: session.status,
                            label: _statusText(l10n, session.status),
                          ),
                        ),
                        if ({
                          SshSessionStatus.failed,
                          SshSessionStatus.reconnectPrompt,
                        }.contains(session.status))
                          Positioned.fill(
                            child: _FailurePanel(
                              message: _failureText(l10n, session.failure),
                              retryLabel: l10n.retry,
                              onRetry: _startConnection,
                            ),
                          ),
                      ],
                    ),
                  ),
                  _SpecialKeyBar(
                    session: session,
                    pasteLabel: l10n.paste,
                    onPaste: _paste,
                    onKeySent: _terminalFocusNode.requestFocus,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _startConnection() async {
    final session = _session;
    final profile = _profile;
    if (!mounted || session == null || profile == null) {
      return;
    }

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
      _terminalFocusNode.requestFocus();
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

    session.paste(text);
    _terminalFocusNode.requestFocus();
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
    await _finishAndPop();
  }

  Future<void> _finishAndPop() async {
    if (!mounted) {
      return;
    }
    setState(() => _allowPop = true);
    await Future<void>.delayed(Duration.zero);
    if (mounted) {
      context.pop();
    }
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

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, required this.label});

  final SshSessionStatus status;
  final String label;

  @override
  Widget build(BuildContext context) {
    final connected = status == SshSessionStatus.connected;
    final failed = {
      SshSessionStatus.failed,
      SshSessionStatus.reconnectPrompt,
    }.contains(status);
    final color = connected
        ? Colors.green
        : failed
        ? Colors.red
        : Colors.orange;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 12),
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
