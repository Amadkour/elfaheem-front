// lib/core/offline/sync/local_db.dart — the device's own tables for the offline-first layer (D-1351, D-1353).
//
// Two tables, nothing else:
//   outbox      the writes made while offline (or before the server answered), one row per op: the op id IS the
//               entity's `client_id`, so a row sent twice is one row on the server (CONTRACT §7);
//   read_cache  the last answer of a few GETs per user, shown while offline (ReadCache).
//
// Phones and macOS use sqflite, Windows / Linux sqflite_common_ffi (local_db_io.dart). The web has no device
// database: it gets MemoryLocalDb and stays online-only (the Outbox answers "post directly" there). Tests use
// MemoryLocalDb, or SqfliteLocalDb over sqflite_common_ffi for the restart check.
//
// Nothing sensitive goes in here (D-1353): no tokens (secure storage), no identity numbers (ReadCache strips them),
// and MyAuthProvider.logout wipes both tables.
library;

import 'local_db_web.dart' if (dart.library.io) 'local_db_io.dart' as device;

/// One queued write.
class OutboxRow {
  const OutboxRow({
    required this.id,
    required this.kind,
    required this.payload,
    required this.clientTs,
    required this.userId,
    this.baseUpdatedAt,
    this.tries = 0,
    this.state = OutboxRow.pending,
    this.seq = 0,
  });

  static const pending = 'pending';

  /// Handed to the server in the current push; a crash in between leaves it here and the next run sends it again
  /// (the op id makes that a `duplicate`, never a second row).
  static const sending = 'sending';

  /// Failed [parkAt] times: left out of automatic runs, tried once on app start and on a manual "Sync now"
  /// (SyncStatus counts it apart, "needs attention").
  static const parked = 'parked';

  /// The tries after which a row is [parked].
  static const parkAt = 10;

  /// The op id = the entity's `client_id` (8–36 of `A-Za-z0-9_.:-`).
  final String id;
  final String kind;

  /// The JSON payload of the kind (CONTRACT §7 "Payloads"), encoded.
  final String payload;

  /// The device's time of the action, ISO UTC.
  final String clientTs;

  /// `study_profile` only: the `updated_at` the edit was made on (D-1352).
  final String? baseUpdatedAt;

  /// The signed-in user who made it: a row only ever goes out under that user's token.
  final int userId;
  final int tries;
  final String state;

  /// Insertion order (the order the ops are sent in); 0 before insertion.
  final int seq;

  OutboxRow copyWith({int? tries, String? state, int? seq}) => OutboxRow(
        id: id,
        kind: kind,
        payload: payload,
        clientTs: clientTs,
        baseUpdatedAt: baseUpdatedAt,
        userId: userId,
        tries: tries ?? this.tries,
        state: state ?? this.state,
        seq: seq ?? this.seq,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'kind': kind,
        'payload': payload,
        'client_ts': clientTs,
        'base_updated_at': baseUpdatedAt,
        'user_id': userId,
        'tries': tries,
        'state': state,
      };

  static OutboxRow fromRow(Map<String, Object?> r) => OutboxRow(
        id: '${r['id']}',
        kind: '${r['kind']}',
        payload: '${r['payload']}',
        clientTs: '${r['client_ts']}',
        baseUpdatedAt: r['base_updated_at'] as String?,
        userId: (r['user_id'] as num).toInt(),
        tries: (r['tries'] as num?)?.toInt() ?? 0,
        state: '${r['state'] ?? pending}',
        seq: (r['seq'] as num?)?.toInt() ?? 0,
      );
}

/// One cached GET answer.
class CacheRow {
  const CacheRow({required this.userId, required this.key, required this.body, required this.savedAt, this.etag});

  final int userId;
  final String key;

  /// The answer, JSON-encoded.
  final String body;

  /// When it was stored, ISO UTC.
  final String savedAt;
  final String? etag;
}

/// What the outbox and the read cache need from the device database.
abstract class LocalDb {
  /// Adds [row] at the end of the queue; false when a row with its id is already queued (it stays as it was).
  Future<bool> outboxInsert(OutboxRow row);

  /// Every queued row in insertion order; [userId] keeps one user's rows.
  Future<List<OutboxRow>> outboxRows({int? userId});

  Future<void> outboxUpdate(String id, {int? tries, String? state});
  Future<void> outboxDelete(Iterable<String> ids);

  Future<void> cachePut(CacheRow row);
  Future<CacheRow?> cacheGet(int userId, String key);

  /// Drops every row of both tables (sign-out).
  Future<void> wipe();
}

/// The web's database and the tests': the same contract in memory, gone with the app.
class MemoryLocalDb implements LocalDb {
  final _rows = <OutboxRow>[];
  final _cache = <String, CacheRow>{};
  var _seq = 0;

  @override
  Future<bool> outboxInsert(OutboxRow row) async {
    if (_rows.any((r) => r.id == row.id)) return false;
    _rows.add(row.copyWith(seq: ++_seq));
    return true;
  }

  @override
  Future<List<OutboxRow>> outboxRows({int? userId}) async =>
      [for (final r in _rows) if (userId == null || r.userId == userId) r];

  @override
  Future<void> outboxUpdate(String id, {int? tries, String? state}) async {
    final i = _rows.indexWhere((r) => r.id == id);
    if (i >= 0) _rows[i] = _rows[i].copyWith(tries: tries, state: state);
  }

  @override
  Future<void> outboxDelete(Iterable<String> ids) async {
    final drop = ids.toSet();
    _rows.removeWhere((r) => drop.contains(r.id));
  }

  @override
  Future<void> cachePut(CacheRow row) async => _cache['${row.userId}|${row.key}'] = row;

  @override
  Future<CacheRow?> cacheGet(int userId, String key) async => _cache['$userId|$key'];

  @override
  Future<void> wipe() async {
    _rows.clear();
    _cache.clear();
  }
}

/// The device database of this platform (sqflite / ffi; memory on the web). Throws when it cannot be opened; the
/// callers then fall back to posting straight to the routes.
Future<LocalDb> openDeviceDb() => device.openDeviceDb();
