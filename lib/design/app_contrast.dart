// lib/design/app_contrast.dart — WCAG 2.x contrast maths (pure, unit-tested).
//
//   relativeLuminance(c)              0 (black) … 1 (white), sRGB → linear
//   contrastRatio(a, b)               1 … 21; body / caption text needs ≥ 4.5 (AA)
//   minContrast(fg, surfaces)         the worst ratio of [fg] over every surface
//   ensureContrast(fg, surfaces)      [fg] unchanged when it passes, else the
//                                     nearest lightness (same hue and saturation)
//                                     that does — darker on light surfaces,
//                                     lighter on dark ones
//
// The theme is server-driven and the super admin can edit it, so the live
// palette's muted text colours go through [ensureContrast] before they are
// used (ThemeConfigModel.fromJson): a stored low-contrast value can never ship
// unreadable text.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/painting.dart';

/// WCAG AA for normal-size text.
const double kWcagAaText = 4.5;

double _channel(double v) =>
    v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();

/// WCAG 2.x relative luminance of [c] (alpha ignored).
double relativeLuminance(Color c) =>
    0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b);

/// WCAG 2.x contrast ratio between [a] and [b] (order does not matter).
double contrastRatio(Color a, Color b) {
  final la = relativeLuminance(a);
  final lb = relativeLuminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// The lowest ratio of [fg] over [surfaces] (21 when there are none).
double minContrast(Color fg, Iterable<Color> surfaces) {
  var worst = 21.0;
  for (final s in surfaces) {
    worst = math.min(worst, contrastRatio(fg, s));
  }
  return worst;
}

/// True when [fg] reaches [min] on every one of [surfaces].
bool passesContrast(Color fg, Iterable<Color> surfaces,
    {double min = kWcagAaText}) =>
    minContrast(fg, surfaces) >= min;

/// [fg] when it already reaches [min] on every surface; otherwise the same
/// hue and saturation with its lightness moved, one step at a time, away
/// from the surfaces (darker when they are light, lighter when they are dark)
/// until it does. Returned opaque. When no lightness passes (surfaces both
/// very light and very dark) the step with the best worst-case ratio wins.
Color ensureContrast(Color fg, List<Color> surfaces,
    {double min = kWcagAaText}) {
  final opaque = fg.withValues(alpha: 1);
  if (surfaces.isEmpty || passesContrast(opaque, surfaces, min: min)) {
    return opaque;
  }
  // Mid-grey splits "light" from "dark": the luminance where black and white
  // give the same ratio.
  final midL = math.sqrt(1.05 * 0.05) - 0.05;
  final avgL = surfaces.map(relativeLuminance).reduce((a, b) => a + b) /
      surfaces.length;
  final darken = avgL > midL;

  final hsl = HSLColor.fromColor(opaque);
  var best = opaque;
  var bestRatio = minContrast(opaque, surfaces);
  for (var i = 1; i <= 200; i++) {
    final l = (hsl.lightness + (darken ? -i : i) * 0.005).clamp(0.0, 1.0);
    final c = hsl.withLightness(l).toColor();
    final r = minContrast(c, surfaces);
    if (r >= min) return c;
    if (r > bestRatio) {
      best = c;
      bestRatio = r;
    }
    if (l == 0.0 || l == 1.0) break;
  }
  return best;
}

/// The colours mixed with a main colour (D-550). A shade of one hue reads as flat, so the mesh walks around the
/// wheel: warm mains (red, orange, gold) walk toward pink and violet, cool mains (green, teal, blue, purple) toward
/// blue and magenta. Each colour is moved until [ink] keeps [min] on it. Yellows never darken into olive: they turn
/// to amber first, the way a painter shades yellow.
@immutable
class AppHarmony {
  const AppHarmony(this.base, this.near, this.far, this.depth, this.spark);

  final Color base;

  /// About 35° away: the colour most of the gradient mixes with.
  final Color near;

  /// About 75° away: a second, clearly different hue.
  final Color far;

  /// A deep tone about 110° away, which gives the surface depth without going grey.
  final Color depth;

  /// The contrasting highlight.
  final Color spark;

  factory AppHarmony.of(Color main, Color ink, {double min = kWcagAaText, Color? spark, bool dark = false}) {
    Color safe(Color x) => ensureContrast(_unmuddy(ensureContrast(_unmuddy(x), [ink], min: min)), [ink], min: min);
    final h = HSLColor.fromColor(main);
    if (h.saturation < 0.12) {
      // a grey has no hue to walk: slate tones keep it calm and still not flat
      Color slate(double hue, double l) => safe(HSLColor.fromAHSL(1, hue, 0.28, l).toColor());
      return AppHarmony(safe(main), slate(215, 0.36), slate(250, 0.34), slate(235, dark ? 0.12 : 0.2), spark == null ? slate(190, 0.34) : safe(spark));
    }
    final warm = h.hue >= 330 || h.hue < 100;
    final way = warm ? -1.0 : 1.0;
    final s = h.saturation < 0.55 ? 0.55 : h.saturation;
    Color turn(double degrees, double lightness) =>
        safe(HSLColor.fromAHSL(1, (h.hue + way * degrees) % 360, s.clamp(0.0, 0.92), lightness).toColor());
    final base = safe(main);
    return AppHarmony(
      base,
      turn(36, 0.38),
      turn(78, 0.38),
      turn(112, dark ? 0.14 : 0.22),
      safe(spark ?? HSLColor.fromAHSL(1, (h.hue + 150) % 360, 0.8, 0.42).toColor()),
    );
  }

  /// A yellow or lime that is dark enough to carry light ink is olive. Amber keeps it looking like a colour.
  static Color _unmuddy(Color c) {
    final h = HSLColor.fromColor(c);
    if (h.saturation < 0.25 || h.hue < 42 || h.hue > 82 || h.lightness > 0.6) return c;
    return h.withHue(32 + (h.hue - 42) * 0.1).withSaturation(math.max(h.saturation, 0.82)).toColor();
  }
}

/// The harmonious partner of [c]: a neighbouring hue a little cooler (green -> teal, blue -> violet, red -> amber).
/// A near-grey has no hue to turn, so it gets a lighter shade of itself.
Color companionOf(Color c) {
  final h = HSLColor.fromColor(c);
  if (h.saturation < 0.12) return h.withLightness((h.lightness + 0.12).clamp(0.0, 1.0)).toColor();
  final turn = h.hue >= 70 && h.hue < 200 ? 38.0 : (h.hue >= 200 && h.hue < 300 ? 30.0 : 24.0);
  return h.withHue((h.hue + turn) % 360).withSaturation(h.saturation < 0.45 ? 0.45 : h.saturation).toColor();
}
