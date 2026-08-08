import 'app_font.dart';

abstract interface class AppFontStore {
  Future<AppFont?> read();

  Future<void> save(AppFont font);
}

class EphemeralAppFontStore implements AppFontStore {
  const EphemeralAppFontStore();

  @override
  Future<AppFont?> read() async => null;

  @override
  Future<void> save(AppFont font) async {}
}
