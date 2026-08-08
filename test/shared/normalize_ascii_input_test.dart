import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_terminal_ja/shared/utils/normalize_ascii_input.dart';

void main() {
  test('日本語IMEの全角英数字を接続情報向けの半角へ変換する', () {
    expect(normalizeFullWidthAscii('１２７．０．０．１'), '127.0.0.1');
    expect(normalizeFullWidthAscii('ｕｓｅｒ：２１'), 'user:21');
    expect(normalizeFullWidthAscii('名前　付き'), '名前 付き');
  });
}
