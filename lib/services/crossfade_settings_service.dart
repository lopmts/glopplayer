import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persiste e expõe as preferências de crossfade (fade entre faixas).
/// ChangeNotifier simples pra UI reagir (ex: switch/slider na tela de
/// configurações) sem precisar de um pacote de state management extra.
class CrossfadeSettingsService extends ChangeNotifier {
  static const _keyEnabled = 'crossfade_enabled';
  static const _keyDurationSeconds = 'crossfade_duration_seconds';

  static const int minSeconds = 1;
  static const int maxSeconds = 10;
  static const int defaultSeconds = 4;

  bool _enabled = false;
  int _durationSeconds = defaultSeconds;
  bool _loaded = false;

  bool get enabled => _enabled;
  int get durationSeconds => _durationSeconds;
  Duration get duration => Duration(seconds: _durationSeconds);
  bool get isLoaded => _loaded;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_keyEnabled) ?? false;
    _durationSeconds = (prefs.getInt(_keyDurationSeconds) ?? defaultSeconds)
        .clamp(minSeconds, maxSeconds);
    _loaded = true;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, value);
  }

  Future<void> setDurationSeconds(int seconds) async {
    _durationSeconds = seconds.clamp(minSeconds, maxSeconds);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyDurationSeconds, _durationSeconds);
  }
}
