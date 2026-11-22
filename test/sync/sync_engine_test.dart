// The sync engine over FakeApi (F12, D-1351 / D-1352): no request with an empty outbox, ops drained in order in
// batches of ≤ 100, a 5xx keeps the op and books ONE retry on a growing backoff (a fake timer: no real waiting),
// a rejected op dropped and told once, `duplicate` treated as applied, two users kept apart, the status
// transitions, and the kill switch. 7.R: the push names its user and a 409 `sync_wrong_user` keeps the rows, View-As
// queues and sends nothing, a 4xx batch is split to find the one bad op, a 429 backs off, ten failures park a row
// (no timer left; tried again on a manual run), a `sync_error` answer keeps the row.
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart' show RequestOptions;
import 'package:flutter/foundation.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/offline/sync/local_db.dart';
import 'package:flutter_education_app/core/offline/sync/outbox.dart';
import 'package:flutter_education_app/core/offline/sync/sync_engine.dart';
import 'package:flutter_education_app/core/offline/sync/sync_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';

/// A timer the test fires by hand.
class _FakeTimer implements Timer {
  _FakeTimer(this.duration, this.callback);
  final Duration duration;
  final void Function() callback;
  bool _active = true;

  void fire() {
    if (!_active) return;
    _active = false;
    callback();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;
}

class _Rig {
  _Rig({this.user = 7}) {
    outbox = Outbox(open: () async => db, userId: () async => user, available: () => on, viewingAs: () => viewing, status: status);
    engine = SyncEngine(
      api: ApiClient(),
      outbox: outbox,
      status: status,
      online: online,
      notify: notices.add,
      timer: (d, f) {
        final t = _FakeTimer(d, f);
        timers.add(t);
        return t;
      },
    );
  }

  int? user;
  bool on = true;
  bool viewing = false;
  final db = MemoryLocalDb();
  final status = SyncStatus();
  final online = ValueNotifier<bool>(true);
  final notices = <String>[];
  final timers = <_FakeTimer>[];
  late final Outbox outbox;
  late final SyncEngine engine;

  Future<void> add(String id, {String kind = SyncKinds.gamePlay, Map<String, dynamic>? payload}) async =>
      expect(await outbox.enqueue(id: id, kind: kind, payload: payload ?? {'game_id': 1, 'score': 3, 'max_score': 5}),
          EnqueueResult.queued);
}

Map<String, dynamic> _body(RequestOptions o) {
  final d = o.data;
  return (d is String ? jsonDecode(d) : d) as Map<String, dynamic>;
}

List<Map<String, dynamic>> _ops(RequestOptions o) => [for (final x in _body(o)['ops'] as List) x as Map<String, dynamic>];

/// Answers every op with [status] (and its own entity).
Object _answerAll(RequestOptions o, {String status = 'applied'}) => {
      'results': [
        for (final op in _ops(o)) {'id': op['id'], 'status': status, 'entity': {'client_id': op['id'], 'points': 5}},
      ],
      'server_time': '2026-11-21T12:00:00Z',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeApi api;
  late List<RequestOptions> pushes;
  late Object? Function(RequestOptions o) answer;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    pushes = [];
    answer = (o) => _answerAll(o);
    api = FakeApi({
      'POST /api/v1/sync/push': (o) {
        pushes.add(o);
        return answer(o);
      },
    }, latency: Duration.zero);
    api.install();
  });
  tearDown(() => api.uninstall());

  test('an empty outbox makes no request', () async {
    final r = _Rig();
    await r.engine.run();
    r.engine.onReconnect();
    r.engine.onResume();
    await r.engine.run();
    expect(api.calls, isEmpty);
    expect(r.status.value, SyncSnapshot.idle);
  });

  test('drains in order, in batches of at most 100, and hands each entity to its kind', () async {
    final r = _Rig();
    final seen = <SyncResult>[];
    r.engine.listen(SyncKinds.gamePlay, seen.add);
    for (var i = 0; i < 150; i++) {
      await r.add('op-${i.toString().padLeft(5, '0')}');
    }
    await r.engine.run();
    expect(pushes, hasLength(2));
    expect(_ops(pushes[0]), hasLength(100));
    expect(_ops(pushes[1]), hasLength(50));
    final sent = [for (final p in pushes) ..._ops(p).map((o) => o['id'])];
    expect(sent, [for (var i = 0; i < 150; i++) 'op-${i.toString().padLeft(5, '0')}']);
    final first = _ops(pushes[0]).first;
    expect(first['kind'], 'game_play');
    expect(first['payload'], {'game_id': 1, 'score': 3, 'max_score': 5});
    expect(first['client_ts'], isA<String>());
    expect(first.containsKey('base_updated_at'), isFalse);
    expect(await r.outbox.rowsFor(7), isEmpty);
    expect(seen, hasLength(150));
    expect(seen.first.entity, {'client_id': 'op-00000', 'points': 5});
    expect(r.notices, isEmpty);
    expect(r.status.value, SyncSnapshot.idle);
  });

  test('a 5xx keeps the op and backs off; the retry sends it; the backoff grows', () async {
    final r = _Rig();
    await r.add('op-retry-01');
    answer = (_) => const FakeResponse(503, {'detail': 'busy'});
    await r.engine.run();
    expect(pushes, hasLength(1));
    expect((await r.outbox.rowsFor(7)).single.tries, 1);
    expect(r.timers, hasLength(1));
    expect(r.timers.single.duration, const Duration(seconds: 5));
    expect(r.status.value, const SyncSnapshot(phase: SyncPhase.online, pending: 1));

    // the retry fails again: the next wait is longer, still one timer at a time
    r.timers.last.fire();
    await pumpEventQueue();
    expect(pushes, hasLength(2));
    expect(r.timers.where((t) => t.isActive), hasLength(1));
    expect(r.timers.last.duration, const Duration(seconds: 10));
    expect(r.engine.failures, 2);

    // the server is back: the op goes, the backoff is forgotten
    answer = (o) => _answerAll(o);
    r.timers.last.fire();
    await pumpEventQueue();
    expect(pushes, hasLength(3));
    expect(await r.outbox.rowsFor(7), isEmpty);
    expect(r.engine.failures, 0);
    expect(r.engine.retryBooked, isFalse);

    // a transport error behaves like a 5xx
    await r.add('op-retry-02');
    answer = (_) => throw const ApiException(statusCode: 0, message: 'offline', type: ApiErrorType.network);
    await r.engine.run();
    expect((await r.outbox.rowsFor(7)).single.id, 'op-retry-02');
    expect(r.engine.retryBooked, isTrue);
    expect(syncBackoff(1), const Duration(seconds: 5));
    expect(syncBackoff(20), const Duration(minutes: 5));
  });

  test('a rejected op is dropped and told once; the good ones around it are applied', () async {
    AppConfig.lang = 'en';
    final r = _Rig();
    final rejected = <SyncResult>[];
    r.engine.listen(SyncKinds.quranProgress, (x) {
      if (x.rejected) rejected.add(x);
    });
    await r.add('op-good-001');
    await r.add('op-bad-0001', kind: SyncKinds.quranProgress, payload: {'surah': 200, 'from_ayah': 1, 'to_ayah': 2, 'kind': 'new'});
    await r.add('op-good-002');
    answer = (o) => {
          'results': [
            for (final op in _ops(o))
              op['id'] == 'op-bad-0001'
                  ? {'id': op['id'], 'status': 'rejected', 'code': 'sync_bad_op'}
                  : {'id': op['id'], 'status': 'applied', 'entity': <String, dynamic>{}},
          ],
        };
    await r.engine.run();
    expect(await r.outbox.rowsFor(7), isEmpty);
    expect(r.notices, ['Something you did offline could not be saved, so it was dropped from the queue.']);
    expect(rejected.single.code, 'sync_bad_op');
    // nothing is left, so nothing is sent or told again
    await r.engine.run();
    expect(pushes, hasLength(1));
    expect(r.notices, hasLength(1));
  });

  test('a stale profile edit reaches its listener (the screen refetches) with the server copy', () async {
    AppConfig.lang = 'ar';
    final r = _Rig();
    SyncResult? got;
    r.engine.listen(SyncKinds.studyProfile, (x) => got = x);
    await r.outbox.enqueue(id: 'op-prof-001', kind: SyncKinds.studyProfile, payload: {'grade_id': 4}, baseUpdatedAt: '2026-11-01T00:00:00Z');
    answer = (o) {
      expect(_ops(o).single['base_updated_at'], '2026-11-01T00:00:00Z');
      return {
        'results': [
          {'id': 'op-prof-001', 'status': 'rejected', 'code': 'sync_stale', 'entity': {'grade_id': 5, 'updated_at': '2026-11-10T00:00:00Z'}},
        ],
      };
    };
    await r.engine.run();
    expect(got!.stale, isTrue);
    expect(got!.entity!['grade_id'], 5);
    expect(r.notices.single, contains('ملفك الدراسي'));
    AppConfig.lang = 'en';
  });

  test('duplicate counts as applied and answers the first entity', () async {
    final r = _Rig();
    SyncResult? got;
    r.engine.listen(SyncKinds.gamePlay, (x) => got = x);
    await r.add('op-dupe-001');
    answer = (o) => _answerAll(o, status: 'duplicate');
    await r.engine.run();
    expect(await r.outbox.rowsFor(7), isEmpty);
    expect(got!.accepted, isTrue);
    expect(got!.entity!['points'], 5);
    expect(r.notices, isEmpty);
  });

  test('an op the answer leaves out stays for later and does not spin', () async {
    final r = _Rig();
    await r.add('op-left-001');
    answer = (_) => {'results': <Object>[]};
    await r.engine.run();
    expect(pushes, hasLength(1));
    expect((await r.outbox.rowsFor(7)).single.state, OutboxRow.pending);
    expect(r.engine.retryBooked, isTrue);
  });

  test('two users on one device: only the signed-in user\'s rows go out', () async {
    final r = _Rig(user: 7);
    await r.add('op-user7-01');
    r.user = 8;
    await r.add('op-user8-01');
    await r.engine.run();
    expect(pushes, hasLength(1));
    expect(_ops(pushes.single).map((o) => o['id']), ['op-user8-01']);
    expect((await r.outbox.rowsFor(7)).single.id, 'op-user7-01');
    r.user = null; // signed out: nothing is sent
    await r.engine.run();
    expect(pushes, hasLength(1));
  });

  test('the status: offline with writes waiting → syncing → online and quiet', () async {
    final r = _Rig();
    final seen = <SyncSnapshot>[];
    r.status.addListener(() => seen.add(r.status.value));
    r.status.bindOnline(r.online);
    r.online.value = false;
    await r.add('op-stat-001');
    await r.engine.run(); // offline: no request
    expect(api.calls, isEmpty);
    expect(r.status.value, const SyncSnapshot(phase: SyncPhase.offline, pending: 1));
    // the older queues only report into it
    r.status.report(SyncStatus.attendance, 2);
    expect(r.status.value.pending, 3);
    r.status.report(SyncStatus.attendance, 0);

    r.online.value = true;
    expect(r.status.value, const SyncSnapshot(phase: SyncPhase.online, pending: 1));
    await r.engine.run();
    expect(seen, containsAllInOrder([
      const SyncSnapshot(phase: SyncPhase.offline, pending: 1),
      const SyncSnapshot(phase: SyncPhase.online, pending: 1),
      const SyncSnapshot(phase: SyncPhase.syncing, pending: 1),
      const SyncSnapshot(phase: SyncPhase.syncing, pending: 0),
      SyncSnapshot.idle,
    ]));
    expect(r.status.value.quiet, isTrue);
  });

  test('an enqueue runs the engine once bound; sync.offline off = no outbox and no request', () async {
    final r = _Rig();
    r.engine.bind();
    await r.add('op-bind-001');
    await pumpEventQueue();
    await r.engine.run();
    expect(pushes, hasLength(1));

    r.on = false; // the kill switch
    expect(await r.outbox.enqueue(id: 'op-off-0001', kind: SyncKinds.gamePlay, payload: {}), EnqueueResult.postDirectly);
    await r.engine.run();
    expect(pushes, hasLength(1));
  });

  test('the push names its user; 409 sync_wrong_user keeps the rows, books no retry, is not a failure', () async {
    final r = _Rig();
    await r.add('op-whose-001');
    await r.engine.run();
    expect(_body(pushes.single)['user_id'], 7);

    await r.add('op-whose-002');
    answer = (_) => const FakeResponse(409, {'detail': {'code': 'sync_wrong_user', 'message': 'x'}});
    await r.engine.run();
    final row = (await r.outbox.rowsFor(7)).single;
    expect(row.id, 'op-whose-002');
    expect(row.state, OutboxRow.pending);
    expect(row.tries, 0);
    expect(r.engine.retryBooked, isFalse);
    expect(r.engine.failures, 0);
    expect(r.notices, isEmpty);
  });

  test('while View-As is on nothing is queued and nothing is sent', () async {
    final r = _Rig();
    await r.add('op-view-0001');
    r.viewing = true;
    expect(await r.outbox.enqueue(id: 'op-view-0002', kind: SyncKinds.gamePlay, payload: {}), EnqueueResult.postDirectly);
    await r.engine.run();
    expect(pushes, isEmpty);
    r.viewing = false;
    await r.engine.run();
    expect(_ops(pushes.single).map((o) => o['id']), ['op-view-0001']);
  });

  test('a 422 on a batch of three: only the bad op is dropped (told once), the other two are sent', () async {
    AppConfig.lang = 'en';
    final r = _Rig();
    final seen = <SyncResult>[];
    r.engine.listen(SyncKinds.gamePlay, seen.add);
    await r.add('op-four-001');
    await r.add('op-four-bad');
    await r.add('op-four-003');
    answer = (o) => _ops(o).any((x) => x['id'] == 'op-four-bad')
        ? const FakeResponse(422, {'detail': [{'msg': 'bad'}]})
        : _answerAll(o);
    await r.engine.run();
    expect([for (final p in pushes) _ops(p).map((o) => o['id']).toList()], [
      ['op-four-001', 'op-four-bad', 'op-four-003'],
      ['op-four-001'],
      ['op-four-bad'],
      ['op-four-003'],
    ]);
    expect(await r.outbox.rowsFor(7), isEmpty);
    expect([for (final x in seen) '${x.id} ${x.status}'], ['op-four-001 applied', 'op-four-bad rejected', 'op-four-003 applied']);
    expect(seen[1].code, 'sync_bad_op');
    expect(r.notices, [syncRejectedText('sync_bad_op')]);
    expect(r.engine.retryBooked, isFalse);
  });

  test('a 429 backs off and keeps the op', () async {
    final r = _Rig();
    await r.add('op-slow-001');
    answer = (_) => const FakeResponse(429, {'detail': 'slow down'});
    await r.engine.run();
    final row = (await r.outbox.rowsFor(7)).single;
    expect(row.tries, 1);
    expect(row.state, OutboxRow.pending);
    expect(r.engine.retryBooked, isTrue);
    expect(r.timers.single.duration, const Duration(seconds: 5));
  });

  test('a 500 ten times parks the row: no timer left, counted apart, tried again on a manual run', () async {
    final r = _Rig();
    await r.add('op-park-001');
    answer = (_) => const FakeResponse(500, {'detail': 'boom'});
    await r.engine.run();
    for (var i = 1; i < OutboxRow.parkAt; i++) {
      expect(r.engine.retryBooked, isTrue, reason: 'try $i');
      r.timers.last.fire();
      await pumpEventQueue();
    }
    expect(pushes, hasLength(OutboxRow.parkAt));
    final row = (await r.outbox.rowsFor(7)).single;
    expect(row.state, OutboxRow.parked);
    expect(row.tries, OutboxRow.parkAt);
    expect(r.engine.retryBooked, isFalse);
    expect(r.timers.where((t) => t.isActive), isEmpty);
    expect(r.status.value, const SyncSnapshot(phase: SyncPhase.online, pending: 0, attention: 1));

    // automatic runs leave it out; a manual "Sync now" tries it once
    r.engine.onReconnect();
    await r.engine.run();
    expect(pushes, hasLength(OutboxRow.parkAt));
    answer = (o) => _answerAll(o);
    await r.engine.run(withParked: true);
    expect(pushes, hasLength(OutboxRow.parkAt + 1));
    expect(await r.outbox.rowsFor(7), isEmpty);
    expect(r.status.value, SyncSnapshot.idle);
  });

  test('a sync_error answer keeps the row (no notice), retries it, and parks it after ten', () async {
    final r = _Rig();
    final seen = <SyncResult>[];
    r.engine.listen(SyncKinds.gamePlay, seen.add);
    await r.add('op-flaky-01');
    await r.add('op-fine-001');
    answer = (o) => {
          'results': [
            for (final op in _ops(o))
              op['id'] == 'op-flaky-01'
                  ? {'id': op['id'], 'status': 'rejected', 'code': 'sync_error'}
                  : {'id': op['id'], 'status': 'applied', 'entity': <String, dynamic>{}},
          ],
        };
    await r.engine.run();
    expect(pushes, hasLength(1));                  // not sent again in the same run
    final row = (await r.outbox.rowsFor(7)).single;
    expect(row.id, 'op-flaky-01');
    expect(row.tries, 1);
    expect(row.state, OutboxRow.pending);
    expect(r.notices, isEmpty);
    expect(seen.map((x) => x.id), ['op-fine-001']);
    expect(r.engine.retryBooked, isTrue);
    for (var i = 1; i < OutboxRow.parkAt; i++) {
      r.timers.last.fire();
      await pumpEventQueue();
    }
    expect((await r.outbox.rowsFor(7)).single.state, OutboxRow.parked);
    expect(r.engine.retryBooked, isFalse);
    expect(r.notices, isEmpty);
  });
}
