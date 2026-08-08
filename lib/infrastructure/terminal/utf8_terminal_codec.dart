import 'dart:convert';
import 'dart:typed_data';

import '../../features/terminal/domain/ssh_gateway.dart';

class Utf8TerminalCodec implements TerminalCodec {
  const Utf8TerminalCodec();

  @override
  Stream<String> decode(Stream<List<int>> source) {
    return source.transform(const Utf8Decoder(allowMalformed: true));
  }

  @override
  Uint8List encode(String input) => Uint8List.fromList(utf8.encode(input));
}
