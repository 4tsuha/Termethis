import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../features/connections/domain/ssh_route_configuration.dart';

class SharedPreferencesSshRouteStore implements SshRouteStore {
  SharedPreferencesSshRouteStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const _key = 'connections.ssh_routes.v1';
  final SharedPreferencesAsync _preferences;

  @override
  Future<List<SshRouteConfiguration>> load() async {
    final value = await _preferences.getString(_key);
    if (value == null) return const [];
    final decoded = jsonDecode(value);
    if (decoded is! List) return const [];
    return decoded
        .map(SshRouteConfiguration.fromJson)
        .whereType<SshRouteConfiguration>()
        .toList(growable: false);
  }

  @override
  Future<void> save(List<SshRouteConfiguration> routes) =>
      _preferences.setString(
        _key,
        jsonEncode(routes.map((route) => route.toJson()).toList()),
      );
}
