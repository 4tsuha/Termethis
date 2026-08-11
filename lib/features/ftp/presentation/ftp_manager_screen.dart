import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../shared/utils/normalize_ascii_input.dart';
import '../../connections/application/connection_profiles_controller.dart';
import '../../connections/domain/connection_profile.dart';
import '../../connections/domain/credential_vault.dart';
import '../application/ftp_tabs_controller.dart';
import '../domain/ftp_gateway.dart';
import '../../terminal/domain/ssh_gateway.dart';

enum _EntryAction { rename, delete }

final _ftpDateFormat = DateFormat('yyyy/MM/dd HH:mm', 'ja');

class FtpManagerScreen extends ConsumerStatefulWidget {
  const FtpManagerScreen({super.key});

  @override
  ConsumerState<FtpManagerScreen> createState() => _FtpManagerScreenState();
}

class _FtpManagerScreenState extends ConsumerState<FtpManagerScreen> {
  String? _selectedTabId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tabs = ref.watch(ftpTabsProvider);
    final activeId = tabs.any((tab) => tab.id == _selectedTabId)
        ? _selectedTabId
        : tabs.lastOrNull?.id;
    final activeTab = activeId == null
        ? null
        : tabs.firstWhere((tab) => tab.id == activeId);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.ftpTitle),
        actions: [
          IconButton(
            onPressed: _showConnectionDialog,
            tooltip: l10n.ftpAddTab,
            icon: const Icon(Icons.add_link),
          ),
        ],
      ),
      body: tabs.isEmpty
          ? _EmptyFtpState(onAdd: _showConnectionDialog)
          : Column(
              children: [
                _ConnectionTabs(
                  tabs: tabs,
                  selectedId: activeId!,
                  onSelected: (id) => setState(() => _selectedTabId = id),
                  onClose: (tab) => _confirmCloseTab(context, tab),
                  onAdd: _showConnectionDialog,
                ),
                const Divider(height: 1),
                Expanded(child: _buildTabContent(activeTab!)),
              ],
            ),
    );
  }

  Widget _buildTabContent(FtpTabState tab) {
    final l10n = AppLocalizations.of(context);
    if (tab.status == FtpTabStatus.connecting) {
      return _CenteredStatus(
        icon: Icons.cloud_sync_outlined,
        message: l10n.ftpConnecting,
        showProgress: true,
      );
    }
    if (tab.status == FtpTabStatus.failed) {
      return _CenteredStatus(
        icon: Icons.cloud_off_outlined,
        message: l10n.ftpConnectionFailed,
        action: FilledButton.icon(
          onPressed: () => ref.read(ftpTabsProvider.notifier).retry(tab.id),
          icon: const Icon(Icons.refresh),
          label: Text(l10n.retry),
        ),
      );
    }

    return Column(
      children: [
        if (tab.request.securityMode == FtpSecurityMode.ftp)
          _WarningBanner(message: l10n.ftpPlainWarning),
        if (tab.hasOperationError)
          MaterialBanner(
            leading: const Icon(Icons.error_outline),
            content: Text(l10n.ftpOperationFailed),
            actions: [
              TextButton(
                onPressed: () => ref
                    .read(ftpTabsProvider.notifier)
                    .clearOperationError(tab.id),
                child: Text(MaterialLocalizations.of(context).closeButtonLabel),
              ),
            ],
          ),
        _DirectoryToolbar(
          tab: tab,
          onNavigate: (path) =>
              ref.read(ftpTabsProvider.notifier).goToDirectory(tab.id, path),
          onRefresh: () => ref.read(ftpTabsProvider.notifier).refresh(tab.id),
          onNewFolder: () => _showNewFolderDialog(context, tab),
        ),
        const Divider(height: 1),
        if (tab.isBusy) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: tab.entries.isEmpty && !tab.isBusy
              ? _CenteredStatus(
                  icon: Icons.folder_open_outlined,
                  message: l10n.ftpEmptyDirectory,
                )
              : RefreshIndicator(
                  onRefresh: () =>
                      ref.read(ftpTabsProvider.notifier).refresh(tab.id),
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: tab.entries.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1, indent: 72),
                    itemBuilder: (context, index) =>
                        _buildEntryTile(tab, tab.entries[index]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildEntryTile(FtpTabState tab, FtpEntryInfo entry) {
    final theme = Theme.of(context);
    return ListTile(
      enabled: !tab.isBusy,
      leading: CircleAvatar(
        backgroundColor: entry.isDirectory
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        foregroundColor: entry.isDirectory
            ? theme.colorScheme.onPrimaryContainer
            : theme.colorScheme.onSurfaceVariant,
        child: Icon(
          entry.isDirectory ? Icons.folder : Icons.description_outlined,
        ),
      ),
      title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(_entryMetadata(entry)),
      onTap: entry.isDirectory
          ? () => ref
                .read(ftpTabsProvider.notifier)
                .enterDirectory(tab.id, entry.name)
          : null,
      trailing: PopupMenuButton<_EntryAction>(
        onSelected: (action) => _handleEntryAction(tab, entry, action),
        itemBuilder: (context) {
          final l10n = AppLocalizations.of(context);
          return [
            PopupMenuItem(
              value: _EntryAction.rename,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.drive_file_rename_outline),
                title: Text(l10n.ftpRename),
              ),
            ),
            PopupMenuItem(
              value: _EntryAction.delete,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.delete_outline),
                title: Text(l10n.delete),
              ),
            ),
          ];
        },
      ),
    );
  }

  String _entryMetadata(FtpEntryInfo entry) {
    final l10n = AppLocalizations.of(context);
    final type = entry.isDirectory ? l10n.ftpDirectory : l10n.ftpFile;
    final details = <String>[type];
    if (!entry.isDirectory) details.add(_formatBytes(entry.size));
    if (entry.modifiedAt != null) {
      details.add(_ftpDateFormat.format(entry.modifiedAt!));
    }
    return details.join(' ・ ');
  }

  String _formatBytes(int? bytes) {
    if (bytes == null) return AppLocalizations.of(context).ftpUnknownSize;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Future<void> _showConnectionDialog() async {
    final request = await showModalBottomSheet<FtpConnectRequest>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const _FtpConnectionSheet(),
    );
    if (request == null || !mounted) return;
    var configuredRequest = request.securityMode == FtpSecurityMode.sftp
        ? request.withHostKeyApproval(_approveSftpHostKey)
        : request;
    final profile = request.sshProfile;
    if (request.securityMode == FtpSecurityMode.sftp && profile != null) {
      if (profile.authenticationType == AuthenticationType.privateKey) {
        final reference = profile.credentialReference;
        if (reference == null) return;
        try {
          final credential = await ref
              .read(credentialVaultProvider)
              .readPrivateKey(CredentialHandle(reference));
          if (credential == null || !mounted) return;
          var passphrase = credential.passphrase;
          if (credential.isEncrypted &&
              (passphrase == null || passphrase.isEmpty)) {
            passphrase = await _askSftpKeyPassphrase(credential.label);
            if (passphrase == null) return;
          }
          configuredRequest = configuredRequest.withSshAuthentication(
            SshPrivateKeyAuthentication(
              pem: credential.pem,
              passphrase: passphrase,
            ),
          );
        } on CredentialVaultFailure {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(AppLocalizations.of(context).privateKeyInvalid),
              ),
            );
          }
          return;
        }
      } else {
        configuredRequest = configuredRequest.withSshAuthentication(
          SshPasswordAuthentication(request.password),
        );
      }
    }
    final id = ref.read(ftpTabsProvider.notifier).openTab(configuredRequest);
    setState(() => _selectedTabId = id);
  }

  Future<String?> _askSftpKeyPassphrase(String label) async {
    final controller = TextEditingController();
    final l10n = AppLocalizations.of(context);
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(l10n.keyPassphraseTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          decoration: InputDecoration(
            labelText: l10n.keyPassphraseMessage(label),
          ),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(l10n.connect),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<bool> _approveSftpHostKey(HostKeyInfo info) async {
    if (!mounted) return false;
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
                  Text(l10n.hostKeyAlgorithm),
                  SelectableText(info.algorithm),
                  const SizedBox(height: 12),
                  Text(l10n.hostKeyFingerprint),
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

  Future<void> _showNewFolderDialog(
    BuildContext context,
    FtpTabState tab,
  ) async {
    final name = await _showNameDialog(
      context,
      title: AppLocalizations.of(context).ftpNewFolderTitle,
      label: AppLocalizations.of(context).ftpFolderName,
    );
    if (name != null) {
      await ref.read(ftpTabsProvider.notifier).createDirectory(tab.id, name);
    }
  }

  Future<void> _handleEntryAction(
    FtpTabState tab,
    FtpEntryInfo entry,
    _EntryAction action,
  ) async {
    switch (action) {
      case _EntryAction.rename:
        final name = await _showNameDialog(
          context,
          title: AppLocalizations.of(context).ftpRenameTitle,
          label: AppLocalizations.of(context).ftpNewName,
          initialValue: entry.name,
        );
        if (name != null && name != entry.name) {
          await ref
              .read(ftpTabsProvider.notifier)
              .renameEntry(tab.id, entry.name, name);
        }
      case _EntryAction.delete:
        final l10n = AppLocalizations.of(context);
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n.ftpDeleteTitle),
            content: Text(l10n.ftpDeleteMessage(entry.name)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l10n.delete),
              ),
            ],
          ),
        );
        if (confirmed == true) {
          await ref.read(ftpTabsProvider.notifier).deleteEntry(tab.id, entry);
        }
    }
  }

  Future<String?> _showNameDialog(
    BuildContext context, {
    required String title,
    required String label,
    String initialValue = '',
  }) async {
    final controller = TextEditingController(text: initialValue);
    final formKey = GlobalKey<FormState>();
    final l10n = AppLocalizations.of(context);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(labelText: label),
            validator: (value) => value == null || value.trim().isEmpty
                ? l10n.requiredField
                : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, controller.text.trim());
              }
            },
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _confirmCloseTab(BuildContext context, FtpTabState tab) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.ftpCloseTabTitle),
        content: Text(l10n.ftpCloseTabMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.ftpCloseTab),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(ftpTabsProvider.notifier).closeTab(tab.id);
    }
  }
}

class _ConnectionTabs extends StatelessWidget {
  const _ConnectionTabs({
    required this.tabs,
    required this.selectedId,
    required this.onSelected,
    required this.onClose,
    required this.onAdd,
  });

  final List<FtpTabState> tabs;
  final String selectedId;
  final ValueChanged<String> onSelected;
  final ValueChanged<FtpTabState> onClose;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              itemCount: tabs.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final tab = tabs[index];
                return InputChip(
                  selected: tab.id == selectedId,
                  avatar: Icon(
                    tab.status == FtpTabStatus.failed
                        ? Icons.error_outline
                        : Icons.cloud_outlined,
                    size: 18,
                  ),
                  label: Text(tab.request.tabName),
                  onPressed: () => onSelected(tab.id),
                  onDeleted: () => onClose(tab),
                  deleteButtonTooltipMessage: AppLocalizations.of(
                    context,
                  ).ftpCloseTab,
                );
              },
            ),
          ),
          IconButton(
            onPressed: onAdd,
            tooltip: AppLocalizations.of(context).ftpAddTab,
            icon: const Icon(Icons.add),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _DirectoryToolbar extends StatelessWidget {
  const _DirectoryToolbar({
    required this.tab,
    required this.onNavigate,
    required this.onRefresh,
    required this.onNewFolder,
  });

  final FtpTabState tab;
  final ValueChanged<String> onNavigate;
  final VoidCallback onRefresh;
  final VoidCallback onNewFolder;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(children: _breadcrumbs(context)),
            ),
          ),
          IconButton(
            onPressed: tab.isBusy ? null : onRefresh,
            tooltip: l10n.ftpRefresh,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: tab.isBusy ? null : onNewFolder,
            tooltip: l10n.ftpNewFolder,
            icon: const Icon(Icons.create_new_folder_outlined),
          ),
        ],
      ),
    );
  }

  List<Widget> _breadcrumbs(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final parts = tab.path.split('/').where((part) => part.isNotEmpty).toList();
    final widgets = <Widget>[
      TextButton.icon(
        onPressed: tab.isBusy ? null : () => onNavigate('/'),
        icon: const Icon(Icons.home_outlined, size: 18),
        label: Text(l10n.ftpRoot),
      ),
    ];
    var currentPath = '';
    for (final part in parts) {
      currentPath = '$currentPath/$part';
      final destination = currentPath;
      widgets.add(const Icon(Icons.chevron_right, size: 18));
      widgets.add(
        TextButton(
          onPressed: tab.isBusy ? null : () => onNavigate(destination),
          child: Text(part),
        ),
      );
    }
    return widgets;
  }
}

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: colors.tertiaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.lock_open_outlined, color: colors.onTertiaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: colors.onTertiaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyFtpState extends StatelessWidget {
  const _EmptyFtpState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _CenteredStatus(
      icon: Icons.folder_copy_outlined,
      message: l10n.ftpEmptyTitle,
      supportingMessage: l10n.ftpEmptyMessage,
      action: FilledButton.icon(
        onPressed: onAdd,
        icon: const Icon(Icons.add_link),
        label: Text(l10n.ftpAddTab),
      ),
    );
  }
}

class _CenteredStatus extends StatelessWidget {
  const _CenteredStatus({
    required this.icon,
    required this.message,
    this.supportingMessage,
    this.action,
    this.showProgress = false,
  });

  final IconData icon;
  final String message;
  final String? supportingMessage;
  final Widget? action;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (supportingMessage != null) ...[
              const SizedBox(height: 8),
              Text(supportingMessage!, textAlign: TextAlign.center),
            ],
            if (showProgress) ...[
              const SizedBox(height: 20),
              const CircularProgressIndicator(),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

class _FtpConnectionSheet extends ConsumerStatefulWidget {
  const _FtpConnectionSheet();

  @override
  ConsumerState<_FtpConnectionSheet> createState() =>
      _FtpConnectionSheetState();
}

class _FtpConnectionSheetState extends ConsumerState<_FtpConnectionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _tabName = TextEditingController();
  final _host = TextEditingController();
  final _port = TextEditingController(text: '21');
  final _username = TextEditingController();
  final _password = TextEditingController();
  FtpSecurityMode _securityMode = FtpSecurityMode.ftp;
  ConnectionProfile? _sshProfile;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _tabName.dispose();
    _host.dispose();
    _port.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final profiles = ref.watch(connectionProfilesProvider).value ?? const [];
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        16,
        24,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                l10n.ftpConnectionTitle,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 20),
              if (_securityMode == FtpSecurityMode.sftp) ...[
                DropdownButtonFormField<String>(
                  initialValue: _sshProfile?.id,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: l10n.sftpSavedConnection,
                    prefixIcon: const Icon(Icons.terminal),
                  ),
                  items: [
                    for (final profile in profiles)
                      DropdownMenuItem(
                        value: profile.id,
                        child: Text(
                          profile.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (id) {
                    final profile = profiles.firstWhere(
                      (item) => item.id == id,
                    );
                    setState(() {
                      _sshProfile = profile;
                      _tabName.text = profile.name;
                      _host.text = profile.host;
                      _port.text = profile.port.toString();
                      _username.text = profile.username;
                      _password.clear();
                    });
                  },
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _tabName,
                decoration: InputDecoration(
                  labelText: l10n.ftpTabName,
                  hintText: l10n.ftpTabNameHint,
                  prefixIcon: const Icon(Icons.label_outline),
                ),
                validator: _required,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _host,
                decoration: InputDecoration(
                  labelText: l10n.host,
                  hintText: l10n.hostHint,
                  prefixIcon: const Icon(Icons.dns_outlined),
                ),
                keyboardType: TextInputType.url,
                autocorrect: false,
                validator: _required,
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _port,
                      decoration: InputDecoration(labelText: l10n.port),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        final port = int.tryParse(
                          normalizeFullWidthAscii(value ?? ''),
                        );
                        return port == null || port < 1 || port > 65535
                            ? l10n.invalidPort
                            : null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: DropdownButtonFormField<FtpSecurityMode>(
                      initialValue: _securityMode,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: l10n.ftpSecurity),
                      items: [
                        DropdownMenuItem(
                          value: FtpSecurityMode.ftp,
                          child: Text(
                            l10n.ftpPlain,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: FtpSecurityMode.ftpes,
                          child: Text(
                            l10n.ftpExplicitTls,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: FtpSecurityMode.ftps,
                          child: Text(
                            l10n.ftpImplicitTls,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: FtpSecurityMode.sftp,
                          child: Text(
                            l10n.sftp,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _securityMode = value;
                          if (value != FtpSecurityMode.sftp) {
                            _sshProfile = null;
                          }
                          if ({'21', '22', '990'}.contains(_port.text)) {
                            _port.text = switch (value) {
                              FtpSecurityMode.ftps => '990',
                              FtpSecurityMode.sftp => '22',
                              _ => '21',
                            };
                          }
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _username,
                decoration: InputDecoration(
                  labelText: l10n.username,
                  prefixIcon: const Icon(Icons.person_outline),
                ),
                autocorrect: false,
                validator: _required,
              ),
              const SizedBox(height: 12),
              if (_sshProfile?.authenticationType ==
                  AuthenticationType.privateKey)
                _InlineNotice(
                  icon: Icons.key_outlined,
                  message: l10n.sftpUsesPrivateKey(
                    _sshProfile?.privateKeyLabel ?? '',
                  ),
                )
              else
                TextFormField(
                  controller: _password,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: l10n.password,
                    prefixIcon: const Icon(Icons.password),
                    suffixIcon: IconButton(
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              _InlineNotice(
                icon: _securityMode == FtpSecurityMode.ftp
                    ? Icons.warning_amber_outlined
                    : Icons.lock_outline,
                message: _securityMode == FtpSecurityMode.ftp
                    ? l10n.ftpPlainWarning
                    : _securityMode == FtpSecurityMode.sftp
                    ? l10n.sftpSecurityNotice
                    : l10n.ftpPasswordNotSaved,
              ),
              if (_securityMode == FtpSecurityMode.ftp) ...[
                const SizedBox(height: 8),
                _InlineNotice(
                  icon: Icons.memory_outlined,
                  message: l10n.ftpPasswordNotSaved,
                ),
              ],
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(l10n.cancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.link),
                    label: Text(l10n.connect),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _required(String? value) => value == null || value.trim().isEmpty
      ? AppLocalizations.of(context).requiredField
      : null;

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      FtpConnectRequest(
        tabName: _tabName.text.trim(),
        host: normalizeFullWidthAscii(_host.text).trim(),
        port: int.parse(normalizeFullWidthAscii(_port.text)),
        username: normalizeFullWidthAscii(_username.text).trim(),
        password: _password.text,
        securityMode: _securityMode,
        sshProfile: _sshProfile,
      ),
    );
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 20,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(message, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    );
  }
}

extension<T> on List<T> {
  T? get lastOrNull => isEmpty ? null : last;
}
