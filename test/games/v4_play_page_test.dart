// Games v4 T48: the play page opens a level through /draw and draws its template; an unreadable draw shows "needs a
// newer version"; the registry holds the four ready templates; the result extras fit every size.
// G3: Retry after a failed draw draws again; a page opened by URL (empty engine) loads the game and draws; an online
// draw stores the level's pool; offline, a stored pool plays and the play waits in the outbox with `picked`.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/offline/sync/local_db.dart';
import 'package:flutter_education_app/core/offline/sync/outbox.dart';
import 'package:flutter_education_app/core/offline/sync/sync_status.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/games/content/level_cache.dart';
import 'package:flutter_education_app/features/games/content/games_v4_api.dart';
import 'package:flutter_education_app/features/games/core/game_template.dart';
import 'package:flutter_education_app/features/games/game_play_page.dart';
import 'package:flutter_education_app/features/games/games_models.dart';
import 'package:flutter_education_app/features/games/learner/result_sheet.dart';
import 'package:flutter_education_app/features/games/templates/constellation/constellation.dart';
import 'package:flutter_education_app/features/games/templates/register_all.dart';
import 'package:flutter_education_app/features/games/templates/verse_builder/verse_builder.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../ui/layout_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final play = jsonDecode(File('docs/games-v4/fixtures/learner_play.json').readAsStringSync()) as Map<String, dynamic>;
  final draw = Map<String, dynamic>.from((play['POST /games/31/draw'] as Map)['response'] as Map);
  FakeApi? fake;

  final poolAnswer = Map<String, dynamic>.from((play['GET /games/31/pool'] as Map)['response'] as Map);
  // no audio files in these tests (the file cache has its own tests)
  for (final it in poolAnswer['items'] as List) {
    (it as Map)['media'] = {'image': null, 'audio': null};
  }
  GameSummary game() => const GameSummary(id: 31, key: 'vb', engine: 'verse_builder', titleAr: 'لعبة', titleEn: 'Game');
  LevelCache memCache() =>
      LevelCache(store: MemoryLevelStore(), enabled: true, now: () => DateTime.utc(2026, 11, 23, 12), onWifi: () async => false);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pumpPage(WidgetTester tester, Object? answer) async {
    fake = FakeApi({'POST /api/v1/games/31/draw': (_) => answer}, latency: Duration.zero)..install();
    await tester.pumpWidget(layoutHost(GamePlayPage(game: game(), userId: 1, cache: memCache()), scaffold: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  setUp(mockRequestPlugins);
  tearDown(() => fake?.uninstall());

  test('registerGameTemplates holds the four ready templates', () {
    registerGameTemplates();
    expect(kGameTemplates.keys, containsAll(['challenge_quiz', 'verse_builder', 'car_race', 'balloon_pop']));
  });

  testWidgets('a v4 level is drawn and its template shown', (tester) async {
    await pumpPage(tester, draw);
    expect(find.byType(VerseBuilderGame), findsOneWidget);
    expect(fake!.calls.where((c) => c.key.startsWith('POST /api/v1/games/31/draw')), hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Constellation gets the saved sky of the learner profile loaded with the draw', (tester) async {
    final cn = Map<String, dynamic>.from(draw)..['template'] = 'constellation';
    fake = FakeApi({
      'POST /api/v1/games/31/draw': (_) => cn,
      'GET /api/v1/me/games/profile': (_) => {
            'age_band': 'adult',
            'sky': [
              {'shape': 'crescent'},
              {'shape': 'lantern'},
            ],
          },
    }, latency: Duration.zero)
      ..install();
    const g = GameSummary(id: 31, key: 'cn', engine: 'constellation', titleAr: 'كوكبة', titleEn: 'Constellation');
    await tester.pumpWidget(layoutHost(GamePlayPage(game: g, userId: 1, cache: memCache()), scaffold: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.widget<ConstellationView>(find.byType(ConstellationView)).skyBase, 2);
    expect(fake!.calls.where((c) => c.key == 'GET /api/v1/me/games/profile'), hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });

  test('templateWithProfile: only Constellation takes the sky; no profile keeps the registry template', () {
    const p = V4Profile({'sky': [{}, {}, {}]});
    expect((templateWithProfile(const ConstellationTemplate(), p) as ConstellationTemplate).skyBase, 3);
    expect((templateWithProfile(const ConstellationTemplate(), null) as ConstellationTemplate).skyBase, 0);
    final vb = const VerseBuilderTemplate();
    expect(templateWithProfile(vb, p), same(vb));
  });

  testWidgets('an unreadable draw shows the newer-version fallback', (tester) async {
    final bad = Map<String, dynamic>.from(draw)..['items'] = [{'n': 0, 'type': 'hologram', 'body': {}}];
    AppConfig.lang = 'en';
    await pumpPage(tester, bad);
    expect(find.byType(VerseBuilderGame), findsNothing);
    expect(find.textContaining('newer version'), findsOneWidget);
  });

  test('an offline v4 play queues draw_id, picked, trace and calm', () {
    final sub = V4PlaySubmission(
      gameId: 31,
      score: 3,
      maxScore: 4,
      trace: [
        {'i': 0, 'a': 0, 'ms': 900},
      ],
      drawId: 'd-1',
      picked: [3, 1, 0, 2],
      calm: true,
      fromPool: true,
    );
    expect(sub.payload['draw_id'], 'd-1');
    expect(sub.payload['picked'], [3, 1, 0, 2]);
    expect(sub.payload['trace'], hasLength(1));
    expect(sub.payload['calm'], true);
    expect(sub.payload['game_id'], 31);
  });

  testWidgets('G3: Retry after a failed draw draws again', (tester) async {
    var n = 0;
    fake = FakeApi({
      'POST /api/v1/games/31/draw': (_) => n++ == 0
          ? const FakeResponse(409, {
              'detail': {'code': 'no_items'},
            })
          : draw,
    }, latency: Duration.zero)
      ..install();
    await tester.pumpWidget(layoutHost(GamePlayPage(game: game(), userId: 4, cache: memCache()), scaffold: false));
    await settle(tester);
    expect(find.byType(VerseBuilderGame), findsNothing);
    tester.widget<AppErrorState>(find.byType(AppErrorState)).onRetry!();
    await settle(tester);
    expect(find.byType(VerseBuilderGame), findsOneWidget);
    expect(fake!.calls.where((c) => c.key.startsWith('POST /api/v1/games/31/draw')), hasLength(2));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('G3: a page opened by URL (empty engine) loads the game, then draws and plays', (tester) async {
    fake = FakeApi({
      'GET /api/v1/games/31': (_) =>
          {'id': 31, 'key': 'vb', 'engine': 'verse_builder', 'title_ar': 'لعبة', 'title_en': 'Game', 'config': {}},
      'POST /api/v1/games/31/draw': (_) => draw,
    }, latency: Duration.zero)
      ..install();
    const stub = GameSummary(id: 31, key: '', engine: '', titleAr: '', titleEn: '');
    await tester.pumpWidget(layoutHost(GamePlayPage(game: stub, userId: 5, cache: memCache()), scaffold: false));
    await settle(tester);
    expect(find.byType(VerseBuilderGame), findsOneWidget);
    expect(fake!.calls.where((c) => c.key.startsWith('POST /api/v1/games/31/draw')), hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('G3: an online draw stores the level pool for offline play', (tester) async {
    final cache = memCache();
    fake = FakeApi({
      'POST /api/v1/games/31/draw': (_) => draw,
      'GET /api/v1/games/31/pool': (_) => poolAnswer,
    }, latency: Duration.zero)
      ..install();
    await tester.pumpWidget(layoutHost(GamePlayPage(game: game(), userId: 2, cache: cache), scaffold: false));
    await settle(tester);
    expect(fake!.calls.where((c) => c.key.startsWith('GET /api/v1/games/31/pool')), hasLength(1));
    expect(await cache.hasPool(2, 31), isTrue);
    expect(find.byIcon(Icons.offline_pin_rounded), findsOneWidget, reason: 'the app bar marks the level saved offline');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('G3: offline, a stored pool plays and the play waits in the outbox with picked', (tester) async {
    final cache = memCache();
    await cache.storePool(3, 31, V4Draw(Map<String, dynamic>.from(poolAnswer)));
    final db = MemoryLocalDb();
    final before = Outbox.instance;
    Outbox.instance = Outbox(open: () async => db, userId: () async => 3, available: () => true, status: SyncStatus());
    addTearDown(() => Outbox.instance = before);
    fake = FakeApi({
      'POST /api/v1/games/31/draw': (_) =>
          throw const ApiException(statusCode: 0, message: 'offline', type: ApiErrorType.network),
    }, latency: Duration.zero)
      ..install();
    await tester.pumpWidget(layoutHost(GamePlayPage(game: game(), userId: 3, cache: cache), scaffold: false));
    await settle(tester);
    final vb = find.byType(VerseBuilderGame);
    expect(vb, findsOneWidget);
    tester.widget<VerseBuilderGame>(vb).session.finish();
    await settle(tester);
    final rows = await db.outboxRows(userId: 3);
    expect(rows, hasLength(1));
    expect(rows.single.kind, SyncKinds.gamePlay);
    final body = jsonDecode(rows.single.payload) as Map;
    expect(body['draw_id'], poolAnswer['draw_id']);
    expect(body['picked'], isNotEmpty);
    expect(fake!.calls.where((c) => c.key.startsWith('POST /api/v1/games/31/plays')), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('result extras: no layout errors', (tester) async {
    await expectNoLayoutErrors(tester, () => const GameResultExtras(coinsAwarded: 12, coins: 340, unlocked: 2));
  });
}
