// Games v4 T48: the play page opens a level through /draw and draws its template; an unreadable draw shows "needs a
// newer version"; the registry holds the four ready templates; the result extras fit every size.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/games/core/game_template.dart';
import 'package:flutter_education_app/features/games/game_play_page.dart';
import 'package:flutter_education_app/features/games/games_models.dart';
import 'package:flutter_education_app/features/games/learner/result_sheet.dart';
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

  GameSummary game() => const GameSummary(id: 31, key: 'vb', engine: 'verse_builder', titleAr: 'لعبة', titleEn: 'Game');

  Future<void> pumpPage(WidgetTester tester, Object? answer) async {
    fake = FakeApi({'POST /api/v1/games/31/draw': (_) => answer}, latency: Duration.zero)..install();
    await tester.pumpWidget(layoutHost(GamePlayPage(game: game(), userId: 1), scaffold: false));
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

  testWidgets('an unreadable draw shows the newer-version fallback', (tester) async {
    final bad = Map<String, dynamic>.from(draw)..['items'] = [{'n': 0, 'type': 'hologram', 'body': {}}];
    AppConfig.lang = 'en';
    await pumpPage(tester, bad);
    expect(find.byType(VerseBuilderGame), findsNothing);
    expect(find.textContaining('newer version'), findsOneWidget);
  });

  testWidgets('result extras: no layout errors', (tester) async {
    await expectNoLayoutErrors(tester, () => const GameResultExtras(coinsAwarded: 12, coins: 340, unlocked: 2));
  });
}
