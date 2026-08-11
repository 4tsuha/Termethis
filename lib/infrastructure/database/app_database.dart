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
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) => migrator.createAll(),
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.addColumn(
          connectionProfileRows,
          connectionProfileRows.credentialReference,
        );
        await migrator.addColumn(
          connectionProfileRows,
          connectionProfileRows.privateKeyLabel,
        );
      }
      if (from < 3) {
        await migrator.addColumn(
          connectionProfileRows,
          connectionProfileRows.wakeOnLanMacAddress,
        );
        await migrator.addColumn(
          connectionProfileRows,
          connectionProfileRows.wakeOnLanBroadcastAddress,
        );
        await migrator.addColumn(
          connectionProfileRows,
          connectionProfileRows.wakeOnLanPort,
        );
      }
      if (from < 4) {
        await migrator.addColumn(
          connectionProfileRows,
          connectionProfileRows.connectionType,
        );
      }
      if (from < 5) {
        await customStatement(
          "UPDATE connection_profile_rows SET connection_type = 'rdp' "
          "WHERE connection_type = 'rds'",
        );
      }
    },
  );
}
