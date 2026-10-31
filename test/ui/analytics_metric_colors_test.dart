// The Analytics tabs' three metric colours (progress · attendance · exams, analytics_summary_ui.dart) stay apart in
// every built-in theme preset (../back/services/theme_presets.py), light and dark: a teal or green primary used to
// draw progress and exams in two greens (palette slot 2 = the primary −60°).
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_charts.dart';
import 'package:flutter_education_app/features/shared/analytics/analytics_summary_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// appChartPalette for a theme, without a widget tree (same formula: primary · accent2 · primary −60° · purple ·
/// primary +90°, snapped into the mode's lightness band).
List<Color> palette(Color primary, Color accent2, Color purple, {required bool dark}) {
  final p = HSLColor.fromColor(primary);
  Color derived(double shift) =>
      p.withHue((p.hue + shift + 360) % 360).withSaturation(math.max(p.saturation, 0.55)).toColor();
  return [for (final x in [primary, accent2, derived(-60), purple, derived(90)]) chartSnapLightness(x, dark: dark)];
}

// (primary, accent2, purple) of the presets
const presets = {
  'normal': (Color(0xFF24B1B1), Color(0xFF7E5CAD), Color(0xFF8B6FFF)),
  'blue': (Color(0xFF2F3E9E), Color(0xFFC9A227), Color(0xFF7C5CFF)),
  'green': (Color(0xFF0F7B5F), Color(0xFFC98A3D), Color(0xFF7C6CE0)),
  'burgundy_champagne': (Color(0xFF7A1F3D), Color(0xFFC8A96A), Color(0xFF8E6CD9)),
  'midnight_coral': (Color(0xFF22306B), Color(0xFFFF6F61), Color(0xFF8B6FFF)),
};

String hex(Color c) => '#${c.toARGB32().toRadixString(16).substring(2)}';

void main() {
  test('progress, attendance and exams are far apart in hue in every preset, light and dark', () {
    for (final e in presets.entries) {
      for (final dark in [false, true]) {
        final pal = palette(e.value.$1, e.value.$2, e.value.$3, dark: dark);
        final m = anDistinctColors(pal, dark: dark, n: 4);
        expect(m.first, pal.first, reason: 'progress is the primary');
        final metrics = m.take(3).toList();
        for (var i = 0; i < 3; i++) {
          for (var j = i + 1; j < 3; j++) {
            expect(anHueGap(metrics[i], metrics[j]), greaterThanOrEqualTo(45),
                reason: '${e.key} dark=$dark ${metrics.map(hex)}');
          }
        }
        // ignore: avoid_print
        print('${e.key} dark=$dark: ${m.map(hex).join(' · ')}');
      }
    }
  });

  test('a theme whose slots are already distinct keeps them (blue: indigo · gold · teal)', () {
    for (final dark in [false, true]) {
      final b = presets['blue']!;
      final pal = palette(b.$1, b.$2, b.$3, dark: dark);
      expect(anDistinctColors(pal, dark: dark), pal.take(3).toList());
    }
  });

  test('the old pairing (teal primary → green slot 2) is what the picker avoids', () {
    final n = presets['normal']!;
    final pal = palette(n.$1, n.$2, n.$3, dark: false);
    expect(anHueGap(pal[0], pal[2]), lessThan(70), reason: 'slot 2 is a near green of the teal primary');
    expect(anDistinctColors(pal, dark: false)[2], isNot(pal[2]));
  });
}
