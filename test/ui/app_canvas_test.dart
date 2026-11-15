// The page canvas (D-949): tinted from the sidebar's own colour, readable, a faint lattice, painted by BasePage behind
// a transparent Scaffold; raised panels stand off it; the upload footer is drawn once, by UploadQueueHost.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_canvas.dart';
import 'package:flutter_education_app/design/app_contrast.dart';
import 'package:flutter_education_app/design/app_gradients.dart' show BrandLayer;
import 'package:flutter_education_app/features/upload/upload_progress_footer.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final production = jsonDecode(File('test/visual/fixtures/theme_production.json').readAsStringSync()) as Map<String, dynamic>;
  // a second palette: another hue on the same roles
  final teal = {...production, 'primary': '#24B1B1', 'primary_light': '#5FD0D0', 'accent': '#D7C3F1', 'background': '#D4FEFD'};

  ThemeConfigProvider palette(Map<String, dynamic>? colors, {required bool dark}) {
    final c = ThemeConfigProvider(api: ApiClient());
    if (colors != null) c.debugUseColors(colors);
    return c..isDark = dark;
  }

  for (final (name, colors) in [('production', production), ('teal', teal), ('built-in', null)]) {
    for (final dark in const [false, true]) {
      final mode = dark ? 'dark' : 'light';
      test('$name $mode: the sidebar paints the colour the canvas is tinted from', () {
        final c = palette(colors, dark: dark);
        expect(BrandLayer.of(c).sidebar.first, AppCanvas.sidebarColour(c, dark: dark));
      });

      test('$name $mode: text keeps AA on the canvas, the lattice is a whisper, raised panels stand off it', () {
        final c = palette(colors, dark: dark);
        final bg = c.background;
        expect(bg.a, 1.0);
        for (final ink in [c.textDark, c.textMedium, c.textLight, c.secondText]) {
          expect(contrastRatio(ink, bg), greaterThanOrEqualTo(4.5), reason: '$ink on $bg');
        }
        final dot = Color.alphaBlend(AppCanvas.dots(c), bg);
        expect(contrastRatio(dot, bg), lessThan(1.3));
        expect(bg, isNot(c.cardBg));
        // a tint of the sidebar's hue, not a grey
        final side = HSLColor.fromColor(AppCanvas.sidebarColour(c, dark: dark));
        if (side.saturation > 0.1) {
          final d = (HSLColor.fromColor(bg).hue - side.hue).abs() % 360;
          expect(d, anyOf(lessThan(12), greaterThan(348)));
        }
        // a raised panel (profile hero, course header) is a visible step off the canvas, and text still reads on it
        final raised = AppCanvas.raised(c);
        expect(raised.a, 1.0);
        expect(contrastRatio(raised, bg), greaterThan(1.04), reason: '$raised vs $bg');
        expect(contrastRatio(c.textDark, raised), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(c.textMedium, raised), greaterThanOrEqualTo(4.5));
      });
    }
  }

  Widget app(ThemeConfigProvider theme, Widget home) => ThemeConfigScope(
        provider: theme,
        child: MaterialApp(theme: theme.materialTheme(dark: false), home: home),
      );

  testWidgets('BasePage paints the canvas behind a transparent Scaffold; an explicit background wins', (tester) async {
    final theme = palette(production, dark: false);
    await tester.pumpWidget(app(theme, const BasePage(child: SizedBox.expand())));
    expect(tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor, Colors.transparent);
    bool canvas(Widget w) => w is ColoredBox && w.color == theme.background;
    expect(find.descendant(of: find.byType(BasePage), matching: find.byWidgetPredicate(canvas)), findsOneWidget);
    expect(Theme.of(tester.element(find.byType(Scaffold).first)).scaffoldBackgroundColor, theme.background);

    const own = Color(0xFF123456);
    await tester.pumpWidget(app(theme, const BasePage(background: own, child: SizedBox.expand())));
    expect(tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor, own);
    expect(find.descendant(of: find.byType(BasePage), matching: find.byWidgetPredicate(canvas)), findsNothing);
  });

  testWidgets('BasePage no longer draws an upload footer of its own', (tester) async {
    final theme = palette(production, dark: false);
    await tester.pumpWidget(app(theme, const BasePage(child: BasePage(child: SizedBox.expand()))));
    expect(find.byType(UploadProgressFooter), findsNothing);
    expect(find.byType(UploadProgressFooterView), findsNothing);
  });

  testWidgets('UploadQueueHost sits round the Navigator once; an empty queue leaves the pages their whole window', (tester) async {
    final theme = palette(production, dark: false);
    tester.view.padding = const FakeViewPadding(bottom: 20);
    addTearDown(tester.view.resetPadding);
    late EdgeInsets seen;
    await tester.pumpWidget(ThemeConfigScope(
      provider: theme,
      child: MaterialApp(
        theme: theme.materialTheme(dark: false),
        builder: (context, child) => UploadQueueHost(child: child!),
        home: Builder(builder: (context) {
          seen = MediaQuery.paddingOf(context);
          return const BasePage(child: SizedBox.expand());
        }),
      ),
    ));
    expect(find.byType(UploadQueueHost), findsOneWidget);
    expect(find.byType(UploadProgressFooterView), findsNothing);
    expect(seen.bottom, 20 / tester.view.devicePixelRatio);
    expect(tester.getSize(find.byType(Navigator)), tester.view.physicalSize / tester.view.devicePixelRatio);
  });
}
