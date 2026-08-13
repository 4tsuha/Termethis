import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/shizuku_diagnostics_controller.dart';
import '../../../shared/presentation/expressive_scaffold.dart';

class LogcatCaptureScreen extends ConsumerStatefulWidget {
  const LogcatCaptureScreen({super.key});

  @override
  ConsumerState<LogcatCaptureScreen> createState() =>
      _LogcatCaptureScreenState();
}

class _LogcatCaptureScreenState extends ConsumerState<LogcatCaptureScreen> {
  Timer? _refreshTimer;
  List<String> _lines = const [];
  bool _capturing = false;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final gateway = ref.read(shizukuDiagnosticsGatewayProvider);
    try {
      final capturing = await gateway.isLogcatCapturing();
      final lines = await gateway.getRecentLogcatLines();
      if (!mounted) return;
      setState(() {
        _capturing = capturing;
        _lines = lines;
        _busy = false;
        _error = null;
      });
      _syncRefreshTimer();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$error';
      });
    }
  }

  void _syncRefreshTimer() {
    _refreshTimer?.cancel();
    if (_capturing) {
      _refreshTimer = Timer.periodic(
        const Duration(milliseconds: 500),
        (_) => _refresh(),
      );
    }
  }

  Future<void> _start() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(shizukuDiagnosticsGatewayProvider)
          .startLogcatCapture(maxLines: 2000);
      await _refresh();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    setState(() => _busy = true);
    await ref.read(shizukuDiagnosticsGatewayProvider).stopLogcatCapture();
    await _refresh();
  }

  Future<void> _clear() async {
    await ref.read(shizukuDiagnosticsGatewayProvider).clearLogcatCapture();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return ExpressiveScaffold(
      title: 'Logcatキャプチャ',
      maxContentWidth: double.infinity,
      actions: [
        IconButton(
          tooltip: '表示を更新',
          onPressed: _busy ? null : _refresh,
          icon: const Icon(Icons.refresh),
        ),
        IconButton(
          tooltip: 'コピー',
          onPressed: _lines.isEmpty
              ? null
              : () => Clipboard.setData(ClipboardData(text: _lines.join('\n'))),
          icon: const Icon(Icons.copy_outlined),
        ),
        IconButton(
          tooltip: '消去',
          onPressed: _lines.isEmpty ? null : _clear,
          icon: const Icon(Icons.delete_outline),
        ),
      ],
      body: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: ListTile(
              leading: Icon(
                _capturing ? Icons.fiber_manual_record : Icons.stop_circle,
                color: _capturing ? Colors.red : null,
              ),
              title: Text(_capturing ? 'キャプチャ中' : '停止中'),
              subtitle: const Text(
                'ShizukuのADB shell権限で取得し、最大2,000行をメモリ内に保持します。',
              ),
              trailing: _busy
                  ? const SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : FilledButton.tonal(
                      onPressed: _capturing ? _stop : _start,
                      child: Text(_capturing ? '停止' : '開始'),
                    ),
            ),
          ),
          if (_error != null)
            MaterialBanner(
              content: Text('Logcatを操作できませんでした: $_error'),
              actions: [
                TextButton(onPressed: _refresh, child: const Text('再試行')),
              ],
            ),
          Expanded(
            child: ColoredBox(
              color: Colors.black,
              child: _lines.isEmpty
                  ? const Center(
                      child: Text(
                        'ログはまだありません',
                        style: TextStyle(color: Colors.white70),
                      ),
                    )
                  : ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.all(8),
                      itemCount: _lines.length,
                      itemBuilder: (context, index) => SelectableText(
                        _lines[_lines.length - index - 1],
                        style: const TextStyle(
                          color: Color(0xffd7ffd9),
                          fontFamily: 'CascadiaMono',
                          fontSize: 11,
                          height: 1.25,
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
