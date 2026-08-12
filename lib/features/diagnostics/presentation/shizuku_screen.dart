import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/shizuku_diagnostics_controller.dart';
import '../domain/shizuku_diagnostics_gateway.dart';

class ShizukuScreen extends ConsumerWidget {
  const ShizukuScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(shizukuStatusProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shizuku連携'),
        actions: [
          IconButton(
            tooltip: '状態を更新',
            onPressed: () => ref.read(shizukuStatusProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: status.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ShizukuError(
          message: '$error',
          onRetry: () => ref.read(shizukuStatusProvider.notifier).refresh(),
        ),
        data: (value) => _ShizukuBody(status: value),
      ),
    );
  }
}

class _ShizukuBody extends ConsumerWidget {
  const _ShizukuBody({required this.status});

  final ShizukuStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final granted = status.canUsePrivilegedFeatures;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        Card(
          elevation: 0,
          color: granted ? colors.primaryContainer : colors.surfaceContainerLow,
          child: ListTile(
            leading: Icon(
              granted ? Icons.check_circle : Icons.admin_panel_settings,
            ),
            title: Text(_statusTitle(status.permission)),
            subtitle: Text(_statusDescription(status)),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          color: colors.surfaceContainerLow,
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'スマホ単体でADBシェルを操作',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 8),
                Text(
                  'Shizukuが提供するshell権限を使い、PCやUSB接続なしで端末内のコマンドを実行します。Shizuku自体は、Android 11以降のワイヤレスデバッグなどで起動しておく必要があります。',
                ),
                SizedBox(height: 8),
                Text(
                  '現在の接続はパイプ方式です。TTYが必要なncursesアプリ、ジョブ制御、suの一部対話動作には制限があります。',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (status.permission == ShizukuPermissionState.denied)
          FilledButton.icon(
            onPressed: () =>
                ref.read(shizukuStatusProvider.notifier).requestPermission(),
            icon: const Icon(Icons.lock_open_outlined),
            label: const Text('Shizuku権限を許可'),
          ),
        if (granted) ...[
          FilledButton.icon(
            onPressed: () => context.go('/connections'),
            icon: const Icon(Icons.terminal),
            label: const Text('ADBシェルを開く'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => context.push('/settings/logcat'),
            icon: const Icon(Icons.bug_report_outlined),
            label: const Text('Logcatキャプチャを開く'),
          ),
        ],
      ],
    );
  }
}

String _statusTitle(ShizukuPermissionState state) => switch (state) {
  ShizukuPermissionState.unavailable => 'Shizukuが起動していません',
  ShizukuPermissionState.unsupported => 'Shizukuの更新が必要です',
  ShizukuPermissionState.denied => '権限が許可されていません',
  ShizukuPermissionState.deniedPermanently => 'Shizukuアプリで権限を許可してください',
  ShizukuPermissionState.granted => 'Shizukuを利用できます',
};

String _statusDescription(ShizukuStatus status) {
  final uid = switch (status.serverUid) {
    0 => 'root権限',
    2000 => 'ADB shell権限',
    final value? => 'UID $value',
    null => null,
  };
  return switch (status.permission) {
    ShizukuPermissionState.unavailable => 'Shizukuアプリからサービスを起動して、状態を更新してください。',
    ShizukuPermissionState.unsupported => 'UserServiceに対応するShizuku v11以降が必要です。',
    ShizukuPermissionState.denied => '許可後にADBシェルとLogcatをTermethis内で利用できます。',
    ShizukuPermissionState.deniedPermanently =>
      'Termethisから再要求できません。Shizukuアプリの許可一覧を確認してください。',
    ShizukuPermissionState.granted =>
      '${uid ?? '権限を確認済み'} ・ Shizuku ${status.serverVersion ?? '-'}',
  };
}

class _ShizukuError extends StatelessWidget {
  const _ShizukuError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48),
          const SizedBox(height: 12),
          const Text('Shizukuの状態を確認できませんでした'),
          const SizedBox(height: 4),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('再試行'),
          ),
        ],
      ),
    ),
  );
}
