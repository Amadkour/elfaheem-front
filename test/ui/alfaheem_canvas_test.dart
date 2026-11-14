// ALFAHEEM ONLY (A-007): the page canvas follows the sidebar's colour, stays readable, and its BasePage hook draws
// the lattice behind a transparent Scaffold.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/alfaheem_canvas.dart';
import 'package:flutter_education_app/design/app_contrast.dart';
import 'package:flutter_education_app/design/app_gradients.dart' show BrandLayer;
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final alfaheem = jsonDecode(File('test/visual/fixtures/theme_alfaheem.json').readAsStringSync()) as Map<String, dynamic>;
  final green = jsonDecode(File('test/visual/fixtures/theme_production.json').readAsStringSync()) as Map<String, dynamic>;

  ThemeConfigProvider palette(Map<String, dynamic>? colors, {required bool dark}) {
    final c = ThemeConfigProvider(api: ApiClient());
    if (colors != null) c.debugUseColors(colors);
    return c..isDark = dark;
  }

  for (final (name, colors) in [('alfaheem', alfaheem), ('green', green), ('built-in', null)]) {
    for (final dark in const [false, true]) {
      final mode = dark ? 'dark' : 'light';
      test('$name $mode: the canvas is derived from the sidebar the sidebar really paints', () {
        final c = palette(colors, dark: dark);
        // the copy of BrandLayer's derivation must not drift after a sync
        expect(AlfaheemCanvas.sidebarColour(c, dark: dark), BrandLayer.of(c).sidebar.first);
      });

      test('$name $mode: text keeps AA on the canvas, cards stand off it', () {
        final c = palette(colors, dark: dark);
        final bg = c.background;
        expect(bg.a, 1.0);
        for (final ink in [c.textDark, c.textMedium, c.textLight, c.secondText]) {
          expect(contrastRatio(ink, bg), greaterThanOrEqualTo(4.5), reason: '$ink on $bg');
        }
        // the lattice stays faint: its blend over the canvas is a near neighbour of the canvas
        final dot = Color.alphaBlend(AlfaheemCanvas.dots(c), bg);
        expect(contrastRatio(dot, bg), lessThan(1.6));
        expect(bg, isNot(c.cardBg));
        // a tint of the sidebar's hue, not a grey
        final hue = HSLColor.fromColor(AlfaheemCanvas.sidebarColour(c, dark: dark)).hue;
        final h = HSLColor.fromColor(bg);
        if (HSLColor.fromColor(AlfaheemCanvas.sidebarColour(c, dark: dark)).saturation > 0.1) {
          expect((h.hue - hue).abs() % 360, anyOf(lessThan(12), greaterThan(348)));
        }
      });
    }
  }

  test('switched off, the canvas is the upstream plain background', () {
    final c = palette(alfaheem, dark: false);
    final on = c.background;
    AlfaheemCanvas.enabled = false;
    try {
      expect(c.background.toARGB32(), 0xFFD4FEFD);
    } finally {
      AlfaheemCanvas.enabled = true;
    }
    expect(on, isNot(const Color(0xFFD4FEFD)));
  });

  testWidgets('BasePage paints the canvas behind a transparent Scaffold; an explicit background wins', (tester) async {
    final theme = palette(alfaheem, dark: false);
    Widget app(Widget home) => ThemeConfigScope(
          provider: theme,
          child: MaterialApp(theme: theme.materialTheme(dark: false), home: home),
        );
    await tester.pumpWidget(app(const BasePage(child: SizedBox.expand())));
    expect(tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor, Colors.transparent);
    expect(
        find.descendant(of: find.byType(BasePage), matching: find.byWidgetPredicate((w) => w is ColoredBox && w.color == theme.background)),
        findsOneWidget);
    expect(Theme.of(tester.element(find.byType(Scaffold).first)).scaffoldBackgroundColor, theme.background);

    const own = Color(0xFF123456);
    await tester.pumpWidget(app(const BasePage(background: own, child: SizedBox.expand())));
    expect(tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor, own);
    expect(find.descendant(of: find.byType(BasePage), matching: find.byWidgetPredicate((w) => w is ColoredBox && w.color == theme.background)),
        findsNothing);
  });
}
