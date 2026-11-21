// The device database on phones and desktops (D-1353): sqflite on Android / iOS / macOS, sqflite_common_ffi on
// Windows and Linux. One file in the app's support folder, two tables (local_db.dart).
import 'dart:io' show Platform;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as plugin;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

import 'local_db.dart';

const _file = 'nb_local_v1.db';

Future<LocalDb> openDeviceDb() async {
  final ffi.DatabaseFactory factory;
  if (Platform.isWindows || Platform.isLinux) {
    ffi.sqfliteFfiInit();
    factory = ffi.databaseFactoryFfi;
  } else {
    factory = plugin.databaseFactory;
  }
  final dir = await getApplicationSupportDirectory();
  return SqfliteLocalDb.open(factory, p.join(dir.path, _file));
}

class SqfliteLocalDb implements LocalDb {
  SqfliteLocalDb._(this._db);

  final ffi.Database _db;

  /// Opens (and creates) the database at [path] through [factory]; tests pass `databaseFactoryFfi`.
  static Future<SqfliteLocalDb> open(ffi.DatabaseFactory factory, String path) async {
    final db = await factory.openDatabase(
      path,
      options: ffi.OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute('CREATE TABLE outbox ('
              'seq INTEGER PRIMARY KEY AUTOINCREMENT, '
              'id TEXT NOT NULL UNIQUE, '
              'kind TEXT NOT NULL, '
              'payload TEXT NOT NULL, '
              'client_ts TEXT NOT NULL, '
              'base_updated_at TEXT, '
              'user_id INTEGER NOT NULL, '
              'tries INTEGER NOT NULL DEFAULT 0, '
              "state TEXT NOT NULL DEFAULT 'pending')");
          await db.execute('CREATE TABLE read_cache ('
              'user_id INTEGER NOT NULL, '
              'key TEXT NOT NULL, '
              'body TEXT NOT NULL, '
              'saved_at TEXT NOT NULL, '
              'etag TEXT, '
              'PRIMARY KEY (user_id, key))');
        },
      ),
    );
    return SqfliteLocalDb._(db);
  }

  Future<void> close() => _db.close();

  @override
  Future<bool> outboxInsert(OutboxRow row) async {
    final n = await _db.insert('outbox', row.toRow(), conflictAlgorithm: ffi.ConflictAlgorithm.ignore);
    return n > 0;
  }

  @override
  Future<List<OutboxRow>> outboxRows({int? userId}) async {
    final rows = await _db.query('outbox',
        where: userId == null ? null : 'user_id = ?', whereArgs: userId == null ? null : [userId], orderBy: 'seq');
    return [for (final r in rows) OutboxRow.fromRow(r)];
  }

  @override
  Future<void> outboxUpdate(String id, {int? tries, String? state}) async {
    final values = <String, Object?>{'tries': ?tries, 'state': ?state};
    if (values.isEmpty) return;
    await _db.update('outbox', values, where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> outboxDelete(Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    await _db.delete('outbox', where: 'id IN (${List.filled(list.length, '?').join(',')})', whereArgs: list);
  }

  @override
  Future<void> cachePut(CacheRow row) => _db.insert(
        'read_cache',
        {'user_id': row.userId, 'key': row.key, 'body': row.body, 'saved_at': row.savedAt, 'etag': row.etag},
        conflictAlgorithm: ffi.ConflictAlgorithm.replace,
      );

  @override
  Future<CacheRow?> cacheGet(int userId, String key) async {
    final r = await _db.query('read_cache', where: 'user_id = ? AND key = ?', whereArgs: [userId, key], limit: 1);
    if (r.isEmpty) return null;
    final m = r.first;
    return CacheRow(userId: userId, key: key, body: '${m['body']}', savedAt: '${m['saved_at']}', etag: m['etag'] as String?);
  }

  @override
  Future<void> wipe() async {
    await _db.delete('outbox');
    await _db.delete('read_cache');
  }
}
