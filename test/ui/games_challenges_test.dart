// Games v4 T76: the challenges widgets: layout at 320 / 1400 (ar + en, text scale 1.3) and the route / date helpers.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/routing/app_routes.dart';
import 'package:flutter_education_app/features/games/content/games_v4_api.dart';
import 'package:flutter_education_app/features/games/learner/challenges.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

V4Challenge challengeOf({bool open = true, bool joined = true, int players = 4, String code = 'K7M2QXP9'}) => V4Challenge({
      'id': 1,
      'code': code,
      'kind': 'friends',
      'owner': 'سارة م.',
      'status': open ? 'open' : 'closed',
      'joined': joined,
      'week_start': '2026-11-23',
      'link': 'https://nextbrain.site/app/games/challenge/K7M2QXP9',
      'game': {'id': 7, 'level_no': 3, 'topic': 'surah-78', 'template': 'challenge_quiz'},
      'board': [
        for (var i = 0; i < players; i++)
          {'rank': i + 1, 'name': i == 1 ? 'عبد الرحمن الطويل جداً جداً' : 'Player ${i + 1}', 'score': 9 - i, 'max_score': 10, 'duration_ms': 41000 + i * 3000, 'is_me': i == 2},
      ],
    });

V4ClassBoard boardOf() => V4ClassBoard(weekStart: '2026-11-23', mine: null, items: [
      for (var i = 0; i < 5; i++) {'rank': i + 1, 'course_id': i, 'title': i == 1 ? 'الرياضيات للصف الخامس الابتدائي - المجموعة الأولى' : 'Course ${i + 1}', 'points_avg': 120.5 - i * 14, 'players': 3 + i * 5, 'is_mine': i == 1},
    ]);

void main() {
  testWidgets('challenge view lays out', (tester) async {
    await expectNoLayoutErrors(tester, () => ChallengeView(challenge: challengeOf(), ageBand: '6-9'));
    await expectNoLayoutErrors(tester, () => ChallengeView(challenge: challengeOf(open: false, joined: false, players: 0), ageBand: '18+'));
  });
  testWidgets('my challenges and class board lay out', (tester) async {
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: MyChallengesView(items: [challengeOf(), challengeOf(open: false, joined: false, code: 'Q4WZ8RTL')], ageBand: '6-9')));
    await expectNoLayoutErrors(tester, () => const SingleChildScrollView(child: MyChallengesView(items: [], ageBand: '18+')));
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: ClassBoardView(board: boardOf(), ageBand: '18+')));
    await expectNoLayoutErrors(tester, () => const SingleChildScrollView(child: ClassBoardView(board: V4ClassBoard(weekStart: null, items: []))));
  });
  test('links', () {
    expect(challengeCodeFromRoute('/games/c/ABC12345'), 'ABC12345');
    expect(challengeCodeFromRoute('/app/games/challenge/ABC12345'), 'ABC12345');
    expect(challengeCodeFromRoute('/games/7'), isNull);
    expect(AppRoutes.match('/games/c/ABC12345')?.id, 'games.challenge');
    expect(AppRoutes.match('/games/challenge/ABC12345')?.params['code'], 'ABC12345');
    expect(AppRoutes.match('/games/progress')?.id, 'games.progress');
  });
  test('the week ends 7 days after its start', () {
    expect(challengeEnds({'week_start': '2026-11-23'}), DateTime.utc(2026, 11, 30));
    expect(challengeEnds({'closes_at': '2026-11-25T10:00:00'}), DateTime.utc(2026, 11, 25, 10));
    expect(challengeEnds({}), isNull);
  });
}

/// Counts the class-board calls; answers no challenges.
class _CountingApi extends GamesV4Api {
  int boardCalls = 0;
  @override
  Future<List<V4Challenge>> myChallenges() async => [challengeOf()];
  @override
  Future<V4ClassBoard> classBoard(int courseId) async {
    boardCalls++;
    return boardOf();
  }
}

void classBoardPrivacyTests() {
  test('only staff roles see the class board', () {
    for (final r in ['teacher', 'admin', 'super-admin', 'developer', 'org-admin', 'org-staff']) {
      expect(gamesClassBoardFor(r), isTrue, reason: r);
    }
    for (final r in ['student', 'parent', '', null]) {
      expect(gamesClassBoardFor(r), isFalse, reason: '$r');
    }
  });

  testWidgets('a learner gets no class-board tab and no class-board call', (tester) async {
    final api = _CountingApi();
    await tester.pumpWidget(layoutHost(GamesChallengesPage(api: api, showClassBoard: false), scale: 1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('games.challenges.tabs')), findsNothing);
    expect(find.byType(MyChallengesView), findsOneWidget);
    expect(api.boardCalls, 0);
  });

  testWidgets('staff keep the class-board tab', (tester) async {
    await tester.pumpWidget(layoutHost(GamesChallengesPage(api: _CountingApi(), showClassBoard: true), scale: 1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('games.challenges.tabs')), findsOneWidget);
  });
}
