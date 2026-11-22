// The games' engines play a round and report (score, max) once (D-1346), and a play keeps its client_id until the
// server answers: a lost answer is retried with the SAME id, a definite answer settles it.
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/games/engines/match_engine.dart';
import 'package:flutter_education_app/features/games/engines/order_engine.dart';
import 'package:flutter_education_app/features/games/engines/quiz_engine.dart';
import 'package:flutter_education_app/features/games/games_api.dart';
import 'package:flutter_education_app/features/games/games_models.dart';
import 'package:flutter_education_app/features/learn_kit/learn_kit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

class _FakeGames extends GamesApi {
  _FakeGames(this.answers) : super(api: ApiClient());

  /// One per call: an Object to throw, or the play's stars.
  final List<Object> answers;
  final List<String> ids = [];

  @override
  Future<GamePlayResult> play(int gameId,
      {required String clientId,
      required int score,
      required int maxScore,
      int? durationS,
      DateTime? playedAt,
      String? roundId,
      List<Map<String, Object>>? trace}) async {
    ids.add(clientId);
    final a = answers.removeAt(0);
    if (a is! int) throw a;
    return GamePlayResult.fromJson({
      'play': {'stars': a, 'score': score, 'max_score': maxScore},
      'new_badges': [
        {'key': 'first_play', 'name_ar': 'أول لعبة', 'name_en': 'First game', 'icon': 'play'},
      ],
      'points_awarded': 5,
      'duplicate': ids.length > 1,
    });
  }
}

Future<void> _pump(WidgetTester tester, Widget w) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(layoutHost(SingleChildScrollView(child: w), scale: 1));
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('quiz: right + wrong → 1 of 2', (tester) async {
    (int, int)? done;
    await _pump(
      tester,
      QuizEngine(
        config: const {
          'questions': [
            {'prompt_en': 'a', 'options': ['x', 'y'], 'answer': 1},
            {'prompt_en': 'b', 'options': ['x', 'y', 'z'], 'answer': 0},
            {'prompt_en': 'broken', 'options': ['only'], 'answer': 0},
          ],
        },
        onFinished: (s, m) => done = (s, m),
      ),
    );
    await _tap(tester, 'learn.option.1');
    await _tap(tester, 'learn.feedback.action');
    await _tap(tester, 'learn.option.2');
    await _tap(tester, 'learn.feedback.action');
    expect(done, (1, 2));
  });

  testWidgets('match: a wrong try costs that pair', (tester) async {
    (int, int)? done;
    final pairs = [
      {'a': 'cat', 'b': 'قطة'},
      {'a': 'dog', 'b': 'كلب'},
    ];
    await _pump(tester, MatchEngine(config: {'pairs': pairs}, random: Random(1), onFinished: (s, m) => done = (s, m)));
    // the b side is shuffled: find the row of each pair by its text
    int rowOf(String b) {
      for (var k = 0; k < 2; k++) {
        final w = tester.widget(find.byKey(ValueKey('match.b.$k')));
        if ((w as dynamic).label == b) return k;
      }
      return -1;
    }

    final cat = rowOf('قطة'), dog = rowOf('كلب');
    await _tap(tester, 'match.a.0');
    await _tap(tester, 'match.b.$dog'); // wrong
    await _tap(tester, 'match.a.0');
    await _tap(tester, 'match.b.$cat');
    await _tap(tester, 'match.a.1');
    await _tap(tester, 'match.b.$dog');
    // every pair matched after a slip: a finish in the calm tone, never the error style (QA Phase 6)
    expect(tester.widget<LearnFeedback>(find.byType(LearnFeedback)).neutral, isTrue);
    await _tap(tester, 'learn.feedback.action');
    expect(done, (1, 2));
  });

  testWidgets('quiz: the question, the step and the score reach a screen reader', (tester) async {
    final h = tester.ensureSemantics();
    AppConfig.lang = 'en';
    addTearDown(() => AppConfig.lang = 'ar');
    await _pump(
      tester,
      QuizEngine(
        config: const {
          'questions': [
            {'prompt_en': 'How much is 3 × 9?', 'options': ['27', '18'], 'answer': 0},
            {'prompt_en': 'b', 'options': ['x', 'y'], 'answer': 0},
          ],
        },
        onFinished: (_, _) {},
      ),
    );
    expect(tester.getSemantics(find.bySemanticsLabel('How much is 3 × 9?')),
        containsSemantics(label: 'How much is 3 × 9?', isHeader: true));
    expect(find.bySemanticsLabel(RegExp(r'^Question 1 of 2, Score 0$')), findsOneWidget);
    h.dispose();
  });

  testWidgets('order: Check and the result scroll into view on a short phone', (tester) async {
    tester.view.physicalSize = const Size(360, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    const items = ['Mercury', 'Venus', 'Earth', 'Mars', 'Jupiter', 'Saturn', 'Uranus', 'Neptune'];
    await tester.pumpWidget(layoutHost(
      ListView(children: [OrderEngine(config: const {'items': items}, random: Random(3), onFinished: (_, _) {})]),
      scale: 1,
    ));
    await tester.pump();
    for (final want in items) {
      await tester.ensureVisible(find.text(want).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(want).last);
      await tester.pumpAndSettle();
    }
    final view = tester.getRect(find.byType(ListView));
    expect(tester.getRect(find.byKey(const ValueKey('order.check'))).bottom, lessThanOrEqualTo(view.bottom));
    await tester.tap(find.byKey(const ValueKey('order.check')));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(const ValueKey('learn.feedback.action'))).bottom, lessThanOrEqualTo(view.bottom));
  });

  testWidgets('order: placed in the right order → full score', (tester) async {
    (int, int)? done;
    const items = ['a', 'b', 'c'];
    await _pump(tester, OrderEngine(config: const {'items': items}, random: Random(2), onFinished: (s, m) => done = (s, m)));
    for (final want in items) {
      // the pool shrinks as items are placed: find the chip that shows [want]
      await tester.tap(find.text(want));
      await tester.pump(const Duration(milliseconds: 400));
    }
    await _tap(tester, 'order.check');
    await _tap(tester, 'learn.feedback.action');
    expect(done, (3, 3));
  });

  test('a play keeps its client_id until the server answers', () async {
    final api = _FakeGames([TimeoutException('lost'), 3]);
    final sub = GamePlaySubmission(gameId: 1, score: 8, maxScore: 8);
    expect(sub.clientId.length, 36);
    expect(await sub.send(api), isNull);
    expect(sub.done, isFalse);
    final r = await sub.send(api);
    expect(r?.stars, 3);
    expect(r?.pointsAwarded, 5);
    expect(api.ids, [sub.clientId, sub.clientId]);
    expect(sub.done, isTrue);
    // a settled play is never sent again
    await sub.send(api);
    expect(api.ids.length, 2);
  });

  test('a definite 4xx settles the play; a new round gets a new id', () async {
    final api = _FakeGames([ApiException(message: 'bad', statusCode: 422, code: 'game_bad_score')]);
    final sub = GamePlaySubmission(gameId: 1, score: 1, maxScore: 1);
    expect(await sub.send(api), isNull);
    expect(sub.done, isTrue);
    expect(sub.error, isNotEmpty);
    expect(GamePlaySubmission(gameId: 1, score: 1, maxScore: 1).clientId, isNot(sub.clientId));
  });
}
