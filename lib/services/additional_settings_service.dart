import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AdditionalSettingsService extends ChangeNotifier {
  static const _showPlayerOnAlbumsKey = 'show_player_on_albums';

  bool _showPlayerOnAlbums = true;
  bool _isLoaded = false;

  bool get showPlayerOnAlbums => _showPlayerOnAlbums;
  bool get isLoaded => _isLoaded;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _showPlayerOnAlbums = prefs.getBool(_showPlayerOnAlbumsKey) ?? true;
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> setShowPlayerOnAlbums(bool value) async {
    _showPlayerOnAlbums = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showPlayerOnAlbumsKey, value);
  }
}
