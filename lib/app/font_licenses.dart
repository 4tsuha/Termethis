import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

void registerBundledLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const [
      'Cascadia Mono',
    ], await rootBundle.loadString('assets/fonts/LICENSE-CascadiaCode.txt'));
    yield LicenseEntryWithLineBreaks(const [
      'Noto Sans JP',
    ], await rootBundle.loadString('assets/fonts/LICENSE-NotoSansJP.txt'));
    yield LicenseEntryWithLineBreaks(const [
      'Koruri',
    ], await rootBundle.loadString('assets/fonts/LICENSE-Koruri.txt'));
    yield LicenseEntryWithLineBreaks(const [
      'Mejiro',
    ], await rootBundle.loadString('assets/fonts/LICENSE-Mejiro.txt'));
    yield LicenseEntryWithLineBreaks(const [
      'Roboto',
    ], await rootBundle.loadString('assets/fonts/LICENSE-Roboto.txt'));
    yield LicenseEntryWithLineBreaks(const [
      'Moralerspace',
    ], await rootBundle.loadString('assets/fonts/LICENSE-Moralerspace.txt'));
    yield LicenseEntryWithLineBreaks(const [
      'Source Code Pro',
    ], await rootBundle.loadString('assets/fonts/LICENSE-SourceCodePro.txt'));
    yield LicenseEntryWithLineBreaks(const [
      'JetBrains Mono',
    ], await rootBundle.loadString('assets/fonts/LICENSE-JetBrainsMono.txt'));
    yield LicenseEntryWithLineBreaks(
      const ['Nerd Fonts Symbols Mono'],
      await rootBundle.loadString('assets/fonts/LICENSE-NerdFontsSymbols.txt'),
    );
    yield LicenseEntryWithLineBreaks(const [
      'ConnectBot termlib',
    ], await rootBundle.loadString('third_party/termlib/LICENSE'));
    yield LicenseEntryWithLineBreaks(const [
      'Termux terminal-emulator',
      'Termux terminal-view',
    ], await rootBundle.loadString('third_party/termlib/LICENSE'));
    yield LicenseEntryWithLineBreaks(
      const ['libvterm'],
      await rootBundle.loadString(
        'third_party/termlib/lib/src/main/cpp/libvterm/LICENSE',
      ),
    );
    yield LicenseEntryWithLineBreaks(const [
      'xterm.dart',
    ], await rootBundle.loadString('third_party/xterm/LICENSE'));
    yield LicenseEntryWithLineBreaks(const [
      'mosh_dart',
    ], await rootBundle.loadString('third_party/mosh_dart/LICENSE'));
    yield LicenseEntryWithLineBreaks(const [
      '@xterm/xterm',
      '@xterm/addon-fit',
      '@xterm/addon-serialize',
      '@xterm/addon-unicode11',
      '@xterm/addon-unicode-graphemes',
      '@xterm/addon-webgl',
    ], await rootBundle.loadString('assets/web_terminal/LICENSE-xterm.txt'));
    yield LicenseEntryWithLineBreaks(const [
      'IronRDP',
    ], await rootBundle.loadString('assets/licenses/LICENSE-IronRDP-MIT.txt'));
    yield LicenseEntryWithLineBreaks(
      const ['IronRDP'],
      await rootBundle.loadString('assets/licenses/LICENSE-IronRDP-APACHE.txt'),
    );
    yield LicenseEntryWithLineBreaks(const [
      'picky',
    ], await rootBundle.loadString('assets/licenses/LICENSE-Picky-MIT.txt'));
    yield LicenseEntryWithLineBreaks(const [
      'picky',
    ], await rootBundle.loadString('assets/licenses/LICENSE-Picky-APACHE.txt'));
    for (final license in const {
      'wgpu': [
        'assets/licenses/LICENSE-wgpu-MIT.txt',
        'assets/licenses/LICENSE-wgpu-APACHE.txt',
      ],
      'raw-window-handle': [
        'assets/licenses/LICENSE-raw-window-handle-MIT.txt',
        'assets/licenses/LICENSE-raw-window-handle-APACHE.txt',
        'assets/licenses/LICENSE-raw-window-handle-ZLIB.txt',
      ],
      'jni': [
        'assets/licenses/LICENSE-jni-MIT.txt',
        'assets/licenses/LICENSE-jni-APACHE.txt',
      ],
      'pollster': [
        'assets/licenses/LICENSE-pollster-MIT.txt',
        'assets/licenses/LICENSE-pollster-APACHE.txt',
      ],
      'anyhow': [
        'assets/licenses/LICENSE-anyhow-MIT.txt',
        'assets/licenses/LICENSE-anyhow-APACHE.txt',
      ],
      'bytes': ['assets/licenses/LICENSE-bytes.txt'],
      'dashmap': ['assets/licenses/LICENSE-dashmap.txt'],
      'flutter_rust_bridge': [
        'assets/licenses/LICENSE-flutter-rust-bridge.txt',
      ],
      'ndk-sys': ['assets/licenses/LICENSE-ndk-sys-APACHE.txt'],
      'once_cell': [
        'assets/licenses/LICENSE-once-cell-MIT.txt',
        'assets/licenses/LICENSE-once-cell-APACHE.txt',
      ],
      'russh': ['assets/licenses/LICENSE-russh-APACHE.txt'],
      'russh-sftp': ['assets/licenses/LICENSE-russh-sftp.txt'],
      'tokio': ['assets/licenses/LICENSE-tokio.txt'],
      'Shizuku API': ['assets/licenses/LICENSE-Shizuku-API.txt'],
      'vnc-rs': [
        'assets/licenses/LICENSE-vnc-rs-MIT.txt',
        'assets/licenses/LICENSE-vnc-rs-APACHE.txt',
      ],
    }.entries) {
      for (final asset in license.value) {
        yield LicenseEntryWithLineBreaks([
          license.key,
        ], await rootBundle.loadString(asset));
      }
    }
  });
}
