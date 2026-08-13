import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termethis/features/connections/domain/connection_profile.dart';
import 'package:termethis/features/terminal/application/ssh_session_controller.dart';
import 'package:termethis/features/terminal/domain/ssh_gateway.dart';
import 'package:termethis/features/terminal/presentation/widgets/terminal_shortcut_bar.dart';
import 'package:termethis/infrastructure/terminal/utf8_terminal_codec.dart';

void main() {
  for (final width in [320.0, 450.0, 800.0]) {
    testWidgets('$width dpで全ショートカットを切らずに表示する', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = await _connectedSession();
      addTearDown(session.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: TerminalShortcutBar(
                session: session,
                supportsTunnels: true,
                pasteLabel: '貼り付け',
                onPaste: () {},
                onKey: (_, _) {},
                onCommandPalette: () {},
                onTunnels: () {},
                agentMode: false,
                onToggleAgentMode: () {},
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Ctrl'), findsOneWidget);
      expect(find.text('Alt'), findsOneWidget);
      expect(find.text('Esc'), findsOneWidget);
      expect(find.text('Tab'), findsOneWidget);
      expect(find.byTooltip('左矢印'), findsOneWidget);
      expect(find.byTooltip('上矢印'), findsOneWidget);
      expect(find.byTooltip('下矢印'), findsOneWidget);
      expect(find.byTooltip('右矢印'), findsOneWidget);
      expect(tester.getSize(find.byType(TerminalShortcutBar)).height, 60);
      if (width < 760) {
        expect(find.byTooltip('貼り付け'), findsOneWidget);
        expect(find.byTooltip('2段表示に切り替え'), findsOneWidget);
        await tester.tap(find.byTooltip('2段表示に切り替え'));
        await tester.pump();
        expect(tester.getSize(find.byType(TerminalShortcutBar)).height, 112);
        expect(find.byTooltip('1段表示に切り替え'), findsOneWidget);
        await tester.tap(find.byTooltip('1段表示に切り替え'));
        await tester.pump();
        expect(tester.getSize(find.byType(TerminalShortcutBar)).height, 60);
        expect(find.byTooltip('その他の操作'), findsOneWidget);
        await tester.tap(find.byTooltip('その他の操作'));
        await tester.pumpAndSettle();
        expect(find.text('Agentモード'), findsOneWidget);
        expect(find.text('コマンドパレット'), findsOneWidget);
        expect(find.text('SSHトンネル'), findsOneWidget);
      } else {
        expect(find.byTooltip('貼り付け'), findsOneWidget);
        expect(find.byTooltip('Agentモード'), findsOneWidget);
        expect(find.byTooltip('コマンドパレット'), findsOneWidget);
        expect(find.byTooltip('SSHトンネル'), findsOneWidget);
      }

      for (final button in find.byType(IconButton).evaluate()) {
        final size = tester.getSize(find.byWidget(button.widget));
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
      }
    });
  }
}

Future<SshSessionController> _connectedSession() async {
  final session = SshSessionController(
    const _Gateway(),
    const Utf8TerminalCodec(),
    profile: const ConnectionProfile(
      id: 'shortcut-layout',
      name: 'Shortcut layout',
      host: '127.0.0.1',
      port: 22,
      username: 'test',
      authenticationType: AuthenticationType.passwordOrInteractive,
    ),
  );
  await session.connect(
    authentication: const SshPasswordAuthentication('test'),
    onUnknownHostKey: (_) async => true,
    onInteractivePrompt: (_) async => const [],
  );
  return session;
}

class _Gateway implements SshGateway {
  const _Gateway();

  @override
  Future<SshConnection> connect(SshConnectRequest request) async =>
      _Connection();
}

class _Connection implements SshConnection {
  @override
  Future<void> close() async {}

  @override
  Future<void> get done => Completer<void>().future;

  @override
  void resize(int width, int height, int pixelWidth, int pixelHeight) {}

  @override
  Stream<Uint8List> get stderr => const Stream.empty();

  @override
  Stream<Uint8List> get stdout => const Stream.empty();

  @override
  void write(Uint8List data) {}
}
