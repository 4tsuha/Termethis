import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

void main() {
  testWidgets('長時間出力中は最新行を表示し、手動スクロールは維持する', (tester) async {
    final terminal = Terminal(maxLines: 80);
    final scrollController = ScrollController();

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 240,
          child: TerminalView(
            terminal,
            autoResize: false,
            scrollController: scrollController,
          ),
        ),
      ),
    );

    for (var index = 0; index < 200; index++) {
      terminal.write('line-$index\r\n');
    }
    await tester.pump();

    expect(terminal.buffer.lines.length, 80);
    expect(terminal.buffer.getText(), contains('line-199'));
    expect(
      scrollController.offset,
      moreOrLessEquals(scrollController.position.maxScrollExtent, epsilon: 1),
    );

    final lineHeight =
        tester.getSize(find.byType(TerminalView)).height / terminal.viewHeight;
    scrollController.jumpTo(
      scrollController.position.maxScrollExtent - lineHeight * 3,
    );
    await tester.pump();
    final manualOffset = scrollController.offset;

    terminal.write('new-output\r\n');
    await tester.pump();

    expect(scrollController.offset, moreOrLessEquals(manualOffset, epsilon: 1));
    expect(
      scrollController.offset,
      lessThan(scrollController.position.maxScrollExtent - lineHeight),
    );
  });
}
