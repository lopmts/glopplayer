import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Acesso cru ao SQLite para a tabela de favoritos. Fica isolado numa
/// classe própria (padrão já usado no app pro cache de artwork) pra quem
/// consumir não precisar saber SQL — só [FavoritesController] fala com
/// essa classe diretamente.
class FavoritesDb {
  FavoritesDb._internal();
  static final FavoritesDb instance = FavoritesDb._internal();

  static const _dbName = 'favorites.db';
  static const _dbVersion = 1;
  static const table = 'favorites';

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, _dbName);

    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $table (
            song_id INTEGER PRIMARY KEY,
            title TEXT NOT NULL,
            artist TEXT,
            album TEXT,
            album_id INTEGER,
            genre TEXT,
            data TEXT,
            favorited_at TEXT NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_favorites_artist ON $table(artist)',
        );
        await db.execute(
          'CREATE INDEX idx_favorites_genre ON $table(genre)',
        );
      },
    );
  }

  Future<List<Map<String, Object?>>> getAll() async {
    final db = await database;
    return db.query(table, orderBy: 'favorited_at DESC');
  }

  Future<bool> exists(int songId) async {
    final db = await database;
    final rows = await db.query(
      table,
      where: 'song_id = ?',
      whereArgs: [songId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> insert(Map<String, Object?> row) async {
    final db = await database;
    await db.insert(
      table,
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete(int songId) async {
    final db = await database;
    await db.delete(table, where: 'song_id = ?', whereArgs: [songId]);
  }

  Future<void> clear() async {
    final db = await database;
    await db.delete(table);
  }
}
