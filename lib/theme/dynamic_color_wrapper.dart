import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:glopplayer/provider/theme_provider.dart';
import 'package:glopplayer/theme/app_themes.dart';
import 'package:provider/provider.dart';

class DynamicColorWrapper extends StatelessWidget {
  final Widget Function(
    BuildContext context,
    ThemeData light,
    ThemeData dark,
    ThemeMode mode,
  )
  builder;

  const DynamicColorWrapper({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        ColorScheme lightScheme;
        ColorScheme darkScheme;

        final canUseDynamic =
            themeProvider.useDynamicColor &&
            lightDynamic != null &&
            darkDynamic != null;

        if (canUseDynamic) {
          lightScheme = lightDynamic.harmonized();
          darkScheme = darkDynamic.harmonized();
        } else {
          lightScheme = ColorScheme.fromSeed(
            seedColor: themeProvider.seedColor,
            brightness: Brightness.light,
          );
          darkScheme = ColorScheme.fromSeed(
            seedColor: themeProvider.seedColor,
            brightness: Brightness.dark,
          );
        }

        if (themeProvider.useAmoled) {
          darkScheme = _applyAmoledColors(darkScheme);
        }

        final lightTheme = AppTheme.light(
          dynamicScheme: lightScheme,
          transparentUi: themeProvider.useTransparentUi,
        );
        final darkTheme = AppTheme.dark(
          dynamicScheme: darkScheme,
          isAmoled: themeProvider.useAmoled,
          transparentUi: themeProvider.useTransparentUi,
        );

        return builder(context, lightTheme, darkTheme, themeProvider.themeMode);
      },
    );
  }

  ColorScheme _applyAmoledColors(ColorScheme scheme) {
    return scheme.copyWith(
      surface: Colors.black,
      onSurface: Colors.white,
      surfaceContainerLowest: Colors.black,
      surfaceContainerLow: const Color(0xFF0A0A0A),
      surfaceContainer: const Color(0xFF121212),
      surfaceContainerHigh: const Color(0xFF1A1A1A),
      surfaceContainerHighest: const Color(0xFF222222),
      inverseSurface: Colors.white,
      onInverseSurface: Colors.black,
    );
  }
}
