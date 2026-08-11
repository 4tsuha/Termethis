import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/app_localizations.dart';
import '../application/connection_profiles_controller.dart';
import '../application/private_key_providers.dart';
import '../domain/connection_profile.dart';
import '../domain/credential_vault.dart';
import '../domain/private_key_importer.dart';
import '../../wake_on_lan/domain/wake_on_lan.dart';

class ConnectionEditorScreen extends ConsumerStatefulWidget {
  const ConnectionEditorScreen({
    super.key,
    this.profileId,
    this.connectionType = ConnectionType.ssh,
  });

  final String? profileId;
  final ConnectionType connectionType;

  @override
  ConsumerState<ConnectionEditorScreen> createState() =>
      _ConnectionEditorScreenState();
}

class _ConnectionEditorScreenState
    extends ConsumerState<ConnectionEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _usernameController;
  late final TextEditingController _wakeOnLanMacController;
  late final TextEditingController _wakeOnLanBroadcastController;
  late final TextEditingController _wakeOnLanPortController;
  final TextEditingController _keyPassphraseController =
      TextEditingController();
  ConnectionProfile? _existing;
  late final ConnectionType _connectionType;
  late AuthenticationType _authenticationType;
  ImportedPrivateKey? _selectedPrivateKey;
  bool _saveKeyPassphrase = false;
  late bool _wakeOnLanEnabled;
  bool _saving = false;
  bool _dirty = false;
  bool _confirmingDiscard = false;

  @override
  void initState() {
    super.initState();
    final profiles = ref.read(connectionProfilesProvider).value ?? const [];
    for (final profile in profiles) {
      if (profile.id == widget.profileId) {
        _existing = profile;
        break;
      }
    }
    _connectionType = _existing?.connectionType ?? widget.connectionType;
    _nameController = TextEditingController(text: _existing?.name ?? '');
    _hostController = TextEditingController(text: _existing?.host ?? '');
    _portController = TextEditingController(
      text: (_existing?.port ?? _connectionType.defaultPort).toString(),
    );
    _usernameController = TextEditingController(
      text: _existing?.username ?? '',
    );
    final wakeOnLan = _existing?.wakeOnLan;
    _wakeOnLanMacController = TextEditingController(
      text: wakeOnLan?.macAddress ?? '',
    );
    _wakeOnLanBroadcastController = TextEditingController(
      text: wakeOnLan?.broadcastAddress ?? '255.255.255.255',
    );
    _wakeOnLanPortController = TextEditingController(
      text: (wakeOnLan?.port ?? 9).toString(),
    );
    _wakeOnLanEnabled = wakeOnLan != null;
    _authenticationType =
        _existing?.authenticationType ??
        AuthenticationType.passwordOrInteractive;
    for (final controller in [
      _nameController,
      _hostController,
      _portController,
      _usernameController,
      _wakeOnLanMacController,
      _wakeOnLanBroadcastController,
      _wakeOnLanPortController,
      _keyPassphraseController,
    ]) {
      controller.addListener(_markDirty);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _wakeOnLanMacController.dispose();
    _wakeOnLanBroadcastController.dispose();
    _wakeOnLanPortController.dispose();
    _keyPassphraseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return PopScope<void>(
      canPop: !_dirty && !_saving,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _confirmDiscard();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _existing == null
                ? l10n.addTypedConnection(_connectionTypeLabel(l10n))
                : l10n.edit,
          ),
        ),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _ConnectionTypeSummary(
                  icon: _connectionTypeIcon,
                  label: _connectionTypeLabel(l10n),
                  description: _connectionTypeDescription(l10n),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: l10n.connectionName,
                    hintText: l10n.connectionNameHint,
                    border: const OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (value) => _required(value, l10n),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _hostController,
                  decoration: InputDecoration(
                    labelText: l10n.host,
                    hintText: l10n.hostHint,
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  validator: (value) => _required(value, l10n),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _portController,
                  decoration: InputDecoration(
                    labelText: l10n.port,
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (value) {
                    final port = int.tryParse(value ?? '');
                    if (port == null || port < 1 || port > 65535) {
                      return l10n.invalidPort;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    labelText: _connectionType == ConnectionType.vnc
                        ? l10n.usernameOptional
                        : l10n.username,
                    border: const OutlineInputBorder(),
                  ),
                  textInputAction: _wakeOnLanEnabled
                      ? TextInputAction.next
                      : TextInputAction.done,
                  autocorrect: false,
                  validator: _connectionType == ConnectionType.vnc
                      ? null
                      : (value) => _required(value, l10n),
                  onFieldSubmitted: (_) {
                    if (!_wakeOnLanEnabled) {
                      _save();
                    }
                  },
                ),
                if (_connectionType == ConnectionType.ssh) ...[
                  const SizedBox(height: 16),
                  DropdownButtonFormField<AuthenticationType>(
                    initialValue: _authenticationType,
                    decoration: InputDecoration(
                      labelText: l10n.authentication,
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: AuthenticationType.passwordOrInteractive,
                        child: Text(l10n.passwordAuthentication),
                      ),
                      DropdownMenuItem(
                        value: AuthenticationType.privateKey,
                        child: Text(l10n.privateKeyAuthentication),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _authenticationType = value;
                          _dirty = true;
                        });
                      }
                    },
                  ),
                ] else ...[
                  const SizedBox(height: 16),
                  Card.outlined(
                    child: ListTile(
                      leading: const Icon(Icons.verified_user_outlined),
                      title: Text(l10n.authentication),
                      subtitle: Text(l10n.externalAuthenticationNotice),
                    ),
                  ),
                ],
                if (_connectionType == ConnectionType.ssh &&
                    _authenticationType == AuthenticationType.privateKey) ...[
                  const SizedBox(height: 16),
                  _PrivateKeySection(
                    label:
                        _selectedPrivateKey?.label ??
                        _existing?.privateKeyLabel,
                    hasExistingKey: _existing?.credentialReference != null,
                    isEncrypted: _selectedPrivateKey?.isEncrypted ?? false,
                    passphraseController: _keyPassphraseController,
                    savePassphrase: _saveKeyPassphrase,
                    onSavePassphraseChanged: (value) {
                      setState(() {
                        _saveKeyPassphrase = value;
                        _dirty = true;
                      });
                    },
                    onPick: _pickPrivateKey,
                  ),
                ],
                const SizedBox(height: 16),
                Card.outlined(
                  child: Column(
                    children: [
                      SwitchListTile.adaptive(
                        value: _wakeOnLanEnabled,
                        title: Text(l10n.wakeOnLanTitle),
                        subtitle: Text(l10n.wakeOnLanDescription),
                        secondary: const Icon(Icons.power_settings_new),
                        onChanged: (value) {
                          setState(() {
                            _wakeOnLanEnabled = value;
                            _dirty = true;
                          });
                        },
                      ),
                      if (_wakeOnLanEnabled)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Column(
                            children: [
                              TextFormField(
                                controller: _wakeOnLanMacController,
                                decoration: InputDecoration(
                                  labelText: l10n.wakeOnLanMacAddress,
                                  hintText: l10n.wakeOnLanMacHint,
                                  border: const OutlineInputBorder(),
                                ),
                                textCapitalization:
                                    TextCapitalization.characters,
                                textInputAction: TextInputAction.next,
                                autocorrect: false,
                                validator: (value) {
                                  if (!_wakeOnLanEnabled) {
                                    return null;
                                  }
                                  return WakeOnLanConfiguration.parseMacAddress(
                                            value ?? '',
                                          ) ==
                                          null
                                      ? l10n.invalidMacAddress
                                      : null;
                                },
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _wakeOnLanBroadcastController,
                                decoration: InputDecoration(
                                  labelText: l10n.wakeOnLanBroadcastAddress,
                                  hintText: l10n.wakeOnLanBroadcastHint,
                                  border: const OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.number,
                                textInputAction: TextInputAction.next,
                                autocorrect: false,
                                validator: (value) {
                                  if (!_wakeOnLanEnabled) {
                                    return null;
                                  }
                                  return WakeOnLanConfiguration.isValidIpv4Address(
                                        value ?? '',
                                      )
                                      ? null
                                      : l10n.invalidIpv4Address;
                                },
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _wakeOnLanPortController,
                                decoration: InputDecoration(
                                  labelText: l10n.wakeOnLanPort,
                                  border: const OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.number,
                                textInputAction: TextInputAction.done,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                validator: (value) {
                                  if (!_wakeOnLanEnabled) {
                                    return null;
                                  }
                                  final port = int.tryParse(value ?? '');
                                  return port == null ||
                                          port < 1 ||
                                          port > 65535
                                      ? l10n.invalidPort
                                      : null;
                                },
                                onFieldSubmitted: (_) => _save(),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(l10n.save),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _markDirty() {
    if (mounted && !_dirty) {
      setState(() => _dirty = true);
    }
  }

  Future<void> _confirmDiscard() async {
    if (_saving || !_dirty || _confirmingDiscard) return;
    _confirmingDiscard = true;
    final l10n = AppLocalizations.of(context);
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.discardChangesTitle),
        content: Text(l10n.discardChangesMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.discardChanges),
          ),
        ],
      ),
    );
    _confirmingDiscard = false;
    if (discard != true || !mounted) return;
    setState(() => _dirty = false);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) context.pop();
  }

  Future<void> _pickPrivateKey() async {
    final l10n = AppLocalizations.of(context);
    try {
      final selected = await ref.read(privateKeyImporterProvider).pick();
      if (!mounted || selected == null) {
        return;
      }
      setState(() {
        _selectedPrivateKey = selected;
        _keyPassphraseController.clear();
        _saveKeyPassphrase = false;
        _dirty = true;
      });
    } on PrivateKeyImportFailure catch (error) {
      if (!mounted) {
        return;
      }
      final message = error.code == PrivateKeyImportFailureCode.tooLarge
          ? l10n.privateKeyTooLarge
          : l10n.privateKeyInvalid;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  String? _required(String? value, AppLocalizations l10n) {
    return value == null || value.trim().isEmpty ? l10n.requiredField : null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final l10n = AppLocalizations.of(context);
    final selectedKey = _selectedPrivateKey;
    if (_connectionType == ConnectionType.ssh &&
        _authenticationType == AuthenticationType.privateKey &&
        selectedKey == null &&
        _existing?.credentialReference == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.privateKeyNotSelected)));
      return;
    }

    setState(() => _saving = true);
    try {
      PrivateKeyCredential? replacementCredential;
      if (_connectionType == ConnectionType.ssh &&
          _authenticationType == AuthenticationType.privateKey &&
          selectedKey != null) {
        final passphrase = _keyPassphraseController.text;
        await ref
            .read(privateKeyValidatorProvider)
            .validate(
              selectedKey,
              passphrase: selectedKey.isEncrypted ? passphrase : null,
            );
        replacementCredential = PrivateKeyCredential(
          pem: selectedKey.pem,
          label: selectedKey.label,
          isEncrypted: selectedKey.isEncrypted,
          passphrase: selectedKey.isEncrypted && _saveKeyPassphrase
              ? passphrase
              : null,
        );
      }

      final id =
          _existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString();
      final keepExistingCredential =
          _connectionType == ConnectionType.ssh &&
          _authenticationType == AuthenticationType.privateKey &&
          selectedKey == null;
      final wakeOnLan = _wakeOnLanEnabled
          ? WakeOnLanConfiguration(
              macAddress: WakeOnLanConfiguration.normalizeMacAddress(
                _wakeOnLanMacController.text,
              )!,
              broadcastAddress: _wakeOnLanBroadcastController.text.trim(),
              port: int.parse(_wakeOnLanPortController.text),
            )
          : null;
      await ref
          .read(connectionProfilesProvider.notifier)
          .save(
            ConnectionProfile(
              id: id,
              name: _nameController.text.trim(),
              host: _hostController.text.trim(),
              port: int.parse(_portController.text),
              username: _usernameController.text.trim(),
              connectionType: _connectionType,
              authenticationType: _authenticationType,
              credentialReference: keepExistingCredential
                  ? _existing?.credentialReference
                  : null,
              privateKeyLabel: keepExistingCredential
                  ? _existing?.privateKeyLabel
                  : null,
              wakeOnLan: wakeOnLan,
            ),
            replacementPrivateKey: replacementCredential,
          );
      if (mounted) {
        setState(() => _dirty = false);
        await WidgetsBinding.instance.endOfFrame;
      }
      if (mounted) {
        context.pop();
      }
    } on PrivateKeyImportFailure {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.privateKeyInvalid)));
      }
    } on CredentialVaultFailure {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.privateKeyInvalid)));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  String _connectionTypeLabel(AppLocalizations l10n) =>
      switch (_connectionType) {
        ConnectionType.ssh => l10n.connectionTypeSsh,
        ConnectionType.rdp => l10n.connectionTypeRdp,
        ConnectionType.vnc => l10n.connectionTypeVnc,
      };

  String _connectionTypeDescription(AppLocalizations l10n) =>
      switch (_connectionType) {
        ConnectionType.ssh => l10n.connectionTypeSshDescription,
        ConnectionType.rdp => l10n.connectionTypeRdpDescription,
        ConnectionType.vnc => l10n.connectionTypeVncDescription,
      };

  IconData get _connectionTypeIcon => switch (_connectionType) {
    ConnectionType.ssh => Icons.terminal,
    ConnectionType.rdp => Icons.desktop_windows_outlined,
    ConnectionType.vnc => Icons.monitor_outlined,
  };
}

class _ConnectionTypeSummary extends StatelessWidget {
  const _ConnectionTypeSummary({
    required this.icon,
    required this.label,
    required this.description,
  });

  final IconData icon;
  final String label;
  final String description;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card.filled(
      color: colors.secondaryContainer,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: colors.secondary,
          foregroundColor: colors.onSecondary,
          child: Icon(icon),
        ),
        title: Text(label, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(description),
      ),
    );
  }
}

class _PrivateKeySection extends StatelessWidget {
  const _PrivateKeySection({
    required this.label,
    required this.hasExistingKey,
    required this.isEncrypted,
    required this.passphraseController,
    required this.savePassphrase,
    required this.onSavePassphraseChanged,
    required this.onPick,
  });

  final String? label;
  final bool hasExistingKey;
  final bool isEncrypted;
  final TextEditingController passphraseController;
  final bool savePassphrase;
  final ValueChanged<bool> onSavePassphraseChanged;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (label case final value?) ...[
              Text(l10n.privateKeySelected(value)),
              const SizedBox(height: 12),
            ],
            OutlinedButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.key_outlined),
              label: Text(
                hasExistingKey || label != null
                    ? l10n.replacePrivateKey
                    : l10n.selectPrivateKey,
              ),
            ),
            if (isEncrypted) ...[
              const SizedBox(height: 12),
              TextField(
                controller: passphraseController,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: l10n.keyPassphrase,
                  border: const OutlineInputBorder(),
                ),
              ),
              CheckboxListTile(
                value: savePassphrase,
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.saveKeyPassphrase),
                onChanged: (value) => onSavePassphraseChanged(value ?? false),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
