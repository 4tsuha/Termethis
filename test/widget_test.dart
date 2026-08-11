import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_terminal_ja/app/app.dart';
import 'package:ssh_terminal_ja/features/connections/application/connection_profiles_controller.dart';
import 'package:ssh_terminal_ja/features/connections/application/private_key_providers.dart';
import 'package:ssh_terminal_ja/features/connections/domain/connection_profile.dart';
import 'package:ssh_terminal_ja/features/connections/domain/connection_profile_repository.dart';
import 'package:ssh_terminal_ja/features/connections/domain/credential_vault.dart';
import 'package:ssh_terminal_ja/features/connections/domain/private_key_importer.dart';
import 'package:ssh_terminal_ja/features/settings/application/app_font_controller.dart';
import 'package:ssh_terminal_ja/features/settings/domain/app_font.dart';
import 'package:ssh_terminal_ja/features/terminal/application/session_registry.dart';
import 'package:ssh_terminal_ja/features/terminal/application/ssh_tabs_controller.dart';
import 'package:ssh_terminal_ja/features/terminal/domain/ssh_gateway.dart';
import 'package:ssh_terminal_ja/features/wake_on_lan/application/wake_on_lan_provider.dart';
import 'package:ssh_terminal_ja/features/wake_on_lan/domain/wake_on_lan.dart';
import 'package:ssh_terminal_ja/main.dart';
import 'package:xterm/xterm.dart';

void main() {
  testWidgets('日本語の接続先一覧を表示する', (tester) async {
    await tester.pumpWidget(const MainApp());
    await tester.pumpAndSettle();

    expect(find.text('接続先'), findsOneWidget);
    expect(find.text('接続先がありません'), findsOneWidget);
    expect(find.text('接続先を追加'), findsOneWidget);
  });

  testWidgets('接続先を登録して一覧に表示する', (tester) async {
    await tester.pumpWidget(const MainApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('接続先を追加'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(4));
    await tester.enterText(fields.at(0), '開発サーバー');
    await tester.enterText(fields.at(1), '192.168.1.20');
    await tester.enterText(fields.at(2), '2222');
    await tester.enterText(fields.at(3), 'developer');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('開発サーバー'), findsOneWidget);
    expect(find.text('developer@192.168.1.20:2222'), findsOneWidget);
  });

  testWidgets('パスワード確定後にダイアログを安全に破棄して接続する', (tester) async {
    final gateway = _WidgetTestGateway();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sshGatewayProvider.overrideWithValue(gateway)],
        child: const SshTerminalApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('接続先を追加'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '接続テスト');
    await tester.enterText(fields.at(1), 'localhost');
    await tester.enterText(fields.at(2), '2222');
    await tester.enterText(fields.at(3), 'demo');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('接続テスト'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'password');
    await tester.tap(find.text('接続'));
    await tester.pumpAndSettle();

    expect(find.text('接続済み'), findsWidgets);
    expect(tester.takeException(), isNull);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    final tab = (await container.read(sshTabsProvider.future)).single;
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('接続先'), findsOneWidget);
    expect(
      container.read(sessionRegistryProvider).find(tab.id)?.isConnected,
      isTrue,
    );
  });

  testWidgets('日本語IMEの確定文字列をUTF-8でSSHへ送る', (tester) async {
    final gateway = _WidgetTestGateway();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(450, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sshGatewayProvider.overrideWithValue(gateway)],
        child: const SshTerminalApp(),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    container.read(appFontProvider.notifier).select(AppFont.mejiro);
    await tester.pumpAndSettle();

    await tester.tap(find.text('接続先を追加'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'IMEテスト');
    await tester.enterText(fields.at(1), 'localhost');
    await tester.enterText(fields.at(2), '2222');
    await tester.enterText(fields.at(3), 'demo');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('IMEテスト'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'password');
    await tester.tap(find.text('接続'));
    await tester.pumpAndSettle();

    final terminalView = tester.widget<TerminalView>(find.byType(TerminalView));
    expect(terminalView.textStyle.fontFamily, 'CascadiaMono');
    expect(terminalView.textStyle.fontFamilyFallback.first, 'Mejiro');
    expect(terminalView.textStyle.fontSize, 13);

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'にほん',
        selection: TextSelection.collapsed(offset: 3),
        composing: TextRange(start: 0, end: 3),
      ),
    );
    await tester.pump();
    expect(gateway.connection.writes, isEmpty);

    tester.view.physicalSize = const Size(900, 450);
    await tester.pumpAndSettle();
    expect(gateway.connection.writes, isEmpty);

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '日本語',
        selection: TextSelection.collapsed(offset: 3),
      ),
    );
    await tester.pump();

    expect(gateway.connection.writes, hasLength(1));
    expect(utf8.decode(gateway.connection.writes.single), '日本語');

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(gateway.connection.writes, hasLength(2));
    expect(utf8.decode(gateway.connection.writes.last), '\r');
  });

  testWidgets('編集途中の戻る操作では破棄確認を表示する', (tester) async {
    await tester.pumpWidget(const MainApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('接続先を追加'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '編集中');
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('変更を破棄しますか？'), findsOneWidget);
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(find.text('編集中'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('破棄して戻る'));
    await tester.pumpAndSettle();

    expect(find.text('接続先'), findsOneWidget);
  });

  testWidgets('600dp以上ではNavigationRailへ切り替える', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(700, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const MainApp());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    tester.view.physicalSize = const Size(599, 900);
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);

    tester.view.physicalSize = const Size(320, 640);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('検索ボタン'), findsOneWidget);
    expect(find.text('最後の出力をコピー'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('秘密鍵を選択してVault参照だけを接続先へ保存する', (tester) async {
    final gateway = _WidgetTestGateway();
    const importedKey = ImportedPrivateKey(
      pem: 'test-private-key',
      label: 'id_ed25519',
      isEncrypted: false,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sshGatewayProvider.overrideWithValue(gateway),
          privateKeyImporterProvider.overrideWithValue(
            const _PrivateKeyImporter(importedKey),
          ),
          privateKeyValidatorProvider.overrideWithValue(
            const _AcceptingPrivateKeyValidator(),
          ),
        ],
        child: const SshTerminalApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('接続先を追加'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '鍵サーバー');
    await tester.enterText(fields.at(1), 'key.example.com');
    await tester.enterText(fields.at(2), '22');
    await tester.enterText(fields.at(3), 'key-user');

    await tester.tap(find.text('パスワードまたは対話形式'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('秘密鍵').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('秘密鍵を選択'));
    await tester.pumpAndSettle();
    expect(find.text('選択済み: id_ed25519'), findsOneWidget);

    final saveButton = find.widgetWithText(FilledButton, '保存');
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -240));
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    final profiles = await container.read(connectionProfilesProvider.future);
    final profile = profiles.single;
    expect(profile.authenticationType, AuthenticationType.privateKey);
    expect(profile.credentialReference, isNotNull);
    expect(profile.privateKeyLabel, 'id_ed25519');
    expect(profile.credentialReference, isNot(contains('test-private-key')));

    final credential = await container
        .read(credentialVaultProvider)
        .readPrivateKey(CredentialHandle(profile.credentialReference!));
    expect(credential?.pem, importedKey.pem);

    await tester.tap(find.text('鍵サーバー'));
    await tester.pumpAndSettle();
    expect(find.text('接続済み'), findsWidgets);
    final authentication = gateway.lastRequest?.authentication;
    expect(authentication, isA<SshPrivateKeyAuthentication>());
    expect(
      (authentication as SshPrivateKeyAuthentication).pem,
      importedKey.pem,
    );
  });

  testWidgets('接続先メニューからWake on LANを送信する', (tester) async {
    final sender = _RecordingWakeOnLanSender();
    final repository = EphemeralConnectionProfileRepository(
      initialProfiles: const [
        ConnectionProfile(
          id: 'wol-server',
          name: '自宅サーバー',
          host: '192.168.1.10',
          port: 22,
          username: 'admin',
          wakeOnLan: WakeOnLanConfiguration(
            macAddress: '00:11:22:33:44:55',
            broadcastAddress: '192.168.1.255',
            port: 9,
          ),
        ),
      ],
    );
    addTearDown(repository.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectionProfileRepositoryProvider.overrideWithValue(repository),
          wakeOnLanSenderProvider.overrideWithValue(sender),
        ],
        child: const SshTerminalApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wake on LANを送信'));
    await tester.pumpAndSettle();

    expect(sender.lastConfiguration?.macAddress, '00:11:22:33:44:55');
    expect(find.text('自宅サーバーへMagic Packetを送信しました。'), findsOneWidget);
  });
}

class _PrivateKeyImporter implements PrivateKeyImporter {
  const _PrivateKeyImporter(this.key);

  final ImportedPrivateKey key;

  @override
  Future<ImportedPrivateKey?> pick() async => key;
}

class _AcceptingPrivateKeyValidator implements PrivateKeyValidator {
  const _AcceptingPrivateKeyValidator();

  @override
  Future<void> validate(ImportedPrivateKey key, {String? passphrase}) async {}
}

class _WidgetTestGateway implements SshGateway {
  final connection = _WidgetTestConnection();
  SshConnectRequest? lastRequest;

  @override
  Future<SshConnection> connect(SshConnectRequest request) async {
    lastRequest = request;
    request.onAuthenticationStarted();
    request.onOpeningPty();
    return connection;
  }
}

class _WidgetTestConnection implements SshConnection {
  final _stdout = StreamController<Uint8List>();
  final _stderr = StreamController<Uint8List>();
  final _done = Completer<void>();
  final List<Uint8List> writes = [];

  @override
  Future<void> close() async {
    await _stdout.close();
    await _stderr.close();
    if (!_done.isCompleted) {
      _done.complete();
    }
  }

  @override
  Future<void> get done => _done.future;

  @override
  void resize(int width, int height, int pixelWidth, int pixelHeight) {}

  @override
  Stream<Uint8List> get stderr => _stderr.stream;

  @override
  Stream<Uint8List> get stdout => _stdout.stream;

  @override
  void write(Uint8List data) => writes.add(data);
}

class _RecordingWakeOnLanSender implements WakeOnLanSender {
  WakeOnLanConfiguration? lastConfiguration;

  @override
  Future<void> send(WakeOnLanConfiguration configuration) async {
    lastConfiguration = configuration;
  }
}
