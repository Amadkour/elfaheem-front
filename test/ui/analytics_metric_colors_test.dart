// The Analytics tabs' three metric colours (progress · attendance · exams, analytics_summary_ui.dart) stay apart in
// every built-in theme preset (../back/services/theme_presets.py), light and dark: a teal or green primary used to
// draw progress and exams in two greens (palette slot 2 = the primary −60°), and an emerald theme used to draw exams
// in a violet borrowed from the `purple` role (D-632).
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_charts.dart';
import 'package:flutter_education_app/features/shared/analytics/analytics_summary_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// appChartPalette for a theme, without a widget tree (same formula: primary · peach (accent1) · sage (accent3) ·
/// gold (accent2) · terracotta (gold −30°), snapped into the mode's lightness band).
List<Color> palette(Color primary, Color accent1, Color accent2, {Color? accent3, required bool dark}) {
  Color vivid(Color x) {
    final h = HSLColor.fromColor(x);
    return h.withSaturation(math.max(h.saturation, 0.55)).toColor();
  }

  final sage = accent3 ??
      ThemeConfigProvider.deriveAccent3(primary: primary, background: const Color(0xFFF1F4F0), ink: const Color(0xFF617068));
  final g = HSLColor.fromColor(accent2);
  final terracotta = g.withHue((g.hue - 30 + 360) % 360).withSaturation(math.max(g.saturation, 0.55)).toColor();
  return [
    for (final x in [primary, vivid(accent1), vivid(sage), accent2, terracotta]) chartSnapLightness(x, dark: dark),
  ];
}

// (primary, accent1, accent2, accent3) of the presets
const presets = {
  'normal': (Color(0xFF24B1B1), Color(0xFFD7C3F1), Color(0xFF7E5CAD), null),
  'blue': (Color(0xFF2F3E9E), Color(0xFFF6E3B4), Color(0xFFC9A227), null),
  'green': (Color(0xFF0F7B5F), Color(0xFFF3E6C4), Color(0xFFD46A4C), null),
  'burgundy_champagne': (Color(0xFF7A1F3D), Color(0xFFF5E6CF), Color(0xFFC8A96A), null),
  'midnight_coral': (Color(0xFF22306B), Color(0xFFFFD9D3), Color(0xFFFF6F61), null),
  'warm_editorial': (Color(0xFF0B6B4F), Color(0xFFFBE2D3), Color(0xFFD46A4C), Color(0xFFE4ECE3)),
};

String hex(Color c) => '#${c.toARGB32().toRadixString(16).substring(2)}';

/// Near the violet of the presets' `purple` role.
bool violet(Color c) => anHueGap(c, const Color(0xFF7C6CE0)) < 30;

void main() {
  test('progress, attendance and exams are apart in hue in every preset, light and dark', () {
    for (final e in presets.entries) {
      for (final dark in [false, true]) {
        final v = e.value;
        final pal = palette(v.$1, v.$2, v.$3, accent3: v.$4, dark: dark);
        final m = anDistinctColors(pal, dark: dark, n: 4);
        expect(m.first, pal.first, reason: 'progress is the primary');
        final metrics = m.take(3).toList();
        // warm_editorial's peach, gold and terracotta sit close in hue; the lightness band still tells them apart
        final minGap = e.key == 'warm_editorial' ? 20 : 40;
        for (var i = 0; i < 3; i++) {
          for (var j = i + 1; j < 3; j++) {
            expect(anHueGap(metrics[i], metrics[j]), greaterThanOrEqualTo(minGap),
                reason: '${e.key} dark=$dark ${metrics.map(hex)}');
          }
        }
        // ignore: avoid_print
        print('${e.key} dark=$dark: ${m.map(hex).join(' · ')}');
      }
    }
  });

  test('an emerald theme draws no violet series (D-632)', () {
    for (final k in ['green', 'warm_editorial']) {
      for (final dark in [false, true]) {
        final v = presets[k]!;
        final pal = palette(v.$1, v.$2, v.$3, accent3: v.$4, dark: dark);
        expect(pal.where(violet), isEmpty, reason: '$k palette ${pal.map(hex)}');
        expect(anDistinctColors(pal, dark: dark, n: 3).where(violet), isEmpty, reason: '$k metrics');
      }
    }
  });

  test('the old pairing (teal primary → a near green) is what the picker avoids', () {
    final n = presets['normal']!;
    final m = anDistinctColors(palette(n.$1, n.$2, n.$3, dark: false), dark: false);
    expect(anHueGap(m[0], m[1]), greaterThanOrEqualTo(45));
    expect(anHueGap(m[0], m[2]), greaterThanOrEqualTo(45));
  });
}
