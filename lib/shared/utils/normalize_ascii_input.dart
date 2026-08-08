String normalizeFullWidthAscii(String value) {
  final buffer = StringBuffer();
  for (final rune in value.runes) {
    if (rune >= 0xff01 && rune <= 0xff5e) {
      buffer.writeCharCode(rune - 0xfee0);
    } else if (rune == 0x3000) {
      buffer.write(' ');
    } else {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}
