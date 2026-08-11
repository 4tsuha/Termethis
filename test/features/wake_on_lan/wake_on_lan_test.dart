import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:termethis/features/wake_on_lan/domain/wake_on_lan.dart';
import 'package:termethis/infrastructure/wake_on_lan/udp_wake_on_lan_sender.dart';

void main() {
  test('MACアドレスを正規化してMagic Packetを生成する', () {
    expect(
      WakeOnLanConfiguration.normalizeMacAddress('aabb-ccdd-eeff'),
      'AA:BB:CC:DD:EE:FF',
    );

    final mac = WakeOnLanConfiguration.parseMacAddress('AA:BB:CC:DD:EE:FF')!;
    final packet = buildMagicPacket(mac);

    expect(packet, hasLength(102));
    expect(packet.take(6), everyElement(0xff));
    for (var offset = 6; offset < packet.length; offset += 6) {
      expect(packet.sublist(offset, offset + 6), mac);
    }
  });

  test('不正なMACアドレスとIPv4アドレスを拒否する', () {
    expect(WakeOnLanConfiguration.parseMacAddress('AA:BB:CC'), isNull);
    expect(WakeOnLanConfiguration.isValidIpv4Address('192.168.1.255'), isTrue);
    expect(WakeOnLanConfiguration.isValidIpv4Address('192.168.1.999'), isFalse);
    expect(
      WakeOnLanConfiguration.isValidIpv4Address('192.168.001.255'),
      isFalse,
    );
  });

  test('UDPで102バイトのMagic Packetを送信する', () async {
    final receiver = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final received = Completer<Datagram>();
    final subscription = receiver.listen((event) {
      if (event == RawSocketEvent.read) {
        final datagram = receiver.receive();
        if (datagram != null && !received.isCompleted) {
          received.complete(datagram);
        }
      }
    });

    await const UdpWakeOnLanSender().send(
      WakeOnLanConfiguration(
        macAddress: '00:11:22:33:44:55',
        broadcastAddress: '127.0.0.1',
        port: receiver.port,
      ),
    );
    final datagram = await received.future.timeout(const Duration(seconds: 2));

    expect(datagram.data, hasLength(102));
    expect(datagram.data.take(6), everyElement(0xff));
    await subscription.cancel();
    receiver.close();
  });
}
