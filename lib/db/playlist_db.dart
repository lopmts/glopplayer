import 'package:glopplayer/models/playlist_models.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class PlaylistDB {
  static const String _dbName = 'playlist.db';
  static const int _dbVersion = 2;
  static const String _playlistTable = 'playlists';
  static const String _playlistSongsTable = 'playlist_songs';

  static Database? _database;

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    return await openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        // Tabela de playlists
        await db.execute('''
          CREATE TABLE $_playlistTable (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            cover_art_id INTEGER,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');

        // Tabela de músicas da playlist
        await db.execute('''
          CREATE TABLE $_playlistSongsTable (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            playlist_id INTEGER NOT NULL,
            song_id INTEGER NOT NULL,
            song_title TEXT NOT NULL,
            song_artist TEXT,
            song_album TEXT,
            song_duration INTEGER,
            added_at INTEGER NOT NULL,
            FOREIGN KEY (playlist_id) REFERENCES $_playlistTable (id) ON DELETE CASCADE
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Adicionar colunas para versão 2
          await db.execute(
              'ALTER TABLE $_playlistTable ADD COLUMN cover_art_id INTEGER');
          await db.execute(
              'ALTER TABLE $_playlistTable ADD COLUMN created_at INTEGER');
          await db.execute(
              'ALTER TABLE $_playlistTable ADD COLUMN updated_at INTEGER');
        }
      },
    );
  }

  // ============ PLAYLIST OPERATIONS ============

  static Future<int> createPlaylist(String name) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;

    return await db.insert(_playlistTable, {
      'name': name,
      'created_at': now,
      'updated_at': now,
    });
  }

  static Future<List<Playlist>> getAllPlaylists() async {
    final db = await database;
    final result = await db.query(
      _playlistTable,
      orderBy: 'created_at DESC',
    );

    final playlists = <Playlist>[];
    for (var map in result) {
      final songs = await getPlaylistSongs(map['id'] as int);
      playlists.add(Playlist.fromMap(map, songs));
    }
    return playlists;
  }

  static Future<Playlist?> getPlaylist(int id) async {
    final db = await database;
    final result = await db.query(
      _playlistTable,
      where: 'id = ?',
      whereArgs: [id],
    );

    if (result.isEmpty) return null;

    final songs = await getPlaylistSongs(id);
    return Playlist.fromMap(result.first, songs);
  }

  static Future<int> updatePlaylistName(int id, String newName) async {
    final db = await database;
    return await db.update(
      _playlistTable,
      {
        'name': newName,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<int> deletePlaylist(int id) async {
    final db = await database;
    return await db.delete(
      _playlistTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ============ PLAYLIST SONGS OPERATIONS ============

  static Future<void> addSongToPlaylist(int playlistId, SongModel song) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;

    // Verificar se a música já existe na playlist
    final existing = await db.query(
      _playlistSongsTable,
      where: 'playlist_id = ? AND song_id = ?',
      whereArgs: [playlistId, song.id],
    );

    if (existing.isNotEmpty) return; // Música já existe

    await db.insert(_playlistSongsTable, {
      'playlist_id': playlistId,
      'song_id': song.id,
      'song_title': song.title,
      'song_artist': song.artist,
      'song_album': song.album,
      'song_duration': song.duration,
      'added_at': now,
    });

    // Atualizar a capa da playlist com a última música adicionada
    await _updatePlaylistCover(playlistId, song.id);

    // Atualizar updated_at
    await db.update(
      _playlistTable,
      {'updated_at': now},
      where: 'id = ?',
      whereArgs: [playlistId],
    );
  }

  static Future<void> removeSongFromPlaylist(int playlistId, int songId) async {
    final db = await database;
    await db.delete(
      _playlistSongsTable,
      where: 'playlist_id = ? AND song_id = ?',
      whereArgs: [playlistId, songId],
    );

    // Atualizar a capa para a última música restante
    await _updatePlaylistCover(playlistId);

    // Atualizar updated_at
    await db.update(
      _playlistTable,
      {'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [playlistId],
    );
  }

  static Future<List<PlaylistSong>> getPlaylistSongs(int playlistId) async {
    final db = await database;
    final result = await db.query(
      _playlistSongsTable,
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
      orderBy: 'added_at DESC',
    );

    return result.map((map) => PlaylistSong.fromMap(map)).toList();
  }

  static Future<void> clearPlaylistSongs(int playlistId) async {
    final db = await database;
    await db.delete(
      _playlistSongsTable,
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
    );

    // Resetar a capa
    await db.update(
      _playlistTable,
      {'cover_art_id': null},
      where: 'id = ?',
      whereArgs: [playlistId],
    );
  }

  static Future<int> getPlaylistSongCount(int playlistId) async {
    final db = await database;
    final result = await db.query(
      _playlistSongsTable,
      columns: ['COUNT(*) as count'],
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // ============ HELPER METHODS ============

  static Future<void> _updatePlaylistCover(int playlistId,
      [int? newSongId]) async {
    final db = await database;

    if (newSongId != null) {
      // Atualizar com a nova música
      await db.update(
        _playlistTable,
        {'cover_art_id': newSongId},
        where: 'id = ?',
        whereArgs: [playlistId],
      );
    } else {
      // Buscar a última música adicionada
      final result = await db.query(
        _playlistSongsTable,
        columns: ['song_id'],
        where: 'playlist_id = ?',
        whereArgs: [playlistId],
        orderBy: 'added_at DESC',
        limit: 1,
      );

      final coverId = result.isNotEmpty ? result.first['song_id'] as int : null;
      await db.update(
        _playlistTable,
        {'cover_art_id': coverId},
        where: 'id = ?',
        whereArgs: [playlistId],
      );
    }
  }
}
