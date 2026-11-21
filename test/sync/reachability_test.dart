// Phase 7 QA fixes (docs/learning-hub/QA_PHASE7.md), over FakeApi with fake clocks and timers:
//   W-1 a request that gets no answer marks the server unreachable (the app goes offline, the "needs a connection"
//       guard fires) and ONE answer marks it reachable again; a stale failure (a request that went out before the
//       last answer) changes nothing, so a slow call never flips the app;
//   W-2 while unreachable with the link up, the server is probed 5 s, 10 s, … at most 60 s apart, one probe at a time,
//       at once on resume and when the link returns; never while it answers; back online the outbox drains;
//   W-3 the Quran record sheet's student list comes from the cache offline, and the cache keeps only id, name and
//       picture (never an identity number).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/offline/app_connectivity.dart';
import 'package:flutter_education_app/core/offline/sync/local_db.dart';
import 'package:flutter_education_app/core/offline/sync/offline_reads.dart';
import 'package:flutter_education_app/core/offline/sync/outbox.dart';
import 'package:flutter_education_app/core/offline/sync/read_cache.dart';
import 'package:flutter_education_app/core/offline/sync/sync_engine.dart';
import 'package:flutter_education_app/core/offline/sync/sync_status.dart';
import 'package:flutter_education_app/features/quran/quran_api.dart';
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

/// A connectivity with a hand-moved clock, hand-fired timers and a scripted probe.
class _Rig {
  _Rig() {
    conn = AppConnectivity.forTest(
      now: () => clock,
      timer: (d, f) {
        final t = _FakeTimer(d, f);
        timers.add(t);
        return t;
      },
    );
  }

  late final AppConnectivity conn;
  DateTime clock = DateTime.utc(2026, 11, 21, 12);
  final timers = <_FakeTimer>[];
  var probes = 0;
  var answers = false;

  void arm() => conn.serverProbe = () async {
        probes++;
        return answers;
      };

  List<_FakeTimer> get live => [for (final t in timers) if (t.isActive) t];

  /// Fires the one booked probe and lets it finish.
  Future<void> fire() async {
    expect(live, hasLength(1), reason: 'exactly one probe is booked at a time');
    live.single.fire();
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('W-1: no answer → offline; one answer → online', () {
    test('a failure marks the server unreachable and the "needs a connection" guard fires', () {
      final r = _Rig();
      offlineReadsOnline = () => r.conn.online;
      addTearDown(() => offlineReadsOnline = () => AppConnectivity.instance.online);
      expect(r.conn.isOnline, isTrue);
      r.conn.noteNoAnswer(startedAt: r.clock);
      expect(r.conn.isOnline, isFalse);
      final told = <String>[];
      expect(offlineBlocked(notify: told.add), isTrue);
      expect(told, [needsConnectionText()]);
      r.conn.noteAnswer();
      expect(r.conn.isOnline, isTrue, reason: 'one answer is enough');
      expect(offlineBlocked(notify: told.add), isFalse);
    });

    test('a stale failure (sent before the last answer) does not flap', () {
      final r = _Rig();
      final sent = r.clock;
      r.clock = r.clock.add(const Duration(seconds: 2));
      r.conn.noteAnswer(); // a later call answered meanwhile
      r.clock = r.clock.add(const Duration(seconds: 28));
      r.conn.noteNoAnswer(startedAt: sent); // the slow one times out
      expect(r.conn.isOnline, isTrue);
      r.conn.noteNoAnswer(startedAt: r.clock);
      expect(r.conn.isOnline, isFalse);
    });

    test('what counts as "no answer"', () {
      final o = RequestOptions(path: '/x');
      bool? of(DioExceptionType t, {int? status, Object? error}) => serverAnsweredBy(DioException(
          requestOptions: o, type: t, error: error, response: status == null ? null : Response(requestOptions: o, statusCode: status)));
      expect(of(DioExceptionType.connectionError), isFalse);
      expect(of(DioExceptionType.connectionTimeout), isFalse);
      expect(of(DioExceptionType.receiveTimeout), isFalse);
      expect(of(DioExceptionType.unknown, error: const SocketException('refused')), isFalse);
      expect(of(DioExceptionType.badResponse, status: 504), isFalse);
      expect(of(DioExceptionType.badResponse, status: 502), isFalse);
      expect(of(DioExceptionType.badResponse, status: 500), isTrue, reason: 'the server answered');
      expect(of(DioExceptionType.badResponse, status: 401), isTrue);
      expect(of(DioExceptionType.cancel), isNull);
      expect(of(DioExceptionType.badCertificate), isNull);
      expect(of(DioExceptionType.unknown, error: const ApiException(statusCode: 0, message: '')), isNull,
          reason: "the app's own refusal says nothing about the server");
    });

    group('through ApiClient (FakeApi)', () {
      late FakeApi api;
      var down = true;
      setUp(() {
        AppConfig.lang = 'ar';
        SharedPreferences.setMockInitialValues({});
        mockRequestPlugins();
        down = true;
        api = FakeApi({
          'GET /api/v1/games': (_) {
            if (down) throw const SocketException('Connection refused');
            return const <Object>[];
          },
        }, latency: Duration.zero);
        api.install();
      });
      tearDown(() {
        api.uninstall();
        AppConnectivity.instance.reportServerReachable(true);
      });

      test('a refused connection takes the app offline, with the Arabic text; the next answer brings it back', () async {
        expect(AppConnectivity.instance.isOnline, isTrue);
        Object? error;
        try {
          await ApiClient().get('/api/v1/games');
        } catch (e) {
          error = e;
        }
        expect(AppConnectivity.instance.isOnline, isFalse);
        expect(AppConnectivity.instance.probeBooked, isFalse, reason: 'no probe without main.dart\'s serverProbe');
        expect(ApiException.from(error!).message, contains('لا يوجد اتصال'), reason: 'W-6: bilingual');
        expect(isConnectionFailure(error), isTrue);

        down = false;
        await ApiClient().get('/api/v1/games');
        expect(AppConnectivity.instance.isOnline, isTrue);
      });
    });
  });

  group('W-2: re-probe while unreachable', () {
    test('5 s doubling to 60 s, one at a time, until the server answers; then nothing is booked', () async {
      final r = _Rig()..arm();
      r.conn.reportServerReachable(false); // an offline start
      expect(r.conn.isOnline, isFalse);
      final waits = <int>[];
      for (var i = 0; i < 6; i++) {
        waits.add(r.live.single.duration.inSeconds);
        await r.fire();
      }
      expect(waits, [5, 10, 20, 40, 60, 60]);
      expect(r.probes, 6);
      r.answers = true;
      await r.fire();
      expect(r.conn.isOnline, isTrue);
      expect(r.live, isEmpty, reason: 'healthy: no timer, no probe');
    });

    test('never while the server answers; a request that answers stops the probing', () async {
      final r = _Rig()..arm();
      r.conn.noteAnswer();
      expect(r.live, isEmpty);
      expect(r.probes, 0);
      r.conn.noteNoAnswer(startedAt: r.clock);
      expect(r.live, hasLength(1));
      r.conn.noteAnswer();
      expect(r.live, isEmpty);
      expect(r.conn.isOnline, isTrue);
    });

    test('resume probes at once and starts the backoff over; no link = no probe', () async {
      final r = _Rig()..arm();
      r.conn.reportServerReachable(false);
      await r.fire();
      await r.fire();
      expect(r.live.single.duration.inSeconds, 20);
      r.conn.onResume();
      await Future<void>.delayed(Duration.zero);
      expect(r.probes, 3, reason: 'resume asks at once');
      expect(r.live.single.duration.inSeconds, 5, reason: 'the backoff starts over');

      await r.conn.onLink(const [ConnectivityResult.none]);
      expect(r.live, isEmpty, reason: 'no link: nothing to ask');
      r.conn.onResume();
      await Future<void>.delayed(Duration.zero);
      expect(r.probes, 3);
      r.answers = true;
      await r.conn.onLink(const [ConnectivityResult.wifi]);
      expect(r.probes, 4, reason: 'the link is back: asked at once');
      expect(r.conn.isOnline, isTrue);
    });

    test('a probe set after an offline start books the first one', () {
      final r = _Rig();
      r.conn.reportServerReachable(false);
      expect(r.live, isEmpty);
      r.arm();
      expect(r.live.single.duration.inSeconds, 5);
    });

    group('back online the outbox drains', () {
      late FakeApi api;
      final pushes = <RequestOptions>[];
      setUp(() {
        AppConfig.lang = 'en';
        SharedPreferences.setMockInitialValues({});
        mockRequestPlugins();
        pushes.clear();
        api = FakeApi({
          'POST /api/v1/sync/push': (o) {
            pushes.add(o);
            final d = o.data is String ? jsonDecode(o.data as String) : o.data;
            final ops = (d is Map ? d['ops'] : null) as List? ?? const [];
            return {
              'results': [for (final op in ops) {'id': (op as Map)['id'], 'status': 'applied', 'entity': <String, dynamic>{}}],
            };
          },
        }, latency: Duration.zero);
        api.install();
      });
      tearDown(() {
        api.uninstall();
        AppConnectivity.instance.reportServerReachable(true);
      });

      test('a queued op goes out once the probe gets an answer', () async {
        final r = _Rig()..arm();
        final status = SyncStatus();
        final db = MemoryLocalDb();
        final outbox = Outbox(open: () async => db, userId: () async => 7, available: () => true, status: status);
        final engine = SyncEngine(api: ApiClient(), outbox: outbox, status: status, online: r.conn.online, notify: (_) {},
            timer: (d, f) => _FakeTimer(d, f));
        // TopRouteObserver's one listener, as in the app
        r.conn.online.addListener(() {
          if (r.conn.isOnline) engine.onReconnect();
        });
        r.conn.reportServerReachable(false);
        expect(await outbox.enqueue(id: 'op-quran-1', kind: SyncKinds.quranProgress, payload: {'student_id': 3}),
            EnqueueResult.queued);
        await engine.run();
        expect(pushes, isEmpty, reason: 'offline: nothing is sent');

        await r.fire(); // the server is still down
        expect(pushes, isEmpty);
        r.answers = true;
        await r.fire();
        for (var i = 0; i < 5 && pushes.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        await engine.run();
        expect(pushes, hasLength(1));
        expect(await outbox.rowsFor(7), isEmpty);
      });
    });
  });

  group('W-3: the record sheet\'s students offline', () {
    late FakeApi api;
    final online = ValueNotifier<bool>(true);
    var calls = 0;
    setUp(() {
      AppConfig.lang = 'en';
      SharedPreferences.setMockInitialValues({});
      mockRequestPlugins();
      calls = 0;
      online.value = true;
      offlineReadsOnline = () => online;
      Outbox.instance = Outbox(open: () async => _db, userId: () async => 29, available: () => true, status: SyncStatus());
      ReadCache.instance = ReadCache();
      api = FakeApi({
        'GET /api/v1/courses/12/enrolled-students': (_) {
          calls++;
          return [
            {'student_id': 34, 'name': 'Sara', 'image_url': 'https://x/a.png', 'national_id': '29801011234567', 'phone': '0100'},
            {'student_id': 35, 'name': 'Omar', 'identity_number': 'A123'},
          ];
        },
      }, latency: Duration.zero);
      api.install();
    });
    tearDown(() {
      api.uninstall();
      offlineReadsOnline = () => AppConnectivity.instance.online;
    });

    test('kept online, read back offline without a request, and only id + name + picture are kept', () async {
      final quran = QuranApi();
      final first = await quran.courseStudents(12);
      expect([for (final s in first) s.id], [34, 35]);
      await Future<void>.delayed(Duration.zero); // the cache write

      online.value = false;
      final again = await quran.courseStudents(12);
      expect(calls, 1, reason: 'offline: from the device');
      expect([for (final s in again) (s.id, s.name)], [(34, 'Sara'), (35, 'Omar')]);
      expect(again.first.imageUrl, 'https://x/a.png');

      final kept = (await ReadCache.instance.get('quran.students.12'))!.body.toString();
      expect(kept, isNot(contains('2980101')));
      expect(kept, isNot(contains('A123')));
      expect(kept, isNot(contains('phone')));
    });
  });
}

final _db = MemoryLocalDb();
