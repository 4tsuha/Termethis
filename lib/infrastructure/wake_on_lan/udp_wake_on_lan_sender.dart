import 'dart:io';

import '../../features/wake_on_lan/domain/wake_on_lan.dart';

class UdpWakeOnLanSender implements WakeOnLanSender {
  const UdpWakeOnLanSender();

  @override
  Future<void> send(WakeOnLanConfiguration configuration) async {
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      final destination = InternetAddress(configuration.broadcastAddress);
      final packet = buildMagicPacket(configuration.macBytes);
      final sent = socket.send(packet, destination, configuration.port);
      if (sent != packet.length) {
        throw const WakeOnLanFailure();
      }
    } on WakeOnLanFailure {
      rethrow;
    } catch (error) {
      throw WakeOnLanFailure(error);
    } finally {
      socket?.close();
    }
  }
}
