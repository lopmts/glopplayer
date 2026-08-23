import 'package:flutter/material.dart';
import 'package:glopplayer/models/theme_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeSettings _settings = const ThemeSettings();
  ThemeSettings get settings => _settings;

  ThemeMode get themeMode => _settings.themeMode;
  bool get useDynamicColor => _settings.useDynamicColor;
  bool get useAmoled => _settings.useAmoled;
  Color get seedColor => _settings.seedColor;

  ThemeProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _settings = ThemeSettings(
      themeMode: themeModeFromString(prefs.getString(kThemeModeKey)),
      useDynamicColor: prefs.getBool(kUseDynamicColorKey) ?? true,
      seedColorValue: prefs.getInt(kSeedColorKey) ?? kDefaultSeedColor,
      useAmoled: prefs.getBool(kUseAmoledKey) ?? false,
    );
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kThemeModeKey, _settings.themeMode.name);
    await prefs.setBool(kUseDynamicColorKey, _settings.useDynamicColor);
    await prefs.setInt(kSeedColorKey, _settings.seedColorValue);
    await prefs.setBool(kUseAmoledKey, _settings.useAmoled);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _settings = _settings.copyWith(themeMode: mode);
    notifyListeners();
    await _persist();
  }

  Future<void> setUseDynamicColor(bool value) async {
    _settings = _settings.copyWith(useDynamicColor: value);
    notifyListeners();
    await _persist();
  }

  Future<void> setSeedColor(Color color) async {
    _settings = _settings.copyWith(
      // toARGB32() em vez de .value (deprecado): garante que o int salvo
      // bate exatamente com o que o _ColorPaletteItem usa para marcar
      // qual cor está selecionada.
      seedColorValue: color.toARGB32(),
      useDynamicColor: false, // escolher uma cor manual desliga o dynamic color
    );
    notifyListeners();
    await _persist();
  }

  Future<void> setUseAmoled(bool value) async {
    _settings = _settings.copyWith(useAmoled: value);
    notifyListeners();
    await _persist();
  }
}
