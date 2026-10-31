// The studio engine's widgets at phone and desktop sizes, ar / en, text × 1.3 (canvas with a selection, toolbar,
// property panel, small-screen notice), plus the real pointer / keyboard path: drag an item, undo restores it,
// and the canvas leaves the keys alone while a text field has focus.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/studio/studio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

StudioController<String> _controller({Set<String> select = const {'b'}}) {
  final c = StudioController<String>(
    adapter: StudioMemoryAdapter<String>([
      const StudioItem(id: 'a', rect: Rect.fromLTWH(100, 100, 200, 100), payload: 'Title'),
      const StudioItem(id: 'b', rect: Rect.fromLTWH(400, 300, 220, 120), payload: 'Logo', resize: StudioResize.aspect),
      const StudioItem(id: 'c', rect: Rect.fromLTWH(650, 520, 260, 60), payload: 'Signature'),
      const StudioItem(id: 'd', rect: Rect.fromLTWH(80, 620, 840, 4), payload: '', resize: StudioResize.horizontal),
    ]),
    page: const StudioPage(1000, 707),
  );
  for (final id in select) {
    c.select(id, additive: true);
  }
  return c;
}

Widget _item(BuildContext context, StudioItem<String> item, bool selected) {
  final s = StudioCanvas.scaleOf(context);
  return StudioBorderBox(
    border: const StudioBorder(style: StudioBorderStyle.dashed, width: 1.5, color: Color(0xFF4B5563), radius: 6),
    background: const Color(0xFFEEF2FF),
    scale: s,
    child: item.payload.isEmpty
        ? null
        : Center(child: FittedBox(fit: BoxFit.scaleDown, child: Text(item.payload, style: TextStyle(fontSize: 22 * s)))),
  );
}

class _Studio extends StatelessWidget {
  const _Studio({required this.controller, this.withPanel = true, this.field});
  final StudioController<String> controller;
  final bool withPanel;
  final FocusNode? field;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 900;
        final canvas = StudioCanvas<String>(controller: controller, itemBuilder: _item);
        return Column(children: [
          Padding(padding: const EdgeInsets.all(8), child: StudioToolbar(controller: controller)),
          if (field != null) TextField(focusNode: field),
          Expanded(
            child: wide && withPanel
                ? Row(children: [
                    Expanded(child: canvas),
                    const SizedBox(width: 300, child: SingleChildScrollView(child: _Panel())),
                  ])
                : canvas,
          ),
        ]);
      });
}

class _Panel extends StatefulWidget {
  const _Panel();

  @override
  State<_Panel> createState() => _PanelState();
}

class _PanelState extends State<_Panel> {
  String font = 'plex';
  double size = 24, opacity = .8;
  FontWeight weight = FontWeight.w500;
  TextAlign align = TextAlign.center;
  Color? ink = const Color(0xFF1C1C24), bg;
  StudioBorder border = const StudioBorder(style: StudioBorderStyle.solid, width: 2, radius: 8);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          StudioPropSection(first: true, title: 'Text', children: [
            StudioFontPicker(
              options: const [
                StudioFontOption(id: 'plex', label: 'IBM Plex Sans Arabic'),
                StudioFontOption(id: 'tajawal', label: 'Tajawal'),
              ],
              value: font,
              onChanged: (v) => setState(() => font = v),
            ),
            StudioStepper(label: 'Size', value: size, min: 6, max: 200, onChanged: (v) => setState(() => size = v)),
            StudioWeightPicker(value: weight, onChanged: (v) => setState(() => weight = v)),
            StudioTextAlignPicker(
              value: align,
              options: const [TextAlign.left, TextAlign.center, TextAlign.right, TextAlign.justify],
              onChanged: (v) => setState(() => align = v),
            ),
            StudioColorField(value: ink, onChanged: (v) => setState(() => ink = v)),
          ]),
          StudioPropSection(title: 'Box', children: [
            StudioBorderEditor(value: border, onChanged: (v) => setState(() => border = v)),
            StudioColorField(label: 'Background', allowNone: true, value: bg, onChanged: (v) => setState(() => bg = v)),
            StudioOpacitySlider(value: opacity, onChanged: (v) => setState(() => opacity = v)),
          ]),
        ]),
      );
}

void main() {
  setUpAll(() => translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>);
  setUp(() => AppConfig.lang = 'ar');

  group('layout', () {
    testWidgets('canvas + toolbar with one item selected (handles)', (tester) async {
      await expectNoLayoutErrors(tester, () => _Studio(controller: _controller()));
    });

    testWidgets('canvas with several items selected, zoomed in', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => _Studio(controller: _controller(select: {'a', 'b', 'c'})..setZoom(2), withPanel: false),
      );
    });

    testWidgets('toolbar alone, with every command enabled', (tester) async {
      await expectNoLayoutErrors(tester, () {
        final c = _controller(select: {'a', 'b', 'c'})..align(StudioAlign.top);
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            StudioToolbar(
              controller: c,
              leading: [StudioToolButton(icon: Icons.text_fields_rounded, label: 'Add text', onPressed: () {})],
              trailing: [StudioToolButton(icon: Icons.save_rounded, label: 'Save', showLabel: true, onPressed: () {})],
            ),
          ]),
        );
      });
    });

    testWidgets('property panel', (tester) async {
      await expectNoLayoutErrors(tester, () => const SingleChildScrollView(child: _Panel()));
    });

    testWidgets('property panel in a narrow side column', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => const Align(
          alignment: AlignmentDirectional.topStart,
          child: SizedBox(width: 240, child: SingleChildScrollView(child: _Panel())),
        ),
      );
    });

    testWidgets('small-screen notice and gate', (tester) async {
      await expectNoLayoutErrors(tester, () => StudioSmallScreenNotice(onContinue: () {}, onBack: () {}));
      await expectNoLayoutErrors(
        tester,
        () => StudioSmallScreenGate(child: _Studio(controller: _controller())),
        act: (t) async {
          final more = find.text(translate('studio_small_continue'));
          if (more.evaluate().isNotEmpty) await t.tap(more);
        },
      );
    });
  });

  group('interaction', () {
    Future<StudioController<String>> pump(WidgetTester tester, {FocusNode? field}) async {
      AppConfig.lang = 'en';
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1400, 900);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final c = _controller(select: const {});
      await tester.pumpWidget(layoutHost(_Studio(controller: c, withPanel: false, field: field), scale: 1));
      await tester.pump();
      return c;
    }

    /// The screen centre of an item, read from the canvas's own layout.
    Offset centreOf(WidgetTester tester, StudioController<String> c, String id) {
      final canvas = find.byType(StudioCanvas<String>);
      final box = tester.getRect(canvas);
      final s = c.scale;
      final page = Size(c.page.width * s, c.page.height * s);
      final origin = box.topLeft + Offset((box.width - page.width) / 2, (box.height - page.height) / 2);
      return origin + c.itemById(id)!.rect.center * s;
    }

    testWidgets('dragging an item moves it as one step and Ctrl+Z restores it', (tester) async {
      final c = await pump(tester);
      const before = Rect.fromLTWH(100, 100, 200, 100);
      expect(c.itemById('a')!.rect, before);

      await tester.dragFrom(centreOf(tester, c, 'a'), const Offset(150, 80));
      await tester.pump();
      final moved = c.itemById('a')!.rect;
      expect(moved, isNot(before));
      expect(moved.left, greaterThan(before.left));
      expect(moved.top, greaterThan(before.top));
      expect(moved.width, closeTo(before.width, 1e-9));
      expect(moved.height, closeTo(before.height, 1e-9));
      expect(c.selection, {'a'});
      expect(c.historyLength, 1);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(c.itemById('a')!.rect, before);

      await tester.tap(find.text('Redo'));
      await tester.pump();
      expect(c.itemById('a')!.rect, moved);

      await tester.tap(find.text('Undo'));
      await tester.pump();
      expect(c.itemById('a')!.rect, before);
    });

    testWidgets('tap selects, arrows nudge, Delete removes, Esc deselects', (tester) async {
      final c = await pump(tester);
      await tester.tapAt(centreOf(tester, c, 'c'));
      await tester.pump();
      expect(c.selection, {'c'});
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(c.itemById('c')!.rect.left, 649);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(c.selection, isEmpty);
      await tester.tapAt(centreOf(tester, c, 'c'));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(c.itemById('c'), isNull);
    });

    testWidgets('keys go to a focused text field, not the canvas', (tester) async {
      final field = FocusNode();
      addTearDown(field.dispose);
      final c = await pump(tester, field: field);
      await tester.tapAt(centreOf(tester, c, 'a'));
      await tester.pump();
      expect(c.selection, {'a'});
      field.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(c.itemById('a')!.rect.left, 100);
      expect(c.itemById('a'), isNotNull);
    });
  });
}
