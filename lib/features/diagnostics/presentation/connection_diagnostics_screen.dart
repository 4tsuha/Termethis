import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/presentation/expressive_scaffold.dart';
import '../../connections/application/connection_profiles_controller.dart';
import '../../connections/application/connection_tabs_controller.dart';
import '../../connections/domain/connection_profile.dart';
import '../application/connection_diagnostics_controller.dart';
import '../domain/connection_diagnostics.dart';

class ConnectionDiagnosticsScreen extends ConsumerWidget {
  const ConnectionDiagnosticsScreen({required this.profileId, super.key});

  final String profileId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref
        .watch(connectionProfilesProvider)
        .value
        ?.where((item) => item.id == profileId)
        .firstOrNull;
    final diagnostic = ref.watch(connectionDiagnosticProvider(profileId));
    final security = ref.watch(connectionSecurityProvider(profileId));
    return ExpressiveScaffold(
      title: profile?.name ?? '接続診断',
      actions: [
        IconButton(
          tooltip: '再診断',
          onPressed: () =>
              ref.invalidate(connectionDiagnosticProvider(profileId)),
          icon: const Icon(Icons.refresh),
        ),
      ],
      body: profile == null
          ? const _MissingProfile()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                _EndpointCard(profile: profile),
                const SizedBox(height: 12),
                _SecurityCard(value: security),
                const SizedBox(height: 12),
                _DiagnosticCard(value: diagnostic),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: diagnostic.value?.canAttemptConnection == true
                      ? () => _connect(context, ref, profile)
                      : null,
                  icon: const Icon(Icons.login_rounded),
                  label: const Text('接続を開く'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () =>
                      context.push('/connections/${profile.id}/edit'),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('接続設定を編集'),
                ),
              ],
            ),
    );
  }

  Future<void> _connect(
    BuildContext context,
    WidgetRef ref,
    ConnectionProfile profile,
  ) async {
    final tabId = await ref.read(connectionTabsProvider.notifier).open(profile);
    if (!context.mounted) return;
    context.go(
      Uri(path: '/connections', queryParameters: {'tab': tabId}).toString(),
    );
  }
}

class _EndpointCard extends StatelessWidget {
  const _EndpointCard({required this.profile});

  final ConnectionProfile profile;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: ListTile(
      leading: const Icon(Icons.dns_outlined),
      title: Text(profile.target),
      subtitle: Text('方式: ${_protocolName(profile.connectionType)}'),
    ),
  );

  String _protocolName(ConnectionType type) => switch (type) {
    ConnectionType.ssh => 'SSH',
    ConnectionType.mosh => 'Mosh',
    ConnectionType.rdp => 'RDP',
    ConnectionType.vnc => 'VNC',
    ConnectionType.opencode => 'OpenCode',
  };
}

class _SecurityCard extends StatelessWidget {
  const _SecurityCard({required this.value});

  final AsyncValue<ConnectionSecuritySummary> value;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    clipBehavior: Clip.antiAlias,
    child: value.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => const ListTile(
        leading: Icon(Icons.error_outline),
        title: Text('安全性の状態を取得できませんでした'),
      ),
      data: (summary) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ListTile(
            leading: Icon(Icons.shield_outlined),
            title: Text('安全性'),
          ),
          const Divider(height: 1),
          _SecurityItem(title: '通信', value: summary.transport),
          _SecurityItem(title: '接続先の本人確認', value: summary.identityVerification),
          _SecurityItem(title: '認証情報', value: summary.credentialProtection),
          for (final warning in summary.warnings)
            ListTile(
              leading: Icon(
                Icons.warning_amber_rounded,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(warning),
            ),
        ],
      ),
    ),
  );
}

class _SecurityItem extends StatelessWidget {
  const _SecurityItem({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) =>
      ListTile(title: Text(title), subtitle: Text(value));
}

class _DiagnosticCard extends StatelessWidget {
  const _DiagnosticCard({required this.value});

  final AsyncValue<ConnectionDiagnosticReport> value;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    clipBehavior: Clip.antiAlias,
    child: value.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('接続経路を確認しています…'),
          ],
        ),
      ),
      error: (_, _) => const ListTile(
        leading: Icon(Icons.error_outline),
        title: Text('診断を開始できませんでした'),
        subtitle: Text('接続先が存在するか確認して、再診断してください。'),
      ),
      data: (report) => Column(
        children: [
          const ListTile(
            leading: Icon(Icons.monitor_heart_outlined),
            title: Text('接続診断'),
            subtitle: Text('認証は実行せず、到達性と事前条件を確認します。'),
          ),
          const Divider(height: 1),
          for (final item in report.items) _DiagnosticItemTile(item: item),
        ],
      ),
    ),
  );
}

class _DiagnosticItemTile extends StatelessWidget {
  const _DiagnosticItemTile({required this.item});

  final ConnectionDiagnosticItem item;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (item.status) {
      ConnectionDiagnosticStatus.passed => (
        Icons.check_circle_outline,
        Theme.of(context).colorScheme.primary,
      ),
      ConnectionDiagnosticStatus.warning => (
        Icons.warning_amber_rounded,
        Theme.of(context).colorScheme.tertiary,
      ),
      ConnectionDiagnosticStatus.failed => (
        Icons.error_outline,
        Theme.of(context).colorScheme.error,
      ),
      ConnectionDiagnosticStatus.notApplicable => (
        Icons.remove_circle_outline,
        Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    };
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(item.title),
      subtitle: Text([item.message, ?item.action].join('\n')),
      isThreeLine: item.action != null,
    );
  }
}

class _MissingProfile extends StatelessWidget {
  const _MissingProfile();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Text('接続先が削除されているため診断できません。'),
    ),
  );
}
