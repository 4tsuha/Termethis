import 'package:flutter_test/flutter_test.dart';
import 'package:termethis/features/settings/domain/terminal_performance_settings.dart';
import 'package:termethis/infrastructure/settings/shared_preferences_terminal_performance_settings_store.dart';

void main() {
  group('native terminal renderer migration', () {
    test('moves the previous WebGL default to the native renderer once', () {
      final renderer = selectRendererAfterNativeSurfaceMigration(
        savedRenderer: TerminalRendererMode.webgl,
        migrationCompleted: false,
      );

      expect(renderer, TerminalRendererMode.connectBot);
    });

    test('preserves a renderer selected after migration', () {
      final renderer = selectRendererAfterNativeSurfaceMigration(
        savedRenderer: TerminalRendererMode.webgl,
        migrationCompleted: true,
      );

      expect(renderer, TerminalRendererMode.webgl);
    });

    test('uses the native renderer when no renderer was saved', () {
      final renderer = selectRendererAfterNativeSurfaceMigration(
        savedRenderer: null,
        migrationCompleted: false,
      );

      expect(renderer, TerminalRendererMode.connectBot);
    });
  });
}
