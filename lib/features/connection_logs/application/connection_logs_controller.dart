import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/connection_log_entry.dart';
import '../domain/connection_log_repository.dart';

final connectionLogRepositoryProvider = Provider<ConnectionLogRepository>(
  (ref) => EphemeralConnectionLogRepository(),
);

final connectionLogsProvider =
    StreamNotifierProvider<ConnectionLogsController, List<ConnectionLogEntry>>(
      ConnectionLogsController.new,
    );

class ConnectionLogsController
    extends StreamNotifier<List<ConnectionLogEntry>> {
  late ConnectionLogRepository _repository;

  @override
  Stream<List<ConnectionLogEntry>> build() {
    _repository = ref.watch(connectionLogRepositoryProvider);
    return _repository.watchAll();
  }

  Future<List<ConnectionLogEntry>> list() => _repository.list();

  Future<void> clear() => _repository.clear();
}
