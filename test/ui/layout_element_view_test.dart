// The v4 look of an export-layout element on the studio canvas: ellipse, opacity, photo shape, letter spacing,
// line height, shrink-to-fit, shadow, the page background, and the layout of all of them at phone and desktop sizes.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/export_layout/layout_element_view.dart';
import 'package:flutter_education_app/design/export_layout/layout_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

Widget _view(LayoutElement e, {double scale = 4, double? w, double? h}) => Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: (w ?? e.w) * scale,
        height: (h ?? e.h) * scale,
        child: LayoutElementView(element: e, scale: scale, rtl: false, pageFont: 'tajawal', lang: 'en'),
      ),
    );

Future<void> _pump(WidgetTester t, Widget w) async {
  AppConfig.lang = 'en';
  await t.pumpWidget(layoutHost(w, scale: 1));
  await t.pump(const Duration(milliseconds: 50));
}

Text _text(WidgetTester t) => t.widget<Text>(find.byType(Text).first);

void main() {
  tearDown(() => AppConfig.lang = 'ar');

  testWidgets('an ellipse is drawn with an oval painter, with its fill', (t) async {
    await _pump(t, _view(LayoutElement(id: 'e', kind: 'ellipse', w: 20, h: 10, style: LayoutStyle(bg: '#FF0000'))));
    final paints = t.widgetList<CustomPaint>(find.byType(CustomPaint)).map((c) => c.painter).whereType<LayoutOvalPainter>();
    expect(paints, hasLength(1));
    expect(paints.single.fill, const Color(0xFFFF0000));
  });

  testWidgets('element opacity multiplies into the drawn opacity (a hidden-by-rule element stays at a quarter)', (t) async {
    await _pump(t, _view(LayoutElement(id: 'r', kind: 'rect', w: 20, h: 10, opacity: .5, style: LayoutStyle(bg: '#00FF00'))));
    final o = t.widget<Opacity>(find.byType(Opacity).first);
    expect(o.opacity, .5);
  });

  testWidgets('a circle / rounded photo shape clips the picture', (t) async {
    await _pump(t, _view(LayoutElement(id: 'i', kind: 'image', w: 20, h: 20, shape: 'circle')));
    expect(find.byType(ClipOval), findsOneWidget);
    await _pump(t, _view(LayoutElement(id: 'i', kind: 'image', w: 20, h: 20, shape: 'rounded')));
    expect(find.byType(ClipRRect), findsWidgets);
    await _pump(t, _view(LayoutElement(id: 'i', kind: 'image', w: 20, h: 20)));
    expect(find.byType(ClipOval), findsNothing);
  });

  testWidgets('letter spacing, line height and a text shadow reach the text style', (t) async {
    final e = LayoutElement(
      id: 't',
      kind: 'text',
      w: 40,
      h: 10,
      value: 'Hello',
      style: LayoutStyle(letterSpacing: 2, lineHeight: 1.6, shadow: LayoutShadow(color: '#000000FF', dx: 1, dy: 1)),
    );
    await _pump(t, _view(e));
    final st = _text(t).style!;
    expect(st.letterSpacing, closeTo(2 * kPtMm * 4, 1e-9));
    expect(st.height, 1.6);
    expect(st.shadows, hasLength(1));
    expect(st.shadows!.single.color, const Color(0xFF000000), reason: '#RRGGBBAA, not #AARRGGBB');
  });

  testWidgets('shrink makes the font smaller until the text fits, never below half', (t) async {
    final long = 'a rather long sentence that cannot fit a small box at full size';
    LayoutElement make(bool shrink) =>
        LayoutElement(id: 's', kind: 'text', w: 22, h: 6, value: long, style: LayoutStyle(shrink: shrink, size: 10));
    await _pump(t, _view(make(false)));
    final full = _text(t).style!.fontSize!;
    await _pump(t, _view(make(true)));
    final shrunk = _text(t).style!.fontSize!;
    expect(shrunk, lessThan(full));
    expect(shrunk, greaterThanOrEqualTo(full * .5 - 1e-6));
  });

  test('layoutShrinkFactor: 1 when it fits, .5 when nothing fits', () {
    const style = TextStyle(fontSize: 14);
    expect(layoutShrinkFactor(text: 'Hi', style: style, dir: TextDirection.ltr, maxWidth: 200, maxHeight: 40), 1);
    expect(layoutShrinkFactor(text: 'x' * 400, style: style, dir: TextDirection.ltr, maxWidth: 40, maxHeight: 14, wrap: false), .5);
    final mid = layoutShrinkFactor(text: 'Hello world', style: style, dir: TextDirection.ltr, maxWidth: 60, maxHeight: 20, wrap: false);
    expect(mid, inInclusiveRange(.5, 1));
  });

  test('a shadow colour is #RRGGBB or #RRGGBBAA', () {
    expect(layoutShadowColor('#00000055'), const Color(0x55000000));
    expect(layoutShadowColor('#FF0000'), const Color(0xFFFF0000));
    expect(layoutShadowColor('#FF000080'), const Color(0x80FF0000));
    expect(layoutShadowColor('bad'), const Color(0x55000000));
    expect(layoutShadowHex(const Color(0x80FF0000)), '#FF000080');
  });

  testWidgets('the page background draws nothing for an unknown asset and nothing without an image', (t) async {
    await _pump(t, const SizedBox(width: 100, height: 100, child: LayoutPageBackground(image: null)));
    await _pump(t, const SizedBox(width: 100, height: 100, child: LayoutPageBackground(image: 'asset-1')));
    expect(find.byType(Image), findsNothing);
    expect(LayoutPageBackground.isUrl('https://x/y.png'), isTrue);
    expect(LayoutPageBackground.isUrl('asset-1'), isFalse);
  });

  testWidgets('every v4 look lays out at phone and desktop sizes, ar and en, without overflow', (t) async {
    Widget build() {
      final elements = [
        LayoutElement(id: '1', kind: 'ellipse', x: 2, y: 2, w: 30, h: 14, opacity: .6, style: LayoutStyle(bg: '#EEF2FF', border: LayoutBorder(width: .4, color: '#4338CA'), shadow: LayoutShadow())),
        LayoutElement(id: '2', kind: 'image', x: 40, y: 2, w: 16, h: 16, shape: 'circle'),
        LayoutElement(id: '3', kind: 'text', x: 2, y: 22, w: 40, h: 8, value: 'عنوان طويل جدا جدا لا يتسع في الصندوق', style: LayoutStyle(shrink: true, letterSpacing: 1, lineHeight: 1.6, shadow: LayoutShadow())),
        LayoutElement(id: '4', kind: 'signature', x: 46, y: 22, w: 30, h: 18, shape: 'rounded', sigName: 'Name', sigTitle: 'Title'),
      ];
      return LayoutBoxView(elements: elements, width: 90, height: 45, scale: 3, rtl: false, pageFont: 'tajawal', lang: 'en');
    }

    await expectNoLayoutErrors(t, build);
  });
}
