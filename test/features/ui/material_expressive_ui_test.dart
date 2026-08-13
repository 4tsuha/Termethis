import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termethis/app/app.dart';
import 'package:termethis/shared/presentation/expressive_scaffold.dart';

void main() {
  testWidgets('主要4画面がExpressiveテーマと共通画面幅を使用する', (tester) async {
    await tester.binding.setSurfaceSize(const Size(411, 891));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ProviderScope(child: TermethisApp()));
    await tester.pumpAndSettle();

    final theme = tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!;
    expect(theme.useMaterial3, isTrue);
    expect(theme.cardTheme.shape, isA<RoundedRectangleBorder>());
    expect(theme.dialogTheme.shape, isA<RoundedRectangleBorder>());
    expect(theme.bottomSheetTheme.showDragHandle, isTrue);

    for (final destination in const ['ホーム', 'ファイル', '設定']) {
      await tester.tap(find.text(destination));
      await tester.pumpAndSettle();
      expect(find.byType(ExpressiveScaffold), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('320dpでもホームと設定にオーバーフローがない', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ProviderScope(child: TermethisApp()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await tester.tap(find.text('設定'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Termethisについて'), 500);
    expect(tester.takeException(), isNull);
  });

  testWidgets('900dpではNavigationRailと接続カードの2列を使用する', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ProviderScope(child: TermethisApp()));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
