// lib/features/games/core/age_theme.dart: the look of a game by the learner's age band (Games v4 T25, CONTRACT §8).
//
//   GameAge        kids (6-9) vivid cartoon, teen (10-17) dusk and neon, adult (18+) muted and elegant
//   GamePalette    every colour the painted art (game_art.dart) and the character (game_character.dart) draw with
//   AgeTheme       a palette + the manner of the age (outline weight, bounce, parallax depth). `calm` is the variant
//                  of sacred content (Quran, Hadith): desaturated, no outline, slow and quiet. `night` follows dark mode.
//   AgeThemeScope  hands an AgeTheme down a game page; `AgeThemeScope.of(context)` falls back to the theme of the
//                  `adult` band, never throws.
//
// The palette is the one place the games' painted art keeps raw colour (hue / saturation / lightness seeds); the
// accent of teen and adult blends with the app theme's primary (`context.colors`), so a server palette still shows.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

enum GameAge {
  kids,
  teen,
  adult;

  /// `6-9` / `10-13` / `14-17` / `18+` (CONTRACT §8); null or unknown reads as teen, the middle look.
  static GameAge fromBand(String? band) {
    switch (band) {
      case '6-9':
        return GameAge.kids;
      case '10-13':
      case '14-17':
        return GameAge.teen;
      case '18+':
        return GameAge.adult;
    }
    return GameAge.teen;
  }
}

class GamePalette {
  const GamePalette({
    required this.skyTop,
    required this.skyMid,
    required this.skyBottom,
    required this.glow,
    required this.far,
    required this.mid,
    required this.near,
    required this.cloud,
    required this.accent,
    required this.accent2,
    required this.ink,
    required this.paper,
    required this.gold,
    required this.skin,
    required this.hair,
  });

  final Color skyTop, skyMid, skyBottom, glow;
  final Color far, mid, near, cloud;
  final Color accent, accent2, ink, paper, gold, skin, hair;

  GamePalette map(Color Function(Color) f) => GamePalette(
        skyTop: f(skyTop), skyMid: f(skyMid), skyBottom: f(skyBottom), glow: f(glow),
        far: f(far), mid: f(mid), near: f(near), cloud: f(cloud),
        accent: f(accent), accent2: f(accent2), ink: f(ink), paper: f(paper), gold: f(gold),
        skin: f(skin), hair: f(hair),
      );

  GamePalette copyWith({Color? accent, Color? accent2}) => GamePalette(
        skyTop: skyTop, skyMid: skyMid, skyBottom: skyBottom, glow: glow,
        far: far, mid: mid, near: near, cloud: cloud,
        accent: accent ?? this.accent, accent2: accent2 ?? this.accent2,
        ink: ink, paper: paper, gold: gold, skin: skin, hair: hair,
      );
}

Color _hsl(double h, double s, double l) => HSLColor.fromAHSL(1, h, s, l).toColor();

Color _tune(Color c, {double sat = 1, double light = 1, double lift = 0}) {
  final h = HSLColor.fromColor(c);
  return h.withSaturation((h.saturation * sat).clamp(0.0, 1.0)).withLightness((h.lightness * light + lift).clamp(0.0, 1.0)).toColor();
}

final GamePalette _kids = GamePalette(
  skyTop: _hsl(207, 0.92, 0.58), skyMid: _hsl(196, 0.88, 0.74), skyBottom: _hsl(52, 0.95, 0.88),
  glow: _hsl(46, 1, 0.68),
  far: _hsl(160, 0.55, 0.66), mid: _hsl(142, 0.6, 0.5), near: _hsl(126, 0.62, 0.38),
  cloud: _hsl(200, 0.6, 0.99),
  accent: _hsl(346, 0.86, 0.62), accent2: _hsl(44, 1, 0.58),
  ink: _hsl(232, 0.46, 0.2), paper: _hsl(40, 0.7, 0.98), gold: _hsl(45, 0.98, 0.55),
  skin: _hsl(26, 0.72, 0.74), hair: _hsl(22, 0.55, 0.24),
);

final GamePalette _teen = GamePalette(
  skyTop: _hsl(246, 0.56, 0.26), skyMid: _hsl(286, 0.5, 0.42), skyBottom: _hsl(14, 0.82, 0.66),
  glow: _hsl(32, 0.96, 0.64),
  far: _hsl(262, 0.38, 0.34), mid: _hsl(252, 0.42, 0.25), near: _hsl(246, 0.46, 0.17),
  cloud: _hsl(300, 0.4, 0.7),
  accent: _hsl(174, 0.78, 0.5), accent2: _hsl(330, 0.82, 0.62),
  ink: _hsl(246, 0.5, 0.12), paper: _hsl(260, 0.3, 0.96), gold: _hsl(42, 0.95, 0.6),
  skin: _hsl(24, 0.55, 0.7), hair: _hsl(250, 0.3, 0.16),
);

final GamePalette _calmPalette = GamePalette(
  skyTop: _hsl(184, 0.34, 0.8), skyMid: _hsl(46, 0.62, 0.9), skyBottom: _hsl(38, 0.78, 0.84),
  glow: _hsl(40, 0.9, 0.74),
  far: _hsl(160, 0.2, 0.76), mid: _hsl(150, 0.24, 0.62), near: _hsl(142, 0.28, 0.44),
  cloud: _hsl(42, 0.7, 0.97),
  accent: _hsl(172, 0.34, 0.36), accent2: _hsl(38, 0.68, 0.58),
  ink: _hsl(190, 0.3, 0.2), paper: _hsl(44, 0.7, 0.97), gold: _hsl(40, 0.7, 0.58),
  skin: _hsl(24, 0.46, 0.72), hair: _hsl(24, 0.3, 0.24),
);

final GamePalette _adult = GamePalette(
  skyTop: _hsl(212, 0.2, 0.72), skyMid: _hsl(26, 0.26, 0.86), skyBottom: _hsl(36, 0.34, 0.93),
  glow: _hsl(38, 0.5, 0.82),
  far: _hsl(204, 0.14, 0.7), mid: _hsl(202, 0.16, 0.56), near: _hsl(206, 0.2, 0.4),
  cloud: _hsl(30, 0.3, 0.97),
  accent: _hsl(200, 0.38, 0.4), accent2: _hsl(34, 0.5, 0.56),
  ink: _hsl(214, 0.28, 0.18), paper: _hsl(36, 0.3, 0.97), gold: _hsl(40, 0.6, 0.56),
  skin: _hsl(24, 0.42, 0.7), hair: _hsl(24, 0.3, 0.22),
);

class AgeTheme {
  const AgeTheme._({
    required this.age,
    required this.palette,
    required this.outline,
    required this.bounce,
    required this.parallax,
    required this.calm,
    required this.night,
  });

  final GameAge age;
  final GamePalette palette;

  /// Outline weight as a share of the art's unit (kids 1, teen 0.45, adult / calm 0).
  final double outline;

  /// How lively the idle motion is (1 = kids).
  final double bounce;

  /// How far the layers drift (0 = still).
  final double parallax;

  /// The sacred variant: quiet colour, no outline, no bounce.
  final bool calm;

  /// Dark mode: a night sky, stars.
  final bool night;

  factory AgeTheme.build(GameAge age, {bool calm = false, bool night = false, Color? primary}) {
    var p = switch (age) { GameAge.kids => _kids, GameAge.teen => _teen, GameAge.adult => _adult };
    if (primary != null && age != GameAge.kids) {
      p = p.copyWith(accent: Color.lerp(p.accent, primary, 0.55));
    }
    if (night && age != GameAge.teen) {
      final sky = {p.skyTop, p.skyMid, p.skyBottom, p.far, p.mid, p.near};
      p = p.map((c) => sky.contains(c) ? _tune(c, sat: 0.9, light: 0.42) : c);
    }
    if (calm) {
      // a warm dawn: the same for every age, with the person's own skin and hair kept
      p = _calmPalette.copyWith(accent: primary == null ? null : Color.lerp(_calmPalette.accent, primary, 0.25));
      night = false;
    }
    return AgeTheme._(
      age: age,
      palette: p,
      outline: calm ? 0.3 : switch (age) { GameAge.kids => 1, GameAge.teen => 0.45, GameAge.adult => 0.3 },
      bounce: calm ? 0.35 : switch (age) { GameAge.kids => 1, GameAge.teen => 0.7, GameAge.adult => 0.45 },
      parallax: calm ? 0.3 : switch (age) { GameAge.kids => 1, GameAge.teen => 0.8, GameAge.adult => 0.5 },
      calm: calm,
      night: !calm && (night || age == GameAge.teen),
    );
  }

  /// From the learner's band, the page's sacred flag and the app's light / dark mode.
  factory AgeTheme.of(BuildContext context, {String? band, GameAge? age, bool sacred = false}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AgeTheme.build(age ?? GameAge.fromBand(band),
        calm: sacred, night: dark, primary: context.colors.primary);
  }
}

class AgeThemeScope extends InheritedWidget {
  const AgeThemeScope({super.key, required this.theme, required super.child});
  final AgeTheme theme;

  static AgeTheme of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AgeThemeScope>()?.theme ?? AgeTheme.build(GameAge.adult);

  @override
  bool updateShouldNotify(AgeThemeScope old) => old.theme != theme;
}
