// D-360: the shared header, sheet, number field and organic gradient.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_contrast.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

Widget _app(Widget home) {
  final t = ThemeConfigProvider(api: ApiClient());
  return ThemeConfigScope(provider: t, child: MaterialApp(theme: t.materialTheme(dark: false), home: home));
}

Widget _page({int rows = 80}) => Scaffold(
      appBar: const AppHeader(title: 'A long page title that has to fit', subtitle: 'Subtitle line'),
      body: ListView(children: [for (var i = 0; i < rows; i++) SizedBox(height: 48, child: Text('row $i'))]),
    );

double _headerHeight(WidgetTester t) => t.getSize(find.byType(AppHeader)).height;

void main() {
  group('companion colour', () {
    test('green turns toward teal', () {
      final hue = HSLColor.fromColor(AppMesh.companion(const Color(0xFF16A34A))).hue;
      expect(hue, inInclusiveRange(165, 200));
    });

    test('a grey stays a grey', () {
      final s = HSLColor.fromColor(AppMesh.companion(const Color(0xFF808080))).saturation;
      expect(s, lessThan(0.12));
    });
  });

  group('brand blend', () {
    for (final dark in const [false, true]) {
      test('every stop keeps the on-hero ink at AA (${dark ? 'dark' : 'light'})', () {
        final t = ThemeConfigProvider(api: ApiClient());
        t.isDark = dark;
        expect(t.primaryGradient.colors.length, greaterThanOrEqualTo(3)); // D-622: three shades of one hue
        for (final s in t.primaryGradient.colors) {
          expect(contrastRatio(t.onHero, s), greaterThanOrEqualTo(kWcagAaText), reason: '$s');
        }
      });
    }
  });

  group('AppHeader', () {
    testWidgets('collapses on scroll down and opens on scroll up', (t) async {
      await t.pumpWidget(_app(_page()));
      final open = _headerHeight(t);

      await t.drag(find.byType(ListView), const Offset(0, -400));
      await t.pumpAndSettle();
      expect(_headerHeight(t), lessThan(open));

      await t.drag(find.byType(ListView), const Offset(0, 120));
      await t.pumpAndSettle();
      expect(_headerHeight(t), open);
    });

    testWidgets('stays open on a page too short to scroll', (t) async {
      await t.pumpWidget(_app(_page(rows: 3)));
      final open = _headerHeight(t);
      await t.drag(find.byType(ListView), const Offset(0, -400));
      await t.pumpAndSettle();
      expect(_headerHeight(t), open);
    });

    testWidgets('no overflow at any size', (t) async {
      await expectNoLayoutErrors(t, () => Scaffold(
        appBar: AppHeader(
          title: 'A very long page title that keeps going past the edge of a small phone screen',
          subtitle: 'And a long subtitle under it that also keeps going past the edge',
          actions: [IconButton(onPressed: () {}, icon: const Icon(Icons.add))],
        ),
        body: const SizedBox.expand(),
      ));
    });
  });

  group('sheet', () {
    testWidgets('is a side panel on a wide window and a bottom sheet on a phone', (t) async {
      Future<void> open(Size size) async {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        await t.pumpWidget(_app(Builder(builder: (context) => TextButton(onPressed: () => showAppSheet<void>(context, (_) => const Text('body')), child: const Text('open')))));
        await t.tap(find.text('open'));
        await t.pumpAndSettle();
      }

      addTearDown(t.view.reset);
      await open(const Size(1400, 900));
      expect(find.byKey(const ValueKey('app.side_sheet.panel')), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      Navigator.of(t.element(find.text('body'))).pop();
      await t.pumpAndSettle();

      await open(const Size(390, 800));
      expect(find.byKey(const ValueKey('app.side_sheet.panel')), findsNothing);
      expect(find.byType(BottomSheet), findsOneWidget);
    });
  });

  group('AppNumberField', () {
    Widget field(TextEditingController c, {GlobalKey<FormState>? form}) =>
        _app(Scaffold(body: Form(key: form, child: AppNumberField(controller: c, label: 'Seats', min: 1, max: 3))));

    testWidgets('the buttons step and stop at the limits', (t) async {
      final c = TextEditingController(text: '2');
      await t.pumpWidget(field(c));
      await t.tap(find.byIcon(Icons.add_rounded));
      await t.pump();
      expect(c.text, '3');
      await t.tap(find.byIcon(Icons.add_rounded));
      await t.pump();
      expect(c.text, '3');
      await t.tap(find.byIcon(Icons.remove_rounded));
      await t.pump();
      expect(c.text, '2');
    });

    testWidgets('a typed value out of range fails the form, Arabic digits are stored as Latin', (t) async {
      final c = TextEditingController();
      final form = GlobalKey<FormState>();
      await t.pumpWidget(field(c, form: form));
      await t.enterText(find.byType(TextFormField), '٩');
      await t.pump();
      expect(c.text, '9');
      expect(form.currentState!.validate(), isFalse);
      await t.enterText(find.byType(TextFormField), '2');
      await t.pump();
      expect(form.currentState!.validate(), isTrue);
    });

    test('text keeps at most the allowed decimals', () {
      expect(appNumberText(2.5, 2), '2.5');
      expect(appNumberText(2, 2), '2');
      expect(appNumberText(2.4, 0), '2');
    });

    testWidgets('no overflow at any size', (t) async {
      await expectNoLayoutErrors(t, () => Scaffold(body: AppNumberField(controller: TextEditingController(text: '5'), label: 'Seats', min: 0, max: 9)));
    });
  });

  group('focus mode', () {
    setUp(() => AppFocusMode.instance.debugReset());

    test('only applies where there is side chrome', () {
      expect(AppFocusMode.availableAt(390), isFalse);
      expect(AppFocusMode.availableAt(1400), isTrue);
    });
  });
}
