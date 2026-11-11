// D-649: the brand gradient layer (the green sidebar, the gradient primary button, the gold highlight CTA, the
// forest → emerald hero) is derived from the server's theme roles, and every ink reaches WCAG AA on BOTH ends of the
// gradient it sits on, in both modes — for the built-in palette, the production palette and an awkward palette
// (a pale primary_light, a dark text-safe gold).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_contrast.dart';
import 'package:flutter_education_app/design/app_gradients.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _prod() =>
    jsonDecode(File('test/visual/fixtures/theme_production.json').readAsStringSync()) as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final palettes = <String, Map<String, dynamic>?>{
    'built-in': null,
    'production': _prod(),
    'awkward': {..._prod(), 'primary_light': '#CFEFE3', 'accent2': '#7A5512', 'primary': '#2FA37E'},
  };

  void aa(Color ink, Iterable<Color> surfaces, String what, {double min = kWcagAaText}) {
    for (final s in surfaces) {
      expect(contrastRatio(ink, s), greaterThanOrEqualTo(min), reason: '$what on $s');
    }
  }

  for (final MapEntry(key: name, value: colors) in palettes.entries) {
    for (final dark in const [false, true]) {
      test('$name ${dark ? 'dark' : 'light'}: every ink keeps AA on both ends of its gradient', () {
        final t = ThemeConfigProvider(api: ApiClient());
        if (colors != null) t.debugUseColors(colors);
        t.isDark = dark;
        final l = BrandLayer.of(t);

        // sidebar: two different shades, the inks AA on both, the active ink AA on the glass over both
        expect(l.sidebar.first, isNot(l.sidebar.last));
        aa(l.sideInk, l.sidebar, 'sidebar ink');
        aa(l.sideMuted, l.sidebar, 'section label');
        aa(l.sideItem, [...l.sidebar, for (final s in l.sidebar) Color.alphaBlend(l.sideHover, s)], 'idle tab');
        aa(l.sideActiveInk, [for (final s in l.sidebar) Color.alphaBlend(l.sideActiveFill, s)], 'open tab');
        aa(l.sideIndicator, [for (final s in l.sidebar) Color.alphaBlend(l.sideActiveFill, s)], 'gold bar', min: 3);

        // the primary button at rest, hovered and pressed
        aa(l.buttonInk, [...l.button, ...l.buttonHover, ...l.buttonPressed], 'button label');
        // the gold CTA: a DARK ink (white on gold fails)
        aa(l.goldInk, [...l.gold, ...l.goldHover, ...l.goldPressed], 'gold label');
        expect(relativeLuminance(l.goldInk), lessThan(relativeLuminance(l.gold.first)));

        // the hero: cream at 7:1 on both ends, muted / faint at AA with the gold glow over either end
        expect(l.forest.first, t.blockForest);
        aa(t.heroInk, l.forest, 'hero title', min: 7);
        final lit = [...l.forest, for (final s in l.forest) Color.alphaBlend(l.forestGlow, s)];
        aa(l.forestMuted, lit, 'hero muted');
        aa(l.forestFaint, lit, 'hero faint');
        aa(t.onHero.withValues(alpha: 1), lit, 'hero on-hero ink');
      });
    }
  }
}
