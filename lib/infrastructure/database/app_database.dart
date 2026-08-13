import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

@DataClassName('ConnectionProfileRecord')
class ConnectionProfileRows extends Table {
  TextColumn get id => text()();

  TextColumn get name => text()();

  TextColumn get host => text()();

  IntColumn get port => integer()();

  TextColumn get username => text()();

  TextColumn get connectionType => text().withDefault(const Constant('ssh'))();

  TextColumn get authenticationType => text()();

  TextColumn get credentialReference => text().nullable()();

  TextColumn get privateKeyLabel => text().nullable()();

  TextColumn get wakeOnLanMacAddress => text().nullable()();

  TextColumn get wakeOnLanBroadcastAddress => text().nullable()();

  IntColumn get wakeOnLanPort => integer().nullable()();

  TextColumn get remotePath => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('KnownHostRecord')
class KnownHostRecords extends Table {
  TextColumn get host => text()();

  IntColumn get port => integer()();

  TextColumn get algorithm => text()();

  TextColumn get fingerprintSha256 => text()();

  DateTimeColumn get acceptedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {
    host,
    port,
    algorithm,
    fingerprintSha256,
  };
}

@DriftDatabase(tables: [ConnectionProfileRows, KnownHostRecords])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  AppDatabase.defaults() : super(driftDatabase(name: 'termethis'));

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) => migrator.createAll(),
    onUpgrade: (migrator, _, _) => _repairSchema(migrator),
    beforeOpen: (details) async {
      if (!details.wasCreated) {
        await _repairSchema(Migrator(this));
      }
    },
  );

  Future<void> _repairSchema(Migrator migrator) async {
    final tables = await _tableNames();
    if (!tables.contains(connectionProfileRows.actualTableName)) {
      await migrator.createTable(connectionProfileRows);
    } else {
      await _addMissingConnectionProfileColumns(migrator);
    }
    if (!tables.contains(knownHostRecords.actualTableName)) {
      await migrator.createTable(knownHostRecords);
    }

    await customStatement(
      "UPDATE connection_profile_rows SET connection_type = 'rdp' "
      "WHERE connection_type = 'rds'",
    );
  }

  Future<void> _addMissingConnectionProfileColumns(Migrator migrator) async {
    final columns = await _columnNames(connectionProfileRows.actualTableName);
    final requiredColumns = <GeneratedColumn<Object>>[
      connectionProfileRows.credentialReference,
      connectionProfileRows.privateKeyLabel,
      connectionProfileRows.wakeOnLanMacAddress,
      connectionProfileRows.wakeOnLanBroadcastAddress,
      connectionProfileRows.wakeOnLanPort,
      connectionProfileRows.connectionType,
      connectionProfileRows.remotePath,
    ];
    for (final column in requiredColumns) {
      if (!columns.contains(column.$name)) {
        await migrator.addColumn(connectionProfileRows, column);
      }
    }
  }

  Future<Set<String>> _tableNames() async {
    final rows = await customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    ).get();
    return rows.map((row) => row.read<String>('name')).toSet();
  }

  Future<Set<String>> _columnNames(String tableName) async {
    final escapedTableName = tableName.replaceAll("'", "''");
    final rows = await customSelect(
      "PRAGMA table_info('$escapedTableName')",
    ).get();
    return rows.map((row) => row.read<String>('name')).toSet();
  }
}
