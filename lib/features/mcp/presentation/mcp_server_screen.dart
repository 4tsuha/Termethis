import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/mcp_providers.dart';
import '../application/mcp_server_controller.dart';
import '../domain/mcp_server_settings.dart';
import '../../../shared/presentation/expressive_scaffold.dart';

class McpServerScreen extends ConsumerStatefulWidget {
  const McpServerScreen({super.key});

  @override
  ConsumerState<McpServerScreen> createState() => _McpServerScreenState();
}

class _McpServerScreenState extends ConsumerState<McpServerScreen> {
  final _portController = TextEditingController();
  final _tokenController = TextEditingController();
  McpServerController? _controller;
  bool _allowLan = false;
  bool _busy = false;
  bool _obscureToken = true;
  String? _error;
  List<String> _lanAddresses = const [];

  @override
  void dispose() {
    _portController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  void _bindController(McpServerController controller) {
    if (identical(_controller, controller)) return;
    _controller = controller;
    _portController.text = controller.settings.port.toString();
    _tokenController.text = controller.settings.bearerToken;
    _allowLan = controller.settings.allowLan;
    if (_tokenController.text.isEmpty) _tokenController.text = _newToken();
    _loadLanAddresses();
  }

  Future<void> _loadLanAddresses() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      final addresses = {
        for (final interface in interfaces)
          for (final address in interface.addresses) address.address,
      }.toList(growable: false);
      if (mounted) setState(() => _lanAddresses = addresses);
    } catch (_) {}
  }

  Future<void> _start() async {
    final controller = _controller;
    final port = int.tryParse(_portController.text);
    if (controller == null || port == null || port < 1 || port > 65535) {
      setState(() => _error = '1〜65535のポート番号を入力してください。');
      return;
    }
    final token = _tokenController.text.trim();
    if (utf8.encode(token).length < 32) {
      setState(() => _error = 'Bearer tokenは32バイト以上にしてください。');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await controller.saveSettings(
        McpServerSettings(
          enabled: true,
          allowLan: _allowLan,
          port: port,
          bearerToken: token,
        ),
      );
      await controller.start();
    } catch (error) {
      _error = '$error';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    final controller = _controller;
    if (controller == null) return;
    setState(() => _busy = true);
    try {
      await controller.stop();
      await controller.saveSettings(
        controller.settings.copyWith(enabled: false),
      );
    } catch (error) {
      _error = '$error';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncController = ref.watch(mcpServerControllerProvider);
    return ExpressiveScaffold(
      title: 'SSH MCPサーバー',
      body: asyncController.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('MCP設定を読み込めませんでした: $error')),
        data: (controller) {
          _bindController(controller);
          return _buildBody(context, controller);
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context, McpServerController controller) {
    final running = controller.status.state == McpServerState.running;
    final colors = Theme.of(context).colorScheme;
    final endpoints = _endpoints(controller.settings.port);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        Card(
          color: running ? colors.primaryContainer : colors.surfaceContainerLow,
          child: ListTile(
            leading: Icon(running ? Icons.hub : Icons.hub_outlined),
            title: Text(running ? 'MCPサーバーは実行中です' : 'MCPサーバーは停止しています'),
            subtitle: Text(
              running
                  ? endpoints.join('\n')
                  : 'アプリ起動時は停止します。必要なときだけ明示的に開始してください。',
            ),
            isThreeLine: running && endpoints.length > 1,
            trailing: _busy
                ? const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : FilledButton.tonal(
                    onPressed: running ? _stop : _start,
                    child: Text(running ? '停止' : '開始'),
                  ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          MaterialBanner(
            content: Text(_error!),
            actions: [
              TextButton(
                onPressed: () => setState(() => _error = null),
                child: const Text('閉じる'),
              ),
            ],
          ),
        ],
        const _SectionLabel('公開範囲と認証'),
        Card(
          color: colors.surfaceContainerLow,
          child: Column(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.lan_outlined),
                title: const Text('LAN内のAIクライアントへ公開'),
                subtitle: Text(
                  _allowLan
                      ? '同じネットワーク上の端末から接続できます。信頼できるLANでのみ有効にしてください。'
                      : 'この端末内の127.0.0.1からだけ接続できます。',
                ),
                value: _allowLan,
                onChanged: running || _busy
                    ? null
                    : (value) => setState(() => _allowLan = value),
              ),
              const Divider(height: 1, indent: 56),
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _portController,
                  enabled: !running && !_busy,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: '待受ポート',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: TextField(
                  controller: _tokenController,
                  enabled: !running && !_busy,
                  obscureText: _obscureToken,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'Bearer token',
                    helperText: 'すべてのMCP要求で必須です。安全な場所へだけ共有してください。',
                    border: const OutlineInputBorder(),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: _obscureToken ? '表示' : '隠す',
                          onPressed: () =>
                              setState(() => _obscureToken = !_obscureToken),
                          icon: Icon(
                            _obscureToken
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                        IconButton(
                          tooltip: '新しいtokenを生成',
                          onPressed: running || _busy
                              ? null
                              : () => setState(
                                  () => _tokenController.text = _newToken(),
                                ),
                          icon: const Icon(Icons.autorenew),
                        ),
                        IconButton(
                          tooltip: 'コピー',
                          onPressed: () => Clipboard.setData(
                            ClipboardData(text: _tokenController.text),
                          ),
                          icon: const Icon(Icons.copy_outlined),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const _SectionLabel('公開するSSH Tool'),
        Card(
          color: colors.surfaceContainerLow,
          child: const Column(
            children: [
              ListTile(
                leading: Icon(Icons.list_alt_outlined),
                title: Text('connections.list'),
                subtitle: Text('保存済みSSH接続先を、資格情報を除いて一覧表示します。'),
              ),
              Divider(height: 1, indent: 56),
              ListTile(
                leading: Icon(Icons.terminal),
                title: Text('ssh.execute'),
                subtitle: Text('保存済み接続先で非PTYコマンドを実行し、標準出力・標準エラー・終了コードを返します。'),
              ),
              Divider(height: 1, indent: 56),
              ListTile(
                leading: Icon(Icons.tab_outlined),
                title: Text('sessions.list'),
                subtitle: Text('Termethisで現在動作しているSSHセッションの状態だけを返します。'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Card(
          color: colors.surfaceContainerLow,
          child: const ListTile(
            leading: Icon(Icons.security_outlined),
            title: Text('実行時の安全条件'),
            subtitle: Text(
              '保存済み接続先、信頼済みホスト鍵、保存済み秘密鍵または許可された保存パスワードが必要です。未知のホスト鍵や対話認証は自動承認しません。',
            ),
          ),
        ),
      ],
    );
  }

  List<String> _endpoints(int port) {
    if (!_allowLan) return ['http://127.0.0.1:$port/mcp'];
    if (_lanAddresses.isEmpty) return ['http://<端末のIP>:$port/mcp'];
    return [for (final address in _lanAddresses) 'http://$address:$port/mcp'];
  }
}

String _newToken() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  return base64UrlEncode(bytes).replaceAll('=', '');
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}
