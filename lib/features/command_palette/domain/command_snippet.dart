class CommandSnippet {
  const CommandSnippet({
    required this.id,
    required this.title,
    required this.command,
    this.profileId,
    this.tags = const [],
    this.favorite = false,
  });

  final String id;
  final String title;
  final String command;
  final String? profileId;
  final List<String> tags;
  final bool favorite;

  bool get containsSecretVariable =>
      RegExp(r'\$\{secret:[^}]+\}').hasMatch(command);

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'command': command,
    'profileId': profileId,
    'tags': tags,
    'favorite': favorite,
  };

  static CommandSnippet? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final title = value['title'];
    final command = value['command'];
    if (id is! String || title is! String || command is! String) return null;
    return CommandSnippet(
      id: id,
      title: title,
      command: command,
      profileId: value['profileId'] is String
          ? value['profileId'] as String
          : null,
      tags: (value['tags'] as List?)?.whereType<String>().toList() ?? const [],
      favorite: value['favorite'] == true,
    );
  }
}

class CommandVariable {
  const CommandVariable({
    required this.name,
    required this.isSecret,
    this.defaultValue,
  });

  final String name;
  final bool isSecret;
  final String? defaultValue;
}

List<CommandVariable> commandVariables(String command) {
  final variables = <String, CommandVariable>{};
  for (final match in RegExp(r'\$\{([^}]+)\}').allMatches(command)) {
    final expression = match.group(1)!;
    final parts = expression.split(':');
    final secret = parts.first == 'secret';
    final name = secret ? parts.skip(1).join(':') : parts.first;
    final defaultValue = !secret && parts.length > 1
        ? parts.skip(1).join(':')
        : null;
    if (name.isEmpty) continue;
    variables.putIfAbsent(
      '${secret ? 'secret:' : ''}$name',
      () => CommandVariable(
        name: name,
        isSecret: secret,
        defaultValue: defaultValue,
      ),
    );
  }
  return variables.values.toList(growable: false);
}

String expandCommand(String command, Map<String, String> values) =>
    command.replaceAllMapped(RegExp(r'\$\{([^}]+)\}'), (match) {
      final expression = match.group(1)!;
      final parts = expression.split(':');
      final secret = parts.first == 'secret';
      final name = secret ? parts.skip(1).join(':') : parts.first;
      return values['${secret ? 'secret:' : ''}$name'] ??
          (!secret && parts.length > 1 ? parts.skip(1).join(':') : '');
    });

abstract interface class CommandSnippetStore {
  Future<List<CommandSnippet>> load();
  Future<void> save(List<CommandSnippet> snippets);
}

class EphemeralCommandSnippetStore implements CommandSnippetStore {
  List<CommandSnippet> _items = const [];

  @override
  Future<List<CommandSnippet>> load() async => List.unmodifiable(_items);

  @override
  Future<void> save(List<CommandSnippet> snippets) async {
    _items = List.unmodifiable(snippets);
  }
}
