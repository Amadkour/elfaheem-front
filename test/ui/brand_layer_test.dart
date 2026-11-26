// D-649 / D-650: the brand gradient layer (the green sidebar deepening toward its foot, the primary → lifted-green button (D-863), the
// gold highlight CTA, the forest → emerald hero) is derived from the server's theme roles, and every ink reaches WCAG
// AA where it actually sits, in both modes — for the built-in palette, the production palette and an awkward palette
// (a pale primary_light, a dark text-safe gold). The button's lighter end is placed past the label, so the label is
// checked along its real span in real buttons (short and long labels, full width, Arabic and English).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_buttons.dart';
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

  ThemeConfigProvider theme(Map<String, dynamic>? colors, bool dark) {
    final t = ThemeConfigProvider(api: ApiClient());
    if (colors != null) t.debugUseColors(colors);
    t.isDark = dark;
    return t;
  }

  for (final MapEntry(key: name, value: colors) in palettes.entries) {
    for (final dark in const [false, true]) {
      test('$name ${dark ? 'dark' : 'light'}: every ink keeps AA where it sits', () {
        final t = theme(colors, dark);
        final l = BrandLayer.of(t);
        Color over(Color top, Color s) => Color.alphaBlend(top, s);

        // sidebar (D-650 r3): the green held solid to 60 %, then the blend to the cream end; the on-hero inks on
        // the green part
        expect(BrandLayer.sideStops, [0, 0.6, 1]);
        expect(l.sidebar[0], l.sidebar[1], reason: 'solid green to 60 %');
        // D-863: the foot is a deeper shade of the same green, never accent1
        expect(l.sidebar.last, isNot(t.accent.withValues(alpha: 1)), reason: 'no cream end');
        expect((HSLColor.fromColor(l.sidebar.last).hue - HSLColor.fromColor(l.sidebar.first).hue).abs(), lessThan(1),
            reason: 'one green');
        expect(relativeLuminance(l.sidebar.last), lessThan(relativeLuminance(l.sidebar.first)), reason: 'deeper');
        final side = l.sideSurfaces;
        aa(l.sideInk, [...side, for (final s in side) over(l.sideActiveFill, s)], 'sidebar ink');
        aa(l.sideMuted, side, 'section label');
        aa(l.sideItem, [...side, for (final s in side) over(l.sideHover, s)], 'idle tab');
        aa(l.sideActiveInk, [for (final s in side) over(l.sideActiveFill, s)], 'open tab');
        aa(l.sideIndicator, [for (final s in side) over(l.sideActiveFill, s)], 'gold bar', min: 3);
        // every 4 px down the panel (and the rail's), the inks chosen for that spot keep AA on what they sit on:
        // bare, hovered, on the open item's glass and on a box's glass; the green part keeps the on-hero set, the
        // foot (the person box, the login figures) the dark set
        for (var y = 0.0; y <= 860; y += 4) {
          final k = AppBrandLayer.inkFor(l, [l.sideAt(const Size(248, 860), Offset(24, y))]);
          final on = k.surfaces, glass = [for (final s in on) over(k.glass, s)];
          aa(k.ink, [...on, ...glass, ...k.activeSurfaces], 'title at $y');
          aa(k.item, [...on, for (final s in on) over(k.hover, s)], 'item at $y');
          aa(k.muted, [...on, ...glass], 'muted at $y');
          aa(k.activeInk, k.activeSurfaces, 'open item at $y');
          aa(k.indicator, k.activeSurfaces, 'bar at $y', min: 3);
          if (y <= 0.6 * 860) expect(k.onCream, isFalse, reason: 'the green part keeps the on-hero ink at $y');
          expect(k.onCream, isFalse, reason: 'the all-green panel keeps the on-hero ink at $y (D-863)');
        }
        // the open tab's ink stays the cream (accent1) itself
        expect(l.sideActiveInk, t.accent.withValues(alpha: 1));

        // the primary button at rest, hovered and pressed: solid primary under the label (white at AA); the third
        // stop is the cream the label never touches
        expect(l.buttonInk, t.onHero.withValues(alpha: 1));
        expect(l.button[0], l.button[1], reason: 'solid primary to 60 %');
        for (final g in [l.button, l.buttonHover, l.buttonPressed]) {
          aa(l.buttonInk, BrandLayer.gradientSamples(g[0], g[1], 9), 'white under the label');
        }
        expect(HSLColor.fromColor(l.button.first).hue, inInclusiveRange(140, 180), reason: 'the green stop');
        // D-863: the end is a lift of the same green (no cream)
        expect(l.button.last, isNot(t.accent.withValues(alpha: 1)), reason: 'no cream stop');
        expect(HSLColor.fromColor(l.button.last).hue, inInclusiveRange(140, 180), reason: 'the end stays green');

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

  // The cream ramp starts past a centred label: hold = max(0.6, (width + label) / 2 + gap) — the 60 / 40 rule.
  test('holdFor: short labels leave the last 40 % to the cream, long ones only the end padding', () {
    expect(AppBrandFill.minHold, 0.6);
    expect(AppBrandFill.holdFor(358, 20), AppBrandFill.minHold);
    expect(AppBrandFill.holdFor(358, 300), closeTo(((358 + 300) / 2 + AppBrandFill.gap) / 358, 1e-9));
    expect(AppBrandFill.holdFor(100, 200), 1.0);
  });

  // A full-width button, short and long labels, both languages and modes, at rest / hovered / pressed: every point
  // of the label's glyph span (the icon's start to the text's end) sits on a colour where white keeps 4.5:1.
  final worst = <String, double>{};
  for (final dark in const [false, true]) {
    for (final lang in const ['ar', 'en']) {
      for (final label in lang == 'ar'
          ? const ['دخول', 'إنشاء حساب جديد والمتابعة إلى لوحة التحكم الخاصة بك']
          : const ['Go', 'Create a new account and continue to your dashboard']) {
        for (final width in const [358.0, 420.0]) {
          testWidgets('label span: ${dark ? 'dark' : 'light'} $lang ${label.length} chars in a $width px button',
              (tester) async {
            final prev = AppConfig.lang;
            addTearDown(() => AppConfig.lang = prev);
            AppConfig.lang = lang;
            final t = theme(_prod(), dark);
            final rtl = lang == 'ar';
            await tester.pumpWidget(ThemeConfigScope(
              provider: t,
              child: MaterialApp(
                theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
                home: Directionality(
                  textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                  child: Scaffold(
                    body: Center(
                      child: SizedBox(
                        width: width,
                        child: AppButton(label: label, icon: Icons.login_rounded, expand: true, onPressed: () {}),
                      ),
                    ),
                  ),
                ),
              ),
            ));
            await tester.pump();
            final boxFinder = find.byWidgetPredicate((w) => w is AnimatedContainer && w.decoration is AppBrandFill);
            expect(boxFinder, findsOneWidget);
            final fill = tester.widget<AnimatedContainer>(boxFinder).decoration! as AppBrandFill;
            final box = tester.getRect(boxFinder);
            final stops = fill.gradientFor(box.width).stops!;
            final text = tester.getRect(find.text(label));
            final icon = tester.getRect(find.byIcon(Icons.login_rounded));
            final from = rtl ? icon.right : icon.left, to = rtl ? text.left : text.right;
            final l = BrandLayer.of(t);
            var low = 21.0;
            for (final colors in [l.button, l.buttonHover, l.buttonPressed]) {
              final painted = AppBrandFill(colors: colors, span: fill.span).gradientFor(box.width);
              for (var i = 0; i <= 40; i++) {
                final x = from + (to - from) * i / 40;
                final f = rtl ? (box.right - x) / box.width : (x - box.left) / box.width;
                final r = contrastRatio(l.buttonInk, AppBrandFill.colorAt(painted.colors, stops, f));
                if (r < low) low = r;
              }
            }
            final mode = dark ? 'dark' : 'light';
            if (low < (worst[mode] ?? 21)) worst[mode] = low;
            expect(low, greaterThanOrEqualTo(kWcagAaText), reason: 'white along "$label"');
            // a short label leaves about the last third or more to the cream
            if (label.length < 6) expect(stops[1], lessThan(0.66));
            // KIT_SPEC §5.4: AppButton.primary is the area set's button gradient now (no AppBrandFill); the
            // ink-on-stops contrast it checked is kit_palette_contrast_test's btn_fg on btn_a / btn_b
          }, skip: true);
        }
      }
    }
  }
  tearDownAll(() {
    // ignore: avoid_print
    if (worst.isNotEmpty) print('lowest label contrast: $worst');
  });
}
