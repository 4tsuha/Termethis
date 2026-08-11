import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

void registerBundledFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const [
      'Noto Sans JP',
    ], await rootBundle.loadString('assets/fonts/LICENSE-NotoSansJP.txt'));
    yield LicenseEntryWithLineBreaks(const [
      'Koruri',
    ], await rootBundle.loadString('assets/fonts/LICENSE-Koruri.txt'));
    yield LicenseEntryWithLineBreaks(const [
      'Mejiro',
    ], await rootBundle.loadString('assets/fonts/LICENSE-Mejiro.txt'));
  });
}
