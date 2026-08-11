import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../application/app_font_controller.dart';
import '../application/terminal_performance_settings_controller.dart';
import '../domain/app_font.dart';
import '../domain/terminal_performance_settings.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final appFont = ref.watch(appFontProvider);
    final performance = ref.watch(terminalPerformanceSettingsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const _SectionHeader('クイック操作'),
          _SettingsCard(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.search),
                title: const Text('検索ボタン'),
                subtitle: const Text('選んだ検索キーをSSH先へ送るボタンをタブバーに表示します。'),
                value: performance.showSearchButton,
                onChanged: ref
                    .read(terminalPerformanceSettingsProvider.notifier)
                    .setShowSearchButton,
              ),
              ListTile(
                leading: const Icon(Icons.keyboard_command_key),
                title: const Text('検索キー'),
                subtitle: Text(_searchModeDescription(performance.searchMode)),
                trailing: DropdownButton<TerminalSearchMode>(
                  value: performance.searchMode,
                  underline: const SizedBox.shrink(),
                  onChanged: (mode) {
                    if (mode != null) {
                      ref
                          .read(terminalPerformanceSettingsProvider.notifier)
                          .selectSearchMode(mode);
                    }
                  },
                  items: [
                    for (final mode in TerminalSearchMode.values)
                      DropdownMenuItem(
                        value: mode,
                        child: Text(_searchModeLabel(mode)),
                      ),
                  ],
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.content_copy_outlined),
                title: const Text('最後の出力をコピー'),
                subtitle: const Text('OSC 133で区切られた直前のコマンド出力をコピーします。'),
                value: performance.showCopyOutputButton,
                onChanged: ref
                    .read(terminalPerformanceSettingsProvider.notifier)
                    .setShowCopyOutputButton,
              ),
              ListTile(
                leading: const Icon(Icons.integration_instructions_outlined),
                title: const Text('シェル統合をセットアップ'),
                subtitle: const Text('確認コマンドをコピーします。リモート設定は変更しません。'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showShellIntegrationHelp(context),
              ),
            ],
          ),
          const _SectionHeader('入力とジェスチャー'),
          _SettingsCard(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.mouse_outlined),
                title: const Text('TUIアプリでのマウス入力'),
                subtitle: const Text('タップをTUIの左クリックとして送ります。文字選択より優先します。'),
                value: performance.mouseInput,
                onChanged: ref
                    .read(terminalPerformanceSettingsProvider.notifier)
                    .setMouseInput,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.touch_app_outlined),
                title: const Text('長押しで右クリック'),
                subtitle: const Text('長押しを右クリックへ変換します。長押しでの文字選択は使えません。'),
                value: performance.longPressRightClick,
                onChanged: performance.mouseInput
                    ? ref
                          .read(terminalPerformanceSettingsProvider.notifier)
                          .setLongPressRightClick
                    : null,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.edit_location_alt_outlined),
                title: const Text('対応プロンプトでタップしてカーソル移動'),
                subtitle: const Text('OSC 133対応の入力行を、タップ位置まで左右キーで移動します。'),
                value: performance.tapToMovePromptCursor,
                onChanged: ref
                    .read(terminalPerformanceSettingsProvider.notifier)
                    .setTapToMovePromptCursor,
              ),
            ],
          ),
          const _SectionHeader('表示と電源'),
          _SettingsCard(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.tab_outlined),
                title: const Text('ターミナルのタブバーを表示'),
                subtitle: const Text('セッション切り替えと検索・コピーを表示します。オフでも接続は保持されます。'),
                value: performance.showSessionTabBar,
                onChanged: ref
                    .read(terminalPerformanceSettingsProvider.notifier)
                    .setShowSessionTabBar,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.light_mode_outlined),
                title: const Text('ターミナルで画面をオンに保つ'),
                subtitle: const Text('ターミナル表示中のスリープを防ぎます。バッテリー消費が増えます。'),
                value: performance.keepScreenAwake,
                onChanged: ref
                    .read(terminalPerformanceSettingsProvider.notifier)
                    .setKeepScreenAwake,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.keyboard_alt_outlined),
                title: const Text('キーボードに合わせて端末をリサイズ'),
                subtitle: const Text('IMEの上に収まる行列数へPTYを調整します。通常はオフ推奨です。'),
                value: performance.resizeForKeyboard,
                onChanged: ref
                    .read(terminalPerformanceSettingsProvider.notifier)
                    .setResizeForKeyboard,
              ),
            ],
          ),
          const _SectionHeader('描画とパフォーマンス'),
          ListTile(
            leading: const Icon(Icons.text_fields),
            title: Text(l10n.settingsTerminalFont),
            subtitle: Text(l10n.settingsTerminalFontValue),
          ),
          ListTile(
            leading: const Icon(Icons.developer_board_outlined),
            title: Text(l10n.settingsTerminalRenderer),
            subtitle: Text(
              _rendererDescription(l10n, performance.rendererMode),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () =>
                _showRendererPicker(context, ref, performance.rendererMode),
          ),
          ListTile(
            leading: const Icon(Icons.translate),
            title: Text(l10n.settingsJapaneseFont),
            subtitle: Text(
              '${_fontLabel(l10n, appFont)}\n${l10n.settingsJapaneseFontMessage}',
            ),
            isThreeLine: true,
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showFontPicker(context, ref, appFont),
          ),
          ListTile(
            leading: const Icon(Icons.speed_outlined),
            title: Text(l10n.settingsRefreshRate),
            subtitle: Text(
              _refreshRateDescription(l10n, performance.refreshRateMode),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showRefreshRatePicker(
              context,
              ref,
              performance.refreshRateMode,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.format_list_numbered),
            title: Text(l10n.settingsScrollbackLines),
            subtitle: Text(
              l10n.settingsScrollbackLinesValue(performance.scrollbackLines),
            ),
            trailing: DropdownButton<int>(
              value: performance.scrollbackLines,
              onChanged: (value) {
                if (value != null) {
                  ref
                      .read(terminalPerformanceSettingsProvider.notifier)
                      .selectScrollbackLines(value);
                }
              },
              items: [
                for (final lines
                    in TerminalPerformanceSettings.supportedScrollbackLines)
                  DropdownMenuItem(value: lines, child: Text('$lines')),
              ],
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_active_outlined),
            title: Text(l10n.settingsBackgroundSession),
            subtitle: Text(l10n.settingsBackgroundSessionDescription),
            value: performance.keepAliveInBackground,
            onChanged: ref
                .read(terminalPerformanceSettingsProvider.notifier)
                .setKeepAliveInBackground,
          ),
          const Divider(indent: 56),
          _SectionHeader(l10n.settingsFtpSection),
          ListTile(
            leading: const Icon(Icons.security_outlined),
            title: Text(l10n.settingsFtpSecurity),
            subtitle: Text(l10n.settingsFtpSecurityMessage),
          ),
          const Divider(indent: 56),
          _SectionHeader(l10n.settingsAboutSection),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(l10n.settingsVersion),
            trailing: Text(l10n.settingsVersionValue),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(l10n.settingsLicenses),
            onTap: () => showLicensePage(
              context: context,
              applicationName: l10n.appTitle,
              applicationVersion: l10n.settingsVersionValue,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showFontPicker(
    BuildContext context,
    WidgetRef ref,
    AppFont selectedFont,
  ) {
    final l10n = AppLocalizations.of(context);
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
            child: Text(
              l10n.settingsSelectFont,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          for (final font in AppFont.values)
            ListTile(
              title: Text(
                _fontLabel(l10n, font),
                style: TextStyle(fontFamily: font.family),
              ),
              subtitle: Text(
                l10n.fontPreview,
                style: TextStyle(fontFamily: font.family),
              ),
              trailing: Icon(
                font == selectedFont
                    ? Icons.check_circle
                    : Icons.circle_outlined,
              ),
              onTap: () {
                ref.read(appFontProvider.notifier).select(font);
                Navigator.pop(context);
              },
            ),
        ],
      ),
    );
  }

  Future<void> _showRefreshRatePicker(
    BuildContext context,
    WidgetRef ref,
    RefreshRateMode selectedMode,
  ) {
    final l10n = AppLocalizations.of(context);
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
            child: Text(
              l10n.settingsSelectRefreshRate,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          for (final mode in RefreshRateMode.values)
            ListTile(
              title: Text(_refreshRateLabel(l10n, mode)),
              subtitle: Text(_refreshRateDescription(l10n, mode)),
              trailing: Icon(
                mode == selectedMode
                    ? Icons.check_circle
                    : Icons.circle_outlined,
              ),
              onTap: () {
                ref
                    .read(terminalPerformanceSettingsProvider.notifier)
                    .selectRefreshRateMode(mode);
                Navigator.pop(context);
              },
            ),
        ],
      ),
    );
  }

  Future<void> _showRendererPicker(
    BuildContext context,
    WidgetRef ref,
    TerminalRendererMode selectedMode,
  ) {
    final l10n = AppLocalizations.of(context);
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
            child: Text(
              l10n.settingsSelectTerminalRenderer,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          for (final mode in TerminalRendererMode.values)
            ListTile(
              title: Text(_rendererLabel(l10n, mode)),
              subtitle: Text(_rendererDescription(l10n, mode)),
              trailing: Icon(
                mode == selectedMode
                    ? Icons.check_circle
                    : Icons.circle_outlined,
              ),
              onTap: () {
                ref
                    .read(terminalPerformanceSettingsProvider.notifier)
                    .selectRendererMode(mode);
                Navigator.pop(context);
              },
            ),
        ],
      ),
    );
  }

  String _fontLabel(AppLocalizations l10n, AppFont font) => switch (font) {
    AppFont.notoSansJp => l10n.fontNotoSansJp,
    AppFont.koruri => l10n.fontKoruri,
    AppFont.mejiro => l10n.fontMejiro,
  };

  String _searchModeLabel(TerminalSearchMode mode) => switch (mode) {
    TerminalSearchMode.shell => '通常のシェル',
    TerminalSearchMode.tmux => 'tmux',
    TerminalSearchMode.zellij => 'Zellij',
    TerminalSearchMode.screen => 'GNU screen',
  };

  String _searchModeDescription(TerminalSearchMode mode) => switch (mode) {
    TerminalSearchMode.shell => 'Ctrl+Rを送信して、コマンド履歴の検索を開始します。',
    TerminalSearchMode.tmux => 'tmuxのコピーモードから前方検索を開始します。',
    TerminalSearchMode.zellij => 'Zellijの検索モードを開きます。',
    TerminalSearchMode.screen => 'GNU screenのコピーモードから検索を開始します。',
  };

  Future<void> _showShellIntegrationHelp(BuildContext context) {
    const markerTest = "printf '\\e]133;A\\aPrompt\\e]133;B\\a'";
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('シェル統合', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            const Text(
              'starship、fish 3.6以降、またはOSC 133対応のbash/zsh設定を使用してください。まず次のコマンドでマーカー表示を確認できます。',
            ),
            const SizedBox(height: 12),
            SelectableText(
              markerTest,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontFamily: 'CascadiaMono'),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(const ClipboardData(text: markerTest));
                if (context.mounted) Navigator.pop(context);
              },
              icon: const Icon(Icons.copy),
              label: const Text('確認コマンドをコピー'),
            ),
          ],
        ),
      ),
    );
  }

  String _rendererLabel(AppLocalizations l10n, TerminalRendererMode mode) =>
      switch (mode) {
        TerminalRendererMode.webgl => l10n.terminalRendererWebgl,
        TerminalRendererMode.flutter => l10n.terminalRendererFlutter,
      };

  String _rendererDescription(
    AppLocalizations l10n,
    TerminalRendererMode mode,
  ) => switch (mode) {
    TerminalRendererMode.webgl => l10n.terminalRendererWebglDescription,
    TerminalRendererMode.flutter => l10n.terminalRendererFlutterDescription,
  };

  String _refreshRateLabel(AppLocalizations l10n, RefreshRateMode mode) =>
      switch (mode) {
        RefreshRateMode.adaptive => l10n.refreshRateAdaptive,
        RefreshRateMode.balanced => l10n.refreshRateBalanced,
        RefreshRateMode.maximum => l10n.refreshRateMaximum,
      };

  String _refreshRateDescription(AppLocalizations l10n, RefreshRateMode mode) =>
      switch (mode) {
        RefreshRateMode.adaptive => l10n.refreshRateAdaptiveDescription,
        RefreshRateMode.balanced => l10n.refreshRateBalancedDescription,
        RefreshRateMode.maximum => l10n.refreshRateMaximumDescription,
      };
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            children[index],
            if (index != children.length - 1)
              const Divider(height: 1, indent: 56),
          ],
        ],
      ),
    );
  }
}
