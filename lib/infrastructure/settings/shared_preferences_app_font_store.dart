import 'package:shared_preferences/shared_preferences.dart';

import '../../features/settings/domain/app_font.dart';
import '../../features/settings/domain/app_font_store.dart';

class SharedPreferencesAppFontStore implements AppFontStore {
  SharedPreferencesAppFontStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const _fontKey = 'settings.japanese_font';

  final SharedPreferencesAsync _preferences;

  @override
  Future<AppFont?> read() async {
    final savedName = await _preferences.getString(_fontKey);
    for (final font in AppFont.values) {
      if (font.name == savedName) {
        return font;
      }
    }
    return null;
  }

  @override
  Future<void> save(AppFont font) {
    return _preferences.setString(_fontKey, font.name);
  }
}
