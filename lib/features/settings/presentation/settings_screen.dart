import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
        ],
      ),
    );
  }
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
