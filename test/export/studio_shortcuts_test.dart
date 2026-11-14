// The studio keyboard (D-385): the command table, the rules around AppKeyboardSupport (not while typing, not under a
// dialog, only the canvas on screen, nothing on phones), group selection.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_keyboard.dart';
import 'package:flutter_education_app/design/studio/studio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

StudioController<String> _ctl() => StudioController<String>(
      adapter: StudioMemoryAdapter<String>(const [
        StudioItem(id: 'a', rect: Rect.fromLTWH(10, 10, 100, 50), payload: 'A'),
        StudioItem(id: 'b', rect: Rect.fromLTWH(200, 10, 100, 50), payload: 'B'),
        StudioItem(id: 'c', rect: Rect.fromLTWH(400, 10, 100, 50), payload: 'C'),
      ]),
      page: const StudioPage(1000, 707),
    );

Widget _canvas(StudioController<String> c) => StudioCanvas<String>(controller: c, itemBuilder: (_, i, _) => Text(i.payload));

Future<void> _show(WidgetTester t, Widget child, {VoidCallback? onSave}) async {
  AppKeyboardSupport.enabledOverride = true;
  AppConfig.lang = 'en';
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = const Size(1200, 800);
  addTearDown(() {
    AppKeyboardSupport.enabledOverride = null;
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
    AppConfig.lang = 'ar';
  });
  await t.pumpWidget(layoutHost(AppKeyboardSupport(child: StudioKeyboardScope(onSave: onSave, child: child)), scale: 1));
  await t.pump(const Duration(milliseconds: 100));
}

Future<void> _chord(WidgetTester t, LogicalKeyboardKey key, {bool ctrl = false, bool shift = false}) async {
  if (ctrl) await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await t.sendKeyEvent(key);
  if (shift) await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  if (ctrl) await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await t.pump();
}

void main() {
  group('the command table', () {
    StudioCommand? plain(LogicalKeyboardKey k, {bool ctrl = false, bool shift = false, String? ch}) => studioCommandFor(
          k,
          PhysicalKeyboardKey.fn,
          ch,
          primary: ctrl,
          shift: shift,
        );
    test('modifier chords', () {
      expect(plain(LogicalKeyboardKey.keyZ, ctrl: true), StudioCommand.undo);
      expect(plain(LogicalKeyboardKey.keyZ, ctrl: true, shift: true), StudioCommand.redo);
      expect(plain(LogicalKeyboardKey.keyY, ctrl: true), StudioCommand.redo);
      expect(plain(LogicalKeyboardKey.keyS, ctrl: true), StudioCommand.save);
      expect(plain(LogicalKeyboardKey.keyG, ctrl: true), StudioCommand.group);
      expect(plain(LogicalKeyboardKey.keyG, ctrl: true, shift: true), StudioCommand.ungroup);
      expect(plain(LogicalKeyboardKey.equal, ctrl: true), StudioCommand.zoomIn);
      expect(plain(LogicalKeyboardKey.minus, ctrl: true), StudioCommand.zoomOut);
      expect(plain(LogicalKeyboardKey.digit0, ctrl: true), StudioCommand.zoomFit);
    });
    test('plain keys; an Arabic layout through the physical key and ؟', () {
      expect(plain(LogicalKeyboardKey.delete), StudioCommand.delete);
      expect(plain(LogicalKeyboardKey.tab, shift: true), StudioCommand.prevLayer);
      expect(plain(LogicalKeyboardKey.escape), StudioCommand.deselect);
      expect(studioCommandFor(LogicalKeyboardKey.keyZ, PhysicalKeyboardKey.fn, null, primary: true, shift: false, alt: true), isNull);
      expect(studioCommandFor(LogicalKeyboardKey(0x0627), PhysicalKeyboardKey.keyZ, 'ئ', primary: true, shift: false), StudioCommand.undo);
      expect(plain(LogicalKeyboardKey(0x061f), ch: '؟'), StudioCommand.help);
    });
    test('hints: none where the keyboard layer is off (phones)', () {
      expect(studioShortcutHint(StudioCommand.undo), isNull);
      AppKeyboardSupport.enabledOverride = true;
      addTearDown(() => AppKeyboardSupport.enabledOverride = null);
      expect(studioShortcutHint(StudioCommand.undo), 'Ctrl+Z');
      expect(studioTip('Undo', StudioCommand.undo), 'Undo (Ctrl+Z)');
    });
  });

  group('groups', () {
    test('selecting a member selects the group; ungroup dissolves; a copy is its own group', () {
      final c = _ctl();
      c
        ..select('a')
        ..select('b', additive: true)
        ..group();
      expect(c.groupOf('a'), isNotNull);
      c.select('c');
      c.select('a');
      expect(c.selection, {'a', 'b'});
      c.duplicate();
      expect(c.selection.length, 2);
      final copies = c.selection.toList();
      expect(c.groupOf(copies.first), c.groupOf(copies.last));
      expect(c.groupOf(copies.first), isNot(c.groupOf('a')));
      c.select('a');
      c.ungroup();
      expect(c.groupOf('a'), isNull);
      c.select('b');
      expect(c.selection, {'b'});
    });
  });

  group('on the page', () {
    testWidgets('chords and plain keys work, focus on the canvas or nowhere; Ctrl+S calls the host', (t) async {
      final c = _ctl();
      var saves = 0;
      await _show(t, Row(children: [Expanded(child: _canvas(c))]), onSave: () => saves++);
      c.select('a');
      await _chord(t, LogicalKeyboardKey.arrowRight);
      expect(c.itemById('a')!.rect.left, 11);
      await _chord(t, LogicalKeyboardKey.arrowRight, shift: true);
      expect(c.itemById('a')!.rect.left, 21);
      await _chord(t, LogicalKeyboardKey.keyZ, ctrl: true);
      expect(c.itemById('a')!.rect.left, 10);
      await _chord(t, LogicalKeyboardKey.keyS, ctrl: true);
      expect(saves, 1);
      await _chord(t, LogicalKeyboardKey.equal, ctrl: true);
      expect(c.fitted, isFalse);
      await _chord(t, LogicalKeyboardKey.digit0, ctrl: true);
      expect(c.fitted, isTrue);
      await _chord(t, LogicalKeyboardKey.tab);
      expect(c.selection, {'c'}); // top first, wrapping past the bottom
      await _chord(t, LogicalKeyboardKey.escape);
      expect(c.selection, isEmpty);
      c.select('c');
      await _chord(t, LogicalKeyboardKey.delete);
      expect(c.itemById('c'), isNull);
    });

    testWidgets('never while typing: text fields keep every key', (t) async {
      final c = _ctl();
      final text = TextEditingController(text: 'x');
      addTearDown(text.dispose);
      await _show(t, Row(children: [Expanded(child: _canvas(c)), SizedBox(width: 200, child: TextField(controller: text))]));
      c.select('a');
      await t.showKeyboard(find.byType(TextField));
      await t.pump();
      await _chord(t, LogicalKeyboardKey.delete);
      expect(c.itemById('a'), isNotNull);
      await _chord(t, LogicalKeyboardKey.keyA, ctrl: true);
      expect(c.selection, {'a'});
    });

    testWidgets('under a dialog nothing fires; "?" opens the sheet', (t) async {
      final c = _ctl();
      await _show(t, Row(children: [Expanded(child: _canvas(c))]));
      c.select('a');
      final ctx = t.element(find.byType(StudioCanvas<String>));
      showDialog<void>(context: ctx, builder: (_) => const AlertDialog(content: Text('hello')));
      await t.pumpAndSettle();
      await _chord(t, LogicalKeyboardKey.delete);
      expect(c.itemById('a'), isNotNull);
      Navigator.of(ctx, rootNavigator: true).pop();
      await t.pumpAndSettle();
      await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.slash, character: '?');
      await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await t.pumpAndSettle();
      expect(find.text('Keyboard shortcuts'), findsOneWidget);
    });

    testWidgets('of two canvases in an IndexedStack only the one on screen reacts', (t) async {
      final ar = _ctl(), en = _ctl();
      await _show(t, IndexedStack(index: 1, children: [_canvas(ar), _canvas(en)]));
      ar.select('a');
      en.select('a');
      await _chord(t, LogicalKeyboardKey.delete);
      expect(ar.itemById('a'), isNotNull);
      expect(en.itemById('a'), isNull);
    });
  });

  testWidgets('the shortcut sheet has no overflow', (t) async {
    AppKeyboardSupport.enabledOverride = true;
    addTearDown(() => AppKeyboardSupport.enabledOverride = null);
    await expectNoLayoutErrors(t, () => const StudioShortcutsPanel());
  });
}
