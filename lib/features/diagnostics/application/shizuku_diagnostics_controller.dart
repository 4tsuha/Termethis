import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/shizuku_diagnostics_gateway.dart';

final shizukuDiagnosticsGatewayProvider = Provider<ShizukuDiagnosticsGateway>(
  (ref) => const UnavailableShizukuDiagnosticsGateway(),
);

final shizukuStatusProvider =
    AsyncNotifierProvider<ShizukuStatusController, ShizukuStatus>(
      ShizukuStatusController.new,
    );

class ShizukuStatusController extends AsyncNotifier<ShizukuStatus> {
  @override
  Future<ShizukuStatus> build() {
    return ref.watch(shizukuDiagnosticsGatewayProvider).getStatus();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      ref.read(shizukuDiagnosticsGatewayProvider).getStatus,
    );
  }

  Future<void> requestPermission() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      ref.read(shizukuDiagnosticsGatewayProvider).requestPermission,
    );
  }
}
