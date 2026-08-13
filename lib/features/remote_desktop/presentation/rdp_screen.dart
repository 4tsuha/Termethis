import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../connections/application/connection_profiles_controller.dart';
import '../../connections/domain/connection_profile.dart';
import '../application/rdp_session_registry.dart';
import 'widgets/rdp_vulkan_view.dart';

class RdpScreen extends ConsumerStatefulWidget {
  const RdpScreen({
    required this.profileId,
    required this.tabId,
    this.embedded = false,
    super.key,
  });

  final String profileId;
  final String tabId;
  final bool embedded;

  @override
  ConsumerState<RdpScreen> createState() => _RdpScreenState();
}

class _RdpScreenState extends ConsumerState<RdpScreen> {
  final _password = TextEditingController();
  final _domain = TextEditingController();
  final _textInput = TextEditingController();
  ConnectionProfile? _profile;
  RdpSessionController? _session;

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
    setState(() {
      _profile = profile;
      if (profile != null) {
        _session = ref
            .read(rdpSessionRegistryProvider)
            .open(widget.tabId, profile);
      }
    });
  }

  @override
  void dispose() {
    _password.dispose();
    _domain.dispose();
    _textInput.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    final session = _session;
    final body = profile == null || session == null
        ? const Center(child: CircularProgressIndicator())
        : ListenableBuilder(
            listenable: session,
            builder: (context, _) => session.sessionId == null
                ? _buildConnectForm(profile, session)
                : _buildDesktop(session),
          );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: Text(profile?.name ?? 'RDP')),
      body: body,
    );
  }

  Widget _buildConnectForm(
    ConnectionProfile profile,
    RdpSessionController session,
  ) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Icon(
          Icons.desktop_windows_outlined,
          size: 56,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text('リモートデスクトップ', style: Theme.of(context).textTheme.headlineSmall),
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
          onSubmitted: (_) => _connect(session),
          decoration: const InputDecoration(
            labelText: 'パスワード',
            prefixIcon: Icon(Icons.password_outlined),
          ),
        ),
        const SizedBox(height: 12),
        const Text('画面はアプリ内で表示し、描画データをターミナルUIへ渡さず処理します。'),
        const SizedBox(height: 8),
        Text(
          '現在のIronRDP公開版はRDPサーバー証明書を厳格検証しません。信頼できる接続先とネットワークで使用してください。',
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
        if (session.error != null) ...[
          const SizedBox(height: 12),
          Text(
            session.error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: session.state == 'connecting'
              ? null
              : () => _connect(session),
          icon: session.state == 'connecting'
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

  Future<void> _connect(RdpSessionController session) async {
    FocusScope.of(context).unfocus();
    final logicalSize = MediaQuery.sizeOf(context);
    final width = logicalSize.width.round().clamp(800, 1920);
    final height = (logicalSize.height - 120).round().clamp(600, 1080);
    await session.connect(
      password: _password.text,
      domain: _domain.text.trim(),
      width: width,
      height: height,
    );
    _password.clear();
  }

  Widget _buildDesktop(RdpSessionController session) {
    final sessionId = session.sessionId!;
    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (session.state == 'ready')
                RdpVulkanView(
                  key: ValueKey('rdp-vulkan-$sessionId'),
                  sessionId: sessionId,
                  onRendererReady: (renderer) {
                    session.updateRenderer(renderer);
                  },
                  onRendererError: (error) {
                    session.updateError(error);
                  },
                )
              else
                const ColoredBox(color: Colors.black),
              if (session.state == 'connecting')
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
              if (session.error != null)
                Align(
                  alignment: Alignment.topCenter,
                  child: Material(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.warning_amber_rounded),
                      title: Text(session.error!),
                      subtitle: Text(session.renderer),
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
              enabled: session.state == 'ready',
              onSubmitted: (_) => unawaited(_submitText(session)),
              decoration: InputDecoration(
                hintText: 'リモートへ文字入力',
                prefixIcon: const Icon(Icons.keyboard_outlined),
                suffixIcon: IconButton(
                  tooltip: '送信',
                  onPressed: session.state == 'ready'
                      ? () => unawaited(_submitText(session))
                      : null,
                  icon: const Icon(Icons.send),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _submitText(RdpSessionController session) async {
    final text = _textInput.text;
    if (text.isEmpty) return;
    if (await session.sendText(text)) _textInput.clear();
  }
}
