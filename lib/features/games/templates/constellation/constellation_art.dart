// lib/features/games/templates/constellation/constellation_art.dart — what Constellation draws with (T62).
//
//   NightSky           the colours of the night, taken from the age theme's own palette (no literals): deep gradient,
//                      two nebulae, the star white, the golden thread. Kids vivid, teen deep, adult quiet, calm soft teal.
//   ConstellationShape the drawings a finished set reveals (crescent, lantern, book): strokes and fills in unit
//                      coordinates (-1..1, y down), a dot at every few vertices so it reads as stars joined by threads
//   sparklePath        the four-point star, built once
library;

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/painting.dart' show HSLColor;

import 'package:flutter_education_app/features/games/core/age_theme.dart';

Color _tune(Color c, {double sat = 1, double light = 1, double lift = 0}) {
  final h = HSLColor.fromColor(c);
  return h
      .withSaturation((h.saturation * sat).clamp(0.0, 1.0))
      .withLightness((h.lightness * light + lift).clamp(0.0, 1.0))
      .toColor();
}

class NightSky {
  const NightSky({
    required this.top,
    required this.mid,
    required this.bottom,
    required this.nebulaA,
    required this.nebulaB,
    required this.star,
    required this.gold,
    required this.amber,
    required this.chip,
    required this.text,
    required this.textLit,
    required this.ground,
  });

  final Color top, mid, bottom, nebulaA, nebulaB;

  /// The white of a star and of the label text.
  final Color star;
  final Color gold, amber;

  /// The plate under a label.
  final Color chip;
  final Color text, textLit;

  /// The dark edge of the screen (vignette).
  final Color ground;

  factory NightSky.of(AgeTheme theme) {
    final p = theme.palette;
    final kids = theme.age == GameAge.kids && !theme.calm;
    final adult = theme.age == GameAge.adult || theme.calm;
    final base = _tune(p.ink, sat: kids ? 1.25 : 1.0, light: kids ? 1.0 : 0.78);
    final top = _tune(base, light: 0.62);
    final mid = Color.lerp(base, p.accent, kids ? 0.34 : (adult ? 0.1 : 0.22))!;
    final bottom = Color.lerp(_tune(base, light: 1.15, lift: 0.03), p.glow, kids ? 0.24 : (adult ? 0.1 : 0.2))!;
    final star = Color.lerp(p.paper, p.gold, 0.12)!;
    return NightSky(
      top: top,
      mid: _tune(mid, light: 0.95),
      bottom: bottom,
      nebulaA: Color.lerp(p.accent, p.skyTop, 0.2)!,
      nebulaB: Color.lerp(p.accent2, p.glow, 0.3)!,
      star: star,
      gold: Color.lerp(p.gold, p.paper, 0.1)!,
      amber: p.accent2,
      chip: Color.lerp(top, p.ink, 0.5)!,
      text: Color.lerp(p.paper, p.skyTop, 0.04)!,
      textLit: Color.lerp(p.gold, p.paper, 0.45)!,
      ground: _tune(top, light: 0.55),
    );
  }
}

/// The four-point sparkle of radius 1, built once.
final Path sparklePath = () {
  final p = Path();
  const pts = 4;
  for (var i = 0; i < pts * 2; i++) {
    final a = -math.pi / 2 + i * math.pi / pts;
    final r = i.isEven ? 1.0 : 0.28;
    final x = math.cos(a) * r, y = math.sin(a) * r;
    i == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
  }
  return p..close();
}();

/// A drawing a finished set reveals. Strokes and fills in unit coordinates.
class ConstellationShape {
  const ConstellationShape(this.id, this.strokes, this.fills);
  final int id;
  final List<List<Offset>> strokes;
  final List<List<Offset>> fills;

  /// How many segments the strokes hold in all (the reveal draws the first part of them).
  int get segments => strokes.fold(0, (a, s) => a + math.max(0, s.length - 1));

  Path fillPath(double cx, double cy, double r) {
    final p = Path();
    for (final f in fills) {
      for (var i = 0; i < f.length; i++) {
        final x = cx + f[i].dx * r, y = cy + f[i].dy * r;
        i == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
      }
      p.close();
    }
    return p;
  }
}

List<Offset> _arc(double cx, double cy, double r, double from, double to, int steps) {
  final out = <Offset>[];
  for (var i = 0; i <= steps; i++) {
    final a = from + (to - from) * i / steps;
    out.add(Offset(cx + math.cos(a) * r, cy + math.sin(a) * r));
  }
  return out;
}

double _rad(double d) => d * math.pi / 180;

final ConstellationShape crescentShape = () {
  final outer = _arc(0, 0, 1, _rad(51.3), _rad(308.7), 34);
  final inner = _arc(0.45, 0, 0.8, _rad(282.6), _rad(77.4), 30);
  final loop = [...outer, ...inner, outer.first];
  return ConstellationShape(0, [loop], [loop]);
}();

final ConstellationShape lanternShape = () {
  List<Offset> side(double sign) => [
        for (var i = 0; i <= 14; i++)
          Offset(sign * (0.3 + 0.26 * math.sin(math.pi * i / 14)), -0.68 + 1.3 * i / 14),
      ];
  final left = side(-1), right = side(1);
  final body = [...left, ...right.reversed, left.first];
  List<Offset> rib(double sign) => [
        for (var i = 0; i <= 14; i++) Offset(sign * (0.1 + 0.15 * math.sin(math.pi * i / 14)), -0.68 + 1.3 * i / 14),
      ];
  return ConstellationShape(
    1,
    [
      body,
      [const Offset(-0.3, -0.68), const Offset(-0.17, -0.86), const Offset(0.17, -0.86), const Offset(0.3, -0.68)],
      [const Offset(-0.3, 0.62), const Offset(-0.2, 0.76), const Offset(0.2, 0.76), const Offset(0.3, 0.62)],
      [const Offset(0, -1), const Offset(0, -0.86)],
      [const Offset(0, 0.76), const Offset(0, 0.96)],
      rib(-1),
      rib(1),
    ],
    [body],
  );
}();

final ConstellationShape bookShape = () {
  List<Offset> page(double s) => [
        const Offset(0, -0.42),
        Offset(s * 0.25, -0.58),
        Offset(s * 0.62, -0.64),
        Offset(s * 0.98, -0.52),
        Offset(s * 0.98, 0.5),
        Offset(s * 0.62, 0.6),
        Offset(s * 0.25, 0.56),
        Offset(0, 0.48),
        Offset(0, -0.42),
      ];
  List<Offset> line(double s, double y) => [Offset(s * 0.2, y - 0.02), Offset(s * 0.78, y - 0.1)];
  final l = page(-1), r = page(1);
  return ConstellationShape(
    2,
    [
      l,
      r,
      for (final y in const [-0.3, -0.12, 0.06, 0.24]) ...[line(-1, y), line(1, y)],
    ],
    [l, r],
  );
}();

final List<ConstellationShape> kConstellationShapes = [crescentShape, lanternShape, bookShape];

ConstellationShape shapeFor(int k) => kConstellationShapes[k % kConstellationShapes.length];
