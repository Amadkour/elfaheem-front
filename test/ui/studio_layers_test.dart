// The engine's layers panel (select, lock, hide, reorder, rename), the rotate knob on the canvas and the render
// budget of a page with 150 items (a drag rebuilds only the item that moves).
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/studio/studio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

class _Named extends StudioMemoryAdapter<String> implements StudioLayersAdapter {
  _Named(List<StudioItem<String>> items) : super(items);
  final names = <String, String>{};

  @override
  bool get canRename => true;

  @override
  void rename(String id, String name) => names[id] = name;
}

StudioController<String> _ctl(StudioAdapter<String> a) => StudioController<String>(adapter: a, page: const StudioPage(1000, 707));

List<StudioItem<String>> _three() => const [
      StudioItem(id: 'a', rect: Rect.fromLTWH(10, 10, 100, 50), payload: 'Alpha'),
      StudioItem(id: 'b', rect: Rect.fromLTWH(200, 10, 100, 50), payload: 'Bravo'),
      StudioItem(id: 'c', rect: Rect.fromLTWH(400, 10, 100, 50), payload: 'Charlie'),
    ];

Widget _panel(StudioController<String> c) => Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 340,
        height: 400,
        child: StudioLayersPanel<String>(controller: c, nameOf: (i) => i.payload, iconOf: (_) => Icons.crop_square_rounded),
      ),
    );

Future<void> _show(WidgetTester t, Widget w) async {
  AppConfig.lang = 'en';
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = const Size(900, 700);
  addTearDown(() {
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
    AppConfig.lang = 'ar';
  });
  await t.pumpWidget(layoutHost(w, scale: 1));
  await t.pump(const Duration(milliseconds: 100));
}

void main() {
  group('layers panel', () {
    testWidgets('lists the top-most layer first and selects on tap, ctrl adds, shift takes the range', (t) async {
      final c = _ctl(StudioMemoryAdapter<String>(_three()));
      await _show(t, _panel(c));
      final ys = ['Charlie', 'Bravo', 'Alpha'].map((n) => t.getTopLeft(find.text(n)).dy).toList();
      expect(ys[0], lessThan(ys[1]));
      expect(ys[1], lessThan(ys[2]));

      await t.tap(find.text('Bravo'));
      await t.pump();
      expect(c.selection, {'b'});

      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.tap(find.text('Alpha'));
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await t.pump();
      expect(c.selection, {'a', 'b'});

      await t.tap(find.text('Charlie'));
      await t.pump();
      await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await t.tap(find.text('Alpha'));
      await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await t.pump();
      expect(c.selection, {'a', 'b', 'c'});
    });

    testWidgets('the lock and the eye toggle a layer, each one undo step', (t) async {
      final c = _ctl(StudioMemoryAdapter<String>(_three()));
      await _show(t, _panel(c));
      await t.tap(find.byIcon(Icons.lock_open_rounded).first); // the top row: Charlie
      await t.pump();
      expect(c.itemById('c')!.locked, isTrue);
      expect(c.historyLength, 1);
      await t.tap(find.byIcon(Icons.visibility_outlined).first);
      await t.pump();
      expect(c.itemById('c')!.visible, isFalse);
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
      c.undo();
      c.undo();
      await t.pump();
      expect(c.itemById('c')!.locked, isFalse);
      expect(c.itemById('c')!.visible, isTrue);
    });

    testWidgets('dragging the handle reorders the layers in one undo step', (t) async {
      final c = _ctl(StudioMemoryAdapter<String>(_three()));
      await _show(t, _panel(c));
      final from = t.getCenter(find.byIcon(Icons.drag_indicator_rounded).first); // Charlie, the top
      final g = await t.startGesture(from);
      await t.pump(const Duration(milliseconds: 50));
      await g.moveBy(const Offset(0, 20));
      await t.pump(const Duration(milliseconds: 50));
      await g.moveBy(const Offset(0, 160));
      await t.pump(const Duration(milliseconds: 50));
      await g.up();
      await t.pumpAndSettle();
      expect([for (final i in c.items) i.id], isNot(['a', 'b', 'c']));
      expect(c.historyLength, 1);
      c.undo();
      expect([for (final i in c.items) i.id], ['a', 'b', 'c']);
    });

    testWidgets('a double tap renames the layer when the adapter can', (t) async {
      final a = _Named(_three());
      final c = _ctl(a);
      await _show(t, _panel(c));
      await t.tap(find.text('Bravo'));
      await t.pump(const Duration(milliseconds: 40));
      await t.tap(find.text('Bravo'));
      await t.pump();
      expect(find.byKey(const ValueKey('layer-rename')), findsOneWidget);
      await t.enterText(find.byKey(const ValueKey('layer-rename')), 'Heading');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pump();
      expect(a.names['b'], 'Heading');
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('a host without the optional hooks still gets select and lock, no eye, no rename', (t) async {
      final c = _ctl(_Plain(_three()));
      await _show(t, _panel(c));
      expect(find.byIcon(Icons.visibility_outlined), findsNothing);
      expect(find.byIcon(Icons.lock_open_rounded), findsNothing);
      await t.tap(find.text('Alpha'));
      await t.pump();
      expect(c.selection, {'a'});
    });

    testWidgets('lays out at phone and desktop sizes, ar and en, text x1.3', (t) async {
      final many = [for (var i = 0; i < 12; i++) StudioItem<String>(id: 'i$i', rect: Rect.fromLTWH(i * 10.0, 10, 50, 50), payload: 'A fairly long layer name number $i')];
      await expectNoLayoutErrors(t, () => SizedBox.expand(child: StudioLayersPanel<String>(controller: _ctl(StudioMemoryAdapter<String>(many)), nameOf: (i) => i.payload, iconOf: (_) => Icons.crop_square_rounded)));
    });
  });

  group('canvas', () {
    Future<(StudioController<String>, Rect)> mount(WidgetTester t, StudioAdapter<String> a, {void Function(String id)? built}) async {
      final c = _ctl(a);
      await _show(
        t,
        StudioCanvas<String>(
          controller: c,
          itemBuilder: (context, item, selected) {
            built?.call(item.id);
            return const ColoredBox(color: Color(0xFFCBD5E1));
          },
        ),
      );
      return (c, t.getRect(find.byType(StudioCanvas<String>)));
    }

    /// Screen rect of an item: the page is centred in the canvas at the fitted scale.
    Rect screen(StudioController<String> c, Rect canvas, Rect r) {
      final s = c.scale;
      final origin = canvas.center - Offset(c.page.width * s / 2, c.page.height * s / 2);
      return Rect.fromLTWH(origin.dx + r.left * s, origin.dy + r.top * s, r.width * s, r.height * s);
    }

    testWidgets('the rotate knob turns the selected item, shift snaps to 15 degrees, one undo step', (t) async {
      final (c, canvas) = await mount(t, StudioMemoryAdapter<String>([const StudioItem(id: 'a', rect: Rect.fromLTWH(400, 300, 200, 100), payload: 'A')]));
      c.select('a');
      await t.pump();
      final r = screen(c, canvas, c.itemById('a')!.rect);
      final knob = studioRotateHandle(r, 0);
      final g = await t.createGesture(kind: PointerDeviceKind.mouse);
      await g.addPointer(location: knob);
      await g.down(knob);
      await t.pump();
      // a quarter turn clockwise: from straight above the centre to straight right of it
      final target = r.center + Offset(r.height + 80, 0);
      await g.moveTo(knob + const Offset(40, 0));
      await t.pump();
      await g.moveTo(target);
      await t.pump();
      expect(c.rotating, isTrue);
      expect(c.rotationOf('a'), closeTo(90, 1));
      await g.up();
      await t.pump();
      expect(c.itemById('a')!.rotation, closeTo(90, 1));
      expect(c.historyLength, 1);
      c.undo();
      expect(c.itemById('a')!.rotation, 0);
    });

    testWidgets('a turned item is resized from its handles (the handle follows the turn)', (t) async {
      final (c, canvas) = await mount(
        t,
        StudioMemoryAdapter<String>([const StudioItem(id: 'a', rect: Rect.fromLTWH(400, 300, 200, 100), payload: 'A', rotation: 90)]),
      );
      c.select('a');
      await t.pump();
      expect(c.resizable, isNotNull);
      final r = screen(c, canvas, c.itemById('a')!.rect);
      // the item's right edge now faces down: its handle sits below the centre
      final handle = r.center + Offset(0, r.width / 2);
      final g = await t.createGesture(kind: PointerDeviceKind.mouse);
      await g.addPointer(location: handle);
      await g.down(handle);
      await t.pump();
      await g.moveTo(handle + const Offset(0, 20));
      await t.pump();
      await g.moveTo(handle + Offset(0, 20 + c.scale * 50));
      await t.pump();
      await g.up();
      await t.pump();
      final after = c.itemById('a')!.rect;
      expect(after.width, greaterThan(230));
      expect(after.height, closeTo(100, 1e-6));
      expect(c.itemById('a')!.rotation, 90);
      expect(c.historyLength, 1);
    });

    testWidgets('150 items: selecting and dragging one rebuilds none of the others', (t) async {
      final items = [
        for (var i = 0; i < 150; i++)
          StudioItem<String>(id: 'i$i', rect: Rect.fromLTWH((i % 15) * 60.0, (i ~/ 15) * 60.0, 50, 50), payload: '$i'),
      ];
      final builds = <String, int>{};
      final (c, _) = await mount(t, StudioMemoryAdapter<String>(items), built: (id) => builds[id] = (builds[id] ?? 0) + 1);
      expect(builds.length, 150);
      final base = Map<String, int>.of(builds);

      c.select('i77');
      await t.pump();
      final others = [for (final id in builds.keys) if (id != 'i77') id];
      expect([for (final id in others) builds[id]! - base[id]!].reduce((a, b) => a + b), 0, reason: 'a selection change rebuilds only the item it touches');

      expect(c.beginMove(), isTrue);
      for (var i = 1; i <= 30; i++) {
        c.updateMove(Offset(i * 2.0, i.toDouble()));
        await t.pump(const Duration(milliseconds: 16));
      }
      final during = [for (final id in others) builds[id]! - base[id]!].reduce((a, b) => a + b);
      expect(during, 0, reason: '30 drag frames must not rebuild the 149 other items');
      c.endGesture();
      await t.pump();
      // the drop is a structural change: every item may draw once more, never more than once
      for (final id in others) {
        expect(builds[id]! - base[id]!, lessThanOrEqualTo(1), reason: id);
      }
      expect(c.itemById('i77')!.rect.left, greaterThan(77 % 15 * 60.0));
    });
  });
}

/// An adapter with none of the optional hooks (like the certificate designer's).
class _Plain implements StudioAdapter<String> {
  _Plain(List<StudioItem<String>> items) : _m = StudioMemoryAdapter<String>(items);
  final StudioMemoryAdapter<String> _m;

  @override
  List<StudioItem<String>> readItems() => _m.readItems();
  @override
  void writeRects(Map<String, Rect> rects) => _m.writeRects(rects);
  @override
  void addItems(List<StudioItem<String>> items) => _m.addItems(items);
  @override
  void removeItems(Set<String> ids) => _m.removeItems(ids);
  @override
  void reorder(List<String> ids) => _m.reorder(ids);
  @override
  StudioItem<String> cloneItem(StudioItem<String> item) => _m.cloneItem(item);
  @override
  Object snapshot() => _m.snapshot();
  @override
  void restore(Object snapshot) => _m.restore(snapshot);
}
