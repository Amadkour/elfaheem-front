// The offline outbox and the read cache (F12, D-1351 – D-1353): a queue that survives a restart on the real device
// database (sqflite_common_ffi over a temp file), one user's rows kept apart from another's, the "post directly"
// answers, the sign-out wipe, and a cache that never keeps an identity number.
import 'dart:io';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/offline/sync/local_db.dart';
import 'package:flutter_education_app/core/offline/sync/local_db_io.dart';
import 'package:flutter_education_app/core/offline/sync/outbox.dart';
import 'package:flutter_education_app/core/offline/sync/read_cache.dart';
import 'package:flutter_education_app/core/offline/sync/sync_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('nb_outbox_'));
  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Outbox boxOver(LocalDb db, {int? Function()? user, SyncStatus? status, bool on = true}) =>
      Outbox(open: () async => db, userId: () async => user == null ? 7 : user(), available: () => on, status: status ?? SyncStatus());

  test('the queue survives a restart, in the order it was made', () async {
    final path = '${tmp.path}${Platform.pathSeparator}nb.db';
    final db1 = await SqfliteLocalDb.open(databaseFactoryFfi, path);
    final a = boxOver(db1);
    expect(await a.enqueue(id: 'op-aaaa-1', kind: SyncKinds.gamePlay, payload: {'game_id': 3, 'score': 4, 'max_score': 5}),
        EnqueueResult.queued);
    expect(await a.enqueue(id: 'op-aaaa-2', kind: SyncKinds.nahwAttempt, payload: {'lesson_id': 9, 'score': 1, 'max_score': 2}),
        EnqueueResult.queued);
    expect(await a.enqueue(id: 'op-aaaa-3', kind: SyncKinds.studyProfile, payload: {'grade_id': 2}, baseUpdatedAt: '2026-11-20T10:00:00Z'),
        EnqueueResult.queued);
    // a double tap keeps one row
    expect(await a.enqueue(id: 'op-aaaa-1', kind: SyncKinds.gamePlay, payload: {'game_id': 3}), EnqueueResult.alreadyQueued);
    await db1.close();

    // the app starts again
    final db2 = await SqfliteLocalDb.open(databaseFactoryFfi, path);
    final status = SyncStatus();
    final b = boxOver(db2, status: status);
    final rows = await b.rowsFor(7);
    expect(rows.map((r) => r.id), ['op-aaaa-1', 'op-aaaa-2', 'op-aaaa-3']);
    expect(rows.first.payload, contains('"max_score":5'));
    expect(rows.last.baseUpdatedAt, '2026-11-20T10:00:00Z');
    expect(rows.first.clientTs, endsWith('Z'));
    expect(await b.refreshCount(), 3);
    expect(status.value.pending, 3);

    await b.mark('op-aaaa-2', tries: 2, state: OutboxRow.sending);
    await b.remove(['op-aaaa-1']);
    final left = await b.rowsFor(7);
    expect(left.map((r) => r.id), ['op-aaaa-2', 'op-aaaa-3']);
    expect(left.first.tries, 2);
    expect(left.first.state, OutboxRow.sending);

    // sign-out: nothing left, the count says so
    await b.wipe();
    expect(await b.rowsFor(7), isEmpty);
    expect(status.value.pending, 0);
    await db2.close();
  });

  test('two users on one device: each sees only their own rows', () async {
    final db = MemoryLocalDb();
    var who = 7;
    final box = boxOver(db, user: () => who);
    await box.enqueue(id: 'op-user7-1', kind: SyncKinds.gamePlay, payload: {'game_id': 1});
    who = 8;
    await box.enqueue(id: 'op-user8-1', kind: SyncKinds.quranProgress, payload: {'surah': 1, 'from_ayah': 1, 'to_ayah': 7, 'kind': 'new'});
    expect((await box.rowsFor(7)).map((r) => r.id), ['op-user7-1']);
    expect((await box.rowsFor(8)).map((r) => r.id), ['op-user8-1']);
    expect((await box.rowsFor(8)).single.userId, 8);
    expect(await box.refreshCount(), 1); // the signed-in user's count only
  });

  test('no outbox: switched off, signed out or no database → post directly', () async {
    final db = MemoryLocalDb();
    expect(await boxOver(db, on: false).enqueue(id: 'op-off-0001', kind: SyncKinds.gamePlay, payload: {}), EnqueueResult.postDirectly);
    expect(await Outbox(open: () async => db, userId: () async => null, available: () => true, status: SyncStatus())
            .enqueue(id: 'op-anon-001', kind: SyncKinds.gamePlay, payload: {}),
        EnqueueResult.postDirectly);
    expect(await Outbox(open: () async => throw StateError('no db'), userId: () async => 7, available: () => true, status: SyncStatus())
            .enqueue(id: 'op-nodb-001', kind: SyncKinds.gamePlay, payload: {}),
        EnqueueResult.postDirectly);
    expect(await db.outboxRows(), isEmpty);

    // the kill switch through the disable list
    final prev = AppConfig.disableList;
    addTearDown(() => AppConfig.disableList = prev);
    AppConfig.disableList = [...prev, syncOfflineFeatureKey];
    expect(syncOfflineAvailable(), isFalse);
    AppConfig.disableList = prev.where((k) => k != syncOfflineFeatureKey).toList();
    expect(syncOfflineAvailable(), isTrue);
  });

  test('the read cache is per user, strips identity numbers and goes with the wipe', () async {
    final db = MemoryLocalDb();
    var who = 7;
    final box = boxOver(db, user: () => who);
    final cache = ReadCache(outbox: box);
    await cache.put('me.home', {
      'name': 'Mona',
      'national_id': '29801011234567',
      'children': [
        {'name': 'Ali', 'ID_Number': '123', 'passport_number': 'A1'},
      ],
    }, etag: 'W/"1"');
    final got = await cache.get('me.home');
    expect(got, isNotNull);
    expect(got!.etag, 'W/"1"');
    final body = got.body as Map;
    expect(body['name'], 'Mona');
    expect(body.containsKey('national_id'), isFalse);
    expect((body['children'] as List).single, {'name': 'Ali'});

    who = 8;
    expect(await cache.get('me.home'), isNull); // the next account never reads the last one's

    await box.wipe();
    who = 7;
    expect(await cache.get('me.home'), isNull);
  });
}
