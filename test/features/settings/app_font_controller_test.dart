import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_terminal_ja/features/settings/application/app_font_controller.dart';
import 'package:ssh_terminal_ja/features/settings/domain/app_font.dart';
import 'package:ssh_terminal_ja/features/settings/domain/app_font_store.dart';

void main() {
  test('選択した日本語フォントを保存する', () async {
    final store = _MemoryAppFontStore();
    final container = ProviderContainer(
      overrides: [appFontStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    expect(container.read(appFontProvider), AppFont.notoSansJp);

    container.read(appFontProvider.notifier).select(AppFont.mejiro);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(appFontProvider), AppFont.mejiro);
    expect(store.savedFont, AppFont.mejiro);
  });

  test('保存済みフォントを初期値として使う', () {
    final container = ProviderContainer(
      overrides: [initialAppFontProvider.overrideWithValue(AppFont.koruri)],
    );
    addTearDown(container.dispose);

    expect(container.read(appFontProvider), AppFont.koruri);
  });
}

class _MemoryAppFontStore implements AppFontStore {
  AppFont? savedFont;

  @override
  Future<AppFont?> read() async => savedFont;

  @override
  Future<void> save(AppFont font) async {
    savedFont = font;
  }
}
