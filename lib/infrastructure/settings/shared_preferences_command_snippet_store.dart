import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../features/command_palette/domain/command_snippet.dart';

class SharedPreferencesCommandSnippetStore implements CommandSnippetStore {
  SharedPreferencesCommandSnippetStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const _key = 'terminal.command_snippets.v1';
  final SharedPreferencesAsync _preferences;

  @override
  Future<List<CommandSnippet>> load() async {
    final encoded = await _preferences.getString(_key);
    if (encoded == null) return const [];
    final decoded = jsonDecode(encoded);
    if (decoded is! List) return const [];
    return decoded
        .map(CommandSnippet.fromJson)
        .whereType<CommandSnippet>()
        .toList(growable: false);
  }

  @override
  Future<void> save(List<CommandSnippet> snippets) {
    return _preferences.setString(
      _key,
      jsonEncode(snippets.map((item) => item.toJson()).toList()),
    );
  }
}
