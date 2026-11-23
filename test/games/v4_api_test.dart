// Games v4 T36: GamesV4Api over FakeApi serving the CONTRACT fixtures, and LevelCache (pool, picks, audio, reciter change).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_education_app/features/games/content/games_v4_api.dart';
import 'package:flutter_education_app/features/games/content/level_cache.dart';
import 'package:flutter_education_app/features/games/content/level_store_io.dart';
import 'package:flutter_education_app/features/games/core/game_session.dart';
import 'package:flutter_education_app/features/games/core/recitation_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/fake_api.dart';

Map<String, dynamic> _fx(String f) => jsonDecode(File('docs/games-v4/fixtures/$f.json').readAsStringSync()) as Map<String, dynamic>;
Object? _resp(Map<String, dynamic> fx, String key) => (fx[key] as Map)['response'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  final play = _fx('learner_play'), home = _fx('learner_home'), extras = _fx('learner_extras'), rec = _fx('reciters');
  late FakeApi fake;
  final bodies = <String, Object?>{};

  FakeHandler h(Object? body, String tag) => (o) {
        bodies[tag] = o.data;
        return body;
      };

  setUp(() {
    mockRequestPlugins();
    bodies.clear();
    fake = FakeApi({
      'GET /api/v1/games': h(_resp(home, 'GET /games?v=4&game_subject_id=1'), 'levels'),
      'GET /api/v1/games/v4/home': h(_resp(home, 'GET /games/v4/home'), 'home'),
      'GET /api/v1/me/games/profile': h(_resp(home, 'GET /me/games/profile'), 'profile'),
      'PUT /api/v1/me/games/profile': h(_resp(home, 'PUT /me/games/profile'), 'saveProfile'),
      'POST /api/v1/games/31/draw': h(_resp(play, 'POST /games/31/draw'), 'draw'),
      'GET /api/v1/games/31/pool': h(_resp(play, 'GET /games/31/pool'), 'pool'),
      'POST /api/v1/games/31/plays': h(_resp(play, 'POST /games/31/plays'), 'play'),
      'GET /api/v1/games/44/ghost': h(_resp(play, 'GET /games/44/ghost'), 'ghost'),
      'GET /api/v1/games/reciters': h(_resp(rec, 'GET /games/reciters'), 'reciters'),
      'GET /api/v1/games/quran/audio': h(_resp(rec, 'GET /games/quran/audio?refs=112:1,18:10&reciter=mukhtar_alhaj'), 'audio'),
      'GET /api/v1/games/cosmetics': h(_resp(extras, 'GET /games/cosmetics'), 'cosmetics'),
      'POST /api/v1/games/cosmetics/hat_star/buy': h(_resp(extras, 'POST /games/cosmetics/hat_star/buy'), 'buy'),
      'POST /api/v1/games/challenges': h(_resp(extras, 'POST /games/challenges'), 'challenge'),
      'GET /api/v1/games/class-board': h(_resp(extras, 'GET /games/class-board?course_id=31'), 'board'),
      'GET /api/v1/games/breaks/config': h(_resp(extras, 'GET /games/breaks/config'), 'breaks'),
      'GET /api/v1/games/suggest': h(_resp(extras, 'GET /games/suggest?course_id=31'), 'suggest'),
      'GET /api/v1/parent/children/77/games': h(_resp(extras, 'GET /parent/children/77/games'), 'parent'),
    }, latency: Duration.zero)
      ..install();
  });

  tearDown(() => fake.uninstall());

  group('GamesV4Api over the fixtures', () {
    test('levels, home, profile', () async {
      final api = GamesV4Api();
      final levels = await api.levels(subjectId: 1);
      expect(levels, isNotEmpty);
      expect(fake.calls.single.query, {'v': '4', 'game_subject_id': '1'});
      expect(levels.first.template, isNotNull);
      expect(levels.first.itemsCount, greaterThan(0));

      final hm = await api.home();
      expect(hm.profile.ageBand, '10-13');
      expect(hm.profile.coins, 54);
      expect(hm.subjects.first.key, 'quran');
      expect(hm.subjects.first.sacred, isTrue);
      expect(hm.templates['verse_builder'], isNotNull);
      expect(hm.flag('champions'), isTrue);
      expect(hm.reviewDue, 6);
      expect(hm.reviewLevels[31], 4);

      final p = await api.profile();
      expect(p.reciterEffective, 'alafasy');
      expect(p.needsAge, isFalse);
    });

    test('saveProfile sends only what is given; clearReciter sends null', () async {
      final api = GamesV4Api();
      await api.saveProfile(reciterKey: 'husary_muallim', equipped: {'hat': 'hat_star'});
      expect(bodies['saveProfile'], {'reciter_key': 'husary_muallim', 'equipped': {'hat': 'hat_star'}});
      await api.saveProfile(clearReciter: true);
      expect(bodies['saveProfile'], {'reciter_key': null});
    });

    test('draw: request body, the snapshot, GameSession.fromDraw reads it', () async {
      final d = await GamesV4Api().draw(31, mode: 'play');
      expect(bodies['draw'], {'mode': 'play'});
      expect(d.kind, 'round');
      expect(d.isPool, isFalse);
      expect(d.sacred, isTrue);
      expect(d.template, 'verse_builder');
      expect(d.roundId, isNotNull);
      expect(d.reciter?.key, 'alafasy');
      expect(d.items, isNotEmpty);
      expect(GameSession.fromDraw(d.raw), isNotNull);
    });

    test('pool: kind pool, expires, items, a round of it reads as a session', () async {
      final p = await GamesV4Api().pool(31);
      expect(p.isPool, isTrue);
      expect(p.expiresAt, DateTime.parse('2026-12-23T10:00:00'));
      expect(p.items.length, 2);
      expect(p.roundId, isNull);
    });

    test('play: the v4 fields go out and the v4 answer parses', () async {
      final r = await GamesV4Api().play(
        31,
        clientId: 'a1b2c3d4-0001',
        score: 4,
        maxScore: 5,
        durationS: 15,
        playedAt: '2026-11-23T10:00:00',
        roundId: 'r1',
        trace: const [
          {'i': 0, 'a': [1], 'ms': 1000},
        ],
        drawId: 'd1',
        picked: const [1, 0],
        calm: true,
      );
      final b = bodies['play'] as Map;
      expect(b['draw_id'], 'd1');
      expect(b['picked'], [1, 0]);
      expect(b['calm'], true);
      expect(b['round_id'], 'r1');
      expect(r.play.stars, 2);
      expect(r.play.ranked, isTrue);
      expect(r.coinsAwarded, 6);
      expect(r.coins, 60);
      expect(r.unlocked, [32]);
      expect(r.srsDue, 1);
      expect(r.rankedLeft, 2);
    });

    test('play without the optional fields sends none of them', () async {
      await GamesV4Api().play(31, clientId: 'c', score: 0, maxScore: 1, durationS: 1, playedAt: 'x');
      final b = bodies['play'] as Map;
      expect(b.keys.toSet(), {'client_id', 'score', 'max_score', 'duration_s', 'played_at'});
    });

    test('ghost: events as pairs', () async {
      final g = await GamesV4Api().ghost(44);
      expect(g?.name, 'Sara A.');
      expect(g?.events.first, (4000, 1));
      expect(g?.events.length, 3);
    });

    test('reciters and the audio of a reciter (a fallback entry names who played)', () async {
      final api = GamesV4Api();
      final l = await api.reciters();
      expect(l.items.map((r) => r.key), contains('alafasy'));
      expect(l.effective, isNotNull);
      final a = await api.quranAudio(['112:1', '18:10'], 'mukhtar_alhaj');
      expect(fake.calls.last.query, {'refs': '112:1,18:10', 'reciter': 'mukhtar_alhaj'});
      expect(a['112:1']!.startMs, 4800);
      expect(a['112:1']!.endMs, 8300);
      expect(a['112:1']!.ref, '112:1');
      expect(a['18:10']!.reciter, 'alafasy');
      expect(a['18:10']!.wholeFile, isTrue);
    });

    test('quranAudio sends at most 60 refs per call', () async {
      await GamesV4Api().quranAudio([for (var i = 1; i <= 130; i++) '2:$i'], 'alafasy');
      final calls = fake.calls.where((c) => c.path.endsWith('/quran/audio')).toList();
      expect(calls.length, 3);
      expect(calls.map((c) => '${c.query['refs']}'.split(',').length), [60, 60, 10]);
    });

    test('cosmetics, buy, challenge, class board, breaks, suggest, parent', () async {
      final api = GamesV4Api();
      final c = await api.cosmetics();
      expect(c.items, isNotEmpty);
      expect(c.items.first.slot, isNotEmpty);
      final b = await api.buy('hat_star');
      expect(b.item?.key, 'hat_star');
      final ch = await api.createChallenge(31);
      expect(bodies['challenge'], {'game_id': 31});
      expect(ch.code.length, 8);
      expect(ch.open, isTrue);
      expect(ch.link, startsWith('https://alfheemacademy.com/app/games/challenge/'));
      final cb = await api.classBoard(31);
      expect(cb.items, isNotEmpty);
      final br = await api.breaksConfig();
      expect(br.studyMinutes, greaterThan(0));
      final s = await api.suggest(courseId: 31);
      expect(s, isNotNull);
      final pg = await api.parentGames(77);
      expect(pg.minutes7d, greaterThanOrEqualTo(0));
      expect(pg.totals.keys, containsAll(['plays', 'stars']));
    });
  });

  group('LevelCache', () {
    late Directory tmp;
    late RecitationCache audio;
    final fetched = <String>[];
    var now = DateTime.utc(2026, 11, 23, 10);

    Future<LevelCache> cache({bool enabled = true, bool wifi = true}) async {
      final store = await SqfliteLevelStore.open(databaseFactoryFfi, inMemoryDatabasePath);
      return LevelCache(
        store: store,
        audio: audio,
        enabled: enabled,
        now: () => now,
        onWifi: () async => wifi,
        api: GamesV4Api(),
      );
    }

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('lvlcache');
      fetched.clear();
      now = DateTime.utc(2026, 11, 23, 10);
      audio = RecitationCache(
        root: () async => tmp,
        fetch: (url, to) async {
          fetched.add(url);
          await to.writeAsString('mp3');
        },
      );
    });

    tearDown(() => tmp.deleteSync(recursive: true));

    Future<V4Draw> fixturePool() async => V4Draw(Map<String, dynamic>.from(_resp(play, 'GET /games/31/pool') as Map));

    test('storePool keeps the pool and downloads the audio of its items', () async {
      final c = await cache();
      final progress = <int>[];
      final n = await c.storePool(7, 31, await fixturePool(), onProgress: (d, t) => progress.add(d));
      expect(n, greaterThan(0));
      expect(progress, isNotEmpty);
      expect(fetched, isNotEmpty);
      final back = await c.pool(7, 31);
      expect(back?.items.length, 2);
      expect(back?.reciter?.key, 'alafasy');
      expect(await c.cachedGames(7), [31]);
      expect(await c.cachedGames(8), isEmpty);
      final e = poolAudioEntries(back!.raw).first;
      expect(await c.audioFile('alafasy', e['url'] as String), isNotNull);
    });

    test('a pool is dropped after expires_at', () async {
      final c = await cache();
      await c.storePool(7, 31, await fixturePool());
      now = DateTime.utc(2026, 12, 24);
      expect(await c.pool(7, 31), isNull);
      expect(await c.cachedGames(7), isEmpty);
    });

    test('pickRound: renumbers 0..k-1, picked holds the pool n, session reads it, no round_id', () async {
      final c = await cache();
      await c.storePool(7, 31, await fixturePool());
      final r = await c.pickRound(7, 31, count: 1);
      expect(r, isNotNull);
      expect(r!.draw['items'], hasLength(1));
      expect(((r.draw['items'] as List).first as Map)['n'], 0);
      expect(r.picked.length, 1);
      expect(r.draw['round_id'], isNull);
      expect(r.draw['kind'], 'pool');
      expect(r.draw['max_score'], r.picked.first == 0 ? 4 : 1);
      expect(GameSession.fromDraw(r.draw), isNotNull);
    });

    test('pickRound takes unseen items first', () async {
      final c = await cache();
      await c.storePool(7, 31, await fixturePool());
      await c.markPlayed(7, 31, [812]);
      for (var i = 0; i < 8; i++) {
        final r = await c.pickRound(7, 31, count: 1);
        expect(r!.itemIds, [813]);
        expect(r.picked, [1]);
      }
      await c.markPlayed(7, 31, [813]);
      final all = await c.pickRound(7, 31);
      expect(all!.picked.toSet(), {0, 1});
      expect(all.draw['max_score'], 5);
    });

    test('a disabled cache (the web) answers nothing and stores nothing', () async {
      final c = await cache(enabled: false);
      expect(await c.storePool(7, 31, await fixturePool()), 0);
      expect(await c.pool(7, 31), isNull);
      expect(await c.pickRound(7, 31), isNull);
      expect(fetched, isEmpty);
    });

    test('a reciter change re-resolves the audio, downloads it, drops the old reciter files', () async {
      final c = await cache();
      await c.storePool(7, 31, await fixturePool());
      final oldUrl = poolAudioEntries((await c.pool(7, 31))!.raw).first['url'] as String;
      expect(await c.staleFor(7, 'alafasy'), isEmpty);
      expect(await c.staleFor(7, 'mukhtar_alhaj'), [31]);
      // the fake server answers the fixture's two refs; the pool's own refs not in it keep their old entry
      expect(await c.refreshForReciter(7, 'mukhtar_alhaj'), 1);
      final after = await c.pool(7, 31);
      expect(after?.reciter?.key, 'mukhtar_alhaj');
      final e = poolAudioEntries(after!.raw).firstWhere((e) => e['ref'] == '112:1');
      expect(e['url'], 'https://cdn.mp3quran.net/audio/mukhtar-haj/r1/112.mp3');
      expect(e['start_ms'], 4800);
      expect(await c.audioFile('mukhtar_alhaj', e['url'] as String), isNotNull);
      expect(await c.audioFile('alafasy', oldUrl), isNull);
      expect(await c.staleFor(7, 'mukhtar_alhaj'), isEmpty);
    });

    test('a reciter change waits for Wi-Fi unless forced', () async {
      final c = await cache(wifi: false);
      await c.storePool(7, 31, await fixturePool());
      expect(await c.refreshForReciter(7, 'mukhtar_alhaj'), 0);
      expect(await c.staleFor(7, 'mukhtar_alhaj'), [31]);
      expect(await c.refreshForReciter(7, 'mukhtar_alhaj', force: true), 1);
    });
  });
}
