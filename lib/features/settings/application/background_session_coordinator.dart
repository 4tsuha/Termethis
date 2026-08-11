import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/background_session_service_controller.dart';

final backgroundSessionServiceControllerProvider =
    Provider<BackgroundSessionServiceController>(
      (ref) => const NoopBackgroundSessionServiceController(),
    );

final backgroundSessionCoordinatorProvider =
    Provider<BackgroundSessionCoordinator>((ref) {
      final coordinator = BackgroundSessionCoordinator(
        ref.watch(backgroundSessionServiceControllerProvider),
      );
      ref.onDispose(coordinator.dispose);
      return coordinator;
    });

class BackgroundSessionCoordinator {
  BackgroundSessionCoordinator(this._service);

  final BackgroundSessionServiceController _service;
  bool _enabled = false;
  bool _hasActiveSession = false;
  bool _running = false;
  bool _disposed = false;

  void setEnabled(bool enabled) {
    _enabled = enabled;
    _sync();
  }

  void setHasActiveSession(bool hasActiveSession) {
    _hasActiveSession = hasActiveSession;
    _sync();
  }

  void _sync() {
    if (_disposed) return;
    final shouldRun = _enabled && _hasActiveSession;
    if (_running == shouldRun) return;
    _running = shouldRun;
    unawaited(_apply(shouldRun));
  }

  Future<void> _apply(bool shouldRun) async {
    try {
      await _service.setRunning(shouldRun);
    } catch (_) {
      if (!_disposed && shouldRun) {
        _running = false;
      }
    }
  }

  void dispose() {
    _disposed = true;
    if (_running) unawaited(_service.setRunning(false));
  }
}
