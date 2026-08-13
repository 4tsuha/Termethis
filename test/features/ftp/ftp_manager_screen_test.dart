import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termethis/app/app.dart';
import 'package:termethis/features/connections/application/connection_tabs_controller.dart';
import 'package:termethis/features/connections/domain/connection_tab.dart';
import 'package:termethis/features/ftp/application/ftp_tabs_controller.dart';
import 'package:termethis/features/ftp/domain/ftp_gateway.dart';

void main() {
  testWidgets('ボトムナビで主要な4画面を切り替える', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: TermethisApp()));
    await tester.pumpAndSettle();

    expect(find.text('ホーム'), findsOneWidget);
    expect(find.text('接続'), findsOneWidget);
    expect(find.text('ファイル'), findsOneWidget);
    expect(find.text('設定'), findsOneWidget);

    await tester.tap(find.text('接続'));
    await tester.pumpAndSettle();
    expect(find.text('接続は開かれていません'), findsOneWidget);

    await tester.tap(find.text('ファイル'));
    await tester.pumpAndSettle();
    expect(find.text('ファイル'), findsWidgets);
    expect(find.text('ファイル接続がありません'), findsOneWidget);

    await tester.tap(find.text('設定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ターミナル操作'));
    await tester.pumpAndSettle();
    expect(find.text('タブバーに検索ボタンを表示'), findsOneWidget);
    await tester.tap(find.text('ターミナル操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('表示と描画'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('ターミナルフォント'), 500);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ターミナルフォント'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('JetBrains Mono'));
    await tester.pumpAndSettle();
    expect(find.textContaining('JetBrains Mono'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('画面フォント'), 240);
    await tester.pumpAndSettle();
    await tester.tap(find.text('画面フォント'));
    await tester.pumpAndSettle();
    expect(find.text('Noto Sans JP'), findsOneWidget);
    expect(find.text('Koruri'), findsOneWidget);
    expect(find.text('Mejiro'), findsOneWidget);
    expect(find.text('Roboto'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Moralerspace'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Moralerspace'), findsOneWidget);
    expect(find.text('Source Code Pro'), findsOneWidget);
    expect(find.text('JetBrains Mono'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Koruri'),
      -240,
      scrollable: find.byType(Scrollable).last,
    );

    await tester.tap(find.text('Koruri'));
    await tester.pumpAndSettle();
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme?.textTheme.bodyMedium?.fontFamily, 'Koruri');
    expect(find.textContaining('Koruri'), findsOneWidget);

    await tester.tap(find.text('画面フォント'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mejiro'));
    await tester.pumpAndSettle();
    final updatedApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(updatedApp.theme?.textTheme.bodyMedium?.fontFamily, 'Mejiro');

    await tester.tap(find.text('画面フォント'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Roboto'),
      160,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -48));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Roboto'));
    await tester.pumpAndSettle();
    final robotoApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(robotoApp.theme?.textTheme.bodyMedium?.fontFamily, 'Roboto');
  });

  testWidgets('設定項目を機能別のカードにグループ化する', (tester) async {
    await tester.binding.setSurfaceSize(const Size(411, 891));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ProviderScope(child: TermethisApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('設定'));
    await tester.pumpAndSettle();

    expect(find.byType(ExpansionTile), findsNothing);
    expect(find.text('タブバーに検索ボタンを表示').hitTestable(), findsOneWidget);

    for (final group in const [
      (key: 'terminal-operation', label: 'ターミナル操作'),
      (key: 'display-rendering', label: '表示と描画'),
      (key: 'background', label: '動作とバックグラウンド'),
      (key: 'credentials', label: '鍵と認証'),
      (key: 'integrations', label: '連携と診断'),
      (key: 'file-transfer', label: 'ファイル転送'),
      (key: 'about', label: 'Termethisについて'),
    ]) {
      await tester.scrollUntilVisible(find.text(group.label), 300);
      final groupFinder = find.byKey(ValueKey('settings-group-${group.key}'));
      expect(groupFinder, findsWidgets);
      expect(
        find.descendant(
          of: groupFinder.first,
          matching: find.text(group.label),
        ),
        findsWidgets,
      );
    }

    await tester.scrollUntilVisible(find.text('秘密鍵と信頼済みホスト鍵'), -300);
    await tester.tap(find.text('秘密鍵と信頼済みホスト鍵'));
    await tester.pumpAndSettle();
    expect(find.text('認証情報はこの端末内に保存'), findsOneWidget);
    expect(find.text('秘密鍵'), findsOneWidget);
    expect(find.text('信頼済みホスト鍵'), findsOneWidget);
  });

  testWidgets('320dp幅でも設定一覧の末尾までレイアウトが破綻しない', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ProviderScope(child: TermethisApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('設定'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    for (final label in const [
      '表示と描画',
      '動作とバックグラウンド',
      '鍵と認証',
      '連携と診断',
      'ファイル転送',
      'Termethisについて',
    ]) {
      await tester.scrollUntilVisible(find.text(label), 300);
      expect(tester.takeException(), isNull);
    }
    expect(find.text('Termethisについて'), findsOneWidget);
  });

  testWidgets('接続タブ履歴はホームではなく接続画面に表示する', (tester) async {
    final store = EphemeralConnectionTabStore();
    final now = DateTime.utc(2026, 8, 12);
    await store.save([
      ConnectionTab(
        id: 'restored-tab',
        profileId: 'profile-1',
        protocol: ConnectionProtocol.ssh,
        title: '作業セッション',
        createdAt: now,
        lastActivatedAt: now,
      ),
    ]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [connectionTabStoreProvider.overrideWithValue(store)],
        child: const TermethisApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('作業セッション'), findsNothing);
    expect(find.byType(InputChip), findsNothing);

    await tester.tap(find.text('接続'));
    await tester.pumpAndSettle();
    expect(find.text('作業セッション'), findsOneWidget);
  });

  testWidgets('FTPタブからフォルダーを階層移動する', (tester) async {
    final gateway = _FakeFtpGateway();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [ftpGatewayProvider.overrideWithValue(gateway)],
        child: const TermethisApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('ファイル'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ファイル接続'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(5));
    await tester.enterText(fields.at(0), 'テストサーバー');
    await tester.enterText(fields.at(1), '127.0.0.1');
    await tester.enterText(fields.at(2), '2121');
    await tester.enterText(fields.at(3), 'tester');
    await tester.enterText(fields.at(4), 'secret');
    tester.testTextInput.hide();
    final connectButton = find.widgetWithText(FilledButton, '接続');
    await tester.ensureVisible(connectButton);
    await tester.tap(connectButton);
    await tester.pumpAndSettle();

    expect(find.text('テストサーバー'), findsOneWidget);
    expect(find.text('public_html'), findsOneWidget);
    expect(find.text('README.txt'), findsOneWidget);
    expect(find.text('FTP（暗号化なし）'), findsNothing);
    expect(find.textContaining('暗号化されません'), findsOneWidget);

    await tester.tap(find.text('public_html'));
    await tester.pumpAndSettle();
    expect(find.text('images'), findsOneWidget);
    expect(find.text('index.html'), findsOneWidget);
    expect(find.text('public_html'), findsOneWidget);

    await tester.tap(find.text('ルート'));
    await tester.pumpAndSettle();
    expect(find.text('README.txt'), findsOneWidget);
  });

  testWidgets('SFTPを選択してSSHファイル接続を開始する', (tester) async {
    await tester.binding.setSurfaceSize(const Size(411, 891));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final gateway = _FakeFtpGateway();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [ftpGatewayProvider.overrideWithValue(gateway)],
        child: const TermethisApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('ファイル'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ファイル接続'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('FTP（暗号化なし）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SFTP（SSHファイル転送）').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'SFTPサーバー');
    await tester.enterText(fields.at(1), 'sftp.example.com');
    expect((tester.widget<TextFormField>(fields.at(2)).controller?.text), '22');
    await tester.enterText(fields.at(3), 'sftp-user');
    await tester.enterText(fields.at(4), 'secret');
    tester.testTextInput.hide();
    final connectButton = find.widgetWithText(FilledButton, '接続');
    await tester.ensureVisible(connectButton);
    await tester.tap(connectButton);
    await tester.pumpAndSettle();

    expect(gateway.lastRequest?.securityMode, FtpSecurityMode.sftp);
    expect(gateway.lastRequest?.onUnknownHostKey, isNotNull);
    expect(find.text('SFTPサーバー'), findsOneWidget);
  });
}

class _FakeFtpGateway implements FtpGateway {
  FtpConnectRequest? lastRequest;

  @override
  Future<FtpConnection> connect(FtpConnectRequest request) async {
    lastRequest = request;
    return _FakeFtpConnection();
  }
}

class _FakeFtpConnection implements FtpConnection {
  String _path = '/';

  @override
  Future<void> changeDirectory(String path) async {
    if (path.startsWith('/')) {
      _path = path;
    } else if (_path == '/') {
      _path = '/$path';
    } else {
      _path = '$_path/$path';
    }
  }

  @override
  Future<void> close() async {}

  @override
  Future<void> createDirectory(String name) async {}

  @override
  Future<String> currentDirectory() async => _path;

  @override
  Future<void> deleteEmptyDirectory(String name) async {}

  @override
  Future<void> deleteFile(String name) async {}

  @override
  Future<List<FtpEntryInfo>> listDirectory() async {
    if (_path == '/') {
      return const [
        FtpEntryInfo(name: 'README.txt', kind: FtpEntryKind.file, size: 1280),
        FtpEntryInfo(name: 'public_html', kind: FtpEntryKind.directory),
      ];
    }
    return const [
      FtpEntryInfo(name: 'index.html', kind: FtpEntryKind.file, size: 4096),
      FtpEntryInfo(name: 'images', kind: FtpEntryKind.directory),
    ];
  }

  @override
  Future<void> rename(String oldName, String newName) async {}
}
