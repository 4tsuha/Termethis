import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/ssh_route_configuration.dart';

final sshRouteStoreProvider = Provider<SshRouteStore>(
  (ref) => EphemeralSshRouteStore(),
);

final sshRoutesProvider =
    AsyncNotifierProvider<SshRoutesController, List<SshRouteConfiguration>>(
      SshRoutesController.new,
    );

class SshRoutesController extends AsyncNotifier<List<SshRouteConfiguration>> {
  late SshRouteStore _store;

  @override
  Future<List<SshRouteConfiguration>> build() async {
    _store = ref.watch(sshRouteStoreProvider);
    return _store.load();
  }

  SshRouteConfiguration? routeFor(String profileId) => (state.value ?? const [])
      .where((route) => route.profileId == profileId)
      .firstOrNull;

  Future<void> saveRoute(SshRouteConfiguration route) async {
    final current = state.value ?? await future;
    final updated = [
      for (final item in current)
        if (item.profileId != route.profileId) item,
      if (route.jumpProfileIds.isNotEmpty) route,
    ];
    _ensureAcyclic(updated);
    state = AsyncData(updated);
    await _store.save(updated);
  }

  Future<void> removeFor(String profileId) async {
    final current = state.value ?? await future;
    final updated = current
        .where((route) => route.profileId != profileId)
        .map(
          (route) => SshRouteConfiguration(
            profileId: route.profileId,
            jumpProfileIds: route.jumpProfileIds
                .where((id) => id != profileId)
                .toList(),
          ),
        )
        .where((route) => route.jumpProfileIds.isNotEmpty)
        .toList();
    state = AsyncData(updated);
    await _store.save(updated);
  }

  void _ensureAcyclic(List<SshRouteConfiguration> routes) {
    final graph = {
      for (final route in routes) route.profileId: route.jumpProfileIds,
    };
    final visiting = <String>{};
    final visited = <String>{};

    void visit(String profileId, List<String> path) {
      if (visiting.contains(profileId)) {
        throw SshRouteCycleException([...path, profileId]);
      }
      if (!visited.add(profileId)) return;
      visiting.add(profileId);
      for (final next in graph[profileId] ?? const <String>[]) {
        visit(next, [...path, profileId]);
      }
      visiting.remove(profileId);
    }

    for (final profileId in graph.keys) {
      visit(profileId, const []);
    }
  }
}
