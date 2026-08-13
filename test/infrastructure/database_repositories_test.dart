import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termethis/features/connections/domain/connection_profile.dart';
import 'package:termethis/features/terminal/domain/ssh_gateway.dart';
import 'package:termethis/features/wake_on_lan/domain/wake_on_lan.dart';
import 'package:termethis/infrastructure/database/app_database.dart';
import 'package:termethis/infrastructure/database/drift_connection_profile_repository.dart';
import 'package:termethis/infrastructure/database/drift_host_key_repository.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  late Directory temporaryDirectory;
  late File databaseFile;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'termethis-drift-test-',
    );
    databaseFile = File('${temporaryDirectory.path}/termethis.sqlite');
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('接続先を保存し、データベースを開き直して復元する', () async {
    var database = AppDatabase(NativeDatabase(databaseFile));
    var repository = DriftConnectionProfileRepository(database);
    const profile = ConnectionProfile(
      id: 'development',
      name: '開発サーバー',
      host: 'ssh.example.com',
      port: 2222,
      username: 'developer',
      wakeOnLan: WakeOnLanConfiguration(
        macAddress: '00:11:22:33:44:55',
        broadcastAddress: '192.168.1.255',
        port: 9,
      ),
    );

    await repository.save(profile);
    await database.close();

    database = AppDatabase(NativeDatabase(databaseFile));
    repository = DriftConnectionProfileRepository(database);

    expect(await repository.findById(profile.id), profile);
    expect(await repository.watchAll().first, [profile]);

    await repository.delete(profile.id);
    expect(await repository.findById(profile.id), isNull);
    await database.close();
  });

  test('RDPとVNCの接続方式を保存して復元する', () async {
    final database = AppDatabase(NativeDatabase(databaseFile));
    final repository = DriftConnectionProfileRepository(database);
    const profiles = [
      ConnectionProfile(
        id: 'rdp',
        name: 'Windowsサーバー',
        host: 'rdp.example.com',
        port: 3389,
        username: 'operator',
        connectionType: ConnectionType.rdp,
      ),
      ConnectionProfile(
        id: 'vnc',
        name: 'VNCサーバー',
        host: 'vnc.example.com',
        port: 5900,
        username: '',
        connectionType: ConnectionType.vnc,
      ),
    ];

    for (final profile in profiles) {
      await repository.save(profile);
    }

    expect(await repository.watchAll().first, profiles);
    await database.close();
  });

  test('known_hostsを正規化して複数鍵を再起動後も保持する', () async {
    var database = AppDatabase(NativeDatabase(databaseFile));
    var repository = DriftHostKeyRepository(database);
    final first = KnownHost(
      info: const HostKeyInfo(
        host: 'SSH.Example.COM.',
        port: 22,
        algorithm: 'ssh-ed25519',
        fingerprintSha256: 'SHA256:first',
      ),
      acceptedAt: DateTime.utc(2026, 8, 8, 10),
    );
    final second = KnownHost(
      info: const HostKeyInfo(
        host: 'ssh.example.com',
        port: 22,
        algorithm: 'rsa-sha2-512',
        fingerprintSha256: 'SHA256:second',
      ),
      acceptedAt: DateTime.utc(2026, 8, 8, 11),
    );

    await repository.trust(first);
    await repository.trust(second);
    await database.close();

    database = AppDatabase(NativeDatabase(databaseFile));
    repository = DriftHostKeyRepository(database);
    final restored = await repository.find('ssh.example.com', 22);

    expect(await repository.listAll(), hasLength(2));
    expect(restored.map((host) => host.info.fingerprintSha256), [
      'SHA256:first',
      'SHA256:second',
    ]);
    expect(evaluateHostKeyTrust(restored, second.info), HostKeyTrust.trusted);
    expect(
      evaluateHostKeyTrust(
        restored,
        const HostKeyInfo(
          host: 'ssh.example.com',
          port: 22,
          algorithm: 'ssh-ed25519',
          fingerprintSha256: 'SHA256:changed',
        ),
      ),
      HostKeyTrust.mismatch,
    );

    await database.close();
  });

  test('スキーマ1の接続先をスキーマ6へ移行する', () async {
    final legacy = sqlite.sqlite3.open(databaseFile.path);
    legacy.execute('''
      CREATE TABLE connection_profile_rows (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        host TEXT NOT NULL,
        port INTEGER NOT NULL,
        username TEXT NOT NULL,
        authentication_type TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
    ''');
    legacy.execute('''
      CREATE TABLE known_host_records (
        host TEXT NOT NULL,
        port INTEGER NOT NULL,
        algorithm TEXT NOT NULL,
        fingerprint_sha256 TEXT NOT NULL,
        accepted_at INTEGER NOT NULL,
        PRIMARY KEY (host, port, algorithm, fingerprint_sha256)
      );
    ''');
    legacy.execute(
      "INSERT INTO connection_profile_rows VALUES "
      "('legacy', '旧接続先', 'legacy.example.com', 22, 'user', "
      "'passwordOrInteractive', 0, 0);",
    );
    legacy.userVersion = 1;
    legacy.close();

    final database = AppDatabase(NativeDatabase(databaseFile));
    final repository = DriftConnectionProfileRepository(database);
    final restored = await repository.findById('legacy');

    expect(database.schemaVersion, 6);
    expect(restored?.name, '旧接続先');
    expect(restored?.credentialReference, isNull);
    expect(restored?.privateKeyLabel, isNull);
    expect(restored?.wakeOnLan, isNull);
    expect(restored?.connectionType, ConnectionType.ssh);

    await repository.save(
      const ConnectionProfile(
        id: 'private-key',
        name: '鍵認証',
        host: 'key.example.com',
        port: 22,
        username: 'key-user',
        authenticationType: AuthenticationType.privateKey,
        credentialReference: 'vault-reference',
        privateKeyLabel: 'id_ed25519',
        wakeOnLan: WakeOnLanConfiguration(
          macAddress: 'AA:BB:CC:DD:EE:FF',
          broadcastAddress: '10.0.0.255',
          port: 7,
        ),
      ),
    );
    final privateKeyProfile = await repository.findById('private-key');
    expect(privateKeyProfile?.credentialReference, 'vault-reference');
    expect(privateKeyProfile?.privateKeyLabel, 'id_ed25519');
    expect(
      privateKeyProfile?.wakeOnLan,
      const WakeOnLanConfiguration(
        macAddress: 'AA:BB:CC:DD:EE:FF',
        broadcastAddress: '10.0.0.255',
        port: 7,
      ),
    );
    await database.close();
  });

  test('旧接続方式名をRDPへ移行する', () async {
    var database = AppDatabase(NativeDatabase(databaseFile));
    var repository = DriftConnectionProfileRepository(database);
    await repository.save(
      const ConnectionProfile(
        id: 'windows-server',
        name: 'Windowsサーバー',
        host: 'rdp.example.com',
        port: 3389,
        username: 'operator',
        connectionType: ConnectionType.rdp,
      ),
    );
    await database.close();

    final previousDatabase = sqlite.sqlite3.open(databaseFile.path);
    previousDatabase.execute(
      "UPDATE connection_profile_rows SET connection_type = 'rds' "
      "WHERE id = 'windows-server'",
    );
    previousDatabase.userVersion = 4;
    previousDatabase.close();

    database = AppDatabase(NativeDatabase(databaseFile));
    repository = DriftConnectionProfileRepository(database);

    expect(
      (await repository.findById('windows-server'))?.connectionType,
      ConnectionType.rdp,
    );
    await database.close();
  });

  test('DB版が5でも不足列を補い保存済み接続先を維持する', () async {
    final staleDatabase = sqlite.sqlite3.open(databaseFile.path);
    _createVersionOneSchema(staleDatabase);
    staleDatabase.execute(
      "INSERT INTO connection_profile_rows VALUES "
      "('same-app-version', '同一バージョン更新', 'old.example.com', 22, "
      "'operator', 'passwordOrInteractive', 0, 0)",
    );
    staleDatabase.userVersion = 5;
    staleDatabase.close();

    final database = AppDatabase(NativeDatabase(databaseFile));
    final repository = DriftConnectionProfileRepository(database);
    final restored = await repository.findById('same-app-version');

    expect(restored?.name, '同一バージョン更新');
    expect(restored?.connectionType, ConnectionType.ssh);
    expect(restored?.credentialReference, isNull);
    expect(await _columnNames(databaseFile), containsAll(_currentColumns));
    expect(await _userVersion(databaseFile), 6);
    await database.close();
  });

  test('DB版が現行でも不足列を非破壊で修復する', () async {
    final staleDatabase = sqlite.sqlite3.open(databaseFile.path);
    _createVersionOneSchema(staleDatabase);
    staleDatabase.execute(
      "INSERT INTO connection_profile_rows VALUES "
      "('current-db-version', '修復対象', 'repair.example.com', 2222, "
      "'repair-user', 'passwordOrInteractive', 0, 0)",
    );
    staleDatabase.userVersion = 6;
    staleDatabase.close();

    var database = AppDatabase(NativeDatabase(databaseFile));
    var repository = DriftConnectionProfileRepository(database);
    expect((await repository.findById('current-db-version'))?.name, '修復対象');
    await database.close();

    database = AppDatabase(NativeDatabase(databaseFile));
    repository = DriftConnectionProfileRepository(database);
    expect((await repository.findById('current-db-version'))?.name, '修復対象');
    expect(await _columnNames(databaseFile), containsAll(_currentColumns));
    await database.close();
  });
}

const _currentColumns = <String>{
  'credential_reference',
  'private_key_label',
  'wake_on_lan_mac_address',
  'wake_on_lan_broadcast_address',
  'wake_on_lan_port',
  'connection_type',
};

void _createVersionOneSchema(sqlite.Database database) {
  database.execute('''
    CREATE TABLE connection_profile_rows (
      id TEXT NOT NULL PRIMARY KEY,
      name TEXT NOT NULL,
      host TEXT NOT NULL,
      port INTEGER NOT NULL,
      username TEXT NOT NULL,
      authentication_type TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
  ''');
  database.execute('''
    CREATE TABLE known_host_records (
      host TEXT NOT NULL,
      port INTEGER NOT NULL,
      algorithm TEXT NOT NULL,
      fingerprint_sha256 TEXT NOT NULL,
      accepted_at INTEGER NOT NULL,
      PRIMARY KEY (host, port, algorithm, fingerprint_sha256)
    )
  ''');
}

Future<Set<String>> _columnNames(File databaseFile) async {
  final database = sqlite.sqlite3.open(databaseFile.path);
  try {
    return database
        .select("PRAGMA table_info('connection_profile_rows')")
        .map((row) => row['name'] as String)
        .toSet();
  } finally {
    database.close();
  }
}

Future<int> _userVersion(File databaseFile) async {
  final database = sqlite.sqlite3.open(databaseFile.path);
  try {
    return database.userVersion;
  } finally {
    database.close();
  }
}
