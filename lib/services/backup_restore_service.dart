import 'dart:convert';

import 'package:glopplayer/db/favorites_db.dart';
import 'package:glopplayer/db/playlist_db.dart';

typedef BackupProgressCallback = Future<void> Function(int current, int total);

class BackupDataSummary {
  final int playlists;
  final int playlistSongs;
  final int favorites;

  const BackupDataSummary({
    required this.playlists,
    required this.playlistSongs,
    required this.favorites,
  });
}

class AppBackup {
  static const formatName = 'glopplayer-backup';
  static const currentVersion = 1;

  final List<Map<String, Object?>> playlists;
  final List<Map<String, Object?>> favorites;

  const AppBackup({
    required this.playlists,
    required this.favorites,
  });

  factory AppBackup.decode(String json) {
    final decoded = jsonDecode(json);
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != formatName ||
        decoded['version'] != currentVersion) {
      throw const FormatException(
        'O arquivo não é um backup compatível do GlopPlay.',
      );
    }

    return AppBackup(
      playlists: _readPlaylists(decoded['playlists']),
      favorites: _readFavorites(decoded['favorites']),
    );
  }

  Map<String, Object?> toMap() => {
        'format': formatName,
        'version': currentVersion,
        'exported_at': DateTime.now().toUtc().toIso8601String(),
        'playlists': playlists,
        'favorites': favorites,
      };

  static List<Map<String, Object?>> _readPlaylists(Object? value) {
    if (value is! List) {
      throw const FormatException('A lista de playlists está ausente.');
    }

    return value.map((item) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Há uma playlist inválida no backup.');
      }
      final name = item['name'];
      if (name is! String || name.trim().isEmpty) {
        throw const FormatException('Uma playlist não tem nome válido.');
      }
      final songsValue = item['songs'];
      if (songsValue is! List) {
        throw const FormatException(
          'A lista de músicas de uma playlist está inválida.',
        );
      }

      final songs = songsValue.map(_readPlaylistSong).toList();
      return <String, Object?>{
        'name': name.trim(),
        'cover_art_id': _optionalInt(item['cover_art_id'], 'capa'),
        'created_at': _requiredInt(item['created_at'], 'data de criação'),
        'updated_at': _requiredInt(item['updated_at'], 'data de atualização'),
        'songs': songs,
      };
    }).toList();
  }

  static Map<String, Object?> _readPlaylistSong(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Há uma música de playlist inválida.');
    }
    return {
      'song_id': _requiredInt(value['song_id'], 'ID da música'),
      'title': _requiredString(value['title'], 'título da música'),
      'artist': _optionalString(value['artist'], 'artista'),
      'album': _optionalString(value['album'], 'álbum'),
      'duration': _optionalInt(value['duration'], 'duração'),
      'added_at': _requiredInt(value['added_at'], 'data de adição'),
    };
  }

  static List<Map<String, Object?>> _readFavorites(Object? value) {
    if (value is! List) {
      throw const FormatException('A lista de favoritos está ausente.');
    }

    return value.map((item) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Há um favorito inválido no backup.');
      }
      final favoritedAt = item['favorited_at'];
      if (favoritedAt is! String || DateTime.tryParse(favoritedAt) == null) {
        throw const FormatException(
          'A data de um favorito está inválida.',
        );
      }
      return <String, Object?>{
        'song_id': _requiredInt(item['song_id'], 'ID da música favorita'),
        'title': _requiredString(item['title'], 'título da música favorita'),
        'artist': _optionalString(item['artist'], 'artista'),
        'album': _optionalString(item['album'], 'álbum'),
        'album_id': _optionalInt(item['album_id'], 'ID do álbum'),
        'genre': _optionalString(item['genre'], 'gênero'),
        'data': _optionalString(item['data'], 'caminho da música'),
        'favorited_at': favoritedAt,
      };
    }).toList();
  }

  static int _requiredInt(Object? value, String field) {
    if (value is! int || value < 0) {
      throw FormatException('O campo "$field" está inválido.');
    }
    return value;
  }

  static int? _optionalInt(Object? value, String field) {
    if (value == null) return null;
    return _requiredInt(value, field);
  }

  static String _requiredString(Object? value, String field) {
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('O campo "$field" está inválido.');
    }
    return value;
  }

  static String? _optionalString(Object? value, String field) {
    if (value == null) return null;
    if (value is! String) {
      throw FormatException('O campo "$field" está inválido.');
    }
    return value;
  }
}

class BackupImportResult {
  final int playlists;
  final int playlistSongs;
  final int favorites;

  const BackupImportResult({
    required this.playlists,
    required this.playlistSongs,
    required this.favorites,
  });
}

class BackupRestoreService {
  static Future<BackupDataSummary> getDataSummary() async {
    final counts = await Future.wait<int>([
      PlaylistDB.getPlaylistCount(),
      PlaylistDB.getAllPlaylistSongCount(),
      FavoritesDb.instance.getCount(),
    ]);
    return BackupDataSummary(
      playlists: counts[0],
      playlistSongs: counts[1],
      favorites: counts[2],
    );
  }

  static Future<String> exportJson({BackupProgressCallback? onProgress}) async {
    final playlists = await PlaylistDB.getAllPlaylists();
    final favorites = await FavoritesDb.instance.getAll();
    final total = playlists.length +
        playlists.fold<int>(
          0,
          (count, playlist) => count + playlist.songs.length,
        ) +
        favorites.length;
    var current = 0;
    final backupPlaylists = <Map<String, Object?>>[];
    for (final playlist in playlists) {
      final map = playlist.toMap();
      final songs = <Map<String, Object?>>[];
      for (final song in playlist.songs) {
        final songMap = song.toMap();
        songs.add({
          'song_id': songMap['song_id'],
          'title': songMap['song_title'],
          'artist': songMap['song_artist'],
          'album': songMap['song_album'],
          'duration': songMap['song_duration'],
          'added_at': songMap['added_at'],
        });
        current++;
        await onProgress?.call(current, total);
      }
      map['songs'] = songs;
      backupPlaylists.add(Map<String, Object?>.from(map));
      current++;
      await onProgress?.call(current, total);
    }
    final backupFavorites = <Map<String, Object?>>[];
    for (final favorite in favorites) {
      backupFavorites.add(favorite);
      current++;
      await onProgress?.call(current, total);
    }

    final backup = AppBackup(
      playlists: backupPlaylists,
      favorites: backupFavorites,
    );
    if (total == 0) {
      await onProgress?.call(1, 1);
    } else if (onProgress != null) {
      await onProgress(current, total);
    }
    return const JsonEncoder.withIndent('  ').convert(backup.toMap());
  }

  static Future<BackupImportResult> importBackup(
    AppBackup backup, {
    BackupProgressCallback? onProgress,
  }) async {
    final total = backup.playlists.length +
        backup.playlists.fold<int>(
          0,
          (count, playlist) =>
              count + (playlist['songs'] as List<Map<String, Object?>>).length,
        ) +
        backup.favorites.length;
    var current = 0;

    Future<void> reportProgress() async {
      current++;
      await onProgress?.call(current, total);
    }

    final playlistCount = await PlaylistDB.mergeImportedPlaylists(
      backup.playlists,
      onPlaylistProcessed: reportProgress,
      onSongProcessed: reportProgress,
    );
    final favoriteCount = await FavoritesDb.instance.mergeImported(
      backup.favorites,
      onRowProcessed: reportProgress,
    );
    if (total == 0) {
      await onProgress?.call(1, 1);
    } else if (onProgress != null) {
      await onProgress(current, total);
    }
    return BackupImportResult(
      playlists: backup.playlists.length,
      playlistSongs: playlistCount,
      favorites: favoriteCount,
    );
  }
}
