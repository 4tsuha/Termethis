// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $ConnectionProfileRowsTable extends ConnectionProfileRows
    with TableInfo<$ConnectionProfileRowsTable, ConnectionProfileRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ConnectionProfileRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hostMeta = const VerificationMeta('host');
  @override
  late final GeneratedColumn<String> host = GeneratedColumn<String>(
    'host',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _portMeta = const VerificationMeta('port');
  @override
  late final GeneratedColumn<int> port = GeneratedColumn<int>(
    'port',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _usernameMeta = const VerificationMeta(
    'username',
  );
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
    'username',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _connectionTypeMeta = const VerificationMeta(
    'connectionType',
  );
  @override
  late final GeneratedColumn<String> connectionType = GeneratedColumn<String>(
    'connection_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('ssh'),
  );
  static const VerificationMeta _authenticationTypeMeta =
      const VerificationMeta('authenticationType');
  @override
  late final GeneratedColumn<String> authenticationType =
      GeneratedColumn<String>(
        'authentication_type',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _credentialReferenceMeta =
      const VerificationMeta('credentialReference');
  @override
  late final GeneratedColumn<String> credentialReference =
      GeneratedColumn<String>(
        'credential_reference',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _privateKeyLabelMeta = const VerificationMeta(
    'privateKeyLabel',
  );
  @override
  late final GeneratedColumn<String> privateKeyLabel = GeneratedColumn<String>(
    'private_key_label',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _wakeOnLanMacAddressMeta =
      const VerificationMeta('wakeOnLanMacAddress');
  @override
  late final GeneratedColumn<String> wakeOnLanMacAddress =
      GeneratedColumn<String>(
        'wake_on_lan_mac_address',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _wakeOnLanBroadcastAddressMeta =
      const VerificationMeta('wakeOnLanBroadcastAddress');
  @override
  late final GeneratedColumn<String> wakeOnLanBroadcastAddress =
      GeneratedColumn<String>(
        'wake_on_lan_broadcast_address',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _wakeOnLanPortMeta = const VerificationMeta(
    'wakeOnLanPort',
  );
  @override
  late final GeneratedColumn<int> wakeOnLanPort = GeneratedColumn<int>(
    'wake_on_lan_port',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _remotePathMeta = const VerificationMeta(
    'remotePath',
  );
  @override
  late final GeneratedColumn<String> remotePath = GeneratedColumn<String>(
    'remote_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    host,
    port,
    username,
    connectionType,
    authenticationType,
    credentialReference,
    privateKeyLabel,
    wakeOnLanMacAddress,
    wakeOnLanBroadcastAddress,
    wakeOnLanPort,
    remotePath,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'connection_profile_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<ConnectionProfileRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('host')) {
      context.handle(
        _hostMeta,
        host.isAcceptableOrUnknown(data['host']!, _hostMeta),
      );
    } else if (isInserting) {
      context.missing(_hostMeta);
    }
    if (data.containsKey('port')) {
      context.handle(
        _portMeta,
        port.isAcceptableOrUnknown(data['port']!, _portMeta),
      );
    } else if (isInserting) {
      context.missing(_portMeta);
    }
    if (data.containsKey('username')) {
      context.handle(
        _usernameMeta,
        username.isAcceptableOrUnknown(data['username']!, _usernameMeta),
      );
    } else if (isInserting) {
      context.missing(_usernameMeta);
    }
    if (data.containsKey('connection_type')) {
      context.handle(
        _connectionTypeMeta,
        connectionType.isAcceptableOrUnknown(
          data['connection_type']!,
          _connectionTypeMeta,
        ),
      );
    }
    if (data.containsKey('authentication_type')) {
      context.handle(
        _authenticationTypeMeta,
        authenticationType.isAcceptableOrUnknown(
          data['authentication_type']!,
          _authenticationTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_authenticationTypeMeta);
    }
    if (data.containsKey('credential_reference')) {
      context.handle(
        _credentialReferenceMeta,
        credentialReference.isAcceptableOrUnknown(
          data['credential_reference']!,
          _credentialReferenceMeta,
        ),
      );
    }
    if (data.containsKey('private_key_label')) {
      context.handle(
        _privateKeyLabelMeta,
        privateKeyLabel.isAcceptableOrUnknown(
          data['private_key_label']!,
          _privateKeyLabelMeta,
        ),
      );
    }
    if (data.containsKey('wake_on_lan_mac_address')) {
      context.handle(
        _wakeOnLanMacAddressMeta,
        wakeOnLanMacAddress.isAcceptableOrUnknown(
          data['wake_on_lan_mac_address']!,
          _wakeOnLanMacAddressMeta,
        ),
      );
    }
    if (data.containsKey('wake_on_lan_broadcast_address')) {
      context.handle(
        _wakeOnLanBroadcastAddressMeta,
        wakeOnLanBroadcastAddress.isAcceptableOrUnknown(
          data['wake_on_lan_broadcast_address']!,
          _wakeOnLanBroadcastAddressMeta,
        ),
      );
    }
    if (data.containsKey('wake_on_lan_port')) {
      context.handle(
        _wakeOnLanPortMeta,
        wakeOnLanPort.isAcceptableOrUnknown(
          data['wake_on_lan_port']!,
          _wakeOnLanPortMeta,
        ),
      );
    }
    if (data.containsKey('remote_path')) {
      context.handle(
        _remotePathMeta,
        remotePath.isAcceptableOrUnknown(data['remote_path']!, _remotePathMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ConnectionProfileRecord map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ConnectionProfileRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      host: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host'],
      )!,
      port: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}port'],
      )!,
      username: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}username'],
      )!,
      connectionType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}connection_type'],
      )!,
      authenticationType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}authentication_type'],
      )!,
      credentialReference: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}credential_reference'],
      ),
      privateKeyLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}private_key_label'],
      ),
      wakeOnLanMacAddress: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}wake_on_lan_mac_address'],
      ),
      wakeOnLanBroadcastAddress: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}wake_on_lan_broadcast_address'],
      ),
      wakeOnLanPort: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}wake_on_lan_port'],
      ),
      remotePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remote_path'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ConnectionProfileRowsTable createAlias(String alias) {
    return $ConnectionProfileRowsTable(attachedDatabase, alias);
  }
}

class ConnectionProfileRecord extends DataClass
    implements Insertable<ConnectionProfileRecord> {
  final String id;
  final String name;
  final String host;
  final int port;
  final String username;
  final String connectionType;
  final String authenticationType;
  final String? credentialReference;
  final String? privateKeyLabel;
  final String? wakeOnLanMacAddress;
  final String? wakeOnLanBroadcastAddress;
  final int? wakeOnLanPort;
  final String? remotePath;
  final DateTime createdAt;
  final DateTime updatedAt;
  const ConnectionProfileRecord({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    required this.connectionType,
    required this.authenticationType,
    this.credentialReference,
    this.privateKeyLabel,
    this.wakeOnLanMacAddress,
    this.wakeOnLanBroadcastAddress,
    this.wakeOnLanPort,
    this.remotePath,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['host'] = Variable<String>(host);
    map['port'] = Variable<int>(port);
    map['username'] = Variable<String>(username);
    map['connection_type'] = Variable<String>(connectionType);
    map['authentication_type'] = Variable<String>(authenticationType);
    if (!nullToAbsent || credentialReference != null) {
      map['credential_reference'] = Variable<String>(credentialReference);
    }
    if (!nullToAbsent || privateKeyLabel != null) {
      map['private_key_label'] = Variable<String>(privateKeyLabel);
    }
    if (!nullToAbsent || wakeOnLanMacAddress != null) {
      map['wake_on_lan_mac_address'] = Variable<String>(wakeOnLanMacAddress);
    }
    if (!nullToAbsent || wakeOnLanBroadcastAddress != null) {
      map['wake_on_lan_broadcast_address'] = Variable<String>(
        wakeOnLanBroadcastAddress,
      );
    }
    if (!nullToAbsent || wakeOnLanPort != null) {
      map['wake_on_lan_port'] = Variable<int>(wakeOnLanPort);
    }
    if (!nullToAbsent || remotePath != null) {
      map['remote_path'] = Variable<String>(remotePath);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ConnectionProfileRowsCompanion toCompanion(bool nullToAbsent) {
    return ConnectionProfileRowsCompanion(
      id: Value(id),
      name: Value(name),
      host: Value(host),
      port: Value(port),
      username: Value(username),
      connectionType: Value(connectionType),
      authenticationType: Value(authenticationType),
      credentialReference: credentialReference == null && nullToAbsent
          ? const Value.absent()
          : Value(credentialReference),
      privateKeyLabel: privateKeyLabel == null && nullToAbsent
          ? const Value.absent()
          : Value(privateKeyLabel),
      wakeOnLanMacAddress: wakeOnLanMacAddress == null && nullToAbsent
          ? const Value.absent()
          : Value(wakeOnLanMacAddress),
      wakeOnLanBroadcastAddress:
          wakeOnLanBroadcastAddress == null && nullToAbsent
          ? const Value.absent()
          : Value(wakeOnLanBroadcastAddress),
      wakeOnLanPort: wakeOnLanPort == null && nullToAbsent
          ? const Value.absent()
          : Value(wakeOnLanPort),
      remotePath: remotePath == null && nullToAbsent
          ? const Value.absent()
          : Value(remotePath),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory ConnectionProfileRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ConnectionProfileRecord(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      host: serializer.fromJson<String>(json['host']),
      port: serializer.fromJson<int>(json['port']),
      username: serializer.fromJson<String>(json['username']),
      connectionType: serializer.fromJson<String>(json['connectionType']),
      authenticationType: serializer.fromJson<String>(
        json['authenticationType'],
      ),
      credentialReference: serializer.fromJson<String?>(
        json['credentialReference'],
      ),
      privateKeyLabel: serializer.fromJson<String?>(json['privateKeyLabel']),
      wakeOnLanMacAddress: serializer.fromJson<String?>(
        json['wakeOnLanMacAddress'],
      ),
      wakeOnLanBroadcastAddress: serializer.fromJson<String?>(
        json['wakeOnLanBroadcastAddress'],
      ),
      wakeOnLanPort: serializer.fromJson<int?>(json['wakeOnLanPort']),
      remotePath: serializer.fromJson<String?>(json['remotePath']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'host': serializer.toJson<String>(host),
      'port': serializer.toJson<int>(port),
      'username': serializer.toJson<String>(username),
      'connectionType': serializer.toJson<String>(connectionType),
      'authenticationType': serializer.toJson<String>(authenticationType),
      'credentialReference': serializer.toJson<String?>(credentialReference),
      'privateKeyLabel': serializer.toJson<String?>(privateKeyLabel),
      'wakeOnLanMacAddress': serializer.toJson<String?>(wakeOnLanMacAddress),
      'wakeOnLanBroadcastAddress': serializer.toJson<String?>(
        wakeOnLanBroadcastAddress,
      ),
      'wakeOnLanPort': serializer.toJson<int?>(wakeOnLanPort),
      'remotePath': serializer.toJson<String?>(remotePath),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ConnectionProfileRecord copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    String? username,
    String? connectionType,
    String? authenticationType,
    Value<String?> credentialReference = const Value.absent(),
    Value<String?> privateKeyLabel = const Value.absent(),
    Value<String?> wakeOnLanMacAddress = const Value.absent(),
    Value<String?> wakeOnLanBroadcastAddress = const Value.absent(),
    Value<int?> wakeOnLanPort = const Value.absent(),
    Value<String?> remotePath = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => ConnectionProfileRecord(
    id: id ?? this.id,
    name: name ?? this.name,
    host: host ?? this.host,
    port: port ?? this.port,
    username: username ?? this.username,
    connectionType: connectionType ?? this.connectionType,
    authenticationType: authenticationType ?? this.authenticationType,
    credentialReference: credentialReference.present
        ? credentialReference.value
        : this.credentialReference,
    privateKeyLabel: privateKeyLabel.present
        ? privateKeyLabel.value
        : this.privateKeyLabel,
    wakeOnLanMacAddress: wakeOnLanMacAddress.present
        ? wakeOnLanMacAddress.value
        : this.wakeOnLanMacAddress,
    wakeOnLanBroadcastAddress: wakeOnLanBroadcastAddress.present
        ? wakeOnLanBroadcastAddress.value
        : this.wakeOnLanBroadcastAddress,
    wakeOnLanPort: wakeOnLanPort.present
        ? wakeOnLanPort.value
        : this.wakeOnLanPort,
    remotePath: remotePath.present ? remotePath.value : this.remotePath,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ConnectionProfileRecord copyWithCompanion(
    ConnectionProfileRowsCompanion data,
  ) {
    return ConnectionProfileRecord(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      host: data.host.present ? data.host.value : this.host,
      port: data.port.present ? data.port.value : this.port,
      username: data.username.present ? data.username.value : this.username,
      connectionType: data.connectionType.present
          ? data.connectionType.value
          : this.connectionType,
      authenticationType: data.authenticationType.present
          ? data.authenticationType.value
          : this.authenticationType,
      credentialReference: data.credentialReference.present
          ? data.credentialReference.value
          : this.credentialReference,
      privateKeyLabel: data.privateKeyLabel.present
          ? data.privateKeyLabel.value
          : this.privateKeyLabel,
      wakeOnLanMacAddress: data.wakeOnLanMacAddress.present
          ? data.wakeOnLanMacAddress.value
          : this.wakeOnLanMacAddress,
      wakeOnLanBroadcastAddress: data.wakeOnLanBroadcastAddress.present
          ? data.wakeOnLanBroadcastAddress.value
          : this.wakeOnLanBroadcastAddress,
      wakeOnLanPort: data.wakeOnLanPort.present
          ? data.wakeOnLanPort.value
          : this.wakeOnLanPort,
      remotePath: data.remotePath.present
          ? data.remotePath.value
          : this.remotePath,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ConnectionProfileRecord(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('host: $host, ')
          ..write('port: $port, ')
          ..write('username: $username, ')
          ..write('connectionType: $connectionType, ')
          ..write('authenticationType: $authenticationType, ')
          ..write('credentialReference: $credentialReference, ')
          ..write('privateKeyLabel: $privateKeyLabel, ')
          ..write('wakeOnLanMacAddress: $wakeOnLanMacAddress, ')
          ..write('wakeOnLanBroadcastAddress: $wakeOnLanBroadcastAddress, ')
          ..write('wakeOnLanPort: $wakeOnLanPort, ')
          ..write('remotePath: $remotePath, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    host,
    port,
    username,
    connectionType,
    authenticationType,
    credentialReference,
    privateKeyLabel,
    wakeOnLanMacAddress,
    wakeOnLanBroadcastAddress,
    wakeOnLanPort,
    remotePath,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ConnectionProfileRecord &&
          other.id == this.id &&
          other.name == this.name &&
          other.host == this.host &&
          other.port == this.port &&
          other.username == this.username &&
          other.connectionType == this.connectionType &&
          other.authenticationType == this.authenticationType &&
          other.credentialReference == this.credentialReference &&
          other.privateKeyLabel == this.privateKeyLabel &&
          other.wakeOnLanMacAddress == this.wakeOnLanMacAddress &&
          other.wakeOnLanBroadcastAddress == this.wakeOnLanBroadcastAddress &&
          other.wakeOnLanPort == this.wakeOnLanPort &&
          other.remotePath == this.remotePath &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ConnectionProfileRowsCompanion
    extends UpdateCompanion<ConnectionProfileRecord> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> host;
  final Value<int> port;
  final Value<String> username;
  final Value<String> connectionType;
  final Value<String> authenticationType;
  final Value<String?> credentialReference;
  final Value<String?> privateKeyLabel;
  final Value<String?> wakeOnLanMacAddress;
  final Value<String?> wakeOnLanBroadcastAddress;
  final Value<int?> wakeOnLanPort;
  final Value<String?> remotePath;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ConnectionProfileRowsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.host = const Value.absent(),
    this.port = const Value.absent(),
    this.username = const Value.absent(),
    this.connectionType = const Value.absent(),
    this.authenticationType = const Value.absent(),
    this.credentialReference = const Value.absent(),
    this.privateKeyLabel = const Value.absent(),
    this.wakeOnLanMacAddress = const Value.absent(),
    this.wakeOnLanBroadcastAddress = const Value.absent(),
    this.wakeOnLanPort = const Value.absent(),
    this.remotePath = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ConnectionProfileRowsCompanion.insert({
    required String id,
    required String name,
    required String host,
    required int port,
    required String username,
    this.connectionType = const Value.absent(),
    required String authenticationType,
    this.credentialReference = const Value.absent(),
    this.privateKeyLabel = const Value.absent(),
    this.wakeOnLanMacAddress = const Value.absent(),
    this.wakeOnLanBroadcastAddress = const Value.absent(),
    this.wakeOnLanPort = const Value.absent(),
    this.remotePath = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       host = Value(host),
       port = Value(port),
       username = Value(username),
       authenticationType = Value(authenticationType),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<ConnectionProfileRecord> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? host,
    Expression<int>? port,
    Expression<String>? username,
    Expression<String>? connectionType,
    Expression<String>? authenticationType,
    Expression<String>? credentialReference,
    Expression<String>? privateKeyLabel,
    Expression<String>? wakeOnLanMacAddress,
    Expression<String>? wakeOnLanBroadcastAddress,
    Expression<int>? wakeOnLanPort,
    Expression<String>? remotePath,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (host != null) 'host': host,
      if (port != null) 'port': port,
      if (username != null) 'username': username,
      if (connectionType != null) 'connection_type': connectionType,
      if (authenticationType != null) 'authentication_type': authenticationType,
      if (credentialReference != null)
        'credential_reference': credentialReference,
      if (privateKeyLabel != null) 'private_key_label': privateKeyLabel,
      if (wakeOnLanMacAddress != null)
        'wake_on_lan_mac_address': wakeOnLanMacAddress,
      if (wakeOnLanBroadcastAddress != null)
        'wake_on_lan_broadcast_address': wakeOnLanBroadcastAddress,
      if (wakeOnLanPort != null) 'wake_on_lan_port': wakeOnLanPort,
      if (remotePath != null) 'remote_path': remotePath,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ConnectionProfileRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? host,
    Value<int>? port,
    Value<String>? username,
    Value<String>? connectionType,
    Value<String>? authenticationType,
    Value<String?>? credentialReference,
    Value<String?>? privateKeyLabel,
    Value<String?>? wakeOnLanMacAddress,
    Value<String?>? wakeOnLanBroadcastAddress,
    Value<int?>? wakeOnLanPort,
    Value<String?>? remotePath,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ConnectionProfileRowsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      connectionType: connectionType ?? this.connectionType,
      authenticationType: authenticationType ?? this.authenticationType,
      credentialReference: credentialReference ?? this.credentialReference,
      privateKeyLabel: privateKeyLabel ?? this.privateKeyLabel,
      wakeOnLanMacAddress: wakeOnLanMacAddress ?? this.wakeOnLanMacAddress,
      wakeOnLanBroadcastAddress:
          wakeOnLanBroadcastAddress ?? this.wakeOnLanBroadcastAddress,
      wakeOnLanPort: wakeOnLanPort ?? this.wakeOnLanPort,
      remotePath: remotePath ?? this.remotePath,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (host.present) {
      map['host'] = Variable<String>(host.value);
    }
    if (port.present) {
      map['port'] = Variable<int>(port.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (connectionType.present) {
      map['connection_type'] = Variable<String>(connectionType.value);
    }
    if (authenticationType.present) {
      map['authentication_type'] = Variable<String>(authenticationType.value);
    }
    if (credentialReference.present) {
      map['credential_reference'] = Variable<String>(credentialReference.value);
    }
    if (privateKeyLabel.present) {
      map['private_key_label'] = Variable<String>(privateKeyLabel.value);
    }
    if (wakeOnLanMacAddress.present) {
      map['wake_on_lan_mac_address'] = Variable<String>(
        wakeOnLanMacAddress.value,
      );
    }
    if (wakeOnLanBroadcastAddress.present) {
      map['wake_on_lan_broadcast_address'] = Variable<String>(
        wakeOnLanBroadcastAddress.value,
      );
    }
    if (wakeOnLanPort.present) {
      map['wake_on_lan_port'] = Variable<int>(wakeOnLanPort.value);
    }
    if (remotePath.present) {
      map['remote_path'] = Variable<String>(remotePath.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ConnectionProfileRowsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('host: $host, ')
          ..write('port: $port, ')
          ..write('username: $username, ')
          ..write('connectionType: $connectionType, ')
          ..write('authenticationType: $authenticationType, ')
          ..write('credentialReference: $credentialReference, ')
          ..write('privateKeyLabel: $privateKeyLabel, ')
          ..write('wakeOnLanMacAddress: $wakeOnLanMacAddress, ')
          ..write('wakeOnLanBroadcastAddress: $wakeOnLanBroadcastAddress, ')
          ..write('wakeOnLanPort: $wakeOnLanPort, ')
          ..write('remotePath: $remotePath, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $KnownHostRecordsTable extends KnownHostRecords
    with TableInfo<$KnownHostRecordsTable, KnownHostRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $KnownHostRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _hostMeta = const VerificationMeta('host');
  @override
  late final GeneratedColumn<String> host = GeneratedColumn<String>(
    'host',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _portMeta = const VerificationMeta('port');
  @override
  late final GeneratedColumn<int> port = GeneratedColumn<int>(
    'port',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _algorithmMeta = const VerificationMeta(
    'algorithm',
  );
  @override
  late final GeneratedColumn<String> algorithm = GeneratedColumn<String>(
    'algorithm',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fingerprintSha256Meta = const VerificationMeta(
    'fingerprintSha256',
  );
  @override
  late final GeneratedColumn<String> fingerprintSha256 =
      GeneratedColumn<String>(
        'fingerprint_sha256',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _acceptedAtMeta = const VerificationMeta(
    'acceptedAt',
  );
  @override
  late final GeneratedColumn<DateTime> acceptedAt = GeneratedColumn<DateTime>(
    'accepted_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    host,
    port,
    algorithm,
    fingerprintSha256,
    acceptedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'known_host_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<KnownHostRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('host')) {
      context.handle(
        _hostMeta,
        host.isAcceptableOrUnknown(data['host']!, _hostMeta),
      );
    } else if (isInserting) {
      context.missing(_hostMeta);
    }
    if (data.containsKey('port')) {
      context.handle(
        _portMeta,
        port.isAcceptableOrUnknown(data['port']!, _portMeta),
      );
    } else if (isInserting) {
      context.missing(_portMeta);
    }
    if (data.containsKey('algorithm')) {
      context.handle(
        _algorithmMeta,
        algorithm.isAcceptableOrUnknown(data['algorithm']!, _algorithmMeta),
      );
    } else if (isInserting) {
      context.missing(_algorithmMeta);
    }
    if (data.containsKey('fingerprint_sha256')) {
      context.handle(
        _fingerprintSha256Meta,
        fingerprintSha256.isAcceptableOrUnknown(
          data['fingerprint_sha256']!,
          _fingerprintSha256Meta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fingerprintSha256Meta);
    }
    if (data.containsKey('accepted_at')) {
      context.handle(
        _acceptedAtMeta,
        acceptedAt.isAcceptableOrUnknown(data['accepted_at']!, _acceptedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_acceptedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {
    host,
    port,
    algorithm,
    fingerprintSha256,
  };
  @override
  KnownHostRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return KnownHostRecord(
      host: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host'],
      )!,
      port: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}port'],
      )!,
      algorithm: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}algorithm'],
      )!,
      fingerprintSha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fingerprint_sha256'],
      )!,
      acceptedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}accepted_at'],
      )!,
    );
  }

  @override
  $KnownHostRecordsTable createAlias(String alias) {
    return $KnownHostRecordsTable(attachedDatabase, alias);
  }
}

class KnownHostRecord extends DataClass implements Insertable<KnownHostRecord> {
  final String host;
  final int port;
  final String algorithm;
  final String fingerprintSha256;
  final DateTime acceptedAt;
  const KnownHostRecord({
    required this.host,
    required this.port,
    required this.algorithm,
    required this.fingerprintSha256,
    required this.acceptedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['host'] = Variable<String>(host);
    map['port'] = Variable<int>(port);
    map['algorithm'] = Variable<String>(algorithm);
    map['fingerprint_sha256'] = Variable<String>(fingerprintSha256);
    map['accepted_at'] = Variable<DateTime>(acceptedAt);
    return map;
  }

  KnownHostRecordsCompanion toCompanion(bool nullToAbsent) {
    return KnownHostRecordsCompanion(
      host: Value(host),
      port: Value(port),
      algorithm: Value(algorithm),
      fingerprintSha256: Value(fingerprintSha256),
      acceptedAt: Value(acceptedAt),
    );
  }

  factory KnownHostRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return KnownHostRecord(
      host: serializer.fromJson<String>(json['host']),
      port: serializer.fromJson<int>(json['port']),
      algorithm: serializer.fromJson<String>(json['algorithm']),
      fingerprintSha256: serializer.fromJson<String>(json['fingerprintSha256']),
      acceptedAt: serializer.fromJson<DateTime>(json['acceptedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'host': serializer.toJson<String>(host),
      'port': serializer.toJson<int>(port),
      'algorithm': serializer.toJson<String>(algorithm),
      'fingerprintSha256': serializer.toJson<String>(fingerprintSha256),
      'acceptedAt': serializer.toJson<DateTime>(acceptedAt),
    };
  }

  KnownHostRecord copyWith({
    String? host,
    int? port,
    String? algorithm,
    String? fingerprintSha256,
    DateTime? acceptedAt,
  }) => KnownHostRecord(
    host: host ?? this.host,
    port: port ?? this.port,
    algorithm: algorithm ?? this.algorithm,
    fingerprintSha256: fingerprintSha256 ?? this.fingerprintSha256,
    acceptedAt: acceptedAt ?? this.acceptedAt,
  );
  KnownHostRecord copyWithCompanion(KnownHostRecordsCompanion data) {
    return KnownHostRecord(
      host: data.host.present ? data.host.value : this.host,
      port: data.port.present ? data.port.value : this.port,
      algorithm: data.algorithm.present ? data.algorithm.value : this.algorithm,
      fingerprintSha256: data.fingerprintSha256.present
          ? data.fingerprintSha256.value
          : this.fingerprintSha256,
      acceptedAt: data.acceptedAt.present
          ? data.acceptedAt.value
          : this.acceptedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('KnownHostRecord(')
          ..write('host: $host, ')
          ..write('port: $port, ')
          ..write('algorithm: $algorithm, ')
          ..write('fingerprintSha256: $fingerprintSha256, ')
          ..write('acceptedAt: $acceptedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(host, port, algorithm, fingerprintSha256, acceptedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is KnownHostRecord &&
          other.host == this.host &&
          other.port == this.port &&
          other.algorithm == this.algorithm &&
          other.fingerprintSha256 == this.fingerprintSha256 &&
          other.acceptedAt == this.acceptedAt);
}

class KnownHostRecordsCompanion extends UpdateCompanion<KnownHostRecord> {
  final Value<String> host;
  final Value<int> port;
  final Value<String> algorithm;
  final Value<String> fingerprintSha256;
  final Value<DateTime> acceptedAt;
  final Value<int> rowid;
  const KnownHostRecordsCompanion({
    this.host = const Value.absent(),
    this.port = const Value.absent(),
    this.algorithm = const Value.absent(),
    this.fingerprintSha256 = const Value.absent(),
    this.acceptedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  KnownHostRecordsCompanion.insert({
    required String host,
    required int port,
    required String algorithm,
    required String fingerprintSha256,
    required DateTime acceptedAt,
    this.rowid = const Value.absent(),
  }) : host = Value(host),
       port = Value(port),
       algorithm = Value(algorithm),
       fingerprintSha256 = Value(fingerprintSha256),
       acceptedAt = Value(acceptedAt);
  static Insertable<KnownHostRecord> custom({
    Expression<String>? host,
    Expression<int>? port,
    Expression<String>? algorithm,
    Expression<String>? fingerprintSha256,
    Expression<DateTime>? acceptedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (host != null) 'host': host,
      if (port != null) 'port': port,
      if (algorithm != null) 'algorithm': algorithm,
      if (fingerprintSha256 != null) 'fingerprint_sha256': fingerprintSha256,
      if (acceptedAt != null) 'accepted_at': acceptedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  KnownHostRecordsCompanion copyWith({
    Value<String>? host,
    Value<int>? port,
    Value<String>? algorithm,
    Value<String>? fingerprintSha256,
    Value<DateTime>? acceptedAt,
    Value<int>? rowid,
  }) {
    return KnownHostRecordsCompanion(
      host: host ?? this.host,
      port: port ?? this.port,
      algorithm: algorithm ?? this.algorithm,
      fingerprintSha256: fingerprintSha256 ?? this.fingerprintSha256,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (host.present) {
      map['host'] = Variable<String>(host.value);
    }
    if (port.present) {
      map['port'] = Variable<int>(port.value);
    }
    if (algorithm.present) {
      map['algorithm'] = Variable<String>(algorithm.value);
    }
    if (fingerprintSha256.present) {
      map['fingerprint_sha256'] = Variable<String>(fingerprintSha256.value);
    }
    if (acceptedAt.present) {
      map['accepted_at'] = Variable<DateTime>(acceptedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('KnownHostRecordsCompanion(')
          ..write('host: $host, ')
          ..write('port: $port, ')
          ..write('algorithm: $algorithm, ')
          ..write('fingerprintSha256: $fingerprintSha256, ')
          ..write('acceptedAt: $acceptedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ConnectionProfileRowsTable connectionProfileRows =
      $ConnectionProfileRowsTable(this);
  late final $KnownHostRecordsTable knownHostRecords = $KnownHostRecordsTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    connectionProfileRows,
    knownHostRecords,
  ];
}

typedef $$ConnectionProfileRowsTableCreateCompanionBuilder =
    ConnectionProfileRowsCompanion Function({
      required String id,
      required String name,
      required String host,
      required int port,
      required String username,
      Value<String> connectionType,
      required String authenticationType,
      Value<String?> credentialReference,
      Value<String?> privateKeyLabel,
      Value<String?> wakeOnLanMacAddress,
      Value<String?> wakeOnLanBroadcastAddress,
      Value<int?> wakeOnLanPort,
      Value<String?> remotePath,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$ConnectionProfileRowsTableUpdateCompanionBuilder =
    ConnectionProfileRowsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> host,
      Value<int> port,
      Value<String> username,
      Value<String> connectionType,
      Value<String> authenticationType,
      Value<String?> credentialReference,
      Value<String?> privateKeyLabel,
      Value<String?> wakeOnLanMacAddress,
      Value<String?> wakeOnLanBroadcastAddress,
      Value<int?> wakeOnLanPort,
      Value<String?> remotePath,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$ConnectionProfileRowsTableFilterComposer
    extends Composer<_$AppDatabase, $ConnectionProfileRowsTable> {
  $$ConnectionProfileRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get host => $composableBuilder(
    column: $table.host,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get port => $composableBuilder(
    column: $table.port,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get connectionType => $composableBuilder(
    column: $table.connectionType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get authenticationType => $composableBuilder(
    column: $table.authenticationType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get credentialReference => $composableBuilder(
    column: $table.credentialReference,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get privateKeyLabel => $composableBuilder(
    column: $table.privateKeyLabel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get wakeOnLanMacAddress => $composableBuilder(
    column: $table.wakeOnLanMacAddress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get wakeOnLanBroadcastAddress => $composableBuilder(
    column: $table.wakeOnLanBroadcastAddress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get wakeOnLanPort => $composableBuilder(
    column: $table.wakeOnLanPort,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get remotePath => $composableBuilder(
    column: $table.remotePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ConnectionProfileRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $ConnectionProfileRowsTable> {
  $$ConnectionProfileRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get host => $composableBuilder(
    column: $table.host,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get port => $composableBuilder(
    column: $table.port,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get connectionType => $composableBuilder(
    column: $table.connectionType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get authenticationType => $composableBuilder(
    column: $table.authenticationType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get credentialReference => $composableBuilder(
    column: $table.credentialReference,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get privateKeyLabel => $composableBuilder(
    column: $table.privateKeyLabel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get wakeOnLanMacAddress => $composableBuilder(
    column: $table.wakeOnLanMacAddress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get wakeOnLanBroadcastAddress => $composableBuilder(
    column: $table.wakeOnLanBroadcastAddress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get wakeOnLanPort => $composableBuilder(
    column: $table.wakeOnLanPort,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get remotePath => $composableBuilder(
    column: $table.remotePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ConnectionProfileRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ConnectionProfileRowsTable> {
  $$ConnectionProfileRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get host =>
      $composableBuilder(column: $table.host, builder: (column) => column);

  GeneratedColumn<int> get port =>
      $composableBuilder(column: $table.port, builder: (column) => column);

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<String> get connectionType => $composableBuilder(
    column: $table.connectionType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get authenticationType => $composableBuilder(
    column: $table.authenticationType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get credentialReference => $composableBuilder(
    column: $table.credentialReference,
    builder: (column) => column,
  );

  GeneratedColumn<String> get privateKeyLabel => $composableBuilder(
    column: $table.privateKeyLabel,
    builder: (column) => column,
  );

  GeneratedColumn<String> get wakeOnLanMacAddress => $composableBuilder(
    column: $table.wakeOnLanMacAddress,
    builder: (column) => column,
  );

  GeneratedColumn<String> get wakeOnLanBroadcastAddress => $composableBuilder(
    column: $table.wakeOnLanBroadcastAddress,
    builder: (column) => column,
  );

  GeneratedColumn<int> get wakeOnLanPort => $composableBuilder(
    column: $table.wakeOnLanPort,
    builder: (column) => column,
  );

  GeneratedColumn<String> get remotePath => $composableBuilder(
    column: $table.remotePath,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ConnectionProfileRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ConnectionProfileRowsTable,
          ConnectionProfileRecord,
          $$ConnectionProfileRowsTableFilterComposer,
          $$ConnectionProfileRowsTableOrderingComposer,
          $$ConnectionProfileRowsTableAnnotationComposer,
          $$ConnectionProfileRowsTableCreateCompanionBuilder,
          $$ConnectionProfileRowsTableUpdateCompanionBuilder,
          (
            ConnectionProfileRecord,
            BaseReferences<
              _$AppDatabase,
              $ConnectionProfileRowsTable,
              ConnectionProfileRecord
            >,
          ),
          ConnectionProfileRecord,
          PrefetchHooks Function()
        > {
  $$ConnectionProfileRowsTableTableManager(
    _$AppDatabase db,
    $ConnectionProfileRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ConnectionProfileRowsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$ConnectionProfileRowsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ConnectionProfileRowsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> host = const Value.absent(),
                Value<int> port = const Value.absent(),
                Value<String> username = const Value.absent(),
                Value<String> connectionType = const Value.absent(),
                Value<String> authenticationType = const Value.absent(),
                Value<String?> credentialReference = const Value.absent(),
                Value<String?> privateKeyLabel = const Value.absent(),
                Value<String?> wakeOnLanMacAddress = const Value.absent(),
                Value<String?> wakeOnLanBroadcastAddress = const Value.absent(),
                Value<int?> wakeOnLanPort = const Value.absent(),
                Value<String?> remotePath = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ConnectionProfileRowsCompanion(
                id: id,
                name: name,
                host: host,
                port: port,
                username: username,
                connectionType: connectionType,
                authenticationType: authenticationType,
                credentialReference: credentialReference,
                privateKeyLabel: privateKeyLabel,
                wakeOnLanMacAddress: wakeOnLanMacAddress,
                wakeOnLanBroadcastAddress: wakeOnLanBroadcastAddress,
                wakeOnLanPort: wakeOnLanPort,
                remotePath: remotePath,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String host,
                required int port,
                required String username,
                Value<String> connectionType = const Value.absent(),
                required String authenticationType,
                Value<String?> credentialReference = const Value.absent(),
                Value<String?> privateKeyLabel = const Value.absent(),
                Value<String?> wakeOnLanMacAddress = const Value.absent(),
                Value<String?> wakeOnLanBroadcastAddress = const Value.absent(),
                Value<int?> wakeOnLanPort = const Value.absent(),
                Value<String?> remotePath = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ConnectionProfileRowsCompanion.insert(
                id: id,
                name: name,
                host: host,
                port: port,
                username: username,
                connectionType: connectionType,
                authenticationType: authenticationType,
                credentialReference: credentialReference,
                privateKeyLabel: privateKeyLabel,
                wakeOnLanMacAddress: wakeOnLanMacAddress,
                wakeOnLanBroadcastAddress: wakeOnLanBroadcastAddress,
                wakeOnLanPort: wakeOnLanPort,
                remotePath: remotePath,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ConnectionProfileRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ConnectionProfileRowsTable,
      ConnectionProfileRecord,
      $$ConnectionProfileRowsTableFilterComposer,
      $$ConnectionProfileRowsTableOrderingComposer,
      $$ConnectionProfileRowsTableAnnotationComposer,
      $$ConnectionProfileRowsTableCreateCompanionBuilder,
      $$ConnectionProfileRowsTableUpdateCompanionBuilder,
      (
        ConnectionProfileRecord,
        BaseReferences<
          _$AppDatabase,
          $ConnectionProfileRowsTable,
          ConnectionProfileRecord
        >,
      ),
      ConnectionProfileRecord,
      PrefetchHooks Function()
    >;
typedef $$KnownHostRecordsTableCreateCompanionBuilder =
    KnownHostRecordsCompanion Function({
      required String host,
      required int port,
      required String algorithm,
      required String fingerprintSha256,
      required DateTime acceptedAt,
      Value<int> rowid,
    });
typedef $$KnownHostRecordsTableUpdateCompanionBuilder =
    KnownHostRecordsCompanion Function({
      Value<String> host,
      Value<int> port,
      Value<String> algorithm,
      Value<String> fingerprintSha256,
      Value<DateTime> acceptedAt,
      Value<int> rowid,
    });

class $$KnownHostRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $KnownHostRecordsTable> {
  $$KnownHostRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get host => $composableBuilder(
    column: $table.host,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get port => $composableBuilder(
    column: $table.port,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get algorithm => $composableBuilder(
    column: $table.algorithm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fingerprintSha256 => $composableBuilder(
    column: $table.fingerprintSha256,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get acceptedAt => $composableBuilder(
    column: $table.acceptedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$KnownHostRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $KnownHostRecordsTable> {
  $$KnownHostRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get host => $composableBuilder(
    column: $table.host,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get port => $composableBuilder(
    column: $table.port,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get algorithm => $composableBuilder(
    column: $table.algorithm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fingerprintSha256 => $composableBuilder(
    column: $table.fingerprintSha256,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get acceptedAt => $composableBuilder(
    column: $table.acceptedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$KnownHostRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $KnownHostRecordsTable> {
  $$KnownHostRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get host =>
      $composableBuilder(column: $table.host, builder: (column) => column);

  GeneratedColumn<int> get port =>
      $composableBuilder(column: $table.port, builder: (column) => column);

  GeneratedColumn<String> get algorithm =>
      $composableBuilder(column: $table.algorithm, builder: (column) => column);

  GeneratedColumn<String> get fingerprintSha256 => $composableBuilder(
    column: $table.fingerprintSha256,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get acceptedAt => $composableBuilder(
    column: $table.acceptedAt,
    builder: (column) => column,
  );
}

class $$KnownHostRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $KnownHostRecordsTable,
          KnownHostRecord,
          $$KnownHostRecordsTableFilterComposer,
          $$KnownHostRecordsTableOrderingComposer,
          $$KnownHostRecordsTableAnnotationComposer,
          $$KnownHostRecordsTableCreateCompanionBuilder,
          $$KnownHostRecordsTableUpdateCompanionBuilder,
          (
            KnownHostRecord,
            BaseReferences<
              _$AppDatabase,
              $KnownHostRecordsTable,
              KnownHostRecord
            >,
          ),
          KnownHostRecord,
          PrefetchHooks Function()
        > {
  $$KnownHostRecordsTableTableManager(
    _$AppDatabase db,
    $KnownHostRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$KnownHostRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$KnownHostRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$KnownHostRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> host = const Value.absent(),
                Value<int> port = const Value.absent(),
                Value<String> algorithm = const Value.absent(),
                Value<String> fingerprintSha256 = const Value.absent(),
                Value<DateTime> acceptedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => KnownHostRecordsCompanion(
                host: host,
                port: port,
                algorithm: algorithm,
                fingerprintSha256: fingerprintSha256,
                acceptedAt: acceptedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String host,
                required int port,
                required String algorithm,
                required String fingerprintSha256,
                required DateTime acceptedAt,
                Value<int> rowid = const Value.absent(),
              }) => KnownHostRecordsCompanion.insert(
                host: host,
                port: port,
                algorithm: algorithm,
                fingerprintSha256: fingerprintSha256,
                acceptedAt: acceptedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$KnownHostRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $KnownHostRecordsTable,
      KnownHostRecord,
      $$KnownHostRecordsTableFilterComposer,
      $$KnownHostRecordsTableOrderingComposer,
      $$KnownHostRecordsTableAnnotationComposer,
      $$KnownHostRecordsTableCreateCompanionBuilder,
      $$KnownHostRecordsTableUpdateCompanionBuilder,
      (
        KnownHostRecord,
        BaseReferences<_$AppDatabase, $KnownHostRecordsTable, KnownHostRecord>,
      ),
      KnownHostRecord,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ConnectionProfileRowsTableTableManager get connectionProfileRows =>
      $$ConnectionProfileRowsTableTableManager(_db, _db.connectionProfileRows);
  $$KnownHostRecordsTableTableManager get knownHostRecords =>
      $$KnownHostRecordsTableTableManager(_db, _db.knownHostRecords);
}
