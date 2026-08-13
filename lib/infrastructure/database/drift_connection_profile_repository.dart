import 'package:drift/drift.dart';

import '../../features/connections/domain/connection_profile.dart';
import '../../features/connections/domain/connection_profile_repository.dart';
import '../../features/wake_on_lan/domain/wake_on_lan.dart';
import 'app_database.dart';

class DriftConnectionProfileRepository implements ConnectionProfileRepository {
  DriftConnectionProfileRepository(this._database);

  final AppDatabase _database;

  @override
  Stream<List<ConnectionProfile>> watchAll() {
    final query = _database.select(_database.connectionProfileRows)
      ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]);
    return query.watch().map(
      (rows) => rows.map(_toDomain).toList(growable: false),
    );
  }

  @override
  Future<ConnectionProfile?> findById(String id) async {
    final query = _database.select(_database.connectionProfileRows)
      ..where((row) => row.id.equals(id));
    final row = await query.getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  @override
  Future<void> save(ConnectionProfile profile) async {
    final table = _database.connectionProfileRows;
    final existingQuery = _database.select(table)
      ..where((row) => row.id.equals(profile.id));
    final existing = await existingQuery.getSingleOrNull();
    final now = DateTime.now().toUtc();

    await _database
        .into(table)
        .insertOnConflictUpdate(
          ConnectionProfileRowsCompanion.insert(
            id: profile.id,
            name: profile.name,
            host: profile.host,
            port: profile.port,
            username: profile.username,
            connectionType: Value(profile.connectionType.name),
            authenticationType: profile.authenticationType.name,
            credentialReference: Value(profile.credentialReference),
            privateKeyLabel: Value(profile.privateKeyLabel),
            wakeOnLanMacAddress: Value(profile.wakeOnLan?.macAddress),
            wakeOnLanBroadcastAddress: Value(
              profile.wakeOnLan?.broadcastAddress,
            ),
            wakeOnLanPort: Value(profile.wakeOnLan?.port),
            remotePath: Value(profile.remotePath),
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
          ),
        );
  }

  @override
  Future<void> delete(String id) async {
    final query = _database.delete(_database.connectionProfileRows)
      ..where((row) => row.id.equals(id));
    await query.go();
  }

  ConnectionProfile _toDomain(ConnectionProfileRecord row) {
    return ConnectionProfile(
      id: row.id,
      name: row.name,
      host: row.host,
      port: row.port,
      username: row.username,
      connectionType: _connectionType(row.connectionType),
      authenticationType: _authenticationType(row.authenticationType),
      credentialReference: row.credentialReference,
      privateKeyLabel: row.privateKeyLabel,
      wakeOnLan: _wakeOnLan(row),
      remotePath: row.remotePath,
    );
  }

  AuthenticationType _authenticationType(String value) {
    return AuthenticationType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => AuthenticationType.passwordOrInteractive,
    );
  }

  ConnectionType _connectionType(String value) {
    return ConnectionType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => ConnectionType.ssh,
    );
  }

  WakeOnLanConfiguration? _wakeOnLan(ConnectionProfileRecord row) {
    final macAddress = row.wakeOnLanMacAddress;
    final broadcastAddress = row.wakeOnLanBroadcastAddress;
    final port = row.wakeOnLanPort;
    if (macAddress == null || broadcastAddress == null || port == null) {
      return null;
    }
    return WakeOnLanConfiguration(
      macAddress: macAddress,
      broadcastAddress: broadcastAddress,
      port: port,
    );
  }
}
