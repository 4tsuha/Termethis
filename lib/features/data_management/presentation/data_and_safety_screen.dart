import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../infrastructure/ftp/android_sftp_file_transfer_gateway.dart';
import '../../../shared/presentation/expressive_scaffold.dart';
import '../../diagnostics/application/diagnostic_export_controller.dart';
import '../application/app_backup_controller.dart';
import '../domain/app_backup.dart';

class DataAndSafetyScreen extends ConsumerStatefulWidget {
  const DataAndSafetyScreen({super.key});

  @override
  ConsumerState<DataAndSafetyScreen> createState() =>
      _DataAndSafetyScreenState();
}

class _DataAndSafetyScreenState extends ConsumerState<DataAndSafetyScreen> {
  static const _documents = AndroidSftpFileTransferGateway();
  static const _maximumBackupBytes = 10 * 1024 * 1024;
  bool _busy = false;

  @override
  Widget build(BuildContext context) => ExpressiveScaffold(
    title: 'データと安全性',
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        _SectionCard(
          icon: Icons.settings_backup_restore,
          title: 'バックアップと復元',
          description: '接続先、既知のホスト鍵、タブ、スニペット、表示設定をJSONで移行します。',
          children: [
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('バックアップを書き出す'),
              subtitle: const Text('秘密鍵、パスワード、パスフレーズは含みません。'),
              trailing: const Icon(Icons.chevron_right),
              enabled: !_busy,
              onTap: _exportBackup,
            ),
            ListTile(
              leading: const Icon(Icons.restore_page_outlined),
              title: const Text('バックアップから復元'),
              subtitle: const Text('内容を確認してから既存データへ反映します。'),
              trailing: const Icon(Icons.chevron_right),
              enabled: !_busy,
              onTap: _importBackup,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _SectionCard(
          icon: Icons.health_and_safety_outlined,
          title: '診断情報',
          description: '問題の調査に使える情報を、資格情報と接続先名を除外して書き出します。',
          children: [
            ListTile(
              leading: const Icon(Icons.file_download_outlined),
              title: const Text('安全な診断情報を書き出す'),
              subtitle: const Text('内容と接続ログの有無を選んでから保存します。'),
              trailing: const Icon(Icons.chevron_right),
              enabled: !_busy,
              onTap: _exportDiagnostics,
            ),
          ],
        ),
        if (_busy) ...[
          const SizedBox(height: 20),
          const LinearProgressIndicator(),
        ],
      ],
    ),
  );

  Future<void> _exportBackup() async {
    await _run(() async {
      final json = await ref.read(appBackupControllerProvider).create();
      final now = DateTime.now();
      final fileName =
          'termethis-backup-${now.year.toString().padLeft(4, '0')}'
          '${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}.json';
      final saved = await _exportText(json, fileName);
      if (mounted && saved) _showMessage('バックアップを保存しました。');
    });
  }

  Future<void> _importBackup() async {
    await _run(() async {
      final files = await _documents.pickFiles();
      if (files.isEmpty) return;
      final selected = files.first;
      final roots = files.map((item) => File(item.path).parent).toSet();
      try {
        final file = File(selected.path);
        if (await file.length() > _maximumBackupBytes) {
          throw const FormatException('バックアップファイルが10MBを超えています。');
        }
        final encoded = await file.readAsString();
        final preview = await ref
            .read(appBackupControllerProvider)
            .preview(encoded);
        if (!mounted || !await _confirmRestore(preview)) return;
        await ref.read(appBackupControllerProvider).restore(preview);
        if (mounted) {
          _showMessage('バックアップを復元しました。');
        }
      } finally {
        for (final root in roots) {
          if (await root.exists()) await root.delete(recursive: true);
        }
      }
    });
  }

  Future<void> _exportDiagnostics() async {
    final includeLogs = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => const _DiagnosticExportSheet(),
    );
    if (includeLogs == null) return;
    await _run(() async {
      final json = await ref
          .read(diagnosticExportControllerProvider)
          .create(includeConnectionLogs: includeLogs);
      final saved = await _exportText(
        json,
        'termethis-diagnostics-${DateTime.now().millisecondsSinceEpoch}.json',
      );
      if (mounted && saved) _showMessage('診断情報を保存しました。');
    });
  }

  Future<bool> _exportText(String contents, String fileName) async {
    final temporary = await getTemporaryDirectory();
    final directory = await Directory(
      p.join(
        temporary.path,
        'document_export',
        DateTime.now().microsecondsSinceEpoch.toString(),
      ),
    ).create(recursive: true);
    final file = File(p.join(directory.path, fileName));
    try {
      await file.writeAsString(contents, flush: true);
      return await _documents.exportFile(
        localPath: file.path,
        fileName: fileName,
        mimeType: 'application/json',
      );
    } finally {
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  }

  Future<bool> _confirmRestore(AppBackupPreview preview) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.restore),
          title: const Text('バックアップを復元'),
          content: Text(
            '接続先: 新規 ${preview.newProfiles}件 / 更新 ${preview.updatedProfiles}件\n'
            'タブ: ${preview.backup.tabs.length - preview.skippedTabs}件\n'
            '信頼済みホスト鍵: ${preview.backup.knownHosts.length}件\n'
            '再入力が必要な認証情報: ${preview.credentialsToReenter}件\n\n'
            '秘密鍵とパスワードは復元されません。ホスト鍵は接続先の本人確認に使う信頼情報です。出所を確認したバックアップだけを復元してください。既存の同じIDの接続先と設定は上書きされます。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('復元'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await operation();
    } on FormatException catch (error) {
      if (mounted) {
        _showMessage(error.message, error: true);
      }
    } catch (_) {
      if (mounted) {
        _showMessage('処理を完了できませんでした。ファイルと空き容量を確認してください。', error: true);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _showMessage(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.children,
  });

  final IconData icon;
  final String title;
  final String description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(description),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        ...children,
      ],
    ),
  );
}

class _DiagnosticExportSheet extends StatefulWidget {
  const _DiagnosticExportSheet();

  @override
  State<_DiagnosticExportSheet> createState() => _DiagnosticExportSheetState();
}

class _DiagnosticExportSheetState extends State<_DiagnosticExportSheet> {
  bool _includeLogs = false;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('診断情報を確認', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        const Text('含まれる情報: アプリ版、Android版、端末モデル、描画設定、接続先とタブの件数。'),
        const SizedBox(height: 8),
        const Text('含まれない情報: パスワード、秘密鍵、ホスト名、IPアドレス、ユーザー名、コマンド、端末出力。'),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('匿名化した接続ログを含める'),
          subtitle: const Text('日時、状態、失敗コードだけを含めます。既定ではオフです。'),
          value: _includeLogs,
          onChanged: (value) => setState(() => _includeLogs = value),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, _includeLogs),
          icon: const Icon(Icons.save_alt),
          label: const Text('保存先を選ぶ'),
        ),
      ],
    ),
  );
}
