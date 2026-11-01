// The studio engine's pure controller: snapping and guides, resize from every handle, aspect lock, align /
// distribute, nudge, duplicate / delete, z order, undo / redo (a drag is one step, record() edits, coalescing),
// multi-select moves and zoom bounds.
import 'dart:ui';

import 'package:flutter_education_app/design/studio/studio.dart';
import 'package:flutter_test/flutter_test.dart';

StudioItem<String> box(String id, double l, double t, double w, double h,
        {StudioResize resize = StudioResize.free, bool locked = false, bool visible = true, Size? min}) =>
    StudioItem<String>(
      id: id,
      rect: Rect.fromLTWH(l, t, w, h),
      payload: id,
      resize: resize,
      locked: locked,
      visible: visible,
      minSize: min,
    );

StudioController<String> make(List<StudioItem<String>> items,
        {Size? grid, bool clamp = true, bool snap = true, DateTime Function()? clock, int historyLimit = 60}) =>
    StudioController<String>(
      adapter: StudioMemoryAdapter<String>(items),
      page: const StudioPage(1000, 700),
      grid: grid,
      clampToPage: clamp,
      snapEnabled: snap,
      clock: clock,
      historyLimit: historyLimit,
    );

Rect rectOf(StudioController<String> c, String id) => c.itemById(id)!.rect;

List<String> order(StudioController<String> c) => [for (final i in c.items) i.id];

void drag(StudioController<String> c, Offset by) {
  expect(c.beginMove(), isTrue);
  c.updateMove(by);
  c.endGesture();
}

void main() {
  group('snapping', () {
    test('an edge near another item snaps onto it and draws the guide between the two', () {
      final c = make([box('a', 100, 100, 100, 50), box('b', 400, 300, 100, 50)])..select('a');
      c.beginMove();
      final guides = c.updateMove(const Offset(297, 0));
      expect(c.rectOf('a')!.left, 400);
      expect(guides, contains(const StudioGuide(vertical: true, position: 400, start: 100, end: 350)));
      c.endGesture();
      expect(rectOf(c, 'a'), const Rect.fromLTWH(400, 100, 100, 50));
      expect(c.guides, isEmpty);
    });

    test('the centre snaps to the page centre with a full-height guide', () {
      final c = make([box('a', 100, 100, 100, 50)])..select('a');
      c.beginMove();
      final guides = c.updateMove(const Offset(348, 0)); // centre 498 → 500
      expect(c.rectOf('a')!.center.dx, 500);
      expect(guides, contains(const StudioGuide(vertical: true, position: 500, start: 0, end: 700)));
      c.cancelGesture();
      expect(rectOf(c, 'a'), const Rect.fromLTWH(100, 100, 100, 50));
    });

    test('with nothing near, the leading edge snaps to the grid', () {
      final c = make([box('a', 100, 100, 100, 50)], grid: const Size(10, 10))..select('a');
      drag(c, const Offset(13, 27));
      expect(rectOf(c, 'a').topLeft, const Offset(110, 130));
    });

    test('snap off moves exactly and draws no guide', () {
      final c = make([box('a', 100, 100, 100, 50), box('b', 400, 300, 100, 50)])..select('a');
      c.toggleSnap();
      c.beginMove();
      expect(c.updateMove(const Offset(297, 0)), isEmpty);
      c.endGesture();
      expect(rectOf(c, 'a').left, 397);
    });

    test('the snap distance is in screen pixels, so it shrinks in page units when zoomed in', () {
      final c = make([box('a', 100, 100, 100, 50), box('b', 400, 300, 100, 50)])..select('a');
      c.setZoom(2); // 6 px = 3 units
      drag(c, const Offset(296, 0)); // every edge 4 units from a target
      expect(rectOf(c, 'a').left, 396);
    });

    test('hidden items and the moving items are not targets', () {
      final c = make([box('a', 0, 0, 10, 10), box('h', 300, 300, 10, 10, visible: false)]);
      final t = c.targetsExcluding({'a'});
      expect(t.xPositions, [0, 500, 1000]);
      expect(t.yPositions, [0, 350, 700]);
    });

    test('a move is clamped to the page', () {
      final c = make([box('a', 100, 100, 100, 50)])..select('a');
      drag(c, const Offset(-500, 2000));
      expect(rectOf(c, 'a'), const Rect.fromLTWH(0, 650, 100, 50));
    });

    test('shift keeps the move on the dominant axis', () {
      final c = make([box('a', 100, 100, 100, 50)], snap: false)..select('a');
      c.beginMove();
      c.updateMove(const Offset(40, 15), constrain: true);
      c.endGesture();
      expect(rectOf(c, 'a').topLeft, const Offset(140, 100));
    });
  });

  group('resize', () {
    const start = Rect.fromLTWH(100, 100, 200, 100);
    const d = Offset(20, 30);
    final expected = <StudioHandle, Rect>{
      StudioHandle.topLeft: const Rect.fromLTRB(120, 130, 300, 200),
      StudioHandle.top: const Rect.fromLTRB(100, 130, 300, 200),
      StudioHandle.topRight: const Rect.fromLTRB(100, 130, 320, 200),
      StudioHandle.right: const Rect.fromLTRB(100, 100, 320, 200),
      StudioHandle.bottomRight: const Rect.fromLTRB(100, 100, 320, 230),
      StudioHandle.bottom: const Rect.fromLTRB(100, 100, 300, 230),
      StudioHandle.bottomLeft: const Rect.fromLTRB(120, 100, 300, 230),
      StudioHandle.left: const Rect.fromLTRB(120, 100, 300, 200),
    };

    for (final e in expected.entries) {
      test('from ${e.key.name}', () {
        final c = make([box('a', 100, 100, 200, 100)], snap: false)..select('a');
        expect(c.beginResize(e.key), isTrue);
        c.updateResize(d);
        c.endGesture();
        expect(rectOf(c, 'a'), e.value);
        expect(c.historyLength, 1);
        expect(c.undoLabel, 'resize');
      });
    }

    test('never below the minimum size, anchored on the opposite edge', () {
      final c = make([], snap: false);
      expect(c.resizeRect(start: start, handle: StudioHandle.topLeft, delta: const Offset(500, 500)),
          const Rect.fromLTRB(292, 192, 300, 200));
      expect(
          c.resizeRect(
              start: start, handle: StudioHandle.right, delta: const Offset(-500, 0), min: const Size(50, 40)),
          const Rect.fromLTRB(100, 100, 150, 200));
    });

    test('the item minSize wins over the controller default', () {
      final c = make([box('a', 100, 100, 200, 100, min: const Size(60, 30))], snap: false)..select('a');
      c.beginResize(StudioHandle.bottomRight);
      c.updateResize(const Offset(-1000, -1000));
      c.endGesture();
      expect(rectOf(c, 'a'), const Rect.fromLTWH(100, 100, 60, 30));
    });

    test('a resized edge stays on the page', () {
      final c = make([], snap: false);
      expect(c.resizeRect(start: start, handle: StudioHandle.left, delta: const Offset(-500, 0)).left, 0);
      expect(c.resizeRect(start: start, handle: StudioHandle.bottom, delta: const Offset(0, 2000)).bottom, 700);
    });

    test('a moving edge snaps to another item', () {
      final c = make([box('a', 100, 100, 200, 100), box('b', 400, 400, 50, 50)])..select('a');
      c.beginResize(StudioHandle.right);
      final g = c.updateResize(const Offset(97, 0)); // right 397 → 400
      expect(c.rectOf('a')!.right, 400);
      expect(g.where((x) => x.vertical && x.position == 400), isNotEmpty);
      c.endGesture();
    });

    test('aspect items keep their ratio from a corner, anchored on the opposite corner', () {
      final c = make([], snap: false);
      expect(
          c.resizeRect(
              start: start, handle: StudioHandle.bottomRight, delta: const Offset(100, 0), mode: StudioResize.aspect),
          const Rect.fromLTRB(100, 100, 400, 250));
      expect(
          c.resizeRect(
              start: start, handle: StudioHandle.topLeft, delta: const Offset(-50, -10), mode: StudioResize.aspect),
          const Rect.fromLTRB(50, 75, 300, 200));
    });

    test('shift keeps the ratio of a free item; the page caps the growth', () {
      final c = make([], snap: false);
      final r = c.resizeRect(
          start: start, handle: StudioHandle.bottomRight, delta: const Offset(2000, 0), keepAspect: true);
      expect(r, const Rect.fromLTRB(100, 100, 1000, 550));
      expect(r.width / r.height, closeTo(2, 1e-9));
    });

    test('aspect lock respects the minimum size', () {
      final c = make([], snap: false);
      final r = c.resizeRect(
          start: start,
          handle: StudioHandle.bottomRight,
          delta: const Offset(-1000, -1000),
          mode: StudioResize.aspect,
          min: const Size(40, 10));
      expect(r, const Rect.fromLTWH(100, 100, 40, 20));
    });

    test('one-axis items refuse the other axis', () {
      final c = make([box('t', 100, 100, 200, 40, resize: StudioResize.horizontal)], snap: false)..select('t');
      expect(c.beginResize(StudioHandle.top), isFalse);
      expect(c.beginResize(StudioHandle.bottomRight), isTrue);
      c.updateResize(const Offset(50, 80));
      c.endGesture();
      expect(rectOf(c, 't'), const Rect.fromLTWH(100, 100, 250, 40));
    });

    test('locked items, several selected and resize none show no handles', () {
      expect((make([box('a', 0, 0, 10, 10, locked: true)])..select('a')).resizable, isNull);
      expect((make([box('a', 0, 0, 10, 10, resize: StudioResize.none)])..select('a')).resizable, isNull);
      final c = make([box('a', 0, 0, 10, 10), box('b', 50, 50, 10, 10)])
        ..select('a')
        ..select('b', additive: true);
      expect(c.resizable, isNull);
      expect(c.beginResize(StudioHandle.right), isFalse);
    });
  });

  group('align and distribute', () {
    List<StudioItem<String>> three() =>
        [box('a', 100, 100, 50, 50), box('b', 300, 200, 100, 50), box('c', 600, 150, 50, 100)];

    test('several items align to the selection bounds, as one undo step', () {
      final c = make(three())..selectAll();
      c.align(StudioAlign.left);
      expect([for (final i in c.items) i.rect.left], [100, 100, 100]);
      c.align(StudioAlign.bottom);
      expect([for (final i in c.items) i.rect.bottom], [250, 250, 250]);
      expect(c.historyLength, 2);
      c.undo();
      expect([for (final i in c.items) i.rect.bottom], [150, 250, 250]);
    });

    test('one item aligns to the page; "relative to page" does it for several', () {
      final c = make(three())..select('b');
      c.align(StudioAlign.centerH);
      expect(rectOf(c, 'b').center.dx, 500);
      c
        ..selectAll()
        ..alignToPage = true
        ..align(StudioAlign.right);
      expect([for (final i in c.items) i.rect.right], [1000, 1000, 1000]);
      c.align(StudioAlign.middle);
      expect([for (final i in c.items) i.rect.center.dy], [350, 350, 350]);
    });

    test('locked items are left alone', () {
      final c = make([box('a', 100, 100, 50, 50), box('l', 300, 300, 50, 50, locked: true)])..selectAll();
      c.align(StudioAlign.top);
      expect(rectOf(c, 'l').top, 300);
    });

    test('distribute gives equal gaps, the outer items stay', () {
      final c = make([box('a', 100, 0, 50, 50), box('b', 170, 0, 100, 50), box('c', 600, 0, 50, 50)])..selectAll();
      expect(c.canDistribute, isTrue);
      c.distribute(StudioAxis.horizontal);
      expect(rectOf(c, 'a').left, 100);
      expect(rectOf(c, 'b').left, 325);
      expect(rectOf(c, 'c').left, 600);
      expect(c.historyLength, 1);
    });

    test('distribute vertically needs three items', () {
      final c = make([box('a', 0, 0, 10, 10), box('b', 0, 30, 10, 10)])..selectAll();
      expect(c.canDistribute, isFalse);
      c.distribute(StudioAxis.vertical);
      expect(c.historyLength, 0);
    });
  });

  group('history', () {
    test('a drag of many moves is ONE undo step', () {
      final c = make([box('a', 100, 100, 100, 50)], snap: false)..select('a');
      c.beginMove();
      for (var i = 1; i <= 20; i++) {
        c.updateMove(Offset(i * 3.0, i * 2.0));
        expect(rectOf(c, 'a').topLeft, const Offset(100, 100), reason: 'the model is untouched mid-drag');
      }
      expect(c.rectOf('a')!.topLeft, const Offset(160, 140));
      c.endGesture();
      expect(c.historyLength, 1);
      expect(rectOf(c, 'a').topLeft, const Offset(160, 140));
      c.undo();
      expect(rectOf(c, 'a').topLeft, const Offset(100, 100));
      expect(c.canRedo, isTrue);
      c.redo();
      expect(rectOf(c, 'a').topLeft, const Offset(160, 140));
      expect(c.canRedo, isFalse);
    });

    test('a gesture that moves nothing records nothing', () {
      final c = make([box('a', 100, 100, 100, 50)])..select('a');
      c.beginMove();
      c.updateMove(Offset.zero);
      c.endGesture();
      expect(c.canUndo, isFalse);
    });

    test('record() makes a host edit undoable, and redo replays it', () {
      final a = StudioMemoryAdapter<String>([box('a', 0, 0, 10, 10)]);
      final c = StudioController<String>(adapter: a, page: const StudioPage(100, 100));
      c.record('colour', () => a.update('a', (i) => i.copyWith(payload: 'red')));
      expect(c.itemById('a')!.payload, 'red');
      expect(c.undoLabel, 'colour');
      c.undo();
      expect(c.itemById('a')!.payload, 'a');
      c.redo();
      expect(c.itemById('a')!.payload, 'red');
    });

    test('coalesced edits within the window are one step; a pause starts a new one', () {
      var now = DateTime(2026);
      final a = StudioMemoryAdapter<String>([box('a', 0, 0, 10, 10)]);
      final c = StudioController<String>(adapter: a, page: const StudioPage(100, 100), clock: () => now);
      for (final v in ['1', '2', '3']) {
        c.record('opacity', () => a.update('a', (i) => i.copyWith(payload: v)), coalesce: true);
        now = now.add(const Duration(milliseconds: 300));
      }
      expect(c.historyLength, 1);
      now = now.add(const Duration(seconds: 5));
      c.record('opacity', () => a.update('a', (i) => i.copyWith(payload: '4')), coalesce: true);
      expect(c.historyLength, 2);
      c.undo();
      expect(c.itemById('a')!.payload, '3');
      c.undo();
      expect(c.itemById('a')!.payload, 'a');
    });

    test('the history is bounded and a new step clears redo', () {
      final a = StudioMemoryAdapter<String>([box('a', 0, 0, 10, 10)]);
      final c = StudioController<String>(adapter: a, page: const StudioPage(100, 100), historyLimit: 3);
      for (var i = 0; i < 5; i++) {
        c.record('e$i', () => a.update('a', (x) => x.copyWith(payload: '$i')));
      }
      expect(c.historyLength, 3);
      c.undo();
      expect(c.canRedo, isTrue);
      c.record('new', () {});
      expect(c.canRedo, isFalse);
    });

    test('nudges coalesce; shift nudges by 10; the page stops them', () {
      final c = make([box('a', 985, 100, 10, 10)])..select('a');
      c.nudge(1, 0);
      c.nudge(0, 1);
      expect(rectOf(c, 'a').topLeft, const Offset(986, 101));
      expect(c.historyLength, 1);
      c.nudge(1, 0, big: true);
      expect(rectOf(c, 'a').left, 990); // right edge at 1000
      c.undo();
      expect(rectOf(c, 'a').topLeft, const Offset(985, 100));
    });

    test('undo brings back the selection of the time', () {
      final c = make([box('a', 0, 0, 10, 10), box('b', 50, 50, 10, 10)])..select('a');
      c.deleteSelection();
      expect(c.selection, isEmpty);
      c.undo();
      expect(c.itemById('a'), isNotNull);
      expect(c.selection, {'a'});
    });
  });

  group('selection, duplicate, delete, z order', () {
    test('shift-click toggles; a marquee skips locked and hidden items', () {
      final c = make([box('a', 0, 0, 10, 10), box('b', 20, 0, 10, 10), box('l', 40, 0, 10, 10, locked: true)]);
      c
        ..select('a')
        ..select('b', additive: true);
      expect(c.selection, {'a', 'b'});
      c.select('a', additive: true);
      expect(c.selection, {'b'});
      c.selectInRect(const Rect.fromLTWH(0, 0, 100, 100));
      expect(c.selection, {'a', 'b'});
    });

    test('a multi-selection moves together, clamped by its bounds; locked members stay', () {
      final c = make([box('a', 100, 100, 50, 50), box('b', 300, 300, 50, 50), box('l', 500, 500, 50, 50, locked: true)],
          snap: false)
        ..selectAll();
      drag(c, const Offset(10, 20));
      expect(rectOf(c, 'a').topLeft, const Offset(110, 120));
      expect(rectOf(c, 'b').topLeft, const Offset(310, 320));
      expect(rectOf(c, 'l').topLeft, const Offset(500, 500));
      drag(c, const Offset(0, 1000));
      expect(rectOf(c, 'b').bottom, 700);
      expect(rectOf(c, 'a').top, 120 + (700 - 370));
      expect(c.historyLength, 2);
    });

    test('duplicate copies with new ids, offset, selected; undo removes them', () {
      final c = make([box('a', 100, 100, 50, 50)])..select('a');
      c.duplicate();
      expect(c.items, hasLength(2));
      final copy = c.items.last;
      expect(copy.id, isNot('a'));
      expect(copy.rect.topLeft, const Offset(110, 110));
      expect(c.selection, {copy.id});
      c.undo();
      expect(c.items, hasLength(1));
    });

    test('delete leaves locked items', () {
      final c = make([box('a', 0, 0, 10, 10), box('l', 20, 0, 10, 10, locked: true)])..selectAll();
      c.deleteSelection();
      expect(order(c), ['l']);
    });

    test('bring forward / to front, send backward / to back', () {
      final c = make([box('a', 0, 0, 1, 1), box('b', 0, 0, 1, 1), box('c', 0, 0, 1, 1), box('d', 0, 0, 1, 1)])
        ..select('b');
      c.bringForward();
      expect(order(c), ['a', 'c', 'b', 'd']);
      expect(c.zOf('b'), 2);
      c.bringToFront();
      expect(order(c), ['a', 'c', 'd', 'b']);
      c.sendToBack();
      expect(order(c), ['b', 'a', 'c', 'd']);
      final steps = c.historyLength;
      c.sendBackward();
      expect(c.historyLength, steps, reason: 'already at the bottom: no step');
      c
        ..select('a')
        ..select('d', additive: true)
        ..sendBackward();
      expect(order(c), ['a', 'b', 'd', 'c']);
      c.undo();
      expect(order(c), ['b', 'a', 'c', 'd']);
    });
  });

  group('zoom', () {
    test('steps stay within 25 % – 400 %', () {
      final c = make([]);
      for (var i = 0; i < 20; i++) {
        c.zoomIn();
      }
      expect(c.zoom, StudioController.maxZoom);
      for (var i = 0; i < 30; i++) {
        c.zoomOut();
      }
      expect(c.zoom, StudioController.minZoom);
      c.setZoom(10);
      expect(c.zoom, 4);
      c.setZoom(.01);
      expect(c.zoom, .25);
      expect(c.fitted, isFalse);
    });

    test('fit follows the viewport and is the starting state', () {
      final c = make([]);
      expect(c.fitted, isTrue);
      expect(c.fitZoomFor(const Size(1048, 748)), closeTo(1, 1e-9));
      c.setViewport(const Size(548, 398));
      expect(c.zoom, closeTo(.5, 1e-9));
      c.zoomIn();
      expect(c.zoom, .67);
      c.fitPage();
      expect(c.zoom, closeTo(.5, 1e-9));
      expect(c.fitZoomFor(const Size(10, 10)), StudioController.minFitZoom);
    });

    test('scale is zoom × unitPx', () {
      final c = StudioController<String>(
        adapter: StudioMemoryAdapter<String>(const []),
        page: const StudioPage(210, 297, unitPx: 96 / 25.4),
      )..setZoom(1);
      expect(c.scale, closeTo(3.7795, 1e-3));
    });
  });

  group('clipboard, lock, in-place text', () {
    test('copy / paste adds unlocked copies offset by pasteOffset, each paste further; selection = the copies', () {
      final c = make([box('a', 100, 100, 50, 50), box('b', 300, 300, 50, 50, locked: true)])..pasteOffset = const Offset(4, 4);
      expect(c.canPaste, isFalse);
      c
        ..select('a')
        ..select('b', additive: true)
        ..copy();
      expect(c.canPaste, isTrue);
      expect(c.clipboardLength, 2);
      c.paste();
      expect(c.items, hasLength(4));
      final first = c.selection.toList();
      expect(first, hasLength(2));
      expect(first.every((id) => id != 'a' && id != 'b'), isTrue);
      final copies = [for (final id in first) c.itemById(id)!];
      expect(copies.map((i) => i.rect.topLeft).toSet(), {const Offset(104, 104), const Offset(304, 304)});
      expect(copies.every((i) => !i.locked), isTrue);
      c.paste();
      expect(c.items, hasLength(6));
      expect({for (final id in c.selection) c.itemById(id)!.rect.topLeft}, {const Offset(108, 108), const Offset(308, 308)});
      // one undo step per paste
      c.undo();
      expect(c.items, hasLength(4));
    });

    test('cut removes what is not locked; the first paste lands in place', () {
      final c = make([box('a', 100, 100, 50, 50), box('l', 300, 300, 50, 50, locked: true)]);
      c
        ..select('a')
        ..select('l', additive: true)
        ..cut();
      expect(order(c), ['l']);
      c.paste();
      expect(c.items, hasLength(3));
      expect({for (final id in c.selection) c.itemById(id)!.rect.topLeft}, {const Offset(100, 100), const Offset(300, 300)});
    });

    test('the clipboard keeps the copied payload, not later edits', () {
      final a = StudioMemoryAdapter<String>([box('a', 0, 0, 10, 10)]);
      final c = StudioController<String>(adapter: a, page: const StudioPage(1000, 700));
      c
        ..select('a')
        ..copy();
      c.record('text', () => a.update('a', (i) => i.copyWith(payload: 'changed')));
      c.paste();
      expect(c.itemById(c.selection.single)!.payload, 'a');
    });

    test('bring to front / send to back / forward / backward', () {
      final c = make([box('a', 0, 0, 10, 10), box('b', 0, 0, 10, 10), box('c', 0, 0, 10, 10)]);
      c
        ..select('a')
        ..bringToFront();
      expect(order(c), ['b', 'c', 'a']);
      c.sendBackward();
      expect(order(c), ['b', 'a', 'c']);
      c.sendToBack();
      expect(order(c), ['a', 'b', 'c']);
      c.bringForward();
      expect(order(c), ['b', 'a', 'c']);
      c.undo();
      expect(order(c), ['a', 'b', 'c']);
    });

    test('lock blocks move, resize, nudge and delete; unlock restores them; each is one undo step', () {
      final c = make([box('a', 100, 100, 50, 50), box('b', 300, 300, 50, 50)], snap: false);
      c.select('a');
      expect(c.canLock, isTrue);
      expect(c.selectionLocked, isFalse);
      c.toggleLock();
      expect(c.itemById('a')!.locked, isTrue);
      expect(c.selectionLocked, isTrue);
      expect(c.undoLabel, 'lock');
      expect(c.beginMove(), isFalse);
      expect(c.beginResize(StudioHandle.bottomRight), isFalse);
      c.nudge(1, 0);
      c.deleteSelection();
      c.cut();
      expect(rectOf(c, 'a'), const Rect.fromLTWH(100, 100, 50, 50));
      expect(order(c), ['a', 'b']);
      c.toggleLock();
      expect(c.itemById('a')!.locked, isFalse);
      c.nudge(1, 0);
      expect(rectOf(c, 'a').left, 101);
      c
        ..undo()
        ..undo();
      expect(c.itemById('a')!.locked, isTrue);
    });

    test('an adapter without StudioLockAdapter cannot lock', () {
      final c = StudioController<String>(adapter: _NoLock([box('a', 0, 0, 10, 10)]), page: const StudioPage(100, 100))..select('a');
      expect(c.canLock, isFalse);
      c.toggleLock();
      expect(c.itemById('a')!.locked, isFalse);
    });

    test('commitText is ONE undo step, also when the host records on its own', () {
      final a = StudioMemoryAdapter<String>([box('a', 0, 0, 10, 10)]);
      final c = StudioController<String>(adapter: a, page: const StudioPage(1000, 700));
      expect(c.startTextEdit('a'), isTrue);
      expect(c.editingId, 'a');
      expect(c.selection, {'a'});
      c.commitText('a', 'Hello', (item, text) => c.record('inner', () => a.update(item.id, (i) => i.copyWith(payload: text)), coalesce: true));
      expect(c.editingId, isNull);
      expect(c.itemById('a')!.payload, 'Hello');
      expect(c.historyLength, 1);
      expect(c.undoLabel, 'text');
      c.undo();
      expect(c.itemById('a')!.payload, 'a');
      c.redo();
      expect(c.itemById('a')!.payload, 'Hello');
    });

    test('a locked or hidden item never opens the in-place editor', () {
      final c = make([box('l', 0, 0, 10, 10, locked: true), box('h', 0, 0, 10, 10, visible: false)]);
      expect(c.startTextEdit('l'), isFalse);
      expect(c.startTextEdit('h'), isFalse);
      expect(c.startTextEdit('nope'), isFalse);
      expect(c.editingId, isNull);
    });
  });
}

/// An adapter that cannot lock (like the Export Hub's): no StudioLockAdapter.
class _NoLock implements StudioAdapter<String> {
  _NoLock(List<StudioItem<String>> items) : _m = StudioMemoryAdapter<String>(items);
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
