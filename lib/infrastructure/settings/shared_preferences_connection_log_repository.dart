import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../features/connection_logs/domain/connection_log_entry.dart';
import '../../features/connection_logs/domain/connection_log_repository.dart';

class SharedPreferencesConnectionLogRepository
    implements ConnectionLogRepository {
  SharedPreferencesConnectionLogRepository({
    SharedPreferencesAsync? preferences,
    this.maximumEntries = 200,
  }) : assert(maximumEntries > 0),
       _preferences = preferences ?? SharedPreferencesAsync();

  static const _key = 'diagnostics.ssh_connection_logs.v1';
  final SharedPreferencesAsync _preferences;
  final int maximumEntries;
  final _controller = StreamController<List<ConnectionLogEntry>>.broadcast();
  Future<void> _mutationTail = Future<void>.value();

  @override
  Stream<List<ConnectionLogEntry>> watchAll() async* {
    yield await list();
    yield* _controller.stream;
  }

  @override
  Future<List<ConnectionLogEntry>> list() async {
    final encoded = await _preferences.getString(_key);
    if (encoded == null) return const [];
    try {
      final values = jsonDecode(encoded);
      if (values is! List) return const [];
      return values
          .map(ConnectionLogEntry.fromJson)
          .whereType<ConnectionLogEntry>()
          .take(maximumEntries)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> append(ConnectionLogEntry entry) {
    return _enqueue(() async {
      final entries = [entry, ...await list()];
      if (entries.length > maximumEntries) {
        entries.removeRange(maximumEntries, entries.length);
      }
      await _save(entries);
    });
  }

  @override
  Future<void> clear() => _enqueue(() async {
    await _preferences.remove(_key);
    _controller.add(const []);
  });

  Future<void> _save(List<ConnectionLogEntry> entries) async {
    await _preferences.setString(
      _key,
      jsonEncode([for (final entry in entries) entry.toJson()]),
    );
    _controller.add(List.unmodifiable(entries));
  }

  Future<void> _enqueue(Future<void> Function() mutation) {
    final operation = _mutationTail.then((_) => mutation());
    _mutationTail = operation.catchError((Object _) {});
    return operation;
  }
}
