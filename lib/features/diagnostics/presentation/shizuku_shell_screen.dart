import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:xterm/xterm.dart';

import '../../settings/application/app_font_controller.dart';
import '../../settings/application/terminal_performance_settings_controller.dart';
import '../../settings/domain/terminal_performance_settings.dart';
import '../application/shizuku_diagnostics_controller.dart';
import '../application/shizuku_shell_controller.dart';
import '../domain/shizuku_diagnostics_gateway.dart';

class ShizukuShellScreen extends ConsumerStatefulWidget {
  const ShizukuShellScreen({this.embedded = false, super.key});

  final bool embedded;

  @override
  ConsumerState<ShizukuShellScreen> createState() => _ShizukuShellScreenState();
}

class _ShizukuShellScreenState extends ConsumerState<ShizukuShellScreen> {
  bool _startRequested = false;

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(shizukuStatusProvider);
    final controller = ref.watch(shizukuShellControllerProvider);
    final performance = ref.watch(terminalPerformanceSettingsProvider);
    final appFont = ref.watch(appFontProvider);

    if (status.value?.canUsePrivilegedFeatures == true && !_startRequested) {
      _startRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(controller.start());
      });
    }

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: Column(
            children: [
              if (!widget.embedded)
                _ShizukuTabBar(
                  running: controller.isRunning,
                  onClose: () async {
                    await controller.stop();
                    if (context.mounted) context.go('/connections');
                  },
                ),
              Expanded(
                child: status.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => _ShellUnavailable(
                    message: '$error',
                    onPressed: () =>
                        ref.read(shizukuStatusProvider.notifier).refresh(),
                    buttonLabel: '再試行',
                  ),
                  data: (value) => value.canUsePrivilegedFeatures
                      ? Stack(
                          children: [
                            Positioned.fill(
                              child: TerminalView(
                                controller.terminal,
                                autofocus: true,
                                textStyle: TerminalStyle(
                                  fontFamily: performance.terminalFont.family,
                                  fontFamilyFallback: [
                                    appFont.family,
                                    'NerdSymbolsMono',
                                    'Noto Color Emoji',
                                  ],
                                  fontSize: 13,
                                  height: 1.2,
                                ),
                              ),
                            ),
                            if (controller.isStarting)
                              const Positioned.fill(
                                child: ColoredBox(
                                  color: Color(0x66000000),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                ),
                              ),
                            if (!controller.isStarting && !controller.isRunning)
                              Positioned.fill(
                                child: _ShellUnavailable(
                                  message:
                                      controller.errorMessage ??
                                      'ADBシェルは停止しています。',
                                  onPressed: () {
                                    _startRequested = true;
                                    unawaited(controller.start());
                                  },
                                  buttonLabel: '開始',
                                ),
                              ),
                          ],
                        )
                      : _PermissionRequired(
                          status: value,
                          onRequest: () => ref
                              .read(shizukuStatusProvider.notifier)
                              .requestPermission(),
                        ),
                ),
              ),
              _ShizukuSpecialKeyBar(controller: controller),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShizukuTabBar extends StatelessWidget {
  const _ShizukuTabBar({required this.running, required this.onClose});

  final bool running;
  final VoidCallback onClose;

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
        child: Align(
          alignment: Alignment.bottomLeft,
          child: Container(
            constraints: const BoxConstraints(minWidth: 144, maxWidth: 220),
            height: 44,
            margin: const EdgeInsets.only(left: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: running ? const Color(0xff43a047) : colors.outline,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'ADBシェル',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'ADBシェルを閉じる',
                  visualDensity: VisualDensity.compact,
                  onPressed: onClose,
                  icon: const Icon(Icons.close, color: Colors.white, size: 17),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PermissionRequired extends StatelessWidget {
  const _PermissionRequired({required this.status, required this.onRequest});

  final ShizukuStatus status;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    final canRequest = status.permission == ShizukuPermissionState.denied;
    return _ShellUnavailable(
      message: switch (status.permission) {
        ShizukuPermissionState.unavailable => 'Shizukuを起動してから状態を更新してください。',
        ShizukuPermissionState.unsupported => 'Shizuku v11以降へ更新してください。',
        ShizukuPermissionState.denied => 'ADBシェルを開くにはShizuku権限が必要です。',
        ShizukuPermissionState.deniedPermanently =>
          'Shizukuアプリの許可一覧からTermethisを許可してください。',
        ShizukuPermissionState.granted => '',
      },
      onPressed: canRequest ? onRequest : null,
      buttonLabel: '権限を許可',
    );
  }
}

class _ShellUnavailable extends StatelessWidget {
  const _ShellUnavailable({
    required this.message,
    required this.onPressed,
    required this.buttonLabel,
  });

  final String message;
  final VoidCallback? onPressed;
  final String buttonLabel;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.terminal, size: 48, color: Colors.white70),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            if (onPressed != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onPressed, child: Text(buttonLabel)),
            ],
          ],
        ),
      ),
    ),
  );
}

class _ShizukuSpecialKeyBar extends StatelessWidget {
  const _ShizukuSpecialKeyBar({required this.controller});

  final ShizukuShellController controller;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          children: [
            _ModifierButton(
              label: 'Ctrl',
              selected: controller.controlArmed,
              onPressed: controller.toggleControl,
            ),
            _ModifierButton(
              label: 'Alt',
              selected: controller.altArmed,
              onPressed: controller.toggleAlt,
            ),
            _KeyButton(
              label: 'Esc',
              onPressed: () => controller.sendKey(TerminalKey.escape),
            ),
            _KeyButton(
              label: 'Tab',
              onPressed: () => controller.sendKey(TerminalKey.tab),
            ),
            _KeyButton(
              icon: Icons.keyboard_arrow_up,
              onPressed: () => controller.sendKey(TerminalKey.arrowUp),
            ),
            _KeyButton(
              icon: Icons.keyboard_arrow_down,
              onPressed: () => controller.sendKey(TerminalKey.arrowDown),
            ),
            _KeyButton(
              icon: Icons.keyboard_arrow_left,
              onPressed: () => controller.sendKey(TerminalKey.arrowLeft),
            ),
            _KeyButton(
              icon: Icons.keyboard_arrow_right,
              onPressed: () => controller.sendKey(TerminalKey.arrowRight),
            ),
            _KeyButton(
              icon: Icons.content_paste_outlined,
              onPressed: () async {
                final data = await Clipboard.getData(Clipboard.kTextPlain);
                final text = data?.text;
                if (text != null && text.isNotEmpty) controller.paste(text);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ModifierButton extends StatelessWidget {
  const _ModifierButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onPressed(),
    ),
  );
}

class _KeyButton extends StatelessWidget {
  const _KeyButton({this.label, this.icon, required this.onPressed});

  final String? label;
  final IconData? icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(44, 36),
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
      child: icon == null ? Text(label!) : Icon(icon, size: 20),
    ),
  );
}
