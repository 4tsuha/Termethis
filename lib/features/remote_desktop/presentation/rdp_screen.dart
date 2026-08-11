import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../connections/application/connection_profiles_controller.dart';
import '../../connections/domain/connection_profile.dart';
import '../../../src/rust/api/rdp.dart' as rust;
import 'widgets/rdp_vulkan_view.dart';

class RdpScreen extends ConsumerStatefulWidget {
  const RdpScreen({required this.profileId, super.key});

  final String profileId;

  @override
  ConsumerState<RdpScreen> createState() => _RdpScreenState();
}

class _RdpScreenState extends ConsumerState<RdpScreen> {
  final _password = TextEditingController();
  final _domain = TextEditingController();
  final _textInput = TextEditingController();
  ConnectionProfile? _profile;
  int? _sessionId;
  String _state = 'idle';
  String _renderer = 'native Vulkan Surface';
  String? _error;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadProfile());
  }

  Future<void> _loadProfile() async {
    final profile = await ref
        .read(connectionProfilesProvider.notifier)
        .loadById(widget.profileId);
    if (!mounted) return;
    setState(() => _profile = profile);
  }

  @override
  void dispose() {
    _disposed = true;
    final sessionId = _sessionId;
    if (sessionId != null) unawaited(rust.rdpClose(sessionId: sessionId));
    _password.dispose();
    _domain.dispose();
    _textInput.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    return Scaffold(
      appBar: AppBar(
        title: Text(profile?.name ?? 'RDP'),
        actions: [
          if (_sessionId != null)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Chip(
                avatar: Icon(Icons.memory, size: 16),
                label: Text('Vulkan Surface'),
              ),
            ),
        ],
      ),
      body: profile == null
          ? const Center(child: CircularProgressIndicator())
          : _sessionId == null
          ? _buildConnectForm(profile)
          : _buildDesktop(),
    );
  }

  Widget _buildConnectForm(ConnectionProfile profile) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Icon(
          Icons.desktop_windows_outlined,
          size: 56,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text('IronRDPで接続', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text('${profile.username} · ${profile.host}:${profile.port}'),
        const SizedBox(height: 20),
        TextField(
          controller: _domain,
          decoration: const InputDecoration(
            labelText: 'ドメイン（任意）',
            prefixIcon: Icon(Icons.domain_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: true,
          autofocus: true,
          onSubmitted: (_) => _connect(profile),
          decoration: const InputDecoration(
            labelText: 'パスワード',
            prefixIcon: Icon(Icons.password_outlined),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          '接続と復号はIronRDP、画面表示はアプリ内のネイティブVulkan Surfaceで処理します。画素データはDartへコピーしません。',
        ),
        const SizedBox(height: 8),
        Text(
          '現在のIronRDP公開版はRDPサーバー証明書を厳格検証しません。信頼できる接続先とネットワークで使用してください。',
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _state == 'connecting' ? null : () => _connect(profile),
          icon: _state == 'connecting'
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.login),
          label: const Text('RDP接続'),
        ),
      ],
    );
  }

  Future<void> _connect(ConnectionProfile profile) async {
    if (_state == 'connecting') return;
    setState(() {
      _state = 'connecting';
      _error = null;
    });
    final logicalSize = MediaQuery.sizeOf(context);
    final width = logicalSize.width.round().clamp(800, 1920);
    final height = (logicalSize.height - 120).round().clamp(600, 1080);
    try {
      final result = await rust.rdpConnect(
        request: rust.RustRdpConnectRequest(
          host: profile.host,
          port: profile.port,
          username: profile.username,
          password: _password.text,
          domain: _domain.text.trim(),
          width: width,
          height: height,
        ),
      );
      if (!mounted) return;
      setState(() {
        _sessionId = result.sessionId;
        _state = 'connecting';
        _renderer = result.renderer;
      });
      unawaited(_pollStatus(result.sessionId));
    } catch (error) {
      if (mounted) {
        setState(() {
          _state = 'failed';
          _error = '$error';
        });
      }
    }
  }

  Future<void> _pollStatus(int sessionId) async {
    while (!_disposed && _sessionId == sessionId) {
      try {
        final status = await rust.rdpReadStatus(sessionId: sessionId);
        if (_disposed || _sessionId != sessionId) return;
        final nextError = status.rendererError ?? status.errorMessage;
        if (_state != status.state ||
            _renderer != status.renderer ||
            _error != nextError) {
          setState(() {
            _state = status.state;
            _renderer = status.renderer;
            _error = nextError;
          });
        }
        if (status.state == 'failed' || status.state == 'closed') return;
        await Future<void>.delayed(
          Duration(milliseconds: status.state == 'ready' ? 1000 : 250),
        );
      } catch (error) {
        if (mounted) {
          setState(() {
            _state = 'failed';
            _error = '$error';
          });
        }
        return;
      }
    }
  }

  Widget _buildDesktop() {
    final sessionId = _sessionId!;
    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              RdpVulkanView(
                sessionId: sessionId,
                onRendererReady: (renderer) {
                  if (mounted && _renderer != renderer) {
                    setState(() => _renderer = renderer);
                  }
                },
                onRendererError: (error) {
                  if (mounted && _error != error) {
                    setState(() => _error = error);
                  }
                },
              ),
              if (_state == 'connecting')
                const IgnorePointer(
                  child: ColoredBox(
                    color: Color(0x66000000),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 12),
                          Text(
                            'Windowsへ接続しています…',
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (_error != null)
                Align(
                  alignment: Alignment.topCenter,
                  child: Material(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.warning_amber_rounded),
                      title: Text(_error!),
                      subtitle: Text(_renderer),
                    ),
                  ),
                ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            child: TextField(
              controller: _textInput,
              onSubmitted: (_) => _submitText(),
              decoration: InputDecoration(
                hintText: 'リモートへ文字入力',
                prefixIcon: const Icon(Icons.keyboard_outlined),
                suffixIcon: IconButton(
                  tooltip: '送信',
                  onPressed: _submitText,
                  icon: const Icon(Icons.send),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _submitText() async {
    final sessionId = _sessionId;
    final text = _textInput.text;
    if (sessionId == null || text.isEmpty) return;
    _textInput.clear();
    await rust.rdpSendText(sessionId: sessionId, text: text);
    await rust.rdpSendScancode(
      sessionId: sessionId,
      scancode: 0x1c,
      pressed: true,
    );
    await rust.rdpSendScancode(
      sessionId: sessionId,
      scancode: 0x1c,
      pressed: false,
    );
  }
}
