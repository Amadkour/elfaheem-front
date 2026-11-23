// Games v4 T52: Word Train (the rows of the floating-tokens base, the round, a scripted play-through, the calm pearls).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/games/bases/floating_tokens.dart';
import 'package:flutter_education_app/features/games/core/age_theme.dart';
import 'package:flutter_education_app/features/games/core/game_items.dart';
import 'package:flutter_education_app/features/games/core/game_session.dart';
import 'package:flutter_education_app/features/games/shell/game_shell.dart';
import 'package:flutter_education_app/features/games/templates/word_train/word_train.dart';
import 'package:flutter_education_app/features/games/templates/word_fishing/word_fishing.dart' show WordFishingRound;
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

GameItem order(int n, {bool sacred = false, List<int> show = const [2, 4, 0, 3, 5, 1]}) => GameItem(
      n: n,
      type: ItemType.sequence,
      sacred: sacred,
      sourceKind: sacred ? 'quran' : null,
      prompt: const GameText('رتّب الكلمات', 'Put the words in order'),
      body: {
        'mode': 'order',
        'unit': 'word',
        'tokens': ['قُلْ', 'هُوَ', 'ٱللَّهُ', 'أَحَدٌ'],
        'blanks': [0, 1, 2, 3],
        'eq': [0, 1, 2, 3, 4, 5],
        'extra': ['ٱلصَّمَدُ', 'كُفُوًا'],
        'show': show,
      },
    );

Future<void> pumpFor(WidgetTester t, int steps) async {
  for (var i = 0; i < steps; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

Future<void> tapFish(WidgetTester t, WordTrainViewState v, int fish) async {
  await t.tapAt(t.getTopLeft(find.byType(WordTrainView)) + v.game.tokenCenter(fish));
  await pumpFor(t, 3);
}

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    GameFeedback.instance.reset();
  });

  test('round: labels follow show, fits uses the equal words', () {
    final r = WordFishingRound.of(order(0));
    expect(r.words, ['قُلْ', 'هُوَ', 'ٱللَّهُ', 'أَحَدٌ']);
    expect(r.labels, ['ٱللَّهُ', 'ٱلصَّمَدُ', 'قُلْ', 'أَحَدٌ', 'كُفُوًا', 'هُوَ']);
    expect(r.fits(0, 0), isTrue);
    expect(r.fits(1, 0), isFalse);
    expect(r.fits(4, 0), isFalse);
    expect(r.fishFor(0, (_) => true), 2);
  });

  for (final sacred in [false, true]) {
    testWidgets("layout: no overflow on any size, both languages, scale 1.3 (sacred=$sacred)", (tester) async {
      await expectNoLayoutErrors(tester, () {
        final s = GameSession(items: [order(0, sacred: sacred)], sacred: sacred, settings: GameSettings.fromJson(const {}, sacred: sacred));
        return AgeThemeScope(theme: AgeTheme.build(GameAge.kids, calm: sacred), child: WordTrainTemplate(silent: true).build(s));
      });
    });
  }

  testWidgets('a scripted play-through: wrong try, then the ayah in order; one answer per place', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 780);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final s = GameSession(items: [order(0), order(1, show: [0, 1, 2, 3, 4, 5])], settings: const GameSettings(speed: 3));
    await tester.pumpWidget(layoutHost(Material(child: AgeThemeScope(theme: AgeTheme.build(GameAge.kids), child: WordTrainTemplate(silent: true).build(s))), scale: 1, scaffold: false));
    await pumpFor(tester, 30);
    final v = tester.state<WordTrainViewState>(find.byType(WordTrainView));
    expect(v.itemIndex, 0);
    // a wrong fish (place 0 wants "قُلْ", fish 0 is "ٱللَّهُ"): reported once, the place stays open
    await tapFish(tester, v, 0);
    expect(v.slot, 0);
    expect(s.trace.length, 1);
    expect(s.trace.single['a'], [0, 2]);
    await tapFish(tester, v, 1);
    expect(s.trace.length, 1, reason: 'a retry of the same place is not reported again');
    // now in order
    for (var p = 0; p < 4; p++) {
      final f = v.round!.fishFor(p, (k) => v.game.isAlive(k));
      await tapFish(tester, v, f);
      expect(v.slot, p + 1);
    }
    expect(v.complete, isTrue);
    expect(s.trace.length, 4);
    expect([for (final e in s.trace) (e['a'] as List)[0]], [0, 1, 2, 3]);
    // the rest of the sea leaves, the next sentence comes
    for (var i = 0; i < 60 && v.itemIndex == 0; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(v.itemIndex, 1);
    for (var i = 0; i < 80 && !v.complete; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('sacred round: calm wagons, calm theme, a wrong pearl costs nothing and the place stays', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 780);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final s = GameSession(items: [order(0, sacred: true)], sacred: true, settings: GameSettings.fromJson(const {}, sacred: true));
    await tester.pumpWidget(layoutHost(Material(child: AgeThemeScope(theme: AgeTheme.build(GameAge.adult), child: WordTrainTemplate(silent: true).build(s))), scale: 1, scaffold: false));
    await pumpFor(tester, 30);
    final v = tester.state<WordTrainViewState>(find.byType(WordTrainView));
    expect(v.game.skin, TokenSkin.train);
    expect(v.game.theme.calm, isTrue);
    await tapFish(tester, v, 0);
    expect(v.slot, 0);
    expect(s.hasLives, isFalse);
    final f = v.round!.fishFor(0, (k) => v.game.isAlive(k));
    await tapFish(tester, v, f);
    expect(v.slot, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });
}
