import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termethis/features/data_management/presentation/data_and_safety_screen.dart';

void main() {
  testWidgets('バックアップと安全な診断出力を分けて表示する', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: DataAndSafetyScreen())),
    );

    expect(find.text('データと安全性'), findsOneWidget);
    expect(find.text('バックアップと復元'), findsOneWidget);
    expect(find.text('バックアップを書き出す'), findsOneWidget);
    expect(find.text('バックアップから復元'), findsOneWidget);
    expect(find.text('安全な診断情報を書き出す'), findsOneWidget);
    expect(find.textContaining('秘密鍵、パスワード、パスフレーズは含みません'), findsOneWidget);
    expect(find.byType(ExpansionTile), findsNothing);
  });
}
