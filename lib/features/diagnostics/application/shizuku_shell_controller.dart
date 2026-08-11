import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../settings/application/terminal_performance_settings_controller.dart';
import '../domain/shizuku_diagnostics_gateway.dart';
import 'shizuku_diagnostics_controller.dart';

final shizukuShellControllerProvider = Provider<ShizukuShellController>((ref) {
  final controller = ShizukuShellController(
    ref.watch(shizukuDiagnosticsGatewayProvider),
    scrollbackLines: ref.watch(
      terminalPerformanceSettingsProvider.select(
        (settings) => settings.scrollbackLines,
      ),
    ),
  );
  ref.onDispose(controller.dispose);
  return controller;
});

class ShizukuShellController extends ChangeNotifier {
  ShizukuShellController(this._gateway, {required int scrollbackLines})
    : terminal = Terminal(maxLines: scrollbackLines) {
    terminal.onOutput = _sendText;
    _decodedSubscription = _inputBytes.stream
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(terminal.write);
  }

  static const _activePollInterval = Duration(milliseconds: 16);
  static const _idlePollInterval = Duration(milliseconds: 96);

  final ShizukuDiagnosticsGateway _gateway;
  final Terminal terminal;
  final StreamController<List<int>> _inputBytes = StreamController();
  late final StreamSubscription<String> _decodedSubscription;

  Timer? _pollTimer;
  bool _pollInFlight = false;
  bool _disposed = false;
  bool _running = false;
  bool _starting = false;
  String? _errorMessage;
  bool _controlArmed = false;
  bool _altArmed = false;

  bool get isRunning => _running;
  bool get isStarting => _starting;
  String? get errorMessage => _errorMessage;
  bool get controlArmed => _controlArmed;
  bool get altArmed => _altArmed;

  Future<bool> start() async {
    if (_starting || _running) return _running;
    _starting = true;
    _errorMessage = null;
    _notify();
    try {
      await _gateway.startShell();
      _running = await _gateway.isShellRunning();
      if (!_running) {
        _errorMessage = 'ADBシェルを開始できませんでした。Shizukuの状態と権限を確認してください。';
        return false;
      }
      _schedulePoll(Duration.zero);
      return true;
    } catch (error) {
      _errorMessage = 'ADBシェルを開始できませんでした: $error';
      return false;
    } finally {
      _starting = false;
      _notify();
    }
  }

  Future<void> stop() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    try {
      await _gateway.stopShell();
    } finally {
      _running = false;
      _notify();
    }
  }

  void toggleControl() {
    _controlArmed = !_controlArmed;
    _notify();
  }

  void toggleAlt() {
    _altArmed = !_altArmed;
    _notify();
  }

  void sendKey(TerminalKey key) {
    terminal.keyInput(key, ctrl: _controlArmed, alt: _altArmed);
    _controlArmed = false;
    _altArmed = false;
    _notify();
  }

  void paste(String text) => terminal.paste(text);

  void _sendText(String text) {
    if (!_running || text.isEmpty) return;
    final bytes = Uint8List.fromList(utf8.encode(text));
    unawaited(
      _gateway.writeShellInput(bytes).then((accepted) {
        if (!accepted && !_disposed) {
          _errorMessage = 'シェル入力を送信できませんでした。';
          _notify();
        }
      }),
    );
  }

  void _schedulePoll(Duration delay) {
    if (_disposed || !_running) return;
    _pollTimer?.cancel();
    _pollTimer = Timer(delay, _pollOutput);
  }

  Future<void> _pollOutput() async {
    if (_disposed || !_running || _pollInFlight) return;
    _pollInFlight = true;
    var receivedOutput = false;
    try {
      final output = await _gateway.readShellOutput();
      if (output.isNotEmpty) {
        receivedOutput = true;
        _inputBytes.add(output);
      } else if (!await _gateway.isShellRunning()) {
        _running = false;
        _notify();
      }
    } catch (error) {
      _running = false;
      _errorMessage = 'ADBシェルとの通信が終了しました: $error';
      _notify();
    } finally {
      _pollInFlight = false;
      _schedulePoll(receivedOutput ? _activePollInterval : _idlePollInterval);
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    if (_running) unawaited(_gateway.stopShell());
    unawaited(_decodedSubscription.cancel());
    unawaited(_inputBytes.close());
    terminal.onOutput = null;
    super.dispose();
  }
}
