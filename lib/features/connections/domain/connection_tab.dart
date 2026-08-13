import 'connection_profile.dart';

enum ConnectionProtocol { ssh, mosh, rdp, vnc, opencode, shizukuShell }

enum ConnectionTabState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  failed,
}

enum ConnectionTabRestorePolicy { manual }

class ConnectionTab {
  const ConnectionTab({
    required this.id,
    required this.profileId,
    required this.protocol,
    required this.title,
    required this.createdAt,
    required this.lastActivatedAt,
    this.connectionState = ConnectionTabState.disconnected,
    this.restorePolicy = ConnectionTabRestorePolicy.manual,
    this.restored = false,
  });

  final String id;
  final String? profileId;
  final ConnectionProtocol protocol;
  final String title;
  final DateTime createdAt;
  final DateTime lastActivatedAt;
  final ConnectionTabState connectionState;
  final ConnectionTabRestorePolicy restorePolicy;
  final bool restored;

  bool get isTerminal => switch (protocol) {
    ConnectionProtocol.ssh ||
    ConnectionProtocol.mosh ||
    ConnectionProtocol.shizukuShell => true,
    ConnectionProtocol.rdp ||
    ConnectionProtocol.vnc ||
    ConnectionProtocol.opencode => false,
  };

  ConnectionTab copyWith({
    String? title,
    DateTime? lastActivatedAt,
    ConnectionTabState? connectionState,
    bool? restored,
  }) => ConnectionTab(
    id: id,
    profileId: profileId,
    protocol: protocol,
    title: title ?? this.title,
    createdAt: createdAt,
    lastActivatedAt: lastActivatedAt ?? this.lastActivatedAt,
    connectionState: connectionState ?? this.connectionState,
    restorePolicy: restorePolicy,
    restored: restored ?? this.restored,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'profileId': profileId,
    'protocol': protocol.name,
    'title': title,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'lastActivatedAt': lastActivatedAt.toUtc().toIso8601String(),
    'restorePolicy': restorePolicy.name,
  };

  static ConnectionTab? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final title = value['title'];
    final protocolName = value['protocol'];
    final createdAt = DateTime.tryParse('${value['createdAt'] ?? ''}');
    final lastActivatedAt = DateTime.tryParse(
      '${value['lastActivatedAt'] ?? ''}',
    );
    if (id is! String || title is! String || protocolName is! String) {
      return null;
    }
    final protocol = ConnectionProtocol.values
        .where((item) => item.name == protocolName)
        .firstOrNull;
    if (protocol == null) return null;
    return ConnectionTab(
      id: id,
      profileId: value['profileId'] is String
          ? value['profileId'] as String
          : null,
      protocol: protocol,
      title: title,
      createdAt:
          createdAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      lastActivatedAt:
          lastActivatedAt ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      restored: true,
    );
  }

  static ConnectionProtocol protocolFor(ConnectionProfile profile) =>
      switch (profile.connectionType) {
        ConnectionType.ssh => ConnectionProtocol.ssh,
        ConnectionType.mosh => ConnectionProtocol.mosh,
        ConnectionType.rdp => ConnectionProtocol.rdp,
        ConnectionType.vnc => ConnectionProtocol.vnc,
        ConnectionType.opencode => ConnectionProtocol.opencode,
      };
}

abstract interface class ConnectionTabStore {
  Future<List<ConnectionTab>> load();
  Future<void> save(List<ConnectionTab> tabs);
}

class EphemeralConnectionTabStore implements ConnectionTabStore {
  EphemeralConnectionTabStore([List<ConnectionTab> initialTabs = const []])
    : _tabs = List.unmodifiable(initialTabs);

  List<ConnectionTab> _tabs;

  @override
  Future<List<ConnectionTab>> load() async => [
    for (final tab in _tabs) tab.copyWith(restored: true),
  ];

  @override
  Future<void> save(List<ConnectionTab> tabs) async {
    _tabs = List.unmodifiable(tabs);
  }
}
