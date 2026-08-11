import 'connection_log_entry.dart';

abstract interface class ConnectionLogRepository {
  Stream<List<ConnectionLogEntry>> watchAll();
  Future<List<ConnectionLogEntry>> list();
  Future<void> append(ConnectionLogEntry entry);
  Future<void> clear();
}

class EphemeralConnectionLogRepository implements ConnectionLogRepository {
  EphemeralConnectionLogRepository({this.maximumEntries = 200})
    : assert(maximumEntries > 0);

  final int maximumEntries;
  final List<ConnectionLogEntry> _entries = [];
  final _listeners = <void Function(List<ConnectionLogEntry>)>{};

  @override
  Stream<List<ConnectionLogEntry>> watchAll() async* {
    yield List.unmodifiable(_entries);
    yield* Stream<List<ConnectionLogEntry>>.multi((controller) {
      void listener(List<ConnectionLogEntry> entries) =>
          controller.add(entries);
      _listeners.add(listener);
      controller.onCancel = () => _listeners.remove(listener);
    });
  }

  @override
  Future<List<ConnectionLogEntry>> list() async => List.unmodifiable(_entries);

  @override
  Future<void> append(ConnectionLogEntry entry) async {
    _entries.insert(0, entry);
    if (_entries.length > maximumEntries) {
      _entries.removeRange(maximumEntries, _entries.length);
    }
    _notify();
  }

  @override
  Future<void> clear() async {
    if (_entries.isEmpty) return;
    _entries.clear();
    _notify();
  }

  void _notify() {
    final snapshot = List<ConnectionLogEntry>.unmodifiable(_entries);
    for (final listener in List.of(_listeners)) {
      listener(snapshot);
    }
  }
}
