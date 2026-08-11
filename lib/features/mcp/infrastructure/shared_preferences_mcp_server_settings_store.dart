import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../infrastructure/secure_storage/secure_value_store.dart';
import '../domain/mcp_server_settings.dart';

class SharedPreferencesMcpServerSettingsStore
    implements McpServerSettingsStore {
  SharedPreferencesMcpServerSettingsStore({
    McpSettingsPreferences? preferences,
    SecureValueStore? secureStore,
  }) : _preferences = preferences ?? _SharedPreferencesAdapter(),
       _secureStore = secureStore ?? const FlutterSecureValueStore();

  static const _key = 'mcp.server.settings.v1';
  static const _tokenKey = 'mcp.server.bearer_token.v1';
  final McpSettingsPreferences _preferences;
  final SecureValueStore _secureStore;

  @override
  Future<McpServerSettings> read() async {
    final value = await _preferences.getString(_key);
    if (value == null) return const McpServerSettings();
    try {
      final settings = McpServerSettings.fromJson(
        (jsonDecode(value) as Map).cast<String, Object?>(),
      );
      return settings.copyWith(
        bearerToken: await _secureStore.read(_tokenKey) ?? '',
      );
    } on Object {
      return const McpServerSettings();
    }
  }

  @override
  Future<void> save(McpServerSettings settings) async {
    final publicSettings = settings.toJson()..remove('bearerToken');
    await _preferences.setString(_key, jsonEncode(publicSettings));
    if (settings.bearerToken.isEmpty) {
      await _secureStore.delete(_tokenKey);
    } else {
      await _secureStore.write(_tokenKey, settings.bearerToken);
    }
  }
}

abstract interface class McpSettingsPreferences {
  Future<String?> getString(String key);
  Future<void> setString(String key, String value);
}

class _SharedPreferencesAdapter implements McpSettingsPreferences {
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  @override
  Future<String?> getString(String key) => _preferences.getString(key);
  @override
  Future<void> setString(String key, String value) =>
      _preferences.setString(key, value);
}
