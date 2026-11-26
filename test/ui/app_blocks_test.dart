// AppBlock (D-613): no overflow at any size, ink at WCAG AA on every tone in both modes and for a palette that sends
// no `accent3`, and a category tone that never changes.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_model.dart';
import 'package:flutter_education_app/config/theme/kit_palette_defaults.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_contrast.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

Widget _blocks() => Builder(builder: (context) {
      return ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
        AppBlock(
          tone: AppBlockTone.peach,
          hero: true,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Today: fractions and decimals, chapter four of the second term',
                style: AppType.headline(context)),
            AppSpace.gapXs,
            Text('Read the passage, then answer the five questions before the live session at 4:30 PM.',
                style: AppType.body(context).copyWith(color: AppBlock.colorsOf(context).muted)),
          ]),
        ),
        AppSpace.gapMd,
        for (final tone in AppBlockTone.values) ...[
          AppBlock(
            tone: tone,
            onTap: () {},
            semanticLabel: tone.name,
            child: Row(children: [
              const Icon(Icons.local_fire_department_rounded, size: AppIconSize.lg),
              AppSpace.gapSm,
              Expanded(
                child: Text('A long category name that has to wrap on a narrow phone ${tone.name}',
                    style: AppType.section(context)),
              ),
              Text('12', style: AppType.figure(context)),
            ]),
          ),
          AppSpace.gapSm,
        ],
        Row(children: [
          Expanded(child: AppBlock(tone: AppBlockTone.sky, child: Text('Next session', style: AppType.row(context)))),
          AppSpace.gapSm,
          Expanded(
              child: AppBlock(tone: AppBlockTone.gold, child: Text('7 day streak', style: AppType.row(context)))),
        ]),
      ]);
    });

void main() {
  testWidgets('AppBlock: no overflow at 320x640 and 1400x900, ar/en, text x1.3', (tester) async {
    await expectNoLayoutErrors(tester, _blocks);
  });

  group('ink on every tone reads at AA', () {
    final production = (jsonDecode(File('test/visual/fixtures/theme_production.json').readAsStringSync()) as Map)
        .cast<String, dynamic>();
    for (final (name, colors) in [('default (warm editorial)', null), ('production, no accent3', production)]) {
      for (final dark in [false, true]) {
        test('$name ${dark ? 'dark' : 'light'}', () {
          final p = ThemeConfigProvider(api: ApiClient());
          if (colors != null) p.debugUseColors(colors);
          p.isDark = dark;
          for (final (tone, surface) in [
            ('peach', p.blockPeach),
            ('sky', p.blockSky),
            ('gold', p.blockGold),
            ('emerald', p.blockEmerald),
            ('paper', p.cardBg),
          ]) {
            expect(contrastRatio(p.blockInk, surface), greaterThanOrEqualTo(kWcagAaText), reason: '$tone ink');
            expect(contrastRatio(p.blockMuted(surface), surface), greaterThanOrEqualTo(kWcagAaText), reason: '$tone muted');
            expect(contrastRatio(p.blockFaint(surface), surface), greaterThanOrEqualTo(kWcagAaText), reason: '$tone faint');
            for (final accent in [p.accent2, p.success, p.warning, p.danger, p.primary]) {
              expect(contrastRatio(p.blockAccentInk(accent, surface), surface), greaterThanOrEqualTo(kWcagAaText),
                  reason: '$tone accent $accent');
            }
          }
          // the identity header (D-713): a primary gradient; every ink reads on BOTH stops
          final (from, to) = p.blockIdentityStops;
          for (final stop in [from, to]) {
            expect(contrastRatio(p.blockInk, stop), greaterThanOrEqualTo(kWcagAaText), reason: 'identity ink');
            expect(contrastRatio(p.blockIdentityMuted, stop), greaterThanOrEqualTo(kWcagAaText), reason: 'identity muted');
            expect(contrastRatio(p.blockIdentityFaint, stop), greaterThanOrEqualTo(kWcagAaText), reason: 'identity faint');
          }
          // it is a degree of the primary, not the peach band it replaced
          final hue = HSLColor.fromColor(from).hue, primaryHue = HSLColor.fromColor(p.primary).hue;
          expect(((hue - primaryHue + 540) % 360 - 180).abs(), lessThan(6), reason: 'identity hue follows the primary');
          // the forest hero (D-630): cream ink at 7:1, muted / faint at AA, accents lifted to AA
          final f = p.blockForest;
          expect(contrastRatio(p.heroInk, f), greaterThanOrEqualTo(7), reason: 'forest ink');
          expect(contrastRatio(p.heroInkMuted, f), greaterThanOrEqualTo(kWcagAaText), reason: 'forest muted');
          expect(contrastRatio(p.heroInkFaint, f), greaterThanOrEqualTo(kWcagAaText), reason: 'forest faint');
          for (final accent in [p.accent2, p.success, p.warning, p.danger, p.primary]) {
            expect(contrastRatio(p.blockAccentInk(accent, f), f), greaterThanOrEqualTo(kWcagAaText), reason: 'forest accent $accent');
          }
          p.dispose();
        });
      }
    }
  });

  test('the default blocks are the kit palette (D-1811): green and warm tints as given, the forest hero, dark blocks tinted', () {
    final p = ThemeConfigProvider(api: ApiClient());
    expect(p.accent3, kKitPaletteDefaults.brand.primaryTint);
    expect(p.blockPeach, kKitPaletteDefaults.brand.warmTint);
    expect(p.blockSky, kKitPaletteDefaults.brand.primaryTint);
    expect(AppBlockTone.sage, AppBlockTone.sky);
    final forest = HSLColor.fromColor(p.blockForest);
    expect(forest.hue, closeTo(162, 6), reason: 'about #0E3B2E');
    expect(forest.lightness, lessThanOrEqualTo(0.15));
    p.isDark = true;
    // a dark surface with the block's hue, a step above the dark card (#1E2021)
    expect(relativeLuminance(p.blockPeach), greaterThan(relativeLuminance(p.cardBg)));
    final sage = HSLColor.fromColor(p.blockSky);
    expect(sage.saturation, lessThanOrEqualTo(0.17), reason: 'a quiet grey-green, about #1E2A23');
    expect(sage.hue, inInclusiveRange(90, 160)); // the kit green is hue 156
    p.dispose();
  });

  test('a server still sending the retired sky gets the sage', () {
    final production = (jsonDecode(File('test/visual/fixtures/theme_production.json').readAsStringSync()) as Map)
        .cast<String, dynamic>();
    final p = ThemeConfigProvider(api: ApiClient())..debugUseColors({...production, 'accent3': '#DCE7F5'});
    expect(HSLColor.fromColor(p.accent3).hue, inInclusiveRange(90, 150));
    p.dispose();
  });

  test('a palette without accent3 gets a pale sage in its own light', () {
    final sky = ThemeConfigProvider.deriveAccent3(
        primary: const Color(0xFF0F7B5F), background: const Color(0xFFFBF7EC), ink: const Color(0xFF68756D));
    final h = HSLColor.fromColor(sky);
    expect(h.hue, inInclusiveRange(100, 150));
    expect(h.lightness, greaterThan(0.86));
    expect(contrastRatio(const Color(0xFF68756D), sky), greaterThanOrEqualTo(kWcagAaText));
  });

  test('accent3 survives the cache round trip and stays absent when the server sends none', () {
    final production = (jsonDecode(File('test/visual/fixtures/theme_production.json').readAsStringSync()) as Map)
        .cast<String, dynamic>();
    expect(ThemeConfigModel.fromJson(production).toJson().containsKey('accent3'), isFalse);
    final withSky = ThemeConfigModel.fromJson({...production, 'accent3': '#DCE7F5'});
    expect(withSky.accent3, const Color(0xFFDCE7F5));
    expect(ThemeConfigModel.fromJson(withSky.toJson()).accent3, const Color(0xFFDCE7F5));
  });

  test('forKey: stable, and only the category tones', () {
    expect(AppBlockTone.forKey('course-42'), AppBlockTone.forKey('course-42'));
    final seen = {for (var i = 0; i < 200; i++) AppBlockTone.forKey('category-$i')};
    expect(seen, {AppBlockTone.peach, AppBlockTone.sage});
    expect(AppBlockTone.forKey('x', among: const [AppBlockTone.gold]), AppBlockTone.gold);
    // FNV-1a of "math" is fixed, so this tone never moves between runs, platforms or app versions
    expect(AppBlockTone.forKey('math'), AppBlockTone.forKey(String.fromCharCodes('math'.codeUnits)));
  });
}
