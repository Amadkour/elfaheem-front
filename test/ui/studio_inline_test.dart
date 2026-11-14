// The studio engine's direct editing: double click / long-press on a text item opens the in-place editor over it
// (Enter confirms as ONE undo step, Esc cancels, a click outside confirms, Shift+Enter is a new line), the right
// click / long-press context menu (copy, paste, z order, lock), Ctrl+C / Ctrl+V, and the editor, the menu and the
// docked phone panel at 320×640 and 1400×900, ar / en, text × 1.3.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/studio/studio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

StudioController<String> _controller() => StudioController<String>(
      adapter: StudioMemoryAdapter<String>([
        const StudioItem(id: 't', rect: Rect.fromLTWH(100, 100, 400, 80), payload: 'Certificate of completion'),
        const StudioItem(id: 'img', rect: Rect.fromLTWH(600, 300, 200, 200), payload: '', resize: StudioResize.aspect),
        const StudioItem(id: 'n', rect: Rect.fromLTWH(100, 400, 300, 60), payload: 'اسم الطالب'),
      ]),
      page: const StudioPage(1000, 707),
    );

class _Host extends StatelessWidget {
  const _Host({required this.controller, this.onDouble, this.dock});
  final StudioController<String> controller;
  final ValueChanged<String>? onDouble;
  final ValueNotifier<bool>? dock;

  @override
  Widget build(BuildContext context) {
    final canvas = StudioCanvas<String>(
      controller: controller,
      inlineText: (item) => item.payload.isEmpty ? null : item.payload,
      inlineStyle: (context, item, scale) => StudioInlineStyle(
        style: TextStyle(fontSize: 28 * scale, color: const Color(0xFF1C1C24)),
        textAlign: TextAlign.center,
        textDirection: RegExp('[؀-ۿ]').hasMatch(item.payload) ? TextDirection.rtl : TextDirection.ltr,
        multiline: true,
      ),
      onInlineCommit: (item, text) =>
          (controller.adapter as StudioMemoryAdapter<String>).update(item.id, (i) => i.copyWith(payload: text)),
      onItemDoubleTap: onDouble,
      itemBuilder: (context, item, selected) => Center(
        child: Text(item.payload, style: TextStyle(fontSize: 28 * StudioCanvas.scaleOf(context))),
      ),
    );
    final d = dock;
    if (d == null) return canvas;
    return LayoutBuilder(
      builder: (context, box) => Column(children: [
        Expanded(child: canvas),
        StudioDockPanel(
          controller: controller,
          open: d,
          maxHeight: box.maxHeight,
          title: controller.single?.payload ?? 'Page',
          body: const SingleChildScrollView(child: Padding(padding: EdgeInsets.all(16), child: Text('Properties'))),
          footer: const Padding(padding: EdgeInsets.all(8), child: Text('Save')),
        ),
      ]),
    );
  }
}

void main() {
  setUpAll(() => translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>);
  setUp(() => AppConfig.lang = 'en');

  Future<StudioController<String>> pump(WidgetTester tester, {ValueChanged<String>? onDouble}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final c = _controller();
    await tester.pumpWidget(layoutHost(_Host(controller: c, onDouble: onDouble), scale: 1));
    await tester.pump();
    return c;
  }

  Offset centreOf(WidgetTester tester, StudioController<String> c, String id) {
    final box = tester.getRect(find.byType(StudioCanvas<String>));
    final s = c.scale;
    final page = Size(c.page.width * s, c.page.height * s);
    final origin = box.topLeft + Offset((box.width - page.width) / 2, (box.height - page.height) / 2);
    return origin + c.itemById(id)!.rect.center * s;
  }

  Future<void> doubleClick(WidgetTester tester, Offset at) async {
    await tester.tapAt(at, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(at, kind: PointerDeviceKind.mouse);
    await tester.pump();
    await tester.pump();
  }

  final editor = find.byKey(const ValueKey('studio-inline-editor'));

  group('in-place text', () {
    testWidgets('double click edits on the page; Enter confirms as one undo step', (tester) async {
      final c = await pump(tester);
      await doubleClick(tester, centreOf(tester, c, 't'));
      expect(editor, findsOneWidget);
      expect(c.editingId, 't');
      expect(tester.widget<TextField>(editor).textAlign, TextAlign.center);
      // the editor sits over the item
      final r = tester.getRect(editor);
      expect(r.center.dy, closeTo(centreOf(tester, c, 't').dy, 40));

      await tester.enterText(editor, 'Award');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(editor, findsNothing);
      expect(c.itemById('t')!.payload, 'Award');
      expect(c.historyLength, 1);
      expect(c.undoLabel, 'text');
      c.undo();
      expect(c.itemById('t')!.payload, 'Certificate of completion');
    });

    testWidgets('Esc cancels without a change', (tester) async {
      final c = await pump(tester);
      await doubleClick(tester, centreOf(tester, c, 't'));
      await tester.enterText(editor, 'Not this');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(editor, findsNothing);
      expect(c.itemById('t')!.payload, 'Certificate of completion');
      expect(c.historyLength, 0);
      expect(c.editingId, isNull);
    });

    testWidgets('Shift+Enter adds a line; a click outside confirms', (tester) async {
      final c = await pump(tester);
      await doubleClick(tester, centreOf(tester, c, 't'));
      await tester.enterText(editor, 'One');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(editor, findsOneWidget);
      expect(tester.widget<TextField>(editor).controller!.text, 'One\n');
      await tester.tapAt(const Offset(5, 5), kind: PointerDeviceKind.mouse);
      await tester.pump();
      await tester.pump();
      expect(editor, findsNothing);
      expect(c.itemById('t')!.payload, 'One\n');
    });

    testWidgets('long-press on touch edits a text item; Arabic text keeps right to left', (tester) async {
      final c = await pump(tester);
      await tester.longPressAt(centreOf(tester, c, 'n'));
      await tester.pump();
      await tester.pump();
      expect(editor, findsOneWidget);
      expect(tester.widget<TextField>(editor).textDirection, TextDirection.rtl);
    });

    testWidgets('a non-text item keeps onItemDoubleTap; a locked text never opens the editor', (tester) async {
      String? doubled;
      final c = await pump(tester, onDouble: (id) => doubled = id);
      await doubleClick(tester, centreOf(tester, c, 'img'));
      expect(doubled, 'img');
      expect(editor, findsNothing);

      c
        ..select('t')
        ..toggleLock();
      await tester.pump();
      await doubleClick(tester, centreOf(tester, c, 't'));
      expect(editor, findsNothing);
    });
  });

  group('context menu and clipboard', () {
    testWidgets('right click selects and offers copy / paste / z order / lock', (tester) async {
      final c = await pump(tester);
      await tester.tapAt(centreOf(tester, c, 't'), kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(c.selection, {'t'});
      for (final k in ['studio_edit_text', 'studio_copy', 'studio_cut', 'studio_paste', 'studio_duplicate', 'studio_delete', 'studio_bring_front', 'studio_send_back', 'studio_lock']) {
        expect(find.text(translate(k)), findsOneWidget, reason: k);
      }
      await tester.tap(find.text(translate('studio_bring_front')));
      await tester.pumpAndSettle();
      expect(c.items.last.id, 't');

      await tester.tapAt(centreOf(tester, c, 't'), kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text(translate('studio_lock')));
      await tester.pumpAndSettle();
      expect(c.itemById('t')!.locked, isTrue);

      await tester.tapAt(centreOf(tester, c, 't'), kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(find.text(translate('studio_unlock')), findsOneWidget);
      expect(find.text(translate('studio_edit_text')), findsNothing); // locked: no edit
      await tester.tap(find.text(translate('studio_copy')));
      await tester.pumpAndSettle();
      expect(c.canPaste, isTrue);
    });

    testWidgets('Ctrl+C / Ctrl+V paste a copy and select it', (tester) async {
      final c = await pump(tester);
      await tester.tapAt(centreOf(tester, c, 'img'), kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 400));
      expect(c.selection, {'img'});
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(c.items, hasLength(4));
      expect(c.selection.single, isNot('img'));
      expect(c.single!.rect.topLeft, const Offset(610, 310));
    });
  });

  group('layout', () {
    testWidgets('the editor open, ar / en, phone and desktop', (tester) async {
      await expectNoLayoutErrors(tester, () {
        final c = _controller();
        WidgetsBinding.instance.addPostFrameCallback((_) => c.startTextEdit('n'));
        return _Host(controller: c);
      });
    });

    testWidgets('the context menu open', (tester) async {
      late StudioController<String> c;
      await expectNoLayoutErrors(
        tester,
        () => _Host(controller: c = _controller()..select('t')),
        act: (t) async {
          final box = t.getRect(find.byType(StudioCanvas<String>));
          final s = c.scale;
          final page = Size(c.page.width * s, c.page.height * s);
          final origin = box.topLeft + Offset((box.width - page.width) / 2, (box.height - page.height) / 2);
          await t.tapAt(origin + c.itemById('t')!.rect.center * s, kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
        },
      );
    });

    testWidgets('the docked panel open with a selection, folded without', (tester) async {
      await expectNoLayoutErrors(tester, () => _Host(controller: _controller()..select('t'), dock: ValueNotifier(true)));
      await expectNoLayoutErrors(tester, () => _Host(controller: _controller(), dock: ValueNotifier(false)));
    });
  });
}
