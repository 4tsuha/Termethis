import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../features/connections/domain/connection_tab.dart';

class SharedPreferencesConnectionTabStore implements ConnectionTabStore {
  SharedPreferencesConnectionTabStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const _key = 'sessions.connection_tabs.v2';
  static const _legacySshKey = 'sessions.ssh_tabs.v1';
  final SharedPreferencesAsync _preferences;

  @override
  Future<List<ConnectionTab>> load() async {
    final current = await _preferences.getString(_key);
    if (current != null) return _decode(current);

    final legacy = await _preferences.getString(_legacySshKey);
    if (legacy == null) return const [];
    final migrated = _decodeLegacySsh(legacy);
    if (migrated.isEmpty) return const [];
    await save(migrated);
    await _preferences.remove(_legacySshKey);
    return migrated;
  }

  @override
  Future<void> save(List<ConnectionTab> tabs) => _preferences.setString(
    _key,
    jsonEncode([for (final tab in tabs) tab.toJson()]),
  );

  List<ConnectionTab> _decode(String encoded) {
    try {
      final values = jsonDecode(encoded);
      if (values is! List) return const [];
      return values
          .map(ConnectionTab.fromJson)
          .whereType<ConnectionTab>()
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  List<ConnectionTab> _decodeLegacySsh(String encoded) {
    try {
      final values = jsonDecode(encoded);
      if (values is! List) return const [];
      final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      return [
        for (var index = 0; index < values.length; index++)
          if (values[index] case final Map value
              when value['id'] is String &&
                  value['profileId'] is String &&
                  value['title'] is String)
            ConnectionTab(
              id: value['id'] as String,
              profileId: value['profileId'] as String,
              protocol: ConnectionProtocol.ssh,
              title: value['title'] as String,
              createdAt: epoch.add(Duration(microseconds: index)),
              lastActivatedAt: epoch.add(Duration(microseconds: index)),
              restored: true,
            ),
      ];
    } catch (_) {
      return const [];
    }
  }
}
