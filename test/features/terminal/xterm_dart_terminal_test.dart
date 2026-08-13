import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termethis/features/connections/domain/connection_profile.dart';
import 'package:termethis/features/terminal/application/ssh_session_controller.dart';
import 'package:termethis/features/terminal/domain/ssh_gateway.dart';
import 'package:termethis/features/terminal/presentation/widgets/xterm_dart_terminal.dart';
import 'package:termethis/infrastructure/terminal/utf8_terminal_codec.dart';
import 'package:xterm/xterm.dart';

void main() {
  testWidgets('xterm.dartは分割された日本語UTF-8を欠落させず表示する', (tester) async {
    final connection = _RecordingConnection();
    final session = SshSessionController(
      _Gateway(connection),
      const Utf8TerminalCodec(),
      profile: _profile,
    );
    await session.connect(
      authentication: const SshPasswordAuthentication('test'),
      onUnknownHostKey: (_) async => true,
      onInteractivePrompt: (_) async => const [],
    );
    session.setViewportVisible(true);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 800,
          height: 400,
          child: XtermDartTerminal(
            session: session,
            scrollbackLines: 2000,
            terminalFontFamily: 'CascadiaMono',
            japaneseFontFamily: 'NotoSansJP',
            fontSize: 14,
          ),
        ),
      ),
    );

    final bytes = utf8.encode('日本語😀\r\n');
    connection.addOutput(bytes.sublist(0, 2));
    await tester.pump(const Duration(milliseconds: 9));
    connection.addOutput(bytes.sublist(2, 7));
    await tester.pump(const Duration(milliseconds: 9));
    connection.addOutput(bytes.sublist(7));
    await tester.pump(const Duration(milliseconds: 9));

    final view = tester.widget<TerminalView>(find.byType(TerminalView));
    expect(view.terminal.buffer.getText(), contains('日本語😀'));
    session.dispose();
  });

  testWidgets('xterm.dartの日本語IME確定文字列をUTF-8でSSHへ一度だけ送る', (tester) async {
    final connection = _RecordingConnection();
    final session = SshSessionController(
      _Gateway(connection),
      const Utf8TerminalCodec(),
      profile: _profile,
    );
    await session.connect(
      authentication: const SshPasswordAuthentication('test'),
      onUnknownHostKey: (_) async => true,
      onInteractivePrompt: (_) async => const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 800,
          height: 400,
          child: XtermDartTerminal(
            session: session,
            scrollbackLines: 2000,
            terminalFontFamily: 'CascadiaMono',
            japaneseFontFamily: 'NotoSansJP',
            fontSize: 14,
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TerminalView));
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'にほんご',
        selection: TextSelection.collapsed(offset: 4),
        composing: TextRange(start: 0, end: 4),
      ),
    );
    await tester.pump();
    expect(connection.writes, isEmpty);

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '日本語😀',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    await tester.pump();

    expect(connection.writes, hasLength(1));
    expect(utf8.decode(connection.writes.single), '日本語😀');
    await tester.pump(const Duration(milliseconds: 301));
    session.dispose();
  });
}

const _profile = ConnectionProfile(
  id: 'xterm-dart-test',
  name: 'xterm.dart test',
  host: '127.0.0.1',
  port: 22,
  username: 'test',
  authenticationType: AuthenticationType.passwordOrInteractive,
);

class _Gateway implements SshGateway {
  const _Gateway(this.connection);

  final _RecordingConnection connection;

  @override
  Future<SshConnection> connect(SshConnectRequest request) async => connection;
}

class _RecordingConnection implements SshConnection {
  final _stdout = StreamController<Uint8List>();
  final writes = <Uint8List>[];

  void addOutput(List<int> bytes) => _stdout.add(Uint8List.fromList(bytes));

  @override
  Stream<Uint8List> get stdout => _stdout.stream;

  @override
  Stream<Uint8List> get stderr => const Stream.empty();

  @override
  Future<void> get done => Completer<void>().future;

  @override
  void write(Uint8List data) => writes.add(Uint8List.fromList(data));

  @override
  void resize(int width, int height, int pixelWidth, int pixelHeight) {}

  @override
  Future<void> close() async => _stdout.close();
}
