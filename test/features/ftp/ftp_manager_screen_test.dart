import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termethis/app/app.dart';
import 'package:termethis/features/ftp/application/ftp_tabs_controller.dart';
import 'package:termethis/features/ftp/domain/ftp_gateway.dart';

void main() {
  testWidgets('ボトムナビでホーム・FTP・設定を切り替える', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: TermethisApp()));
    await tester.pumpAndSettle();

    expect(find.text('ホーム'), findsOneWidget);
    expect(find.text('FTP'), findsOneWidget);
    expect(find.text('設定'), findsOneWidget);

    await tester.tap(find.text('FTP'));
    await tester.pumpAndSettle();
    expect(find.text('FTPマネージャー'), findsOneWidget);
    expect(find.text('FTPタブがありません'), findsOneWidget);

    await tester.tap(find.text('設定'));
    await tester.pumpAndSettle();
    expect(find.text('タブバーに検索ボタンを表示'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('日本語フォント'), 500);
    await tester.pumpAndSettle();
    await tester.tap(find.text('日本語フォント'));
    await tester.pumpAndSettle();
    expect(find.text('Noto Sans JP'), findsOneWidget);
    expect(find.text('Koruri'), findsOneWidget);
    expect(find.text('Mejiro'), findsOneWidget);

    await tester.tap(find.text('Koruri'));
    await tester.pumpAndSettle();
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme?.textTheme.bodyMedium?.fontFamily, 'Koruri');
    expect(find.textContaining('Koruri'), findsOneWidget);

    await tester.tap(find.text('日本語フォント'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mejiro'));
    await tester.pumpAndSettle();
    final updatedApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(updatedApp.theme?.textTheme.bodyMedium?.fontFamily, 'Mejiro');
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
    await tester.tap(find.text('FTP'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FTP接続'));
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
    await tester.tap(find.text('FTP'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FTP接続'));
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
