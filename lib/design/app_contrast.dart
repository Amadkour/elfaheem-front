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
