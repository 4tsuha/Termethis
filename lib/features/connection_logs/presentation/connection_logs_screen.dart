import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/connection_logs_controller.dart';
import '../domain/connection_log_entry.dart';
import '../../../shared/presentation/expressive_scaffold.dart';

class ConnectionLogsScreen extends ConsumerWidget {
  const ConnectionLogsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(connectionLogsProvider);
    return ExpressiveScaffold(
      title: '接続ログ',
      actions: [
        IconButton(
          tooltip: 'すべて削除',
          onPressed: logs.value?.isNotEmpty == true
              ? () => _confirmClear(context, ref)
              : null,
          icon: const Icon(Icons.delete_sweep_outlined),
        ),
      ],
      body: logs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            _ErrorView(onRetry: () => ref.invalidate(connectionLogsProvider)),
        data: (entries) => entries.isEmpty
            ? const _EmptyView()
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                itemCount: entries.length + 1,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  if (index == 0) return const _PrivacyNotice();
                  return _ConnectionLogCard(entry: entries[index - 1]);
                },
              ),
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('接続ログを削除しますか？'),
        content: const Text('保存されている接続状態の履歴をすべて削除します。接続先の設定には影響しません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(connectionLogsProvider.notifier).clear();
    }
  }
}

class _PrivacyNotice extends StatelessWidget {
  const _PrivacyNotice();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: const ListTile(
        leading: Icon(Icons.shield_outlined),
        title: Text('最大200件を端末内に保存'),
        subtitle: Text('パスワード、秘密鍵、入力したコマンド、ターミナル出力は記録しません。'),
      ),
    );
  }
}

class _ConnectionLogCard extends StatelessWidget {
  const _ConnectionLogCard({required this.entry});

  final ConnectionLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final presentation = _statePresentation(entry.state);
    final colors = Theme.of(context).colorScheme;
    final color = presentation.isError ? colors.error : colors.primary;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          foregroundColor: color,
          child: Icon(presentation.icon, size: 20),
        ),
        title: Text(
          entry.profileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${entry.target}\n${presentation.label}${_failureSuffix(entry)} ・ ${_formatTimestamp(entry.timestamp)}',
        ),
        isThreeLine: true,
      ),
    );
  }
}

({String label, IconData icon, bool isError}) _statePresentation(
  ConnectionLogState state,
) => switch (state) {
  ConnectionLogState.idle => (
    label: '待機',
    icon: Icons.pause_circle_outline,
    isError: false,
  ),
  ConnectionLogState.connecting => (
    label: '接続を開始',
    icon: Icons.sync,
    isError: false,
  ),
  ConnectionLogState.verifyingHost => (
    label: 'ホスト鍵を確認',
    icon: Icons.verified_user_outlined,
    isError: false,
  ),
  ConnectionLogState.authenticating => (
    label: '認証中',
    icon: Icons.key_outlined,
    isError: false,
  ),
  ConnectionLogState.openingPty => (
    label: 'PTYを開始',
    icon: Icons.terminal,
    isError: false,
  ),
  ConnectionLogState.connected => (
    label: '接続済み',
    icon: Icons.link,
    isError: false,
  ),
  ConnectionLogState.reconnectPrompt => (
    label: '再接続待ち',
    icon: Icons.replay,
    isError: true,
  ),
  ConnectionLogState.closing => (
    label: '切断中',
    icon: Icons.link_off,
    isError: false,
  ),
  ConnectionLogState.closed => (
    label: '切断済み',
    icon: Icons.check_circle_outline,
    isError: false,
  ),
  ConnectionLogState.failed => (
    label: '接続失敗',
    icon: Icons.error_outline,
    isError: true,
  ),
};

String _failureSuffix(ConnectionLogEntry entry) {
  final failure = entry.failureCode;
  return failure == null ? '' : '（${failure.name}）';
}

String _formatTimestamp(DateTime value) {
  final local = value.toLocal();
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${local.year}/${twoDigits(local.month)}/${twoDigits(local.day)} '
      '${twoDigits(local.hour)}:${twoDigits(local.minute)}:${twoDigits(local.second)}';
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history_outlined, size: 48),
          SizedBox(height: 12),
          Text('接続ログはまだありません'),
          SizedBox(height: 4),
          Text('SSH接続の状態変化がここに表示されます。'),
        ],
      ),
    ),
  );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: FilledButton.icon(
      onPressed: onRetry,
      icon: const Icon(Icons.refresh),
      label: const Text('読み込み直す'),
    ),
  );
}
