import 'dart:async';

import 'connection_profile.dart';

abstract interface class ConnectionProfileRepository {
  Stream<List<ConnectionProfile>> watchAll();

  Future<ConnectionProfile?> findById(String id);

  Future<void> save(ConnectionProfile profile);

  Future<void> delete(String id);
}

class EphemeralConnectionProfileRepository
    implements ConnectionProfileRepository {
  EphemeralConnectionProfileRepository({
    Iterable<ConnectionProfile> initialProfiles = const [],
  }) : _profiles = {for (final profile in initialProfiles) profile.id: profile};

  final Map<String, ConnectionProfile> _profiles;
  final StreamController<List<ConnectionProfile>> _changes =
      StreamController.broadcast();

  @override
  Stream<List<ConnectionProfile>> watchAll() async* {
    yield _snapshot();
    yield* _changes.stream;
  }

  @override
  Future<ConnectionProfile?> findById(String id) async => _profiles[id];

  @override
  Future<void> save(ConnectionProfile profile) async {
    _profiles[profile.id] = profile;
    _changes.add(_snapshot());
  }

  @override
  Future<void> delete(String id) async {
    if (_profiles.remove(id) != null) {
      _changes.add(_snapshot());
    }
  }

  List<ConnectionProfile> _snapshot() => List.unmodifiable(_profiles.values);

  Future<void> close() => _changes.close();
}
