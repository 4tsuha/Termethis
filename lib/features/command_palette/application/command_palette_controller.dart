import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/command_snippet.dart';

final commandSnippetStoreProvider = Provider<CommandSnippetStore>(
  (ref) => EphemeralCommandSnippetStore(),
);

final commandSnippetsProvider =
    AsyncNotifierProvider<CommandPaletteController, List<CommandSnippet>>(
      CommandPaletteController.new,
    );

class CommandPaletteController extends AsyncNotifier<List<CommandSnippet>> {
  late CommandSnippetStore _store;

  @override
  Future<List<CommandSnippet>> build() async {
    _store = ref.watch(commandSnippetStoreProvider);
    return _store.load();
  }

  Future<void> save(CommandSnippet snippet) async {
    final current = state.value ?? await future;
    final updated = [
      for (final item in current)
        if (item.id != snippet.id) item,
      snippet,
    ];
    state = AsyncData(updated);
    await _store.save(updated);
  }

  Future<void> remove(String id) async {
    final current = state.value ?? await future;
    final updated = current.where((item) => item.id != id).toList();
    state = AsyncData(updated);
    await _store.save(updated);
  }
}
