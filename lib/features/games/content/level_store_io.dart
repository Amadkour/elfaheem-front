// lib/features/games/content/level_store_io.dart — the device database of the offline level pools (Games v4 T36).
// sqflite on Android / iOS / macOS, sqflite_common_ffi on Windows / Linux and in tests. Its own file, apart from the
// outbox database (nb_local_v1.db), so a games change never touches the sync layer.
import 'dart:io' show Platform;

import 'package:flutter_education_app/features/games/content/level_cache.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as plugin;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

Future<LevelStore> openLevelStore() async {
  final ffi.DatabaseFactory factory;
  if (Platform.isWindows || Platform.isLinux) {
    ffi.sqfliteFfiInit();
    factory = ffi.databaseFactoryFfi;
  } else {
    factory = plugin.databaseFactory;
  }
  final dir = await getApplicationSupportDirectory();
  return SqfliteLevelStore.open(factory, p.join(dir.path, 'nb_games_v4.db'));
}

class SqfliteLevelStore implements LevelStore {
  SqfliteLevelStore._(this._db);
  final ffi.Database _db;

  /// Opens (and creates) the database at [path]; tests pass `databaseFactoryFfi` and `inMemoryDatabasePath`.
  static Future<SqfliteLevelStore> open(ffi.DatabaseFactory factory, String path) async {
    final db = await factory.openDatabase(
      path,
      options: ffi.OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute('CREATE TABLE level_pool ('
              'user_id INTEGER NOT NULL, '
              'game_id INTEGER NOT NULL, '
              'reciter TEXT, '
              'body TEXT NOT NULL, '
              'expires_at TEXT NOT NULL, '
              'saved_at TEXT NOT NULL, '
              'PRIMARY KEY (user_id, game_id))');
          await db.execute('CREATE TABLE level_seen ('
              'user_id INTEGER NOT NULL, '
              'game_id INTEGER NOT NULL, '
              'item_id INTEGER NOT NULL, '
              'PRIMARY KEY (user_id, game_id, item_id))');
        },
      ),
    );
    return SqfliteLevelStore._(db);
  }

  Future<void> close() => _db.close();

  PoolRow _row(Map<String, Object?> m) => PoolRow(
        userId: m['user_id'] as int,
        gameId: m['game_id'] as int,
        reciter: m['reciter'] as String?,
        body: '${m['body']}',
        expiresAt: '${m['expires_at']}',
        savedAt: '${m['saved_at']}',
      );

  @override
  Future<void> putPool(PoolRow row) => _db.insert(
        'level_pool',
        {
          'user_id': row.userId,
          'game_id': row.gameId,
          'reciter': row.reciter,
          'body': row.body,
          'expires_at': row.expiresAt,
          'saved_at': row.savedAt,
        },
        conflictAlgorithm: ffi.ConflictAlgorithm.replace,
      );

  @override
  Future<PoolRow?> getPool(int userId, int gameId) async {
    final r = await _db.query('level_pool', where: 'user_id = ? AND game_id = ?', whereArgs: [userId, gameId], limit: 1);
    return r.isEmpty ? null : _row(r.first);
  }

  @override
  Future<List<PoolRow>> pools(int userId) async {
    final r = await _db.query('level_pool', where: 'user_id = ?', whereArgs: [userId]);
    return [for (final m in r) _row(m)];
  }

  @override
  Future<void> deletePool(int userId, int gameId) async {
    await _db.delete('level_pool', where: 'user_id = ? AND game_id = ?', whereArgs: [userId, gameId]);
  }

  @override
  Future<void> markSeen(int userId, int gameId, Iterable<int> itemIds) async {
    final batch = _db.batch();
    for (final id in itemIds) {
      batch.insert('level_seen', {'user_id': userId, 'game_id': gameId, 'item_id': id},
          conflictAlgorithm: ffi.ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<Set<int>> seen(int userId, int gameId) async {
    final r = await _db.query('level_seen', columns: ['item_id'], where: 'user_id = ? AND game_id = ?', whereArgs: [userId, gameId]);
    return {for (final m in r) m['item_id'] as int};
  }

  @override
  Future<void> wipe() async {
    await _db.delete('level_pool');
    await _db.delete('level_seen');
  }
}
