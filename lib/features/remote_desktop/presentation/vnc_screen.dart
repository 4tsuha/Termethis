import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../connections/application/connection_profiles_controller.dart';
import '../../connections/domain/credential_vault.dart';
import '../../../src/rust/api/core.dart' as rust;

class VncScreen extends ConsumerStatefulWidget {
  const VncScreen({required this.profileId, required this.tabId, super.key});

  final String profileId;
  final String tabId;

  @override
  ConsumerState<VncScreen> createState() => _VncScreenState();
}

class _VncScreenState extends ConsumerState<VncScreen> {
  final TextEditingController _textInput = TextEditingController();
  int? _sessionId;
  BigInt _sequence = BigInt.zero;
  ui.Image? _image;
  Size _remoteSize = Size.zero;
  String? _error;
  bool _connecting = true;
  bool _closed = false;
  int _buttons = 0;
  int _lastPointerX = 0;
  int _lastPointerY = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_connect());
  }

  @override
  void dispose() {
    final sessionId = _sessionId;
    _sessionId = null;
    if (sessionId != null) unawaited(rust.vncClose(sessionId: sessionId));
    _image?.dispose();
    _textInput.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _connecting = true;
      _closed = false;
      _error = null;
    });
    try {
      final profile = await ref
          .read(connectionProfilesProvider.notifier)
          .loadById(widget.profileId);
      if (profile == null) throw StateError('接続先が削除されています。');
      var password = '';
      final reference = profile.credentialReference;
      if (reference != null) {
        final saved = await ref
            .read(credentialVaultProvider)
            .readPassword(CredentialHandle(reference));
        password = saved?.password ?? '';
      }
      if (password.isEmpty) {
        final entered = await _askPassword(profile.name);
        if (!mounted) return;
        if (entered == null) {
          setState(() {
            _connecting = false;
            _error = 'VNC接続をキャンセルしました。';
          });
          return;
        }
        password = entered;
      }
      final connected = await rust.vncConnect(
        request: rust.RustVncConnectRequest(
          host: profile.host,
          port: profile.port,
          password: password,
          shared: true,
        ),
      );
      if (!mounted) {
        await rust.vncClose(sessionId: connected.sessionId);
        return;
      }
      _sessionId = connected.sessionId;
      setState(() => _connecting = false);
      unawaited(_pumpFrames(connected.sessionId));
    } catch (error) {
      if (mounted) {
        setState(() {
          _connecting = false;
          _error = _friendlyError(error);
        });
      }
    }
  }

  Future<void> _pumpFrames(int sessionId) async {
    while (mounted && _sessionId == sessionId) {
      try {
        final frame = await rust.vncReadFrame(
          sessionId: sessionId,
          afterSequence: _sequence,
          waitMillis: 250,
        );
        if (!mounted || _sessionId != sessionId) return;
        if (frame.bgra.isNotEmpty && frame.width > 0 && frame.height > 0) {
          final image = await _decodeFrame(frame);
          if (!mounted || _sessionId != sessionId) {
            image.dispose();
            return;
          }
          final old = _image;
          setState(() {
            _image = image;
            _remoteSize = Size(frame.width.toDouble(), frame.height.toDouble());
            _sequence = frame.sequence;
          });
          old?.dispose();
        }
        if (frame.errorMessage case final message?) {
          setState(() => _error = _friendlyError(message));
        }
        if (frame.closed) {
          setState(() => _closed = true);
          return;
        }
      } catch (error) {
        if (mounted) setState(() => _error = _friendlyError(error));
        return;
      }
    }
  }

  Future<ui.Image> _decodeFrame(rust.RustVncFrame frame) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      frame.bgra,
      frame.width,
      frame.height,
      ui.PixelFormat.bgra8888,
      completer.complete,
    );
    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (_connecting) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null || _closed) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Card(
            margin: const EdgeInsets.all(24),
            color: colors.surfaceContainerLow,
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.desktop_access_disabled,
                    size: 40,
                    color: colors.error,
                  ),
                  const SizedBox(height: 12),
                  Text(_error ?? 'VNC接続が終了しました。', textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _reconnect,
                    icon: const Icon(Icons.refresh),
                    label: const Text('再接続'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final image = _image;
    if (image == null) return const Center(child: CircularProgressIndicator());
    return Column(
      children: [
        Expanded(
          child: ColoredBox(
            color: Colors.black,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final fitted = applyBoxFit(
                  BoxFit.contain,
                  _remoteSize,
                  constraints.biggest,
                );
                final output = Alignment.center.inscribe(
                  fitted.destination,
                  Offset.zero & constraints.biggest,
                );
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) =>
                      _pointer(details.localPosition, output, 1),
                  onTapUp: (details) =>
                      _pointer(details.localPosition, output, 0),
                  onSecondaryTapDown: (details) =>
                      _pointer(details.localPosition, output, 4),
                  onSecondaryTapUp: (details) =>
                      _pointer(details.localPosition, output, 0),
                  onPanStart: (details) =>
                      _pointer(details.localPosition, output, 1),
                  onPanUpdate: (details) =>
                      _pointer(details.localPosition, output, _buttons),
                  onPanEnd: (_) => _releasePointer(),
                  child: Center(
                    child: SizedBox(
                      width: output.width,
                      height: output.height,
                      child: RawImage(
                        image: image,
                        fit: BoxFit.fill,
                        filterQuality: FilterQuality.low,
                      ),
                    ),
                  ),
                );
              },
            ),
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
    for (final rune in text.runes) {
      await rust.vncKey(sessionId: sessionId, keySym: rune, down: true);
      await rust.vncKey(sessionId: sessionId, keySym: rune, down: false);
    }
    await rust.vncKey(sessionId: sessionId, keySym: 0xff0d, down: true);
    await rust.vncKey(sessionId: sessionId, keySym: 0xff0d, down: false);
  }

  Future<void> _reconnect() async {
    final sessionId = _sessionId;
    _sessionId = null;
    if (sessionId != null) {
      await rust.vncClose(sessionId: sessionId);
    }
    _sequence = BigInt.zero;
    await _connect();
  }

  Future<String?> _askPassword(String profileName) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.lock_outline),
        title: const Text('VNCパスワード'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$profileNameへ接続するパスワードを入力してください。端末には保存しません。'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'パスワード',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (value) => Navigator.pop(context, value),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('接続'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  void _pointer(Offset local, Rect viewport, int buttons) {
    final sessionId = _sessionId;
    if (sessionId == null || !viewport.contains(local) || _remoteSize.isEmpty) {
      return;
    }
    _buttons = buttons;
    final x = ((local.dx - viewport.left) / viewport.width * _remoteSize.width)
        .clamp(0, _remoteSize.width - 1)
        .round();
    final y = ((local.dy - viewport.top) / viewport.height * _remoteSize.height)
        .clamp(0, _remoteSize.height - 1)
        .round();
    _lastPointerX = x;
    _lastPointerY = y;
    unawaited(
      rust.vncPointer(sessionId: sessionId, x: x, y: y, buttons: buttons),
    );
  }

  void _releasePointer() {
    final sessionId = _sessionId;
    if (sessionId == null) return;
    _buttons = 0;
    unawaited(
      rust.vncPointer(
        sessionId: sessionId,
        x: _lastPointerX,
        y: _lastPointerY,
        buttons: 0,
      ),
    );
  }
}

String _friendlyError(Object error) {
  final message = error.toString();
  if (message.contains('WrongPassword') || message.contains('authentication')) {
    return 'VNC認証に失敗しました。保存済みパスワードを確認してください。';
  }
  if (message.contains('timed out')) return 'VNC接続がタイムアウトしました。';
  if (message.contains('unreachable')) return 'VNCサーバーへ接続できません。';
  if (message.contains('2560x1600')) {
    return 'VNC画面が大きすぎます。サーバー側の解像度を2560×1600以下にしてください。';
  }
  return 'VNC接続でエラーが発生しました。';
}
