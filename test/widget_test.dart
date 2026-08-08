import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_terminal_ja/app/app.dart';
import 'package:ssh_terminal_ja/features/terminal/application/session_registry.dart';
import 'package:ssh_terminal_ja/features/terminal/domain/ssh_gateway.dart';
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
  });

  testWidgets('日本語IMEの確定文字列をUTF-8でSSHへ送る', (tester) async {
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
    expect(terminalView.textStyle.fontFamilyFallback.first, 'NotoSansJP');
    expect(terminalView.textStyle.fontSize, 14);

    tester.testTextInput.enterText('日本語');
    await tester.pump();

    expect(gateway.connection.writes, hasLength(1));
    expect(utf8.decode(gateway.connection.writes.single), '日本語');
  });
}

class _WidgetTestGateway implements SshGateway {
  final connection = _WidgetTestConnection();

  @override
  Future<SshConnection> connect(SshConnectRequest request) async {
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
