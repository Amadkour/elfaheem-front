// D-136: the brand gradient roles are derived from the server's primary family, and every stop keeps the on-hero
// ink (button labels, hero titles) at WCAG AA in both modes, for the built-in palette, the production palette and a
// palette whose primary_light is far too pale for white text.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_contrast.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _prod() =>
    jsonDecode(File('test/visual/fixtures/theme_production.json').readAsStringSync()) as Map<String, dynamic>;

void main() {
  final palettes = <String, Map<String, dynamic>?>{
    'built-in': null,
    'production': _prod(),
    'pale light': {..._prod(), 'primary_light': '#CFEFE3'},
    'server stops': {..._prod(), 'primary_gradient_start': '#7FD8B8', 'primary_gradient_end': '#043024'},
  };

  for (final MapEntry(key: name, value: colors) in palettes.entries) {
    for (final dark in const [false, true]) {
      test('$name ${dark ? 'dark' : 'light'}: every brand stop keeps the on-hero ink at AA', () {
        final t = ThemeConfigProvider(api: ApiClient());
        if (colors != null) t.debugUseColors(colors);
        t.isDark = dark;
        final stops = <Color>[
          ...t.primaryGradient.colors,
          ...t.primaryGradientPressed.colors,
          ...t.heroGradient.colors,
        ];
        for (final s in stops) {
          expect(contrastRatio(t.onHero, s), greaterThanOrEqualTo(kWcagAaText), reason: '$s');
        }
        // the warm glow at its peak, over every hero stop
        final glow = t.heroGlow.colors.first;
        for (final s in t.heroGradient.colors) {
          expect(contrastRatio(t.onHero, Color.alphaBlend(glow, s)), greaterThanOrEqualTo(kWcagAaText));
        }
        // a real gradient, not a flat fill: its two ends are different colours (D-550: different hues, not two shades)
        final g = t.primaryGradient.colors;
        expect(g.length, greaterThanOrEqualTo(3)); // D-550: a blend through three hues
        expect(g.first, isNot(g.last));
        // RTL-aware direction
        expect(t.primaryGradient.begin, isA<AlignmentDirectional>());
      });
    }
  }

  test('the production light stop moves toward primary_light, never to it (white on #34A883 is 2.97:1)', () {
    final t = ThemeConfigProvider(api: ApiClient())..debugUseColors(_prod());
    final lift = t.brandStops(dark: false).first;
    expect(lift, isNot(t.primary));
    expect(contrastRatio(t.onHero, t.primaryLight), lessThan(kWcagAaText));
    expect(contrastRatio(t.onHero, lift), greaterThanOrEqualTo(kWcagAaText));
  });

  testWidgets('a primary Filled button is painted with the gradient, a danger one keeps its colour', (tester) async {
    final t = ThemeConfigProvider(api: ApiClient())..debugUseColors(_prod());
    await tester.pumpWidget(ThemeConfigScope(
      provider: t,
      child: MaterialApp(
        theme: t.materialTheme(dark: false),
        home: Scaffold(
          body: Column(children: [
            FilledButton(key: const Key('brand'), onPressed: () {}, child: const Text('Save')),
            FilledButton(
              key: const Key('danger'),
              style: FilledButton.styleFrom(backgroundColor: t.danger),
              onPressed: () {},
              child: const Text('Delete'),
            ),
            const FilledButton(key: Key('off'), onPressed: null, child: Text('Off')),
          ]),
        ),
      ),
    ));
    Iterable<Ink> inks(String key) =>
        tester.widgetList<Ink>(find.descendant(of: find.byKey(Key(key)), matching: find.byType(Ink)));
    final brand = inks('brand');
    expect(brand, hasLength(1));
    expect((brand.single.decoration! as ShapeDecoration).gradient, isA<LinearGradient>());
    expect(inks('danger'), isEmpty);
    expect(inks('off'), isEmpty);
  });
}
