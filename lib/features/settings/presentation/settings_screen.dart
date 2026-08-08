import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../application/app_font_controller.dart';
import '../domain/app_font.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final appFont = ref.watch(appFontProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _SectionHeader(l10n.settingsTerminalSection),
          ListTile(
            leading: const Icon(Icons.text_fields),
            title: Text(l10n.settingsTerminalFont),
            subtitle: Text(l10n.settingsTerminalFontValue),
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

  String _fontLabel(AppLocalizations l10n, AppFont font) => switch (font) {
    AppFont.notoSansJp => l10n.fontNotoSansJp,
    AppFont.koruri => l10n.fontKoruri,
    AppFont.mejiro => l10n.fontMejiro,
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
