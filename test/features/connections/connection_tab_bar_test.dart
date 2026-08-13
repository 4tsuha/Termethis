import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termethis/features/connections/domain/connection_tab.dart';
import 'package:termethis/features/connections/presentation/connections_workspace_screen.dart';

void main() {
  testWidgets('タブ名の文字幅に合わせて横幅が広がり、上限で省略する', (tester) async {
    tester.view.physicalSize = const Size(1200, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.utc(2026, 8, 13);
    final tabs = [
      _tab('short', '短い', now),
      _tab('medium', 'Debian Minimal', now),
      _tab('long', '非常に長い接続先名を持つ開発サーバーのターミナル', now),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: ConnectionTabBar(
              tabs: tabs,
              activeTabId: tabs.first.id,
              onSelect: (_) {},
              onClose: (_) {},
              onAdd: () {},
              onMove: (_, _) async {},
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final shortWidth = tester
        .getSize(find.byKey(const ValueKey('connection-tab-short')))
        .width;
    final mediumWidth = tester
        .getSize(find.byKey(const ValueKey('connection-tab-medium')))
        .width;
    final longWidth = tester
        .getSize(find.byKey(const ValueKey('connection-tab-long')))
        .width;
    expect(shortWidth, greaterThanOrEqualTo(104));
    expect(mediumWidth, greaterThan(shortWidth));
    expect(longWidth, greaterThan(mediumWidth));
    expect(longWidth, lessThanOrEqualTo(324));
  });

  for (final size in const [Size(320, 640), Size(450, 800), Size(800, 450)]) {
    testWidgets('${size.width.toInt()}dpでタブバーが破綻しない', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final now = DateTime.utc(2026, 8, 13);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: Scaffold(
            body: ConnectionTabBar(
              tabs: [
                _tab('one', 'WSL', now),
                _tab('two', 'Debian Minimal 開発環境', now),
                _tab('three', 'RDP Windows Server評価環境', now),
                _tab('four', 'VNCデスクトップ', now),
              ],
              activeTabId: 'one',
              onSelect: (_) {},
              onClose: (_) {},
              onAdd: () {},
              onMove: (_, _) async {},
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('接続を追加'), findsOneWidget);
    });
  }
}

ConnectionTab _tab(String id, String title, DateTime now) => ConnectionTab(
  id: id,
  profileId: id,
  protocol: ConnectionProtocol.ssh,
  title: title,
  createdAt: now,
  lastActivatedAt: now,
);
