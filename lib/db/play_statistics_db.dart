import 'package:on_audio_query/on_audio_query.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class PopularSongEntry {
  final SongModel song;
  final int playCount;
  final int bannerClickCount;

  const PopularSongEntry({
    required this.song,
    required this.playCount,
    required this.bannerClickCount,
  });

  factory PopularSongEntry.fromRow(Map<String, Object?> row) {
    return PopularSongEntry(
      song: SongModel({
        '_id': row['song_id'],
        'title': row['title'],
        'artist': row['artist'],
        'album': row['album'],
        'album_id': row['album_id'],
        'genre': row['genre'],
        '_data': row['data'],
        'duration': row['duration'],
        'is_music': 1,
        'is_podcast': 0,
        'is_ringtone': 0,
        'is_alarm': 0,
        'is_notification': 0,
        'is_audiobook': 0,
      }),
      playCount: row['play_count'] as int,
      bannerClickCount: row['banner_click_count'] as int,
    );
  }
}

class PlayStatisticsDb {
  PlayStatisticsDb._();

  static final PlayStatisticsDb instance = PlayStatisticsDb._();

  static const _dbName = 'play_statistics.db';
  static const _table = 'song_statistics';

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dbPath, _dbName),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_table (
            data TEXT PRIMARY KEY,
            song_id INTEGER NOT NULL,
            title TEXT NOT NULL,
            artist TEXT,
            album TEXT,
            album_id INTEGER,
            genre TEXT,
            duration INTEGER,
            play_count INTEGER NOT NULL DEFAULT 0,
            banner_click_count INTEGER NOT NULL DEFAULT 0,
            last_played INTEGER,
            last_clicked INTEGER
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_song_statistics_song_id ON $_table(song_id)',
        );
        await db.execute(
          'CREATE INDEX idx_song_statistics_popularity '
          'ON $_table(play_count DESC, last_played DESC)',
        );
      },
    );
    return _db!;
  }

  Future<void> recordPlay(SongModel song) => _record(song, play: true);

  Future<void> recordBannerClick(SongModel song) => _record(song, play: false);

  Future<void> _record(SongModel song, {required bool play}) async {
    if (song.id < 0 || song.data.isEmpty) return;

    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final counter = play ? 'play_count' : 'banner_click_count';
    final timestamp = play ? 'last_played' : 'last_clicked';

    await db.transaction((txn) async {
      await txn.insert(
        _table,
        {
          'data': song.data,
          'song_id': song.id,
          'title': song.title,
          'artist': song.artist,
          'album': song.album,
          'album_id': song.albumId,
          'genre': song.genre,
          'duration': song.duration,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

      await txn.rawUpdate(
        'UPDATE $_table SET '
        'title = ?, artist = ?, album = ?, album_id = ?, genre = ?, '
        'song_id = ?, duration = ?, $counter = $counter + 1, $timestamp = ? '
        'WHERE data = ?',
        [
          song.title,
          song.artist,
          song.album,
          song.albumId,
          song.genre,
          song.id,
          song.duration,
          now,
          song.data,
        ],
      );
    });
  }

  Future<List<PopularSongEntry>> getTopSongs({int limit = 5}) async {
    final db = await database;
    final rows = await db.query(
      _table,
      where: 'play_count > 0',
      orderBy: 'play_count DESC, last_played DESC, title COLLATE NOCASE ASC',
      limit: limit.clamp(1, 5).toInt(),
    );
    return rows.map(PopularSongEntry.fromRow).toList(growable: false);
  }
}
