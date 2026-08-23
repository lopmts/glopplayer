import 'package:flutter/foundation.dart';
import 'package:glopplayer/db/favorites_db.dart';
import 'package:on_audio_query/on_audio_query.dart';

/// Registro persistido de uma música favoritada. Guarda os campos
/// necessários pra listar/filtrar sem precisar re-consultar o
/// MediaStore, e pra reconstruir um [SongModel] "utilizável" se a
/// música tiver saído da varredura atual da biblioteca.
class FavoriteEntry {
  final int songId;
  final String title;
  final String artist;
  final String? album;
  final int? albumId;
  final String? genre;
  final String data;
  final DateTime favoritedAt;

  FavoriteEntry({
    required this.songId,
    required this.title,
    required this.artist,
    required this.data,
    required this.favoritedAt,
    this.album,
    this.albumId,
    this.genre,
  });

  factory FavoriteEntry.fromMap(Map<String, Object?> map) {
    return FavoriteEntry(
      songId: map['song_id'] as int,
      title: (map['title'] as String?) ?? 'Sem título',
      artist: (map['artist'] as String?) ?? 'Artista desconhecido',
      album: map['album'] as String?,
      albumId: map['album_id'] as int?,
      genre: map['genre'] as String?,
      data: (map['data'] as String?) ?? '',
      favoritedAt: DateTime.tryParse(map['favorited_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, Object?> toMap() => {
        'song_id': songId,
        'title': title,
        'artist': artist,
        'album': album,
        'album_id': albumId,
        'genre': genre,
        'data': data,
        'favorited_at': favoritedAt.toIso8601String(),
      };

  factory FavoriteEntry.fromSong(SongModel song) {
    return FavoriteEntry(
      songId: song.id,
      title: song.title,
      artist: song.artist ?? 'Artista desconhecido',
      album: song.album,
      albumId: song.albumId,
      genre: song.genre,
      data: song.data,
      favoritedAt: DateTime.now(),
    );
  }

  SongModel toSongModel() {
    return SongModel({
      '_id': songId,
      'title': title,
      'artist': artist,
      'album': album,
      'album_id': albumId,
      'genre': genre,
      '_data': data,
      'duration': null,
      'is_music': 1,
      'is_podcast': 0,
      'is_ringtone': 0,
      'is_alarm': 0,
      'is_notification': 0,
      'is_audiobook': 0,
    });
  }
}

/// Estado de favoritos da aplicação. Mantém um cache em memória
/// (lista + Set de ids pra lookup O(1)) sincronizado com o SQLite,
/// e notifica listeners a cada mudança — assim o ícone de coração no
/// player e a FavoritesScreen atualizam sozinhos via Provider.
class FavoritesController extends ChangeNotifier {
  final FavoritesDb _db;

  FavoritesController({FavoritesDb? db}) : _db = db ?? FavoritesDb.instance {
    _loadAll();
  }

  List<FavoriteEntry> _entries = [];
  final Set<int> _ids = {};
  bool _loading = true;

  List<FavoriteEntry> get entries => List.unmodifiable(_entries);
  bool get isLoading => _loading;

  bool isFavorite(int songId) => _ids.contains(songId);

  Future<void> _loadAll() async {
    final rows = await _db.getAll();
    _entries = rows.map(FavoriteEntry.fromMap).toList();
    _ids
      ..clear()
      ..addAll(_entries.map((e) => e.songId));
    _loading = false;
    notifyListeners();
  }

  Future<void> refresh() => _loadAll();

  /// Alterna o favorito de [song]: adiciona se ainda não existir, remove
  /// se já existir. Retorna o novo estado (true = ficou favoritada).
  Future<bool> toggle(SongModel song) async {
    if (song.id < 0) return false; // ignora arquivos externos "fake" (id = -1)

    if (_ids.contains(song.id)) {
      await _db.delete(song.id);
      _ids.remove(song.id);
      _entries.removeWhere((e) => e.songId == song.id);
      notifyListeners();
      return false;
    }

    final entry = FavoriteEntry.fromSong(song);
    await _db.insert(entry.toMap());
    _ids.add(song.id);
    _entries.insert(0, entry);
    notifyListeners();
    return true;
  }

  Future<void> remove(int songId) async {
    await _db.delete(songId);
    _ids.remove(songId);
    _entries.removeWhere((e) => e.songId == songId);
    notifyListeners();
  }

  /// Desmarca todas as músicas favoritadas.
  Future<void> clearAll() async {
    await _db.clear();
    _ids.clear();
    _entries.clear();
    notifyListeners();
  }

  /// Artistas presentes nos favoritos atuais, ordenados — usado pra
  /// popular o filtro por artista na FavoritesScreen.
  List<String> get availableArtists {
    final set = _entries.map((e) => e.artist).toSet().toList();
    set.sort();
    return set;
  }

  /// Gêneros/"tipos" presentes nos favoritos atuais, ordenados — usado
  /// pra popular o filtro por tipo na FavoritesScreen.
  List<String> get availableGenres {
    final set = _entries
        .map((e) => e.genre)
        .whereType<String>()
        .where((g) => g.trim().isNotEmpty)
        .toSet()
        .toList();
    set.sort();
    return set;
  }
}
