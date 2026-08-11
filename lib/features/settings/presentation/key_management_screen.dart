import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../connections/application/connection_profiles_controller.dart';
import '../../connections/domain/connection_profile.dart';
import '../application/credential_settings_controller.dart';
import '../../terminal/application/session_registry.dart';
import '../../terminal/domain/ssh_gateway.dart';

class KeyManagementScreen extends ConsumerStatefulWidget {
  const KeyManagementScreen({super.key});

  @override
  ConsumerState<KeyManagementScreen> createState() =>
      _KeyManagementScreenState();
}

class _KeyManagementScreenState extends ConsumerState<KeyManagementScreen> {
  late Future<List<KnownHost>> _knownHosts;

  @override
  void initState() {
    super.initState();
    _knownHosts = _loadKnownHosts();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.keyManagementTitle)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const _SectionHeader('保存方針'),
          _KeyCard(
            children: [
              ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: const Text('認証情報はこの端末内に保存'),
                subtitle: Text(
                  ref.watch(credentialSettingsProvider).saveSshPasswords
                      ? 'SSH秘密鍵、保存したパスフレーズとパスワードは暗号化Vaultで保護します。'
                      : 'SSH秘密鍵と保存したパスフレーズは暗号化Vaultで保護します。パスワードは保存しません。',
                ),
              ),
            ],
          ),
          _SectionHeader(l10n.privateKeysTitle),
          _PrivateKeysCard(profiles: ref.watch(connectionProfilesProvider)),
          _SectionHeader(l10n.knownHostsTitle),
          FutureBuilder<List<KnownHost>>(
            future: _knownHosts,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const _LoadingCard();
              }
              if (snapshot.hasError) {
                return _ErrorCard(onRetry: _reloadKnownHosts);
              }
              final hosts = snapshot.data ?? const [];
              if (hosts.isEmpty) {
                return _EmptyCard(
                  icon: Icons.verified_user_outlined,
                  message: l10n.knownHostsEmpty,
                );
              }
              return _KeyCard(
                children: [
                  for (final host in hosts)
                    ListTile(
                      leading: const Icon(Icons.fingerprint),
                      title: Text('${host.info.host}:${host.info.port}'),
                      subtitle: Text(
                        '${host.info.algorithm}\n${host.info.fingerprintSha256}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      isThreeLine: true,
                      trailing: IconButton(
                        tooltip: l10n.delete,
                        onPressed: () => _removeKnownHost(host),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<List<KnownHost>> _loadKnownHosts() =>
      ref.read(hostKeyRepositoryProvider).listAll();

  void _reloadKnownHosts() {
    setState(() => _knownHosts = _loadKnownHosts());
  }

  Future<void> _removeKnownHost(KnownHost host) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.removeKnownHostTitle),
        content: Text(l10n.removeKnownHostMessage),
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
    if (confirmed != true || !mounted) return;
    await ref
        .read(hostKeyRepositoryProvider)
        .remove(host.info.host, host.info.port);
    if (mounted) _reloadKnownHosts();
  }
}

class _PrivateKeysCard extends StatelessWidget {
  const _PrivateKeysCard({required this.profiles});

  final AsyncValue<List<ConnectionProfile>> profiles;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return profiles.when(
      loading: () => const _LoadingCard(),
      error: (_, _) => const _EmptyCard(
        icon: Icons.key_off_outlined,
        message: '秘密鍵を読み込めませんでした。',
      ),
      data: (items) {
        final keyedProfiles = items
            .where(
              (profile) =>
                  profile.authenticationType == AuthenticationType.privateKey &&
                  profile.credentialReference != null,
            )
            .toList(growable: false);
        if (keyedProfiles.isEmpty) {
          return _EmptyCard(
            icon: Icons.key_outlined,
            message: l10n.privateKeysEmpty,
          );
        }
        return _KeyCard(
          children: [
            for (final profile in keyedProfiles)
              ListTile(
                leading: const Icon(Icons.key_outlined),
                title: Text(
                  profile.privateKeyLabel ?? l10n.privateKeyAuthentication,
                ),
                subtitle: Text('${profile.name}\n${profile.target}'),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/connections/${profile.id}/edit'),
              ),
          ],
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 10),
    child: Text(
      label,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _KeyCard extends StatelessWidget {
  const _KeyCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.symmetric(horizontal: 12),
    elevation: 0,
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        for (var index = 0; index < children.length; index++) ...[
          if (index > 0) const Divider(height: 1, indent: 64),
          children[index],
        ],
      ],
    ),
  );
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) => const _KeyCard(
    children: [
      Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
    ],
  );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => _KeyCard(
    children: [
      Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.outline),
            const SizedBox(width: 16),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    ],
  );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _KeyCard(
      children: [
        ListTile(
          leading: const Icon(Icons.error_outline),
          title: Text(l10n.loadConnectionsFailed),
          trailing: TextButton(onPressed: onRetry, child: Text(l10n.retry)),
        ),
      ],
    );
  }
}
