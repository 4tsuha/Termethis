import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_terminal_ja/features/connections/domain/connection_profile.dart';
import 'package:ssh_terminal_ja/features/terminal/application/session_registry.dart';
import 'package:ssh_terminal_ja/features/terminal/application/ssh_tabs_controller.dart';
import 'package:ssh_terminal_ja/features/terminal/domain/ssh_gateway.dart';
import 'package:ssh_terminal_ja/features/terminal/domain/ssh_tab.dart';
import 'package:ssh_terminal_ja/infrastructure/terminal/utf8_terminal_codec.dart';

void main() {
  test('同じ接続先から複数タブを開き、再起動後は切断済みとして復元する', () async {
    final store = EphemeralSshTabStore();
    const profile = ConnectionProfile(
      id: 'server',
      name: '開発サーバー',
      host: 'server.example.com',
      port: 22,
      username: 'developer',
    );
    final firstContainer = ProviderContainer(
      overrides: [sshTabStoreProvider.overrideWithValue(store)],
    );
    await firstContainer.read(sshTabsProvider.future);

    final firstId = await firstContainer
        .read(sshTabsProvider.notifier)
        .open(profile);
    final secondId = await firstContainer
        .read(sshTabsProvider.notifier)
        .open(profile);
    expect(firstId, isNot(secondId));
    expect(firstContainer.read(sshTabsProvider).value, hasLength(2));
    firstContainer.dispose();

    final restoredContainer = ProviderContainer(
      overrides: [sshTabStoreProvider.overrideWithValue(store)],
    );
    final restored = await restoredContainer.read(sshTabsProvider.future);
    expect(restored, hasLength(2));
    expect(restored.every((tab) => tab.restored), isTrue);

    await restoredContainer.read(sshTabsProvider.notifier).close(firstId);
    expect(restoredContainer.read(sshTabsProvider).value, hasLength(1));
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
    );

    final first = registry.open('tab-1', profile);
    final sameTab = registry.open('tab-1', profile);
    final second = registry.open('tab-2', profile);

    expect(sameTab, same(first));
    expect(second, isNot(same(first)));
    registry.dispose();
  });

  test('設定したスクロールバック行数を新規セッションごとに適用する', () {
    var lines = 2000;
    const profile = ConnectionProfile(
      id: 'scrollback',
      name: '履歴設定',
      host: 'server.example.com',
      port: 22,
      username: 'developer',
    );
    final registry = SessionRegistry(
      _UnusedSshGateway(),
      const Utf8TerminalCodec(),
      scrollbackLines: () => lines,
    );

    final compact = registry.open('tab-compact', profile);
    lines = 10000;
    final large = registry.open('tab-large', profile);

    expect(compact.terminal.maxLines, 2000);
    expect(large.terminal.maxLines, 10000);
    registry.dispose();
  });
}

class _UnusedSshGateway implements SshGateway {
  @override
  Future<SshConnection> connect(SshConnectRequest request) {
    throw UnimplementedError();
  }
}
