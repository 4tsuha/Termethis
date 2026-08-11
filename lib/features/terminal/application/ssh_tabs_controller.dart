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
  Future<void> _mutationTail = Future<void>.value();
  int _tabIdSequence = 0;

  @override
  Future<List<SshTab>> build() async {
    _store = ref.watch(sshTabStoreProvider);
    return _store.load();
  }

  Future<String> open(ConnectionProfile profile) async {
    if (profile.connectionType != ConnectionType.ssh) {
      throw ArgumentError.value(
        profile.connectionType,
        'profile.connectionType',
        'SSHタブにはSSH接続先だけを指定できます。',
      );
    }
    return _enqueueMutation(() async {
      final tabs = state.value ?? await future;
      final id = _nextTabId();
      final updated = [
        ...tabs,
        SshTab(id: id, profileId: profile.id, title: profile.name),
      ];
      state = AsyncData(updated);
      await _store.save(updated);
      return id;
    });
  }

  Future<void> close(String id) async {
    await _enqueueMutation(() async {
      final tabs = state.value ?? await future;
      final updated = [
        for (final tab in tabs)
          if (tab.id != id) tab,
      ];
      state = AsyncData(updated);
      await _store.save(updated);
    });
  }

  Future<void> markActive(String id) async {
    await _enqueueMutation(() async {
      final tabs = state.value ?? await future;
      final updated = [
        for (final tab in tabs)
          if (tab.id == id) tab.copyWith(restored: false) else tab,
      ];
      state = AsyncData(updated);
    });
  }

  SshTab? find(String id) {
    for (final tab in state.value ?? const <SshTab>[]) {
      if (tab.id == id) return tab;
    }
    return null;
  }

  Future<T> _enqueueMutation<T>(Future<T> Function() mutation) {
    final result = _mutationTail.then((_) => mutation());
    _mutationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  String _nextTabId() {
    _tabIdSequence += 1;
    return '${DateTime.now().microsecondsSinceEpoch}-$_tabIdSequence';
  }
}
