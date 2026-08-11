import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termethis/app/font_licenses.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('同梱フォントと第三者ライブラリをライセンス一覧へ登録する', () async {
    registerBundledLicenses();

    final entries = await LicenseRegistry.licenses.toList();
    final packages = entries.expand((entry) => entry.packages).toSet();

    expect(
      packages,
      containsAll([
        'Cascadia Mono',
        'Noto Sans JP',
        'Koruri',
        'Mejiro',
        'Roboto',
        'Moralerspace',
        'Source Code Pro',
        'JetBrains Mono',
        'Nerd Fonts Symbols Mono',
        'ConnectBot termlib',
        'Termux terminal-emulator',
        'Termux terminal-view',
        'libvterm',
        'xterm.dart',
        '@xterm/xterm',
        '@xterm/addon-fit',
        '@xterm/addon-serialize',
        '@xterm/addon-unicode11',
        '@xterm/addon-unicode-graphemes',
        '@xterm/addon-webgl',
        'IronRDP',
        'picky',
        'wgpu',
        'raw-window-handle',
        'jni',
        'pollster',
        'anyhow',
        'bytes',
        'dashmap',
        'flutter_rust_bridge',
        'ndk-sys',
        'once_cell',
        'russh',
        'russh-sftp',
        'tokio',
      ]),
    );
  });
}
