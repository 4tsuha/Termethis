import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../connections/domain/connection_profile.dart';
import '../../../src/rust/api/rdp.dart' as rust;

final rdpSessionRegistryProvider = Provider<RdpSessionRegistry>((ref) {
  final registry = RdpSessionRegistry();
  ref.onDispose(registry.dispose);
  return registry;
});

class RdpSessionRegistry {
  final Map<String, RdpSessionController> _sessions = {};

  RdpSessionController open(String tabId, ConnectionProfile profile) =>
      _sessions.putIfAbsent(tabId, () => RdpSessionController(profile));

  RdpSessionController? find(String tabId) => _sessions[tabId];

  Future<void> remove(String tabId) async {
    await _sessions.remove(tabId)?.close();
  }

  void dispose() {
    for (final session in _sessions.values) {
      unawaited(session.close());
    }
    _sessions.clear();
  }
}

class RdpSessionController extends ChangeNotifier {
  RdpSessionController(this.profile);

  final ConnectionProfile profile;
  int? _sessionId;
  String _state = 'idle';
  String _renderer = 'native Vulkan Surface';
  String? _error;
  bool _closed = false;

  int? get sessionId => _sessionId;
  String get state => _state;
  String get renderer => _renderer;
  String? get error => _error;
  bool get isActive => _state == 'connecting' || _state == 'ready';

  Future<void> connect({
    required String password,
    required String domain,
    required int width,
    required int height,
  }) async {
    if (_closed || _state == 'connecting') return;
    _state = 'connecting';
    _error = null;
    notifyListeners();
    try {
      final result = await rust.rdpConnect(
        request: rust.RustRdpConnectRequest(
          host: profile.host,
          port: profile.port,
          username: profile.username,
          password: password,
          domain: domain,
          width: width,
          height: height,
        ),
      );
      if (_closed) {
        await rust.rdpClose(sessionId: result.sessionId);
        return;
      }
      _sessionId = result.sessionId;
      _renderer = result.renderer;
      notifyListeners();
      unawaited(_pollStatus(result.sessionId));
    } catch (error) {
      _state = 'failed';
      _error = '$error';
      notifyListeners();
    }
  }

  Future<void> _pollStatus(int sessionId) async {
    while (!_closed && _sessionId == sessionId) {
      try {
        final status = await rust.rdpReadStatus(sessionId: sessionId);
        if (_closed || _sessionId != sessionId) return;
        final nextError = status.rendererError ?? status.errorMessage;
        if (_state != status.state ||
            _renderer != status.renderer ||
            _error != nextError) {
          _state = status.state;
          _renderer = status.renderer;
          _error = nextError;
          notifyListeners();
        }
        if (_state == 'failed' || _state == 'closed') return;
        await Future<void>.delayed(
          Duration(milliseconds: _state == 'ready' ? 1000 : 250),
        );
      } catch (error) {
        if (_closed) return;
        _state = 'failed';
        _error = '$error';
        notifyListeners();
        return;
      }
    }
  }

  void updateRenderer(String renderer) {
    if (_renderer == renderer) return;
    _renderer = renderer;
    notifyListeners();
  }

  void updateError(String error) {
    if (_error == error) return;
    _error = error;
    notifyListeners();
  }

  Future<void> sendText(String text) async {
    final id = _sessionId;
    if (id == null || text.isEmpty) return;
    await rust.rdpSendText(sessionId: id, text: text);
    await rust.rdpSendScancode(sessionId: id, scancode: 0x1c, pressed: true);
    await rust.rdpSendScancode(sessionId: id, scancode: 0x1c, pressed: false);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final id = _sessionId;
    _sessionId = null;
    _state = 'closed';
    if (id != null) await rust.rdpClose(sessionId: id);
    notifyListeners();
    dispose();
  }
}
