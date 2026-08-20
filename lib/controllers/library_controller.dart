import 'package:flutter/foundation.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../db/library_database.dart'; // ajuste o caminho conforme seu projeto
import '../services/library_scan_notifications_service.dart';
import '../services/music_library_service.dart';

enum AutoScanFrequency { off, daily, weekly }

extension AutoScanFrequencyX on AutoScanFrequency {
  String get storageValue => name;
  String get label {
    switch (this) {
      case AutoScanFrequency.off:
        return 'Desativado';
      case AutoScanFrequency.daily:
        return 'Diário';
      case AutoScanFrequency.weekly:
        return 'Semanal';
    }
  }

  static AutoScanFrequency fromStorage(String value) {
    return AutoScanFrequency.values.firstWhere(
      (e) => e.storageValue == value,
      orElse: () => AutoScanFrequency.daily,
    );
  }
}

/// Motivo pelo qual addFolder() falhou, pra UI mostrar a mensagem certa.
enum AddFolderResult { success, alreadyExists, limitReached }

class LibraryController extends ChangeNotifier {
  final LibraryDatabase _db = LibraryDatabase.instance;
  final MusicLibraryService _library = MusicLibraryService();
  final OnAudioQuery _audioQuery = OnAudioQuery();
  final LibraryScanNotificationService _notifications =
      LibraryScanNotificationService.instance;

  bool _enabled = true;
  bool _showDuplicateIndicator = true;
  AutoScanFrequency _autoScanFrequency = AutoScanFrequency.daily;
  int _trackCount = 0;
  DateTime? _lastScannedAt;
  List<String> _folders = [];

  bool _isScanning = false;
  int _scanCurrent = 0;
  int _scanTotal = 0;
  bool _isLoaded = false;

  bool get enabled => _enabled;
  bool get showDuplicateIndicator => _showDuplicateIndicator;
  AutoScanFrequency get autoScanFrequency => _autoScanFrequency;
  int get trackCount => _trackCount;
  DateTime? get lastScannedAt => _lastScannedAt;
  bool get isScanning => _isScanning;
  int get scanCurrent => _scanCurrent;
  int get scanTotal => _scanTotal;
  bool get isLoaded => _isLoaded;

  List<String> get folders => List.unmodifiable(_folders);
  int get maxFolders => LibraryDatabase.maxFolders;
  bool get canAddMoreFolders => _folders.length < maxFolders;

  /// Exposto pra outras telas (lista de músicas, álbuns) filtrarem seus
  /// próprios fetches sem duplicar a lógica de "pastas configuradas".
  MusicLibraryService get library => _library;

  LibraryController() {
    _load();
  }

  Future<void> _load() async {
    final row = await _db.getSettings();
    _enabled = (row['enabled'] as int) == 1;
    _showDuplicateIndicator = (row['show_duplicate_indicator'] as int) == 1;
    _autoScanFrequency =
        AutoScanFrequencyX.fromStorage(row['auto_scan_frequency'] as String);
    _trackCount = row['track_count'] as int;
    final lastScanned = row['last_scanned_at'] as int?;
    _lastScannedAt = lastScanned != null
        ? DateTime.fromMillisecondsSinceEpoch(lastScanned)
        : null;
    _folders = await _db.getFolders();
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    notifyListeners();
    await _db.updateSettings(enabled: value);
  }

  Future<void> setShowDuplicateIndicator(bool value) async {
    _showDuplicateIndicator = value;
    notifyListeners();
    await _db.updateSettings(showDuplicateIndicator: value);
  }

  Future<void> setAutoScanFrequency(AutoScanFrequency freq) async {
    _autoScanFrequency = freq;
    notifyListeners();
    await _db.updateSettings(autoScanFrequency: freq.storageValue);
  }

  /// Adiciona uma pasta (máx. 3). Dispara um rescan ao final pra já
  /// refletir as músicas da nova pasta na tela.
  Future<AddFolderResult> addFolder(String path) async {
    if (_folders.contains(path)) return AddFolderResult.alreadyExists;
    if (_folders.length >= maxFolders) return AddFolderResult.limitReached;

    final added = await _db.addFolder(path);
    if (!added) return AddFolderResult.alreadyExists;

    _folders = await _db.getFolders();
    notifyListeners();
    await scanLibrary();
    return AddFolderResult.success;
  }

  Future<void> removeFolder(String path) async {
    await _db.removeFolder(path);
    _folders = await _db.getFolders();
    notifyListeners();
    await scanLibrary();
  }

  Future<void> scanLibrary() => _runScan(forceFull: false);
  Future<void> forceFullScan() => _runScan(forceFull: true);

  Future<void> _runScan({required bool forceFull}) async {
    if (_isScanning) return;

    _isScanning = true;
    _scanCurrent = 0;
    _scanTotal = 0;
    notifyListeners();
    await _notifications.showIndeterminate();

    try {
      // Já respeita as pastas configuradas (vazio = biblioteca inteira).
      final songs = await _library.fetchAllSongs(restrictToFolders: _folders);
      _scanTotal = songs.length;

      final alreadyScanned =
          forceFull ? <String>{} : await _db.getScannedPaths();

      var processed = 0;
      for (final song in songs) {
        final path = song.data;
        if (!forceFull && alreadyScanned.contains(path)) {
          processed++;
          continue;
        }

        await _db.upsertScannedFile(
          path: path,
          size: song.size,
          modifiedAt: song.dateModified,
        );

        processed++;
        _scanCurrent = processed;
        notifyListeners();

        if (processed % 10 == 0 || processed == _scanTotal) {
          await _notifications.updateProgress(
            current: processed,
            total: _scanTotal,
          );
        }
      }

      await _db.updateStatsAfterScan(trackCount: songs.length);
      _trackCount = songs.length;
      _lastScannedAt = DateTime.now();

      await _notifications.showCompleted(trackCount: songs.length);
    } catch (e) {
      debugPrint('Erro ao escanear biblioteca: $e');
      await _notifications.dismiss();
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }

  Future<int> cleanupMissingFiles() async {
    final songs = await _audioQuery.querySongs();
    final existing = songs.map((s) => s.data).toSet();
    final removed = await _db.removeMissingPaths(existing);
    notifyListeners();
    return removed;
  }

  Future<void> clearLibrary() async {
    await _db.clearLibrary();
    _trackCount = 0;
    _lastScannedAt = null;
    notifyListeners();
  }
}
