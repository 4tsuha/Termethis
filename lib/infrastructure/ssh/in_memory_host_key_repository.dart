import '../../features/terminal/domain/ssh_gateway.dart';

class InMemoryHostKeyRepository implements HostKeyRepository {
  final Map<String, List<KnownHost>> _hosts = {};

  String _key(String host, int port) => '${normalizeSshHost(host)}:$port';

  @override
  Future<List<KnownHost>> listAll() async {
    final hosts = _hosts.values.expand((items) => items).toList(growable: false)
      ..sort((left, right) {
        final hostOrder = left.info.host.compareTo(right.info.host);
        if (hostOrder != 0) return hostOrder;
        return left.info.port.compareTo(right.info.port);
      });
    return List.unmodifiable(hosts);
  }

  @override
  Future<List<KnownHost>> find(String host, int port) async {
    return List.unmodifiable(_hosts[_key(host, port)] ?? const []);
  }

  @override
  Future<void> trust(KnownHost host) async {
    final hosts = _hosts.putIfAbsent(
      _key(host.info.host, host.info.port),
      () => [],
    );
    final alreadyTrusted = hosts.any(
      (item) =>
          item.info.algorithm == host.info.algorithm &&
          item.info.fingerprintSha256 == host.info.fingerprintSha256,
    );
    if (!alreadyTrusted) {
      hosts.add(host);
    }
  }

  @override
  Future<void> remove(String host, int port) async {
    _hosts.remove(_key(host, port));
  }
}
