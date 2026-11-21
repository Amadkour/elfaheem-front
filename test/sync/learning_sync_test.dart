// The Learning Hub's writes and reads over the offline layer (F13, D-1351 / D-1352), on FakeApi with the device
// database in memory: a game play, a nahw attempt and a Quran entry made offline show at once and reach the server
// ONCE after reconnect; a stale study-profile edit hands the server's copy back and tells the person once; the games,
// nahw and Quran tabs' readers answer from the cache while offline; a refusal is never covered by an old copy; the
// "needs a connection" guard.
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart' show RequestOptions;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/offline/sync/local_db.dart';
import 'package:flutter_education_app/core/offline/sync/offline_reads.dart';
import 'package:flutter_education_app/core/offline/sync/outbox.dart';
import 'package:flutter_education_app/core/offline/sync/read_cache.dart';
import 'package:flutter_education_app/core/offline/sync/sync_engine.dart';
import 'package:flutter_education_app/core/offline/sync/sync_status.dart';
import 'package:flutter_education_app/features/games/game_play_page.dart';
import 'package:flutter_education_app/features/games/games_api.dart';
import 'package:flutter_education_app/features/games/games_models.dart';
import 'package:flutter_education_app/features/nahw/nahw_api.dart';
import 'package:flutter_education_app/features/nahw/nahw_lesson_page.dart';
import 'package:flutter_education_app/features/profile/study_profile/study_profile_model.dart';
import 'package:flutter_education_app/features/quran/quran_api.dart';
import 'package:flutter_education_app/features/quran/quran_models.dart';
import 'package:flutter_education_app/features/quran/quran_record_sheet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../ui/layout_harness.dart';
import '../ui/quran_models_test.dart' show quranTestMeta;

Map<String, dynamic> _body(RequestOptions o) {
  final d = o.data;
  return (d is String ? jsonDecode(d) : d) as Map<String, dynamic>;
}

List<Map<String, dynamic>> _ops(RequestOptions o) => [for (final x in _body(o)['ops'] as List) x as Map<String, dynamic>];

const _offline = ApiException(statusCode: 0, message: 'offline', type: ApiErrorType.network);

final _lesson = {
  'id': 7,
  'level_id': 1,
  'title_ar': 'أقسام الكلمة',
  'title_en': 'Parts of speech',
  'body_ar': 'الكلمة ثلاثة أقسام: اسم، وفعل، وحرف.',
  'exercises': [
    {
      'id': 2,
      'kind': 'choose',
      'prompt': 'أيّ الكلمات الآتية فعل؟',
      'data': {'prompt_en': 'Which word is a verb?', 'options': ['قلم', 'جلسَ', 'إلى', 'بيت']},
      'answer': {'index': 1},
      'explanation': 'جلسَ فعل ماضٍ.',
    },
  ],
};

/// A few frames (the result's stars and a focused field's cursor animate on, so pumpAndSettle would never return).
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Awaits [f] while the fake clock moves (FakeApi answers after a zero-length timer).
Future<void> _drive(WidgetTester tester, Future<void> f) async {
  var done = false;
  f.whenComplete(() => done = true);
  for (var i = 0; i < 50 && !done; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(done, isTrue, reason: 'the sync run never finished');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final online = ValueNotifier<bool>(true);
  final notices = <String>[];
  late MemoryLocalDb db;
  late FakeApi api;
  late List<RequestOptions> pushes;
  late Object? Function(RequestOptions o) answer;
  /// A GET the readers make, answered by [h].
  void route(String path, FakeHandler h) => api.routes['GET $path'] = h;

  // one engine for the whole file: the pages' buses wire themselves to SyncEngine.instance once
  final engine = SyncEngine(
    api: ApiClient(),
    status: SyncStatus(),
    online: online,
    notify: notices.add,
    timer: (d, f) => Timer(const Duration(days: 1), f),
  );
  SyncEngine.instance = engine;
  offlineReadsOnline = () => online;

  setUp(() {
    AppConfig.lang = 'en';
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    db = MemoryLocalDb();
    Outbox.instance = Outbox(open: () async => db, userId: () async => 7, available: () => true, status: SyncStatus());
    ReadCache.instance = ReadCache();
    engine.reset();
    online.value = true;
    notices.clear();
    pushes = [];
    answer = (o) => {
          'results': [for (final op in _ops(o)) {'id': op['id'], 'status': 'applied', 'entity': <String, dynamic>{}}],
          'server_time': '2026-11-21T12:00:00',
        };
    api = FakeApi({
      'POST /api/v1/sync/push': (o) {
        pushes.add(o);
        return answer(o);
      },
    }, latency: Duration.zero);
    api.install();
  });
  tearDown(() => api.uninstall());

  test('a game play made offline shows its stars at once and reaches the server once after reconnect', () async {
    online.value = false;
    final bus = GamesBus.revision.value;
    final sub = GamePlaySubmission(gameId: 3, score: 9, maxScore: 10, durationS: 40);
    engine.listen(SyncKinds.gamePlay, sub.settle);
    GamesBus.wireSync();
    expect(await sub.enqueue(), isTrue);
    expect(sub.queued, isTrue);
    expect(sub.done, isFalse, reason: 'shown from the device grading until the server answers');

    await engine.run();
    expect(pushes, isEmpty, reason: 'offline: nothing is sent');

    answer = (o) => {
          'results': [
            for (final op in _ops(o))
              {
                'id': op['id'],
                'status': 'applied',
                'entity': {
                  'play': {'stars': 3, 'score': 9, 'max_score': 10},
                  'progress': {'game_id': 3, 'best_score': 9, 'stars': 3, 'plays': 1},
                  'new_badges': [],
                  'points_awarded': 5,
                  'duplicate': false,
                },
              },
          ],
          'server_time': '2026-11-21T12:00:00',
        };
    online.value = true;
    await engine.run();
    await engine.run();
    expect(pushes, hasLength(1));
    final op = _ops(pushes.single).single;
    expect(op['id'], sub.clientId);
    expect(op['kind'], 'game_play');
    expect(op['payload'], {'game_id': 3, 'score': 9, 'max_score': 10, 'duration_s': 40});
    expect(DateTime.parse(op['client_ts'] as String).isAtSameMomentAs(sub.playedAt), isTrue);
    expect(sub.result?.pointsAwarded, 5);
    expect(sub.result?.progress?.plays, 1);
    expect(GamesBus.revision.value, bus + 1);
    expect(await db.outboxRows(), isEmpty);
    engine.unlisten(SyncKinds.gamePlay, sub.settle);
  });

  test('without an outbox (sync.offline off) the play goes straight to the route', () async {
    Outbox.instance = Outbox(open: () async => db, userId: () async => 7, available: () => false);
    final sub = GamePlaySubmission(gameId: 3, score: 1, maxScore: 2);
    expect(await sub.enqueue(), isFalse);
    expect(sub.queued, isFalse);
    expect(await db.outboxRows(), isEmpty);
  });

  test('a refused play is final, with its own text', () {
    final sub = GamePlaySubmission(gameId: 3, score: 1, maxScore: 2);
    sub.settle(SyncResult(id: sub.clientId, kind: SyncKinds.gamePlay, status: 'rejected', code: 'game_not_found'));
    expect(sub.done, isTrue);
    expect(sub.error, 'This game is not available');
  });

  testWidgets('the result kept on the device: its note, no layout errors', (tester) async {
    final g = GameSummary.fromJson({'id': 1, 'key': 'g1', 'engine': 'quiz', 'title_ar': 'لعبة', 'title_en': 'A game'});
    await expectNoLayoutErrors(
      tester,
      () => GamePlayView(game: g, finished: (score: 9, max: 10, stars: null, badges: const [], points: 0), kept: true, onReplay: () {}),
    );
    await tester.pumpWidget(layoutHost(
        GamePlayView(game: g, finished: (score: 9, max: 10, stars: null, badges: const [], points: 0), kept: true)));
    expect(find.text(keptOnDeviceText()), findsOneWidget);
  });

  testWidgets('a nahw attempt made offline shows its result at once and reaches the server once', (tester) async {
    route('/api/v1/nahw/lessons/7', (_) => _lesson);
    online.value = false;
    await tester.pumpWidget(layoutHost(NahwLessonPage(lessonId: 7, api: NahwApi()), scaffold: false));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('nahw.start')));
    await _settle(tester);
    await tester.tap(find.text('جلسَ'));
    await _settle(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('nahw.check')));
    await tester.tap(find.byKey(const ValueKey('nahw.check')));
    await _settle(tester);
    await tester.ensureVisible(find.text('See the result'));
    await _settle(tester);
    await tester.tap(find.text('See the result'));
    await _settle(tester);
    expect(find.text('1 / 1 · 100%'), findsOneWidget);
    expect(find.text(keptOnDeviceText()), findsOneWidget);
    final rows = await db.outboxRows();
    expect(rows.single.kind, 'nahw_attempt');
    expect(jsonDecode(rows.single.payload), {'lesson_id': 7, 'score': 1, 'max_score': 1, 'answers': [{'index': 1}]});

    answer = (o) => {
          'results': [
            for (final op in _ops(o))
              {
                'id': op['id'],
                'status': 'applied',
                'entity': {
                  'progress': {'lesson_id': 7, 'best_score': 1, 'max_score': 1, 'attempts': 1, 'completed': true},
                  'duplicate': false,
                },
              },
          ],
          'server_time': '2026-11-21T12:00:00',
        };
    online.value = true;
    await _drive(tester, engine.run());
    await _drive(tester, engine.run());
    await _settle(tester);
    expect(pushes, hasLength(1));
    expect(_ops(pushes.single).single['id'], rows.single.id);
    expect(find.text(keptOnDeviceText()), findsNothing);
    expect(find.textContaining('Lesson complete'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a Quran entry made offline closes the sheet at once and reaches the server once', (tester) async {
    online.value = false;
    final bus = QuranBus.revision.value;
    bool? saved;
    await tester.pumpWidget(layoutHost(Builder(
      builder: (context) => TextButton(
        onPressed: () async => saved = await showQuranRecordSheet(context, meta: quranTestMeta(), selfLog: true),
        child: const Text('open'),
      ),
    )));
    await tester.tap(find.text('open'));
    await _settle(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('quran.record.save')));
    await tester.tap(find.byKey(const ValueKey('quran.record.save')));
    await _settle(tester);
    expect(saved, isTrue);
    final rows = await db.outboxRows();
    final row = rows.single;
    expect(row.kind, 'quran_progress');
    final payload = jsonDecode(row.payload) as Map<String, dynamic>;
    expect(payload.containsKey('client_id'), isFalse, reason: 'the id travels as the op id');
    expect(payload.containsKey('recorded_at'), isFalse, reason: 'the time travels as client_ts');
    expect(payload['surah'], 1);
    expect(payload['from_ayah'], 1);

    online.value = true;
    await _drive(tester, engine.run());
    await _drive(tester, engine.run());
    expect(pushes, hasLength(1));
    expect(_ops(pushes.single).single['id'], row.id);
    expect(QuranBus.revision.value, bus + 1);
    await tester.pumpWidget(const SizedBox());
  });

  test('a stale study-profile edit hands back the server copy and tells the person once', () async {
    final server = {
      'profile': {'stage': 'secondary', 'grade': 2, 'school_name': 'Other device school'},
      'complete': true,
      'missing': [],
      'settings': {},
      'updated_at': '2026-11-21T09:00:00',
    };
    answer = (o) => {
          'results': [for (final op in _ops(o)) {'id': op['id'], 'status': 'rejected', 'code': 'sync_stale', 'entity': server}],
          'server_time': '2026-11-21T12:00:00',
        };
    StudyProfileSync.latest.value = null;
    online.value = false;
    expect(await StudyProfileApi().queue(StudyProfile.empty, baseUpdatedAt: '2026-11-20T08:00:00'), isTrue);
    online.value = true;
    await engine.run();
    final op = _ops(pushes.single).single;
    expect(op['kind'], 'study_profile');
    expect(op['base_updated_at'], '2026-11-20T08:00:00');
    final got = StudyProfileSync.latest.value;
    expect(got?.stale, isTrue);
    expect(got?.view.profile.schoolName, 'Other device school');
    expect(got?.view.updatedAt, '2026-11-21T09:00:00');
    expect(notices, [syncRejectedText('sync_stale')]);
    expect(notices.single, contains('changed on another device'));
    expect(await db.outboxRows(), isEmpty);
  });

  test('the games, nahw and Quran tabs read from the cache while offline', () async {
    var served = 0;
    route('/api/v1/games', (_) {
      served++;
      return {
        'items': [
          {'id': 1, 'key': 'g1', 'engine': 'quiz', 'title_ar': 'لعبة', 'title_en': 'A game'},
        ],
      };
    });
    route('/api/v1/games/1', (_) => {'id': 1, 'key': 'g1', 'engine': 'quiz', 'title_ar': 'لعبة', 'title_en': 'A game', 'config': {'questions': []}});
    route('/api/v1/nahw/levels', (_) => {
          'levels': [
            {'id': 1, 'key': 'beginner', 'title_ar': 'المبتدئ', 'title_en': 'Beginner', 'total': 0, 'completed': 0, 'lessons': []},
          ],
        });
    route('/api/v1/nahw/lessons/7', (_) => _lesson);
    route('/api/v1/quran/teachers', (_) => {'items': [], 'total': 0, 'gender_matching': 'off'});
    route('/api/v1/quran/meta', (_) => jsonDecode(jsonEncode({'surahs': [], 'juz': []})));
    route('/api/v1/me/quran/progress', (_) => {'surahs': [], 'juz': [], 'recent': [], 'memorized_total': 12, 'total_ayahs': 6236});
    final games = GamesApi(), nahw = NahwApi(), quran = QuranApi();
    QuranApi.setMetaForTest(null);
    expect((await games.games()).items, hasLength(1));
    await games.game(1);
    await nahw.levels();
    await nahw.lesson(7);
    await quran.teachers(QuranFilters.empty);
    await quran.meta();
    await quran.myProgress();
    await pumpEventQueue(); // the puts are fire and forget
    final before = api.calls.length;

    online.value = false;
    QuranApi.setMetaForTest(null);
    expect((await games.games()).items.single.titleEn, 'A game');
    expect((await games.game(1)).config, {'questions': []});
    expect((await nahw.levels()).single.titleEn, 'Beginner');
    expect((await nahw.lesson(7)).exercises, hasLength(1));
    expect((await quran.teachers(QuranFilters.empty)).total, 0);
    await quran.meta();
    expect((await quran.myProgress()).memorizedTotal, 12);
    expect(api.calls.length, before, reason: 'offline with a kept copy: no request');
    expect(served, 1);

    // online again but the connection drops on the way: the kept copy, not an error
    online.value = true;
    route('/api/v1/games', (_) => throw _offline);
    expect((await games.games()).items, hasLength(1));
  });

  test('a refusal is never covered by an old copy; nothing kept = the error', () async {
    route('/api/v1/games/2', (_) => {'id': 2, 'key': 'g2', 'engine': 'quiz', 'title_ar': 'لعبة', 'title_en': 'Two'});
    await GamesApi().game(2);
    await pumpEventQueue();
    route('/api/v1/games/2', (_) => const FakeResponse(404, {'detail': {'code': 'game_not_found'}}));
    await expectLater(GamesApi().game(2), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'game_not_found')));
    route('/api/v1/games/9', (_) => throw _offline);
    await expectLater(GamesApi().game(9), throwsA(isA<ApiException>()));
  });

  test('money and enrolment need a connection', () {
    final told = <String>[];
    expect(offlineBlocked(notify: told.add), isFalse);
    online.value = false;
    expect(offlineBlocked(notify: told.add), isTrue);
    expect(told, [needsConnectionText()]);
    expect(isTransportFailure(TimeoutException('x')), isTrue);
    expect(isTransportFailure(const ApiException(statusCode: 503, message: '')), isTrue);
    expect(isTransportFailure(const ApiException(statusCode: 403, message: '')), isFalse);
  });
}
