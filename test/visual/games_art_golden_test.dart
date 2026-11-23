// VISUAL review renders of the Games v4 art (T25): every age theme (and the calm variant) at phone and desktop size,
// into test/visual/goldens/games_art_*.png. Not a CI suite; compared by eye.
//
//   flutter test test/visual/games_art_golden_test.dart --update-goldens
@Tags(['visual'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/games/core/age_theme.dart';
import 'package:flutter_education_app/features/games/core/game_art.dart';
import 'package:flutter_education_app/features/games/core/game_character.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

const _sets = <(String, GameMood, Map<String, String?>)>[
  ('crown', GameMood.happy, {'hat': 'hat_crown', 'outfit': 'outfit_astro', 'vehicle': 'vehicle_rocket', 'trail': 'trail_stars'}),
  ('plain', GameMood.idle, {}),
  ('racer', GameMood.idle, {'hat': 'hat_explorer', 'outfit': 'outfit_traveller', 'vehicle': 'vehicle_racer', 'trail': 'trail_comet'}),
];

void main() {
  const sizes = {'phone': Size(390, 844), 'desktop': Size(1400, 900)};
  final themes = {
    for (final a in GameAge.values) a.name: AgeTheme.build(a),
    'calm': AgeTheme.build(GameAge.adult, calm: true),
    'kids_night': AgeTheme.build(GameAge.kids, night: true),
  };
  for (final s in sizes.entries) {
    for (final th in themes.entries) {
      testWidgets('${th.key} ${s.key}', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = s.value;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        await tester.pumpWidget(layoutHost(
          RepaintBoundary(
            key: const ValueKey('shot'),
            child: GameBackdrop(
              theme: th.value,
              child: Align(
                alignment: const Alignment(0, 0.62),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  for (final c in _sets)
                    Align(widthFactor: 0.72, child: SizedBox.square(dimension: s.value.width < 600 ? 160 : 336, child: GameCharacter(theme: th.value, mood: c.$2, equipped: c.$3))),
                ]),
              ),
            ),
          ),
          scale: 1,
          scaffold: false,
        ));
        await tester.pump(const Duration(milliseconds: 1300));
        await expectLater(find.byKey(const ValueKey('shot')), matchesGoldenFile('goldens/games_art_${th.key}_${s.key}.png'));
      });
    }
  }
}
