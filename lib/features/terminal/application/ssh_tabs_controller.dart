import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../connections/domain/connection_profile.dart';
import '../domain/ssh_tab.dart';

final sshTabStoreProvider = Provider<SshTabStore>(
  (ref) => EphemeralSshTabStore(),
);

final sshTabsProvider = AsyncNotifierProvider<SshTabsController, List<SshTab>>(
  SshTabsController.new,
);

class SshTabsController extends AsyncNotifier<List<SshTab>> {
  late SshTabStore _store;

  @override
  Future<List<SshTab>> build() async {
    _store = ref.watch(sshTabStoreProvider);
    return _store.load();
  }

  Future<String> open(ConnectionProfile profile) async {
    final tabs = await future;
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final updated = [
      ...tabs,
      SshTab(id: id, profileId: profile.id, title: profile.name),
    ];
    state = AsyncData(updated);
    await _store.save(updated);
    return id;
  }

  Future<void> close(String id) async {
    final updated = [
      for (final tab in await future)
        if (tab.id != id) tab,
    ];
    state = AsyncData(updated);
    await _store.save(updated);
  }

  Future<void> markActive(String id) async {
    final updated = [
      for (final tab in await future)
        if (tab.id == id) tab.copyWith(restored: false) else tab,
    ];
    state = AsyncData(updated);
  }

  SshTab? find(String id) {
    for (final tab in state.value ?? const <SshTab>[]) {
      if (tab.id == id) return tab;
    }
    return null;
  }
}
