import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/connection_profile.dart';
import '../domain/connection_tab.dart';

final connectionTabStoreProvider = Provider<ConnectionTabStore>(
  (ref) => EphemeralConnectionTabStore(),
);

final connectionTabsProvider =
    AsyncNotifierProvider<ConnectionTabsController, List<ConnectionTab>>(
      ConnectionTabsController.new,
    );

class ConnectionTabsController extends AsyncNotifier<List<ConnectionTab>> {
  late ConnectionTabStore _store;
  Future<void> _mutationTail = Future<void>.value();
  int _tabIdSequence = 0;
  String? _selectedTabId;

  @override
  Future<List<ConnectionTab>> build() async {
    _store = ref.watch(connectionTabStoreProvider);
    final storedTabs = await _store.load();
    final tabs = _withoutDuplicateProfiles(storedTabs);
    if (tabs.length != storedTabs.length) {
      await _store.save(tabs);
    }
    _selectedTabId = _latest(tabs)?.id;
    return tabs;
  }

  Future<String> open(ConnectionProfile profile) => _enqueueMutation(() async {
    final tabs = state.value ?? await future;
    final protocol = ConnectionTab.protocolFor(profile);
    final existing = tabs
        .where((tab) => tab.profileId == profile.id && tab.protocol == protocol)
        .fold<ConnectionTab?>(
          null,
          (latest, tab) =>
              latest == null ||
                  tab.lastActivatedAt.isAfter(latest.lastActivatedAt)
              ? tab
              : latest,
        );
    if (existing != null) {
      await _markActive(tabs, existing.id);
      return existing.id;
    }
    final now = DateTime.now().toUtc();
    final id = _nextTabId();
    final updated = [
      ...tabs,
      ConnectionTab(
        id: id,
        profileId: profile.id,
        protocol: protocol,
        title: profile.name,
        createdAt: now,
        lastActivatedAt: now,
      ),
    ];
    _selectedTabId = id;
    state = AsyncData(updated);
    await _store.save(updated);
    return id;
  });

  Future<String> openShizukuShell() => _enqueueMutation(() async {
    final tabs = state.value ?? await future;
    final existing = tabs
        .where((tab) => tab.protocol == ConnectionProtocol.shizukuShell)
        .firstOrNull;
    if (existing != null) {
      await _markActive(tabs, existing.id);
      return existing.id;
    }
    final now = DateTime.now().toUtc();
    final tab = ConnectionTab(
      id: _nextTabId(),
      profileId: null,
      protocol: ConnectionProtocol.shizukuShell,
      title: 'ADBシェル',
      createdAt: now,
      lastActivatedAt: now,
    );
    final updated = [...tabs, tab];
    _selectedTabId = tab.id;
    state = AsyncData(updated);
    await _store.save(updated);
    return tab.id;
  });

  Future<void> close(String id) => _enqueueMutation(() async {
    final tabs = state.value ?? await future;
    final updated = [
      for (final tab in tabs)
        if (tab.id != id) tab,
    ];
    if (_selectedTabId == id) {
      _selectedTabId = _latest(updated)?.id;
    }
    state = AsyncData(updated);
    await _store.save(updated);
  });

  Future<void> markActive(String id) => _enqueueMutation(() async {
    final tabs = state.value ?? await future;
    await _markActive(tabs, id);
  });

  Future<void> rename(String id, String title) => _enqueueMutation(() async {
    final tabs = state.value ?? await future;
    final normalized = title.trim();
    if (normalized.isEmpty) return;
    final updated = [
      for (final tab in tabs)
        if (tab.id == id) tab.copyWith(title: normalized) else tab,
    ];
    state = AsyncData(updated);
    await _store.save(updated);
  });

  Future<void> move(String id, int targetIndex) => _enqueueMutation(() async {
    final tabs = [...(state.value ?? await future)];
    final sourceIndex = tabs.indexWhere((tab) => tab.id == id);
    if (sourceIndex < 0 || targetIndex < 0 || targetIndex >= tabs.length) {
      return;
    }
    final tab = tabs.removeAt(sourceIndex);
    tabs.insert(targetIndex, tab);
    state = AsyncData(tabs);
    await _store.save(tabs);
  });

  ConnectionTab? find(String id) => (state.value ?? const <ConnectionTab>[])
      .where((tab) => tab.id == id)
      .firstOrNull;

  ConnectionTab? get selectedTab {
    final tabs = state.value ?? const <ConnectionTab>[];
    if (tabs.isEmpty) return null;
    final selectedId = _selectedTabId;
    if (selectedId != null) {
      for (final tab in tabs) {
        if (tab.id == selectedId) return tab;
      }
    }
    return _latest(tabs);
  }

  Future<void> _markActive(List<ConnectionTab> tabs, String id) async {
    if (!tabs.any((tab) => tab.id == id)) return;
    final now = DateTime.now().toUtc();
    final updated = [
      for (final tab in tabs)
        if (tab.id == id)
          tab.copyWith(lastActivatedAt: now, restored: false)
        else
          tab,
    ];
    _selectedTabId = id;
    state = AsyncData(updated);
    await _store.save(updated);
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

  ConnectionTab? _latest(List<ConnectionTab> tabs) {
    if (tabs.isEmpty) return null;
    return tabs.reduce(
      (current, next) => next.lastActivatedAt.isAfter(current.lastActivatedAt)
          ? next
          : current,
    );
  }

  List<ConnectionTab> _withoutDuplicateProfiles(List<ConnectionTab> tabs) {
    final newestByProfile = <(String, ConnectionProtocol), ConnectionTab>{};
    for (final tab in tabs) {
      final profileId = tab.profileId;
      if (profileId == null) continue;
      final key = (profileId, tab.protocol);
      final existing = newestByProfile[key];
      if (existing == null ||
          tab.lastActivatedAt.isAfter(existing.lastActivatedAt)) {
        newestByProfile[key] = tab;
      }
    }
    return [
      for (final tab in tabs)
        if (tab.profileId == null ||
            identical(newestByProfile[(tab.profileId!, tab.protocol)], tab))
          tab,
    ];
  }
}
