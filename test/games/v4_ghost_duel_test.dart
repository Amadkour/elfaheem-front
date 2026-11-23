// Games v4 T63: Ghost Duel: layout on every size, the ghost's replay on the round's clock, the training partner, and the
// play page's wiring over FakeApi (ghost_play_id sent, never a verdict; the server's `duel` is what the result shows).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/games/core/age_theme.dart';
import 'package:flutter_education_app/features/games/core/duel.dart';
import 'package:flutter_education_app/features/games/core/game_items.dart';
import 'package:flutter_education_app/features/games/core/game_session.dart';
import 'package:flutter_education_app/features/games/game_play_page.dart';
import 'package:flutter_education_app/features/games/games_models.dart';
import 'package:flutter_education_app/features/games/templates/ghost_duel/duel_scene.dart';
import 'package:flutter_education_app/features/games/templates/ghost_duel/ghost_duel.dart';
import 'package:flutter_education_app/features/games/templates/register_all.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../ui/layout_harness.dart';
import 'v4_stage_test.dart' show mcq, tf, spin;

const _ghost = DuelGhost(
  id: 77,
  name: 'Sara A.',
  score: 2,
  maxScore: 3,
  durationMs: 4000,
  events: [(1000, 1), (2000, 0), (3000, 1)],
);

const _ghostJson = {
  'id': 77,
  'name': 'Sara A.',
  'score': 1,
  'max_score': 2,
  'duration_ms': 90000,
  'events': [
    [4000, 1],
    [9000, 0]
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    AppConfig.lang = 'en';
    mockRequestPlugins();
  });

  GameSession session(List<GameItem> items, {int Function()? now, DuelGhost? ghost}) => GameSession(
        items: items,
        settings: GameSettings.fromJson(const {'timer_s': 0, 'lives': 0, 'penalty': 'none'}, sacred: false),
        templateKey: 'ghost_duel',
        nowMs: now,
      )
        ..ghost = ghost
        ..start();

  test('is registered, takes mcq and true_false, never sacred', () {
    expect(kReadyTemplates.any((t) => t.key == 'ghost_duel'), isTrue);
    expect(kGhostDuel.sacredAllowed, isFalse);
    expect(kGhostDuel.accepts, {ItemType.mcq, ItemType.trueFalse});
    expect(GhostDuelTemplate.refuses(session([mcq(0, sacred: true)])), isTrue);
    expect(GhostDuelTemplate.refuses(session([mcq(0)])), isFalse);
  });

  test('the training partner is 7 of 10 at par pace and the contract rule decides', () {
    final b = botDuelGhost(items: 10, parMs: 60000);
    expect((b.score, b.maxScore, b.durationMs, b.bot), (7, 10, 60000, true));
    expect(b.events.where((e) => e.$2 == 1), hasLength(7));
    expect(b.events.last.$1, 60000);
    bool w(int ms, int s, int m, int ts, int tm, int tms) =>
        duelWins(myScore: s, myMax: m, myMs: ms, theirScore: ts, theirMax: tm, theirMs: tms);
    expect(w(9, 8, 10, 7, 10, 9), isTrue, reason: 'a higher share wins');
    expect(w(5, 3, 4, 6, 8, 9), isTrue, reason: 'equal share, shorter time');
    expect(w(9, 3, 4, 6, 8, 5), isFalse, reason: 'equal share, slower');
    expect(w(5, 3, 4, 6, 8, 5), isFalse, reason: 'a tie on both is not a win');
    expect(w(1, 6, 10, 7, 10, 9), isFalse);
  });

  testWidgets('lays out on every size, with a ghost and with the training partner', (tester) async {
    await expectNoLayoutErrors(tester, () => GhostDuelGame(session: session([mcq(0), tf(1)], ghost: _ghost), silent: true), scaffold: false);
    await expectNoLayoutErrors(tester, () => GhostDuelGame(session: session([mcq(0), tf(1)]), silent: true), scaffold: false);
  });

  testWidgets('the result card lays out on every size, won and lost, confirmed or not', (tester) async {
    for (final won in [true, false]) {
      await expectNoLayoutErrors(
          tester,
          () => DuelResultCard(
              theme: AgeTheme.build(GameAge.kids),
              won: won,
              opponentName: 'A very long ghost name that must not overflow the chip',
              myShare: 0.6,
              theirShare: 0.7,
              confirmed: won));
    }
  });

  testWidgets('the ghost pulls when its recorded answers land on the round clock; a right answer pulls the learner', (tester) async {
    var clock = 0;
    final s = session([mcq(0), mcq(1), mcq(2)], now: () => clock, ghost: _ghost);
    await tester.pumpWidget(layoutHost(GhostDuelGame(session: s, silent: true), scaffold: false));
    await spin(tester, 300);
    DuelScene scene() => tester.widget<DuelScene>(find.byType(DuelScene));
    expect((scene().myCount, scene().ghostCount), (0, 0));
    clock = 1100; // the ghost's first step (right) landed
    await spin(tester, 200);
    expect((scene().ghostCount, scene().kick), (1, DuelKick.ghostPull));
    expect(scene().pos, closeTo(-1 / 3, 1e-9));
    clock = 2100; // its second step was a miss: it slips, nothing pulls
    await spin(tester, 200);
    expect((scene().ghostCount, scene().kick), (1, DuelKick.ghostSlip));
    await tester.tap(find.byKey(const ValueKey('opt-1')));
    await spin(tester, 300);
    expect(scene().myCount, 1);
    expect(scene().kick, DuelKick.mePull);
    expect(scene().pos, closeTo(0, 1e-9));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a pause stops the ghost', (tester) async {
    var clock = 0;
    final s = session([mcq(0), mcq(1)], now: () => clock, ghost: _ghost);
    await tester.pumpWidget(layoutHost(GhostDuelGame(session: s, silent: true), scaffold: false));
    await spin(tester, 200);
    s.pause();
    clock = 5000;
    await spin(tester, 300);
    expect(tester.widget<DuelScene>(find.byType(DuelScene)).ghostCount, 0);
    await tester.pumpWidget(const SizedBox());
  });

  group('play page', () {
    GameSummary game() => const GameSummary(id: 44, key: 'gd', engine: 'ghost_duel', titleAr: 'لعبة', titleEn: 'Game');
    Map<String, dynamic> draw() => {
          'draw_id': 'd-44',
          'seed': 1,
          'kind': 'round',
          'sacred': false,
          'template': 'ghost_duel',
          'settings': {'timer_s': 0, 'lives': 0, 'penalty': 'none', 'theme': 'adult'},
          'items': [
            for (var n = 0; n < 2; n++)
              {
                'n': n,
                'type': 'mcq',
                'prompt': {'ar': 'سؤال', 'en': 'Question'},
                'body': {
                  'options': [
                    {'text': 'A'},
                    {'text': 'B'},
                    {'text': 'C'},
                    {'text': 'D'}
                  ],
                  'answer': 1,
                  'show': [0, 1, 2, 3],
                },
                'max': 1,
              },
          ],
          'max_score': 2,
          'round_id': 'r-44',
        };

    /// Plays both questions right; returns the fake and the body of the POST /plays.
    Future<(FakeApi, Map<String, dynamic>)> run(WidgetTester tester, {required bool won, Object? ghost}) async {
      final sent = <String, dynamic>{};
      final fake = FakeApi({
        'POST /api/v1/games/44/draw': (_) => draw(),
        'GET /api/v1/games/44/ghost': (_) => {'ghost': ghost},
        'POST /api/v1/games/44/plays': (o) {
          sent.addAll(Map<String, dynamic>.from(o.data as Map));
          return {
            'play': {'id': 1, 'game_id': 44, 'client_id': 'c', 'score': 2, 'max_score': 2, 'stars': 3, 'duration_s': 5, 'played_at': '2026-11-23T10:00:00'},
            'progress': {'game_id': 44, 'best_score': 2, 'stars': 3, 'plays': 1, 'attempts': 1},
            'new_badges': [],
            'points_awarded': 0,
            'duplicate': false,
            'ranked': true,
            'coins_awarded': won ? 2 : 0,
            'coins': 10,
            'unlocked': [],
            'duel': {'won': won, 'opponent': ghost == null ? 'bot' : 'ghost'},
          };
        },
      }, latency: Duration.zero)
        ..install();
      addTearDown(fake.uninstall);
      await tester.pumpWidget(layoutHost(GamePlayPage(game: game(), userId: 1), scaffold: false));
      await spin(tester, 800);
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byKey(const ValueKey('opt-1')));
        await spin(tester, 3000);
      }
      await spin(tester, 1000);
      return (fake, sent);
    }

    testWidgets('sends ghost_play_id, never a verdict, and shows the server win', (tester) async {
      final (fake, sent) = await run(tester, won: true, ghost: _ghostJson);
      expect(fake.calls.any((c) => c.method == 'GET' && c.path.endsWith('/games/44/ghost')), isTrue);
      expect(sent['ghost_play_id'], 77);
      expect(sent.containsKey('duel_won'), isFalse);
      expect(find.byKey(const ValueKey('games.duel.result')), findsOneWidget);
      expect(find.text('You won the duel!'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the server verdict "lost" is shown even when the own rule would say won', (tester) async {
      await run(tester, won: false, ghost: _ghostJson);
      expect(find.text('You won the duel!'), findsNothing);
      expect(find.textContaining('edged it this time'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('with no ghost the bot plays and ghost_play_id is absent', (tester) async {
      final (_, sent) = await run(tester, won: true, ghost: null);
      expect(sent.containsKey('ghost_play_id'), isFalse);
      expect(find.byKey(const ValueKey('games.duel.result')), findsOneWidget);
      expect(find.text('Against the training partner'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
