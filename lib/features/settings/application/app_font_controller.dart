import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/app_font.dart';
import '../domain/app_font_store.dart';

final initialAppFontProvider = Provider<AppFont>((ref) => AppFont.notoSansJp);

final appFontStoreProvider = Provider<AppFontStore>(
  (ref) => const EphemeralAppFontStore(),
);

final appFontProvider = NotifierProvider<AppFontController, AppFont>(
  AppFontController.new,
);

class AppFontController extends Notifier<AppFont> {
  late AppFontStore _store;

  @override
  AppFont build() {
    _store = ref.watch(appFontStoreProvider);
    return ref.watch(initialAppFontProvider);
  }

  void select(AppFont font) {
    state = font;
    unawaited(_store.save(font));
  }
}
