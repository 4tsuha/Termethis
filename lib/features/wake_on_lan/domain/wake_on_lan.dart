import 'dart:typed_data';

class WakeOnLanConfiguration {
  const WakeOnLanConfiguration({
    required this.macAddress,
    this.broadcastAddress = '255.255.255.255',
    this.port = 9,
  });

  final String macAddress;
  final String broadcastAddress;
  final int port;

  List<int> get macBytes => parseMacAddress(macAddress)!;

  static List<int>? parseMacAddress(String value) {
    final compact = value.replaceAll(RegExp(r'[:-]'), '').trim();
    if (!RegExp(r'^[0-9a-fA-F]{12}$').hasMatch(compact)) {
      return null;
    }
    return List<int>.generate(
      6,
      (index) =>
          int.parse(compact.substring(index * 2, index * 2 + 2), radix: 16),
      growable: false,
    );
  }

  static String? normalizeMacAddress(String value) {
    final bytes = parseMacAddress(value);
    if (bytes == null) {
      return null;
    }
    return bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(':');
  }

  static bool isValidIpv4Address(String value) {
    final parts = value.trim().split('.');
    if (parts.length != 4) {
      return false;
    }
    return parts.every((part) {
      if (part.isEmpty || !RegExp(r'^\d{1,3}$').hasMatch(part)) {
        return false;
      }
      if (part.length > 1 && part.startsWith('0')) {
        return false;
      }
      final number = int.tryParse(part);
      return number != null && number >= 0 && number <= 255;
    });
  }

  @override
  bool operator ==(Object other) {
    return other is WakeOnLanConfiguration &&
        other.macAddress == macAddress &&
        other.broadcastAddress == broadcastAddress &&
        other.port == port;
  }

  @override
  int get hashCode => Object.hash(macAddress, broadcastAddress, port);
}

Uint8List buildMagicPacket(List<int> macAddress) {
  if (macAddress.length != 6) {
    throw ArgumentError.value(macAddress, 'macAddress', '6バイト必要です。');
  }
  final packet = Uint8List(6 + 16 * macAddress.length)..fillRange(0, 6, 0xff);
  for (var repetition = 0; repetition < 16; repetition++) {
    packet.setRange(6 + repetition * 6, 12 + repetition * 6, macAddress);
  }
  return packet;
}

abstract interface class WakeOnLanSender {
  Future<void> send(WakeOnLanConfiguration configuration);
}

class WakeOnLanFailure implements Exception {
  const WakeOnLanFailure([this.cause]);

  final Object? cause;
}
