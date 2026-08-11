import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_terminal_ja/app/font_licenses.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('同梱した日本語フォントをライセンス一覧へ登録する', () async {
    registerBundledFontLicenses();

    final entries = await LicenseRegistry.licenses.toList();
    final packages = entries.expand((entry) => entry.packages).toSet();

    expect(packages, containsAll(['Noto Sans JP', 'Koruri', 'Mejiro']));
  });
}
