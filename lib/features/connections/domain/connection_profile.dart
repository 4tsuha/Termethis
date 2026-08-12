import '../../wake_on_lan/domain/wake_on_lan.dart';

enum AuthenticationType { passwordOrInteractive, privateKey }

enum ConnectionType {
  ssh(defaultPort: 22),
  mosh(defaultPort: 22),
  rdp(defaultPort: 3389),
  vnc(defaultPort: 5900);

  const ConnectionType({required this.defaultPort});

  final int defaultPort;

  bool get usesSshAuthentication =>
      this == ConnectionType.ssh || this == ConnectionType.mosh;
}

class ConnectionProfile {
  const ConnectionProfile({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    this.connectionType = ConnectionType.ssh,
    this.authenticationType = AuthenticationType.passwordOrInteractive,
    this.credentialReference,
    this.privateKeyLabel,
    this.wakeOnLan,
  });

  final String id;
  final String name;
  final String host;
  final int port;
  final String username;
  final ConnectionType connectionType;
  final AuthenticationType authenticationType;
  final String? credentialReference;
  final String? privateKeyLabel;
  final WakeOnLanConfiguration? wakeOnLan;

  String get target {
    final endpoint = '$host:$port';
    if (username.isEmpty) return endpoint;
    return connectionType.usesSshAuthentication
        ? '$username@$endpoint'
        : '$username · $endpoint';
  }

  ConnectionProfile withCredential({
    required String? credentialReference,
    required String? privateKeyLabel,
  }) {
    return ConnectionProfile(
      id: id,
      name: name,
      host: host,
      port: port,
      username: username,
      connectionType: connectionType,
      authenticationType: authenticationType,
      credentialReference: credentialReference,
      privateKeyLabel: privateKeyLabel,
      wakeOnLan: wakeOnLan,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ConnectionProfile &&
        other.id == id &&
        other.name == name &&
        other.host == host &&
        other.port == port &&
        other.username == username &&
        other.connectionType == connectionType &&
        other.authenticationType == authenticationType &&
        other.credentialReference == credentialReference &&
        other.privateKeyLabel == privateKeyLabel &&
        other.wakeOnLan == wakeOnLan;
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
    wakeOnLan,
  );
}
