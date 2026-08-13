import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../../application/ssh_session_controller.dart';

class TerminalShortcutBar extends StatefulWidget {
  const TerminalShortcutBar({
    required this.session,
    required this.supportsTunnels,
    required this.pasteLabel,
    required this.onPaste,
    required this.onKey,
    required this.onCommandPalette,
    required this.onTunnels,
    required this.agentMode,
    required this.onToggleAgentMode,
    super.key,
  });

  final SshSessionController session;
  final bool supportsTunnels;
  final String pasteLabel;
  final VoidCallback onPaste;
  final void Function(TerminalKey key, int repeat) onKey;
  final VoidCallback onCommandPalette;
  final VoidCallback onTunnels;
  final bool agentMode;
  final VoidCallback? onToggleAgentMode;

  @override
  State<TerminalShortcutBar> createState() => _TerminalShortcutBarState();
}

class _TerminalShortcutBarState extends State<TerminalShortcutBar> {
  bool _useTwoRows = false;

  SshSessionController get session => widget.session;
  bool get supportsTunnels => widget.supportsTunnels;
  String get pasteLabel => widget.pasteLabel;
  VoidCallback get onPaste => widget.onPaste;
  void Function(TerminalKey key, int repeat) get onKey => widget.onKey;
  VoidCallback get onCommandPalette => widget.onCommandPalette;
  VoidCallback get onTunnels => widget.onTunnels;
  bool get agentMode => widget.agentMode;
  VoidCallback? get onToggleAgentMode => widget.onToggleAgentMode;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          if (width >= 760) {
            return SizedBox(
              height: 60,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _primaryKeys(),
                    const SizedBox(width: 12),
                    _directionKeys(),
                    const SizedBox(width: 12),
                    _actionKeys(),
                  ],
                ),
              ),
            );
          }
          return _useTwoRows ? _compactTwoRows() : _compactRow();
        },
      ),
    );
  }

  Widget _compactRow() => SizedBox(
    height: 60,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              label: 'ショートカットキー。左右にスクロールできます',
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _primaryKeys(),
                    const SizedBox(width: 8),
                    _directionKeys(),
                    const SizedBox(width: 8),
                    _actionButton(
                      icon: Icons.content_paste_outlined,
                      tooltip: pasteLabel,
                      onPressed: session.isConnected ? onPaste : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          _layoutToggleButton(),
          const SizedBox(width: 4),
          _overflowActions(includePaste: false),
        ],
      ),
    ),
  );

  Widget _compactTwoRows() => SizedBox(
    height: 112,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                SizedBox(
                  height: 48,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: _primaryKeys(),
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 48,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _directionKeys(),
                        const SizedBox(width: 8),
                        _actionButton(
                          icon: Icons.content_paste_outlined,
                          tooltip: pasteLabel,
                          onPressed: session.isConnected ? onPaste : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Column(
            children: [
              _layoutToggleButton(),
              const SizedBox(height: 4),
              _overflowActions(includePaste: false),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _layoutToggleButton() => _actionButton(
    icon: _useTwoRows ? Icons.view_stream_outlined : Icons.view_agenda_outlined,
    tooltip: _useTwoRows ? '1段表示に切り替え' : '2段表示に切り替え',
    onPressed: () => setState(() => _useTwoRows = !_useTwoRows),
    selected: _useTwoRows,
  );

  Widget _primaryKeys() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _modifierChip('Ctrl', session.controlArmed, session.toggleControl),
      const SizedBox(width: 4),
      _modifierChip('Alt', session.altArmed, session.toggleAlt),
      const SizedBox(width: 4),
      _textKey('Esc', 'Escape', TerminalKey.escape),
      const SizedBox(width: 4),
      _textKey('Tab', 'Tab', TerminalKey.tab, longPressRepeat: 2),
      const SizedBox(width: 4),
      _iconKey(Icons.keyboard_return, 'Enter', TerminalKey.enter),
    ],
  );

  Widget _directionKeys() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _iconKey(Icons.arrow_back, '左矢印', TerminalKey.arrowLeft),
      const SizedBox(width: 4),
      _iconKey(Icons.arrow_upward, '上矢印', TerminalKey.arrowUp),
      const SizedBox(width: 4),
      _iconKey(Icons.arrow_downward, '下矢印', TerminalKey.arrowDown),
      const SizedBox(width: 4),
      _iconKey(Icons.arrow_forward, '右矢印', TerminalKey.arrowRight),
    ],
  );

  Widget _actionKeys() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _actionButton(
        icon: Icons.content_paste_outlined,
        tooltip: pasteLabel,
        onPressed: session.isConnected ? onPaste : null,
      ),
      const SizedBox(width: 4),
      _actionButton(
        icon: agentMode ? Icons.smart_toy : Icons.smart_toy_outlined,
        tooltip: agentMode ? 'Agentモードを終了' : 'Agentモード',
        onPressed: session.isConnected ? onToggleAgentMode : null,
        selected: agentMode,
      ),
      const SizedBox(width: 4),
      _actionButton(
        icon: Icons.terminal_outlined,
        tooltip: 'コマンドパレット',
        onPressed: session.isConnected ? onCommandPalette : null,
      ),
      const SizedBox(width: 4),
      _actionButton(
        icon: Icons.route_outlined,
        tooltip: 'SSHトンネル',
        onPressed: session.isConnected && supportsTunnels ? onTunnels : null,
      ),
    ],
  );

  Widget _overflowActions({required bool includePaste}) => SizedBox(
    width: 48,
    height: 48,
    child: PopupMenuButton<_ShortcutAction>(
      tooltip: 'その他の操作',
      enabled: session.isConnected,
      icon: const Icon(Icons.more_horiz),
      onSelected: (action) {
        switch (action) {
          case _ShortcutAction.paste:
            onPaste();
          case _ShortcutAction.agent:
            onToggleAgentMode?.call();
          case _ShortcutAction.commandPalette:
            onCommandPalette();
          case _ShortcutAction.tunnels:
            onTunnels();
        }
      },
      itemBuilder: (context) => [
        if (includePaste)
          PopupMenuItem(
            value: _ShortcutAction.paste,
            child: ListTile(
              leading: const Icon(Icons.content_paste_outlined),
              title: Text(pasteLabel),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        PopupMenuItem(
          value: _ShortcutAction.agent,
          enabled: onToggleAgentMode != null,
          child: ListTile(
            leading: Icon(
              agentMode ? Icons.smart_toy : Icons.smart_toy_outlined,
            ),
            title: Text(agentMode ? 'Agentモードを終了' : 'Agentモード'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: _ShortcutAction.commandPalette,
          child: ListTile(
            leading: Icon(Icons.terminal_outlined),
            title: Text('コマンドパレット'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: _ShortcutAction.tunnels,
          enabled: supportsTunnels,
          child: const ListTile(
            leading: Icon(Icons.route_outlined),
            title: Text('SSHトンネル'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    ),
  );

  Widget _modifierChip(String label, bool selected, VoidCallback onPressed) =>
      SizedBox(
        width: 64,
        height: 48,
        child: FilterChip(
          label: Center(child: Text(label)),
          selected: selected,
          showCheckmark: false,
          onSelected: session.isConnected ? (_) => onPressed() : null,
          tooltip: '$labelキーを${selected ? '解除' : '次の入力に追加'}',
          visualDensity: VisualDensity.compact,
        ),
      );

  Widget _textKey(
    String text,
    String semanticsLabel,
    TerminalKey key, {
    int? longPressRepeat,
  }) => Semantics(
    label: semanticsLabel,
    button: true,
    child: Tooltip(
      message: longPressRepeat == null ? semanticsLabel : 'タップで補完、長押しで候補一覧',
      child: SizedBox(
        width: 56,
        height: 48,
        child: OutlinedButton(
          onPressed: session.isConnected ? () => onKey(key, 1) : null,
          onLongPress: session.isConnected && longPressRepeat != null
              ? () => onKey(key, longPressRepeat)
              : null,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          child: Text(text),
        ),
      ),
    ),
  );

  Widget _iconKey(IconData icon, String tooltip, TerminalKey key) =>
      _actionButton(
        icon: icon,
        tooltip: tooltip,
        onPressed: session.isConnected ? () => onKey(key, 1) : null,
      );

  Widget _actionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    bool selected = false,
  }) => SizedBox(
    width: 48,
    height: 48,
    child: selected
        ? IconButton.filledTonal(
            tooltip: tooltip,
            onPressed: onPressed,
            icon: Icon(icon, size: 21),
          )
        : IconButton.outlined(
            tooltip: tooltip,
            onPressed: onPressed,
            icon: Icon(icon, size: 21),
          ),
  );
}

enum _ShortcutAction { paste, agent, commandPalette, tunnels }
