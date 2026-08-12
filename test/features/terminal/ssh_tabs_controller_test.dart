import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termethis/features/connections/application/connection_tabs_controller.dart';
import 'package:termethis/features/connections/domain/connection_profile.dart';
import 'package:termethis/features/connections/domain/connection_tab.dart';
import 'package:termethis/features/terminal/application/session_registry.dart';
import 'package:termethis/features/terminal/domain/ssh_gateway.dart';
import 'package:termethis/infrastructure/terminal/utf8_terminal_codec.dart';
import 'package:termethis/infrastructure/ssh/in_memory_host_key_repository.dart';

void main() {
  test('初期化中に複数のSSHタブを開いてもすべて保持する', () async {
    final store = _GateLoadConnectionTabStore();
    const profile = ConnectionProfile(
      id: 'server',
      name: '開発サーバー',
      host: 'server.example.com',
      port: 22,
      username: 'developer',
    );
    final container = ProviderContainer(
      overrides: [connectionTabStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    final initialLoad = container.read(connectionTabsProvider.future);
    await store.loadStarted.future;
    final notifier = container.read(connectionTabsProvider.notifier);
    final opens = [notifier.open(profile), notifier.open(profile)];
    store.completeLoad();

    await initialLoad;
    final ids = await Future.wait(opens);
    expect(ids.toSet(), hasLength(1));
    expect(container.read(connectionTabsProvider).value, hasLength(1));
    expect(store.savedTabs, hasLength(1));
  });

  test('同じ接続先から複数タブを開き、再起動後は切断済みとして復元する', () async {
    final store = EphemeralConnectionTabStore();
    const profile = ConnectionProfile(
      id: 'server',
      name: '開発サーバー',
      host: 'server.example.com',
      port: 22,
      username: 'developer',
    );
    final firstContainer = ProviderContainer(
      overrides: [connectionTabStoreProvider.overrideWithValue(store)],
    );
    await firstContainer.read(connectionTabsProvider.future);

    final firstId = await firstContainer
        .read(connectionTabsProvider.notifier)
        .open(profile);
    final secondId = await firstContainer
        .read(connectionTabsProvider.notifier)
        .open(profile);
    expect(secondId, firstId);
    expect(firstContainer.read(connectionTabsProvider).value, hasLength(1));
    firstContainer.dispose();

    final restoredContainer = ProviderContainer(
      overrides: [connectionTabStoreProvider.overrideWithValue(store)],
    );
    final restored = await restoredContainer.read(
      connectionTabsProvider.future,
    );
    expect(restored, hasLength(1));
    expect(restored.every((tab) => tab.restored), isTrue);

    final reopenedId = await restoredContainer
        .read(connectionTabsProvider.notifier)
        .open(profile);
    expect(reopenedId, firstId);
    expect(restoredContainer.read(connectionTabsProvider).value, hasLength(1));
    restoredContainer.dispose();
  });

  test('同じ接続先でもタブIDごとに独立したSSHセッションを保持する', () {
    const profile = ConnectionProfile(
      id: 'server',
      name: '開発サーバー',
      host: 'server.example.com',
      port: 22,
      username: 'developer',
    );
    final registry = SessionRegistry(
      _UnusedSshGateway(),
      const Utf8TerminalCodec(),
      hostKeys: InMemoryHostKeyRepository(),
    );

    final first = registry.open('tab-1', profile);
    final sameTab = registry.open('tab-1', profile);
    final second = registry.open('tab-2', profile);

    expect(sameTab, same(first));
    expect(second, isNot(same(first)));
    registry.dispose();
  });
  test('opening a tab makes it the selected tab', () async {
    final now = DateTime.now().toUtc();
    final store = EphemeralConnectionTabStore([
      ConnectionTab(
        id: 'old-rdp',
        profileId: 'rdp',
        protocol: ConnectionProtocol.rdp,
        title: 'RDP',
        createdAt: now.subtract(const Duration(minutes: 2)),
        lastActivatedAt: now.subtract(const Duration(minutes: 1)),
      ),
    ]);
    const profile = ConnectionProfile(
      id: 'mosh',
      name: 'Mosh',
      host: 'server.example.com',
      port: 22,
      username: 'developer',
      connectionType: ConnectionType.mosh,
    );
    final container = ProviderContainer(
      overrides: [connectionTabStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    await container.read(connectionTabsProvider.future);

    final openedId = await container
        .read(connectionTabsProvider.notifier)
        .open(profile);

    expect(
      container.read(connectionTabsProvider.notifier).selectedTab?.id,
      openedId,
    );
  });

  test('restoring duplicate profile tabs keeps only the newest tab', () async {
    final now = DateTime.now().toUtc();
    final store = EphemeralConnectionTabStore([
      ConnectionTab(
        id: 'older',
        profileId: 'server',
        protocol: ConnectionProtocol.ssh,
        title: 'Server',
        createdAt: now.subtract(const Duration(minutes: 2)),
        lastActivatedAt: now.subtract(const Duration(minutes: 1)),
      ),
      ConnectionTab(
        id: 'newer',
        profileId: 'server',
        protocol: ConnectionProtocol.ssh,
        title: 'Server',
        createdAt: now.subtract(const Duration(minutes: 1)),
        lastActivatedAt: now,
      ),
    ]);
    final container = ProviderContainer(
      overrides: [connectionTabStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    final restored = await container.read(connectionTabsProvider.future);

    expect(restored.map((tab) => tab.id), ['newer']);
    expect(await store.load(), hasLength(1));
  });
}

class _GateLoadConnectionTabStore implements ConnectionTabStore {
  final loadStarted = Completer<void>();
  final _loadResult = Completer<List<ConnectionTab>>();
  List<ConnectionTab> savedTabs = const [];

  @override
  Future<List<ConnectionTab>> load() {
    if (!loadStarted.isCompleted) loadStarted.complete();
    return _loadResult.future;
  }

  @override
  Future<void> save(List<ConnectionTab> tabs) async {
    savedTabs = List.unmodifiable(tabs);
  }

  void completeLoad() => _loadResult.complete(const []);
}

class _UnusedSshGateway implements SshGateway {
  @override
  Future<SshConnection> connect(SshConnectRequest request) {
    throw UnimplementedError();
  }
}
