import 'dart:io';

import '../../features/diagnostics/domain/connection_diagnostics.dart';

class SocketConnectionReachabilityGateway
    implements ConnectionReachabilityGateway {
  const SocketConnectionReachabilityGateway();

  @override
  Future<List<String>> resolve(String host) async =>
      (await InternetAddress.lookup(host).timeout(
        const Duration(seconds: 5),
      )).map((value) => value.address).toList();

  @override
  Future<void> connect({
    required String host,
    required int port,
    required Duration timeout,
  }) async {
    final socket = await Socket.connect(host, port, timeout: timeout);
    await socket.close();
  }
}
