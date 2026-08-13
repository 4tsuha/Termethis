import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/app_localizations.dart';
import '../application/connection_profiles_controller.dart';
import '../application/private_key_providers.dart';
import '../application/ssh_routes_controller.dart';
import '../domain/connection_profile.dart';
import '../domain/credential_vault.dart';
import '../domain/private_key_importer.dart';
import '../domain/ssh_route_configuration.dart';
import '../../wake_on_lan/domain/wake_on_lan.dart';
import '../../settings/application/credential_settings_controller.dart';

class ConnectionEditorScreen extends ConsumerStatefulWidget {
  const ConnectionEditorScreen({
    super.key,
    this.profileId,
    this.connectionType = ConnectionType.ssh,
    this.compactPresentation = false,
    this.allowedConnectionTypes = const {
      ConnectionType.ssh,
      ConnectionType.mosh,
      ConnectionType.rdp,
      ConnectionType.vnc,
      ConnectionType.opencode,
    },
  });

  final String? profileId;
  final ConnectionType connectionType;
  final bool compactPresentation;
  final Set<ConnectionType> allowedConnectionTypes;

  @override
  ConsumerState<ConnectionEditorScreen> createState() =>
      _ConnectionEditorScreenState();
}

Future<void> showNewConnectionEditor(
  BuildContext context, {
  ConnectionType connectionType = ConnectionType.ssh,
  Set<ConnectionType> allowedConnectionTypes = const {
    ConnectionType.ssh,
    ConnectionType.mosh,
    ConnectionType.rdp,
    ConnectionType.vnc,
    ConnectionType.opencode,
  },
}) {
  final size = MediaQuery.sizeOf(context);
  if (size.width >= 600) {
    return showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (context) => Dialog(
        key: const ValueKey('new-connection-dialog'),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 640,
            maxHeight: size.height * 0.88,
          ),
          child: ConnectionEditorScreen(
            connectionType: connectionType,
            allowedConnectionTypes: allowedConnectionTypes,
            compactPresentation: true,
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    constraints: BoxConstraints(maxHeight: size.height * 0.84),
    builder: (context) => KeyedSubtree(
      key: const ValueKey('new-connection-sheet'),
      child: ConnectionEditorScreen(
        connectionType: connectionType,
        allowedConnectionTypes: allowedConnectionTypes,
        compactPresentation: true,
      ),
    ),
  );
}

class _ConnectionEditorScreenState
    extends ConsumerState<ConnectionEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _usernameController;
  late final TextEditingController _remotePathController;
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
  List<String> _jumpProfileIds = const [];

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
      text:
          _existing?.username ??
          (_connectionType == ConnectionType.opencode ? 'opencode' : ''),
    );
    _remotePathController = TextEditingController(
      text: _existing?.remotePath ?? '',
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
    _jumpProfileIds = const [];
    for (final controller in [
      _nameController,
      _hostController,
      _portController,
      _usernameController,
      _remotePathController,
      _wakeOnLanMacController,
      _wakeOnLanBroadcastController,
      _wakeOnLanPortController,
      _keyPassphraseController,
      _passwordController,
    ]) {
      controller.addListener(_markDirty);
    }
    if (widget.profileId case final profileId?) {
      _loadRoute(profileId);
    }
  }

  Future<void> _loadRoute(String profileId) async {
    final routes = await ref.read(sshRoutesProvider.future);
    if (!mounted || _dirty) return;
    final route = routes
        .where((route) => route.profileId == profileId)
        .firstOrNull;
    if (route == null) return;
    setState(() => _jumpProfileIds = route.jumpProfileIds);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _remotePathController.dispose();
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
          automaticallyImplyLeading: !widget.compactPresentation,
          leading: widget.compactPresentation
              ? IconButton(
                  tooltip: l10n.close,
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.close),
                )
              : null,
          actions: widget.compactPresentation
              ? [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilledButton.tonal(
                      onPressed: _saving ? null : _save,
                      child: Text(l10n.save),
                    ),
                  ),
                ]
              : null,
        ),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  key: const ValueKey('connection-editor-scroll'),
                  padding: EdgeInsets.fromLTRB(
                    16,
                    widget.compactPresentation ? 4 : 16,
                    16,
                    widget.compactPresentation ? 16 : 24,
                  ),
                  children: [
                    if (_existing == null) ...[
                      _ConnectionTypeSelector(
                        selectedType: _connectionType,
                        allowedTypes: widget.allowedConnectionTypes,
                        onSelected: _selectConnectionType,
                      ),
                      SizedBox(height: widget.compactPresentation ? 12 : 16),
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
                    SizedBox(height: widget.compactPresentation ? 12 : 16),
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
                    SizedBox(height: widget.compactPresentation ? 12 : 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildPortField(l10n)),
                        const SizedBox(width: 12),
                        Expanded(child: _buildUsernameField(l10n)),
                      ],
                    ),
                    if (_connectionType == ConnectionType.opencode) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _remotePathController,
                        decoration: const InputDecoration(
                          labelText: 'プロジェクトのパス（任意）',
                          hintText: '/home/user/project',
                          border: OutlineInputBorder(),
                        ),
                        autocorrect: false,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: true,
                        enableSuggestions: false,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: 'OpenCode Serveのパスワード（任意）',
                          helperText: saveSshPasswords
                              ? '保存したパスワードを暗号化Vaultで保護します。'
                              : 'パスワードは保存せず、次回の接続時に入力します。',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ],
                    if (_connectionType.usesSshAuthentication) ...[
                      const SizedBox(height: 16),
                      DropdownButtonFormField<AuthenticationType>(
                        initialValue: _authenticationType,
                        isExpanded: true,
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
                    ] else if (_connectionType != ConnectionType.opencode) ...[
                      const SizedBox(height: 16),
                      Card.outlined(
                        child: ListTile(
                          leading: const Icon(Icons.verified_user_outlined),
                          title: Text(l10n.authentication),
                          subtitle: Text(
                            _connectionType == ConnectionType.rdp
                                ? l10n.internalRdpAuthenticationNotice
                                : _connectionType == ConnectionType.vnc
                                ? 'VNC認証は接続開始時にアプリ内で行います。パスワードは接続中だけ保持します。'
                                : l10n.externalAuthenticationNotice,
                          ),
                        ),
                      ),
                    ],
                    if (_connectionType.usesSshAuthentication &&
                        _authenticationType ==
                            AuthenticationType.privateKey) ...[
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
                    ] else if (_connectionType.usesSshAuthentication &&
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
                                      AuthenticationType
                                          .passwordOrInteractive &&
                                  _existing?.credentialReference != null) {
                                return null;
                              }
                              return _required(value, l10n);
                            },
                          ),
                        ),
                      ),
                    ],
                    if (_connectionType.usesSshAuthentication) ...[
                      const SizedBox(height: 16),
                      Card.outlined(
                        child: ListTile(
                          leading: const Icon(Icons.route_outlined),
                          title: const Text('踏み台'),
                          subtitle: Text(
                            _jumpProfileIds.isEmpty
                                ? '直接接続'
                                : '${_jumpProfileIds.length}段のProxyJump',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _selectJumpHosts,
                        ),
                      ),
                    ],
                    if (_connectionType != ConnectionType.opencode) ...[
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
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  16,
                                ),
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
                                        labelText:
                                            l10n.wakeOnLanBroadcastAddress,
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
                    ],
                    if (!widget.compactPresentation) ...[
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: const Icon(Icons.save_outlined),
                        label: Text(l10n.save),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPortField(AppLocalizations l10n) => TextFormField(
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
      if (port == null || port < 1 || port > 65535) return l10n.invalidPort;
      return null;
    },
  );

  Widget _buildUsernameField(AppLocalizations l10n) => TextFormField(
    controller: _usernameController,
    decoration: InputDecoration(
      labelText: _connectionType == ConnectionType.vnc
          ? l10n.usernameOptional
          : _connectionType == ConnectionType.opencode
          ? 'ユーザー名'
          : l10n.username,
      border: const OutlineInputBorder(),
    ),
    textInputAction: _wakeOnLanEnabled
        ? TextInputAction.next
        : TextInputAction.done,
    autocorrect: false,
    validator:
        _connectionType == ConnectionType.vnc ||
            _connectionType == ConnectionType.opencode
        ? null
        : (value) => _required(value, l10n),
    onFieldSubmitted: (_) {
      if (!_wakeOnLanEnabled) _save();
    },
  );

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
    if (_connectionType.usesSshAuthentication &&
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
      if (_connectionType.usesSshAuthentication &&
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
      if (_connectionType == ConnectionType.opencode &&
          ref.read(credentialSettingsProvider).saveSshPasswords &&
          _passwordController.text.isNotEmpty) {
        replacementPassword = PasswordCredential(_passwordController.text);
      }
      if (_connectionType.usesSshAuthentication &&
          _authenticationType == AuthenticationType.passwordOrInteractive &&
          ref.read(credentialSettingsProvider).saveSshPasswords &&
          _passwordController.text.isNotEmpty) {
        replacementPassword = PasswordCredential(_passwordController.text);
      }

      final id =
          _existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString();
      final keepExistingCredential =
          (_connectionType == ConnectionType.opencode &&
              ref.read(credentialSettingsProvider).saveSshPasswords &&
              _passwordController.text.isEmpty &&
              _existing?.connectionType == ConnectionType.opencode &&
              _existing?.credentialReference != null) ||
          (_connectionType.usesSshAuthentication &&
              _existing?.connectionType.usesSshAuthentication == true &&
              ((_authenticationType == AuthenticationType.privateKey &&
                      selectedKey == null &&
                      _existing?.authenticationType ==
                          AuthenticationType.privateKey) ||
                  (_authenticationType ==
                          AuthenticationType.passwordOrInteractive &&
                      ref.read(credentialSettingsProvider).saveSshPasswords &&
                      _passwordController.text.isEmpty &&
                      _existing?.authenticationType ==
                          AuthenticationType.passwordOrInteractive)));
      final wakeOnLan =
          _connectionType != ConnectionType.opencode && _wakeOnLanEnabled
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
              remotePath: _connectionType == ConnectionType.opencode
                  ? _remotePathController.text.trim().nullIfEmpty
                  : null,
            ),
            replacementPrivateKey: replacementCredential,
            replacementPassword: replacementPassword,
          );
      await ref
          .read(sshRoutesProvider.notifier)
          .saveRoute(
            SshRouteConfiguration(
              profileId: id,
              jumpProfileIds: _jumpProfileIds,
            ),
          );
      if (mounted) {
        setState(() => _dirty = false);
        await WidgetsBinding.instance.endOfFrame;
      }
      if (mounted) {
        context.pop();
      }
    } on SshRouteCycleException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('踏み台の接続経路が循環しています。経路を見直してください。')),
        );
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

  Future<void> _selectJumpHosts() async {
    final profiles = await ref.read(connectionProfilesProvider.future);
    if (!mounted) return;
    final selected = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _JumpHostPicker(
        profiles: profiles
            .where(
              (profile) =>
                  profile.id != widget.profileId &&
                  profile.connectionType.usesSshAuthentication,
            )
            .toList(growable: false),
        selectedIds: _jumpProfileIds,
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _jumpProfileIds = selected;
      _dirty = true;
    });
  }

  void _selectConnectionType(ConnectionType type) {
    if (type == _connectionType) return;
    final previousDefaultPort = _connectionType.defaultPort.toString();
    setState(() {
      _connectionType = type;
      if (type == ConnectionType.opencode && _usernameController.text.isEmpty) {
        _usernameController.text = 'opencode';
      }
      if (_portController.text.isEmpty ||
          _portController.text == previousDefaultPort) {
        _portController.text = type.defaultPort.toString();
      }
      _dirty = true;
    });
  }
}

class _JumpHostPicker extends StatefulWidget {
  const _JumpHostPicker({required this.profiles, required this.selectedIds});

  final List<ConnectionProfile> profiles;
  final List<String> selectedIds;

  @override
  State<_JumpHostPicker> createState() => _JumpHostPickerState();
}

class _JumpHostPickerState extends State<_JumpHostPicker> {
  late final List<String> _selected = List.of(widget.selectedIds);

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.68,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '踏み台を選択',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, _selected),
                  child: const Text('完了'),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text('上から順に接続します。長押しして順序を変更できます。'),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ReorderableListView(
              buildDefaultDragHandles: false,
              onReorderItem: (oldIndex, newIndex) {
                setState(() {
                  final id = _selected.removeAt(oldIndex);
                  _selected.insert(newIndex, id);
                });
              },
              children: [
                for (var index = 0; index < _selected.length; index++)
                  if (widget.profiles
                          .where((profile) => profile.id == _selected[index])
                          .firstOrNull
                      case final profile?)
                    ReorderableDragStartListener(
                      key: ValueKey(profile.id),
                      index: index,
                      child: ListTile(
                        leading: CircleAvatar(child: Text('${index + 1}')),
                        title: Text(profile.name),
                        subtitle: Text(profile.target),
                        trailing: IconButton(
                          tooltip: '踏み台から削除',
                          onPressed: () =>
                              setState(() => _selected.remove(profile.id)),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                      ),
                    ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: '踏み台を追加',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final profile in widget.profiles)
                  if (!_selected.contains(profile.id))
                    DropdownMenuItem(
                      value: profile.id,
                      child: Text(profile.name),
                    ),
              ],
              onChanged: (id) {
                if (id != null) setState(() => _selected.add(id));
              },
            ),
          ),
        ],
      ),
    ),
  );
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
    final types = ConnectionType.values
        .where(allowedTypes.contains)
        .toList(growable: false);
    return DropdownButtonFormField<ConnectionType>(
      key: ValueKey('connection-type-selector-${selectedType.name}'),
      initialValue: selectedType,
      isExpanded: true,
      menuMaxHeight: 288,
      itemHeight: 48,
      decoration: InputDecoration(
        labelText: l10n.connectionMethod,
        prefixIcon: Icon(_connectionTypeIcon(selectedType)),
        border: const OutlineInputBorder(),
      ),
      selectedItemBuilder: (context) => [
        for (final type in types)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _connectionTypeLabel(l10n, type),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      items: [
        for (final type in types)
          DropdownMenuItem(
            key: ValueKey('connection-type-${type.name}'),
            value: type,
            child: Row(
              children: [
                Text(_connectionTypeLabel(l10n, type)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _connectionTypeDescription(l10n, type),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
      onChanged: (type) {
        if (type != null) onSelected(type);
      },
    );
  }
}

String _connectionTypeLabel(AppLocalizations l10n, ConnectionType type) =>
    switch (type) {
      ConnectionType.ssh => l10n.connectionTypeSsh,
      ConnectionType.mosh => 'Mosh',
      ConnectionType.rdp => l10n.connectionTypeRdp,
      ConnectionType.vnc => l10n.connectionTypeVnc,
      ConnectionType.opencode => 'OpenCode',
    };

String _connectionTypeDescription(AppLocalizations l10n, ConnectionType type) =>
    switch (type) {
      ConnectionType.ssh => l10n.connectionTypeSshCompactDescription,
      ConnectionType.mosh => 'モバイルシェル',
      ConnectionType.rdp => l10n.connectionTypeRdpCompactDescription,
      ConnectionType.vnc => l10n.connectionTypeVncCompactDescription,
      ConnectionType.opencode => 'AIコーディング',
    };

IconData _connectionTypeIcon(ConnectionType type) => switch (type) {
  ConnectionType.ssh => Icons.terminal,
  ConnectionType.mosh => Icons.swap_horiz,
  ConnectionType.rdp => Icons.desktop_windows_outlined,
  ConnectionType.vnc => Icons.monitor_outlined,
  ConnectionType.opencode => Icons.code_rounded,
};

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
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
