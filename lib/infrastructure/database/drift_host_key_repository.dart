import 'package:drift/drift.dart';

import '../../features/terminal/domain/ssh_gateway.dart';
import 'app_database.dart';

class DriftHostKeyRepository implements HostKeyRepository {
  DriftHostKeyRepository(this._database);

  final AppDatabase _database;

  @override
  Future<List<KnownHost>> find(String host, int port) async {
    final normalizedHost = normalizeSshHost(host);
    final query = _database.select(_database.knownHostRecords)
      ..where((row) => row.host.equals(normalizedHost) & row.port.equals(port))
      ..orderBy([(row) => OrderingTerm.asc(row.acceptedAt)]);
    final rows = await query.get();
    return rows
        .map(
          (row) => KnownHost(
            info: HostKeyInfo(
              host: row.host,
              port: row.port,
              algorithm: row.algorithm,
              fingerprintSha256: row.fingerprintSha256,
            ),
            acceptedAt: row.acceptedAt,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> trust(KnownHost host) async {
    await _database
        .into(_database.knownHostRecords)
        .insert(
          KnownHostRecordsCompanion.insert(
            host: normalizeSshHost(host.info.host),
            port: host.info.port,
            algorithm: host.info.algorithm,
            fingerprintSha256: host.info.fingerprintSha256,
            acceptedAt: host.acceptedAt.toUtc(),
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  @override
  Future<void> remove(String host, int port) async {
    final normalizedHost = normalizeSshHost(host);
    final query = _database.delete(_database.knownHostRecords)
      ..where((row) => row.host.equals(normalizedHost) & row.port.equals(port));
    await query.go();
  }
}
