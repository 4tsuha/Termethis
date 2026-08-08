import '../../features/terminal/domain/ssh_gateway.dart';

class InMemoryHostKeyRepository implements HostKeyRepository {
  final Map<String, KnownHost> _hosts = {};

  String _key(String host, int port) => '${host.toLowerCase()}:$port';

  @override
  Future<KnownHost?> find(String host, int port) async {
    return _hosts[_key(host, port)];
  }

  @override
  Future<void> trust(KnownHost host) async {
    _hosts[_key(host.info.host, host.info.port)] = host;
  }

  @override
  Future<void> remove(String host, int port) async {
    _hosts.remove(_key(host, port));
  }
}
