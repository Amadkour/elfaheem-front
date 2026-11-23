// Games v4 T25: the painted art and the character lay out on every size and language, for every age theme.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/games/core/age_theme.dart';
import 'package:flutter_education_app/features/games/core/game_art.dart';
import 'package:flutter_education_app/features/games/core/game_character.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

void main() {
  test('band to age', () {
    expect(GameAge.fromBand('6-9'), GameAge.kids);
    expect(GameAge.fromBand('10-13'), GameAge.teen);
    expect(GameAge.fromBand('14-17'), GameAge.teen);
    expect(GameAge.fromBand('18+'), GameAge.adult);
    expect(GameAge.fromBand(null), GameAge.teen);
  });

  test('calm has no outline and a quieter palette', () {
    final calm = AgeTheme.build(GameAge.kids, calm: true);
    expect(calm.outline, 0);
    expect(calm.calm, isTrue);
    expect(calm.bounce, lessThan(AgeTheme.build(GameAge.kids).bounce));
  });

  for (final age in GameAge.values) {
    for (final calm in [false, true]) {
      testWidgets('backdrop + character $age calm=$calm', (tester) async {
        final th = AgeTheme.build(age, calm: calm);
        await expectNoLayoutErrors(
          tester,
          () => GameBackdrop(
            theme: th,
            child: Center(
              child: GameCharacter(
                theme: th,
                mood: GameMood.happy,
                equipped: const {'hat': 'hat_crown', 'outfit': 'outfit_astro', 'vehicle': 'vehicle_rocket', 'trail': 'trail_stars'},
              ),
            ),
          ),
        );
      });
    }
  }

  testWidgets('unknown keys draw a default look', (tester) async {
    final th = AgeTheme.build(GameAge.teen);
    await expectNoLayoutErrors(
      tester,
      () => Center(
        child: GameCharacter(
          theme: th,
          mood: GameMood.sad,
          equipped: const {'hat': 'hat_new', 'outfit': 'outfit_new', 'vehicle': 'vehicle_new', 'trail': 'trail_new'},
        ),
      ),
    );
  });
}
