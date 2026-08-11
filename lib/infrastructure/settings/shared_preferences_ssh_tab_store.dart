import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../features/terminal/domain/ssh_tab.dart';

class SharedPreferencesSshTabStore implements SshTabStore {
  SharedPreferencesSshTabStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const _key = 'sessions.ssh_tabs.v1';
  final SharedPreferencesAsync _preferences;

  @override
  Future<List<SshTab>> load() async {
    final encoded = await _preferences.getString(_key);
    if (encoded == null) return const [];
    try {
      final values = jsonDecode(encoded);
      if (values is! List) return const [];
      return values
          .map(SshTab.fromJson)
          .whereType<SshTab>()
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> save(List<SshTab> tabs) {
    return _preferences.setString(
      _key,
      jsonEncode([for (final tab in tabs) tab.toJson()]),
    );
  }
}
