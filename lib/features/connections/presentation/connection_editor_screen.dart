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
import '../../settings/application/credential_settings_controller.dart';

class ConnectionEditorScreen extends ConsumerStatefulWidget {
  const ConnectionEditorScreen({
    super.key,
    this.profileId,
    this.connectionType = ConnectionType.ssh,
    this.allowedConnectionTypes = const {
      ConnectionType.ssh,
      ConnectionType.rdp,
      ConnectionType.vnc,
    },
  });

  final String? profileId;
  final ConnectionType connectionType;
  final Set<ConnectionType> allowedConnectionTypes;

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
  final TextEditingController _passwordController = TextEditingController();
  ConnectionProfile? _existing;
  late ConnectionType _connectionType;
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
      _passwordController,
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
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final saveSshPasswords = ref.watch(
      credentialSettingsProvider.select(
        (settings) => settings.saveSshPasswords,
      ),
    );

    return PopScope<void>(
      canPop: !_dirty && !_saving,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _confirmDiscard();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_existing == null ? l10n.addConnection : l10n.edit),
        ),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_existing == null) ...[
                  _ConnectionTypeSelector(
                    selectedType: _connectionType,
                    allowedTypes: widget.allowedConnectionTypes,
                    onSelected: _selectConnectionType,
                  ),
                  const SizedBox(height: 16),
                ],
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
                      subtitle: Text(
                        _connectionType == ConnectionType.rdp
                            ? l10n.internalRdpAuthenticationNotice
                            : l10n.externalAuthenticationNotice,
                      ),
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
                    hasExistingKey:
                        _existing?.authenticationType ==
                            AuthenticationType.privateKey &&
                        _existing?.credentialReference != null,
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
                ] else if (_connectionType == ConnectionType.ssh &&
                    saveSshPasswords) ...[
                  const SizedBox(height: 16),
                  Card.outlined(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: TextFormField(
                        controller: _passwordController,
                        obscureText: true,
                        enableSuggestions: false,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText:
                              _existing?.authenticationType !=
                                      AuthenticationType
                                          .passwordOrInteractive ||
                                  _existing?.credentialReference == null
                              ? '保存するパスワード'
                              : '新しいパスワード（空欄なら変更しない）',
                          helperText: '設定でパスワード保存が有効です。暗号化Vaultへ保存します。',
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (_existing?.authenticationType ==
                                  AuthenticationType.passwordOrInteractive &&
                              _existing?.credentialReference != null) {
                            return null;
                          }
                          return _required(value, l10n);
                        },
                      ),
                    ),
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
        !(_existing?.authenticationType == AuthenticationType.privateKey &&
            _existing?.credentialReference != null)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.privateKeyNotSelected)));
      return;
    }

    setState(() => _saving = true);
    try {
      PrivateKeyCredential? replacementCredential;
      PasswordCredential? replacementPassword;
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
      if (_connectionType == ConnectionType.ssh &&
          _authenticationType == AuthenticationType.passwordOrInteractive &&
          ref.read(credentialSettingsProvider).saveSshPasswords &&
          _passwordController.text.isNotEmpty) {
        replacementPassword = PasswordCredential(_passwordController.text);
      }

      final id =
          _existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString();
      final keepExistingCredential =
          _connectionType == ConnectionType.ssh &&
          ((_authenticationType == AuthenticationType.privateKey &&
                  selectedKey == null &&
                  _existing?.authenticationType ==
                      AuthenticationType.privateKey) ||
              (_authenticationType ==
                      AuthenticationType.passwordOrInteractive &&
                  ref.read(credentialSettingsProvider).saveSshPasswords &&
                  _passwordController.text.isEmpty &&
                  _existing?.authenticationType ==
                      AuthenticationType.passwordOrInteractive));
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
            replacementPassword: replacementPassword,
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

  void _selectConnectionType(ConnectionType type) {
    if (type == _connectionType) return;
    final previousDefaultPort = _connectionType.defaultPort.toString();
    setState(() {
      _connectionType = type;
      if (_portController.text.isEmpty ||
          _portController.text == previousDefaultPort) {
        _portController.text = type.defaultPort.toString();
      }
      _dirty = true;
    });
  }
}

class _ConnectionTypeSelector extends StatelessWidget {
  const _ConnectionTypeSelector({
    required this.selectedType,
    required this.allowedTypes,
    required this.onSelected,
  });

  final ConnectionType selectedType;
  final Set<ConnectionType> allowedTypes;
  final ValueChanged<ConnectionType> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.connectionMethod,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        for (final type in ConnectionType.values) ...[
          if (allowedTypes.contains(type))
            _ConnectionTypeChoice(
              title: switch (type) {
                ConnectionType.ssh => l10n.connectionTypeSsh,
                ConnectionType.rdp => l10n.connectionTypeRdp,
                ConnectionType.vnc => l10n.connectionTypeVnc,
              },
              description: switch (type) {
                ConnectionType.ssh => l10n.connectionTypeSshCompactDescription,
                ConnectionType.rdp => l10n.connectionTypeRdpCompactDescription,
                ConnectionType.vnc => l10n.connectionTypeVncCompactDescription,
              },
              selected: type == selectedType,
              onTap: () => onSelected(type),
            ),
          if (allowedTypes.contains(type) &&
              type != ConnectionType.values.lastWhere(allowedTypes.contains))
            const SizedBox(height: 6),
        ],
      ],
    );
  }
}

class _ConnectionTypeChoice extends StatelessWidget {
  const _ConnectionTypeChoice({
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: '$title $description',
      child: Material(
        color: selected ? colors.primaryContainer : colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Row(
              children: [
                const SizedBox(width: 16),
                SizedBox(
                  width: 44,
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: selected
                          ? colors.onPrimaryContainer
                          : colors.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: selected
                          ? colors.onPrimaryContainer
                          : colors.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 24,
                  child: selected
                      ? Icon(
                          Icons.check,
                          size: 20,
                          color: colors.onPrimaryContainer,
                        )
                      : null,
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
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
