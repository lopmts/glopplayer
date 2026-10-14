import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme_settings.dart'; // ajuste o import para o caminho real do arquivo

const String _kPrefsKey = 'theme_settings';

/// Controla o [ThemeSettings] atual do app, persiste as escolhas do usuário
/// e notifica o MaterialApp sempre que algo muda (tema, cor dinâmica, AMOLED...).
class ThemeController extends ChangeNotifier {
  ThemeController() {
    _load();
  }

  ThemeSettings _settings = const ThemeSettings();
  bool _isLoaded = false;

  ThemeSettings get settings => _settings;
  bool get isLoaded => _isLoaded;

  ThemeMode get themeMode => _settings.themeMode;
  bool get useDynamicColor => _settings.useDynamicColor;
  bool get useAmoled => _settings.useAmoled;
  bool get useTransparentUi => _settings.useTransparentUi;
  Color get seedColor => _settings.seedColor;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPrefsKey);
    if (raw != null) {
      try {
        _settings = ThemeSettings.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      } catch (_) {
        // JSON inválido/versão antiga -> mantém o padrão
      }
    }
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefsKey, jsonEncode(_settings.toJson()));
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_settings.themeMode == mode) return;
    _settings = _settings.copyWith(themeMode: mode);
    notifyListeners();
    await _persist();
  }

  Future<void> setUseDynamicColor(bool value) async {
    if (_settings.useDynamicColor == value) return;
    _settings = _settings.copyWith(useDynamicColor: value);
    notifyListeners();
    await _persist();
  }

  Future<void> setSeedColor(Color color) async {
    if (_settings.seedColorValue == color.value) return;
    _settings = _settings.copyWith(seedColorValue: color.value);
    notifyListeners();
    await _persist();
  }

  Future<void> setUseAmoled(bool value) async {
    if (_settings.useAmoled == value) return;
    _settings = _settings.copyWith(useAmoled: value);
    notifyListeners();
    await _persist();
  }

  Future<void> setUseTransparentUi(bool value) async {
    if (_settings.useTransparentUi == value) return;
    _settings = _settings.copyWith(useTransparentUi: value);
    notifyListeners();
    await _persist();
  }
}
