import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static ThemeData light({
    required ColorScheme dynamicScheme,
    bool transparentUi = false,
  }) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: dynamicScheme,
      scaffoldBackgroundColor: dynamicScheme.surface,
      textTheme: _textTheme,
      dialogTheme: _dialogTheme(dynamicScheme, transparentUi),
      bottomSheetTheme: _bottomSheetTheme(dynamicScheme, transparentUi),
    );
  }

  static ThemeData dark({
    required ColorScheme dynamicScheme,
    bool isAmoled = false,
    bool transparentUi = false,
  }) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: dynamicScheme,
      scaffoldBackgroundColor: isAmoled ? Colors.black : dynamicScheme.surface,
      textTheme: _textTheme,
      dialogTheme: _dialogTheme(dynamicScheme, transparentUi),
      bottomSheetTheme: _bottomSheetTheme(dynamicScheme, transparentUi),
    );
  }

  static DialogThemeData _dialogTheme(
    ColorScheme colorScheme,
    bool transparentUi,
  ) {
    if (!transparentUi) return const DialogThemeData();
    return DialogThemeData(
      backgroundColor: colorScheme.surface.withValues(alpha: 0.86),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: colorScheme.onSurface.withValues(alpha: 0.12)),
      ),
    );
  }

  static BottomSheetThemeData _bottomSheetTheme(
    ColorScheme colorScheme,
    bool transparentUi,
  ) {
    if (!transparentUi) return const BottomSheetThemeData();
    return BottomSheetThemeData(
      backgroundColor: colorScheme.surface.withValues(alpha: 0.86),
      modalBackgroundColor: colorScheme.surface.withValues(alpha: 0.86),
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    );
  }

  static TextTheme get _textTheme {
    return TextTheme(
      displayLarge: const TextStyle(fontSize: 72, fontWeight: FontWeight.bold),
      titleLarge: GoogleFonts.oswald(fontSize: 30, fontStyle: FontStyle.normal),
      bodyMedium: GoogleFonts.merriweather(),
      displaySmall: GoogleFonts.pacifico(),
    );
  }
}
