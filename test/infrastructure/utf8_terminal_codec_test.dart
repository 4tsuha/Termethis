import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_terminal_ja/infrastructure/terminal/utf8_terminal_codec.dart';

void main() {
  test('分割されたUTF-8の日本語を一文字として復元する', () async {
    const codec = Utf8TerminalCodec();
    final bytes = utf8.encode('日本語🙂');
    final source = StreamController<List<int>>();
    final output = StringBuffer();
    final done = codec
        .decode(source.stream)
        .listen(output.write)
        .asFuture<void>();

    for (final byte in bytes) {
      source.add([byte]);
    }
    await source.close();
    await done;

    expect(output.toString(), '日本語🙂');
  });

  test('不正なUTF-8を置換文字にしてストリームを継続する', () async {
    const codec = Utf8TerminalCodec();
    final result = await codec.decode(Stream.value([0xff, 0x41])).join();

    expect(result, '\uFFFDA');
  });
}
