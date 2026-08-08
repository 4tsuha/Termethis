import '../../wake_on_lan/domain/wake_on_lan.dart';

enum AuthenticationType { passwordOrInteractive, privateKey }

class ConnectionProfile {
  const ConnectionProfile({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.username,
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
  final AuthenticationType authenticationType;
  final String? credentialReference;
  final String? privateKeyLabel;
  final WakeOnLanConfiguration? wakeOnLan;

  String get target => '$username@$host:$port';

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
    authenticationType,
    credentialReference,
    privateKeyLabel,
    wakeOnLan,
  );
}
