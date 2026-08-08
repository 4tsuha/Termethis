enum AuthenticationType { passwordOrInteractive }

class ConnectionProfile {
  const ConnectionProfile({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    this.authenticationType = AuthenticationType.passwordOrInteractive,
  });

  final String id;
  final String name;
  final String host;
  final int port;
  final String username;
  final AuthenticationType authenticationType;

  String get target => '$username@$host:$port';
}
