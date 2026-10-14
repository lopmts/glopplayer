import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glopplayer/models/theme_settings.dart';
import 'package:glopplayer/theme/app_themes.dart';

void main() {
  group('ThemeSettings transparent UI', () {
    test('defaults to disabled and survives JSON serialization', () {
      const settings = ThemeSettings();
      expect(settings.useTransparentUi, isFalse);
      expect(ThemeSettings.fromJson(settings.toJson()), equals(settings));
    });

    test('reads older settings without the transparent UI field', () {
      final settings = ThemeSettings.fromJson({
        kThemeModeKey: ThemeMode.dark.name,
      });
      expect(settings.useTransparentUi, isFalse);
    });
  });

  group('AppTheme transparent surfaces', () {
    test(
      'uses translucent dialog and bottom sheet backgrounds when enabled',
      () {
        final theme = AppTheme.dark(
          dynamicScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1DB954),
            brightness: Brightness.dark,
          ),
          transparentUi: true,
        );

        expect(theme.dialogTheme.backgroundColor!.a, lessThan(1));
        expect(theme.bottomSheetTheme.modalBackgroundColor!.a, lessThan(1));
      },
    );

    test('keeps dialog and bottom sheet defaults when disabled', () {
      final theme = AppTheme.light(
        dynamicScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1DB954),
          brightness: Brightness.light,
        ),
      );

      expect(theme.dialogTheme.backgroundColor, isNull);
      expect(theme.bottomSheetTheme.modalBackgroundColor, isNull);
    });
  });
}
