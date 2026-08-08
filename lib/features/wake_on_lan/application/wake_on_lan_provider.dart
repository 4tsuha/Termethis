import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/wake_on_lan.dart';

final wakeOnLanSenderProvider = Provider<WakeOnLanSender>(
  (ref) => const _UnavailableWakeOnLanSender(),
);

class _UnavailableWakeOnLanSender implements WakeOnLanSender {
  const _UnavailableWakeOnLanSender();

  @override
  Future<void> send(WakeOnLanConfiguration configuration) {
    throw const WakeOnLanFailure();
  }
}
