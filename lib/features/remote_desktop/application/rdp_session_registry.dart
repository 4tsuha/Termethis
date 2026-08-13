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

abstract interface class RdpBackend {
  Future<rust.RustRdpConnectResult> connect(rust.RustRdpConnectRequest request);
  Future<rust.RustRdpStatus> readStatus(int sessionId);
  Future<void> sendText(int sessionId, String text);
  Future<void> sendScancode(int sessionId, int scancode, bool pressed);
  Future<void> close(int sessionId);
}

class RustRdpBackend implements RdpBackend {
  const RustRdpBackend();

  @override
  Future<rust.RustRdpConnectResult> connect(
    rust.RustRdpConnectRequest request,
  ) => rust.rdpConnect(request: request);

  @override
  Future<rust.RustRdpStatus> readStatus(int sessionId) =>
      rust.rdpReadStatus(sessionId: sessionId);

  @override
  Future<void> sendText(int sessionId, String text) =>
      rust.rdpSendText(sessionId: sessionId, text: text);

  @override
  Future<void> sendScancode(int sessionId, int scancode, bool pressed) =>
      rust.rdpSendScancode(
        sessionId: sessionId,
        scancode: scancode,
        pressed: pressed,
      );

  @override
  Future<void> close(int sessionId) => rust.rdpClose(sessionId: sessionId);
}

class RdpSessionRegistry {
  RdpSessionRegistry({this._backend = const RustRdpBackend()});

  final RdpBackend _backend;
  final Map<String, RdpSessionController> _sessions = {};

  RdpSessionController open(String tabId, ConnectionProfile profile) {
    final existing = _sessions[tabId];
    if (existing != null && existing.profile == profile) return existing;
    if (existing != null) unawaited(existing.close());
    final session = RdpSessionController(profile, backend: _backend);
    _sessions[tabId] = session;
    return session;
  }

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
  RdpSessionController(
    this.profile, {
    this._backend = const RustRdpBackend(),
    this.connectionTimeout = const Duration(seconds: 15),
  });

  final ConnectionProfile profile;
  final RdpBackend _backend;
  final Duration connectionTimeout;
  int? _sessionId;
  String _state = 'idle';
  String _renderer = 'native Vulkan Surface';
  String? _error;
  bool _closed = false;
  Timer? _connectionTimer;

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
    if (_closed || _state == 'connecting' || _sessionId != null) return;
    _state = 'connecting';
    _error = null;
    notifyListeners();
    try {
      final result = await _backend.connect(
        rust.RustRdpConnectRequest(
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
        await _backend.close(result.sessionId);
        return;
      }
      _sessionId = result.sessionId;
      _renderer = result.renderer;
      notifyListeners();
      _connectionTimer = Timer(
        connectionTimeout,
        () => unawaited(_expireConnection(result.sessionId)),
      );
      unawaited(_pollStatus(result.sessionId));
    } catch (error) {
      if (_closed) return;
      _state = 'failed';
      _error = '$error';
      notifyListeners();
    }
  }

  Future<void> _pollStatus(int sessionId) async {
    while (!_closed && _sessionId == sessionId) {
      try {
        final status = await _backend.readStatus(sessionId);
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
        if (_state != 'connecting') {
          _connectionTimer?.cancel();
          _connectionTimer = null;
        }
        if (_state == 'failed' || _state == 'closed') {
          await _releaseSession(sessionId);
          return;
        }
        await Future<void>.delayed(
          Duration(milliseconds: _state == 'ready' ? 1000 : 250),
        );
      } catch (error) {
        if (_closed || _sessionId != sessionId) return;
        _state = 'failed';
        _error = '$error';
        notifyListeners();
        await _releaseSession(sessionId);
        return;
      }
    }
  }

  Future<void> _expireConnection(int sessionId) async {
    if (_closed || _sessionId != sessionId || _state != 'connecting') return;
    _connectionTimer = null;
    _state = 'failed';
    _error = 'RDPサーバーから応答がありません。接続先とネットワークを確認してください。';
    notifyListeners();
    await _releaseSession(sessionId);
  }

  void updateRenderer(String renderer) {
    if (_closed) return;
    if (_renderer == renderer) return;
    _renderer = renderer;
    notifyListeners();
  }

  void updateError(String error) {
    if (_closed) return;
    if (_error == error) return;
    _error = error;
    notifyListeners();
  }

  Future<bool> sendText(String text) async {
    final id = _sessionId;
    if (id == null || _state != 'ready' || text.isEmpty) return false;
    try {
      await _backend.sendText(id, text);
      await _backend.sendScancode(id, 0x1c, true);
      await _backend.sendScancode(id, 0x1c, false);
      return true;
    } on Exception catch (error) {
      _error = '$error';
      notifyListeners();
      return false;
    }
  }

  Future<void> _releaseSession(int sessionId) async {
    _connectionTimer?.cancel();
    _connectionTimer = null;
    if (_sessionId == sessionId) {
      _sessionId = null;
      notifyListeners();
    }
    try {
      await _backend.close(sessionId);
    } on Exception {
      // The native side may already have removed a failed session.
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _connectionTimer?.cancel();
    _connectionTimer = null;
    final id = _sessionId;
    _sessionId = null;
    _state = 'closed';
    if (id != null) {
      try {
        await _backend.close(id);
      } on Exception catch (error) {
        _error = '$error';
      }
    }
    notifyListeners();
    dispose();
  }
}
