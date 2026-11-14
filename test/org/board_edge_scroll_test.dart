// Edge auto-scroll while drawing on the whiteboard (D-096, board_edge_scroll.dart): the zone, the speed curve, which
// edges are armed, the room left at the page's ends, the ease-in, and the pointer → page mapping that keeps a stroke
// continuous while the view scrolls under a pointer held still (continuous pages and zoomed fixed ones). Also the
// hand tool's keyboard shortcut.
import 'package:flutter/painting.dart' show EdgeInsets;
import 'package:flutter/services.dart';
import 'package:flutter_education_app/features/live/room/whiteboard/board_controller.dart';
import 'package:flutter_education_app/features/live/room/whiteboard/board_edge_scroll.dart';
import 'package:flutter_education_app/features/live/room/whiteboard/board_format.dart';
import 'package:flutter_education_app/features/live/room/whiteboard/board_toolbar.dart';
import 'package:flutter_test/flutter_test.dart';

const _box = Size(390, 600);
const _all = EdgeInsets.fromLTRB(500, 500, 500, 500);

void main() {
  group('zone and speed', () {
    test('the zone is 12 % of the axis, 28..72 px, at most a quarter of it', () {
      expect(boardEdgeZone(600), closeTo(72, 1e-9));
      expect(boardEdgeZone(400), closeTo(48, 1e-9));
      expect(boardEdgeZone(150), closeTo(28, 1e-9));
      expect(boardEdgeZone(80), closeTo(20, 1e-9), reason: 'a tiny stage keeps a middle');
      expect(boardEdgeZone(2000), 72);
      expect(boardEdgeZone(0), 0);
      expect(boardEdgeZone(double.infinity), 0);
    });

    test('0 outside the zone, the minimum at its border, growing to the maximum at the edge and past it', () {
      const z = 60.0;
      expect(boardEdgeSpeed(61, z), 0);
      expect(boardEdgeSpeed(z, z), 0, reason: 'the border itself is outside');
      expect(boardEdgeSpeed(59.999, z), closeTo(kBoardEdgeMinSpeed, 1));
      expect(boardEdgeSpeed(0, z), closeTo(kBoardEdgeMaxSpeed, 1e-9));
      expect(boardEdgeSpeed(-40, z), closeTo(kBoardEdgeMaxSpeed, 1e-9));
      var last = 0.0;
      for (var d = 59.0; d >= 0; d -= 1) {
        final s = boardEdgeSpeed(d, z);
        expect(s, greaterThan(last), reason: 'faster the closer it gets ($d px)');
        last = s;
      }
      // Quadratic: half way in is a quarter of the way from the minimum to the maximum.
      expect(boardEdgeSpeed(30, z), closeTo(kBoardEdgeMinSpeed + (kBoardEdgeMaxSpeed - kBoardEdgeMinSpeed) / 4, 1e-6));
    });

    test('the room: what of the page is beyond each edge', () {
      expect(boardScrollRoom(const Rect.fromLTWH(-30, -200, 450, 2000), _box), const EdgeInsets.fromLTRB(30, 200, 30, 1200));
      expect(boardScrollRoom(const Rect.fromLTWH(10, 0, 370, 590), _box), EdgeInsets.zero);
      expect(boardScrollRoom(Rect.zero, _box), EdgeInsets.zero);
    });
  });

  group('arming and velocity', () {
    test('a stroke that comes down to the bottom scrolls down; to the top, up; sideways only with room', () {
      final e = BoardEdgeScroll()..begin(const Offset(200, 300), _box);
      expect(e.velocity(const Offset(200, 300), _box, room: _all), Offset.zero);
      final down = e.velocity(const Offset(200, 590), _box, room: _all, dt: 1);
      expect(down.dx, 0);
      expect(down.dy, greaterThan(0));
      final up = e.velocity(const Offset(200, 5), _box, room: _all, dt: 1);
      expect(up.dy, lessThan(0));
      final right = e.velocity(const Offset(385, 300), _box, room: _all, dt: 1);
      expect(right.dx, greaterThan(0));
      expect(e.velocity(const Offset(385, 300), _box, room: const EdgeInsets.only(left: 100), dt: 1), Offset.zero,
          reason: 'no room to the right: nothing moves');
      final corner = e.velocity(const Offset(2, 598), _box, room: _all, dt: 1);
      expect(corner.dx, lessThan(0));
      expect(corner.dy, greaterThan(0));
    });

    test('a stroke that starts in the bottom zone and runs along it never scrolls; moving down towards it does', () {
      final e = BoardEdgeScroll()..begin(const Offset(40, 560), _box);
      expect(e.track(const Offset(200, 565), _box), isFalse);
      expect(e.velocity(const Offset(300, 570), _box, room: _all, dt: 1).dy, 0);
      expect(e.track(const Offset(300, 560 + kBoardEdgeArm), _box), isTrue);
      expect(e.velocity(const Offset(300, 560 + kBoardEdgeArm), _box, room: _all, dt: 1).dy, greaterThan(0));
    });

    test('leaving the zone and coming back arms it too; begin() starts afresh', () {
      final e = BoardEdgeScroll()..begin(const Offset(100, 580), _box);
      expect(e.inZone(const Offset(100, 580), _box), isFalse);
      e.track(const Offset(100, 300), _box);
      expect(e.track(const Offset(100, 575), _box), isTrue);
      e.begin(const Offset(100, 580), _box);
      expect(e.inZone(const Offset(100, 580), _box), isFalse);
    });

    test('the speed eases in over the first quarter second in the zone and starts again after leaving it', () {
      final e = BoardEdgeScroll()..begin(const Offset(200, 300), _box);
      final full = boardEdgeSpeed(0, boardEdgeZone(_box.height));
      final first = e.velocity(const Offset(200, 600), _box, room: _all, dt: 0).dy;
      expect(first, closeTo(full * kBoardEdgeRampFloor, 1e-6));
      final mid = e.velocity(const Offset(200, 600), _box, room: _all, dt: 0.125).dy;
      expect(mid, greaterThan(first));
      expect(mid, lessThan(full));
      expect(e.velocity(const Offset(200, 600), _box, room: _all, dt: 0.2).dy, closeTo(full, 1e-6));
      expect(e.velocity(const Offset(200, 300), _box, room: _all, dt: 0.016), Offset.zero);
      expect(e.velocity(const Offset(200, 600), _box, room: _all, dt: 0).dy, closeTo(full * kBoardEdgeRampFloor, 1e-6));
    });
  });

  group('the stroke follows the pointer while the view scrolls', () {
    test('continuous page: a pointer held at the bottom draws further down the page, step by step, without gaps', () {
      var view = const ContinuousView(box: _box, extent: 0.2);
      final e = BoardEdgeScroll()..begin(const Offset(200, 300), _box);
      const at = Offset(200, 590);
      final ys = <double>[boardStageToPage(at, view.pageRect).dy];
      for (var i = 0; i < 120; i++) {
        final v = e.velocity(at, _box, room: boardScrollRoom(view.shownRect, _box), dt: 1 / 60);
        view = view.scrolledBy(v.dx / 60, v.dy / 60);
        final p = boardStageToPage(at, view.pageRect);
        expect(p.dx, closeTo(boardStageToPage(at, const ContinuousView(box: _box).pageRect).dx, 1e-9), reason: 'straight down');
        ys.add(p.dy);
      }
      final pageH = view.pageHeight;
      for (var i = 1; i < ys.length; i++) {
        final step = (ys[i] - ys[i - 1]) * pageH;
        expect(step, greaterThanOrEqualTo(0), reason: 'never back up');
        expect(step, lessThanOrEqualTo(kBoardEdgeMaxSpeed / 60 + 1e-6), reason: 'no jump bigger than one frame of the top speed');
      }
      expect(ys.last, greaterThan(ys.first));
      // It stops where the shown page ends (here a fixed extent; on the board it grows as the stroke goes down).
      expect(view.scroll, closeTo(view.maxScroll, 1e-9));
      expect(boardScrollRoom(view.shownRect, _box).bottom, 0);
    });

    test('continuous page at the top: no room up, nothing moves', () {
      const view = ContinuousView(box: _box, extent: 0.5);
      final e = BoardEdgeScroll()..begin(const Offset(200, 300), _box);
      expect(e.velocity(const Offset(200, 3), _box, room: boardScrollRoom(view.shownRect, _box), dt: 0.1), Offset.zero);
    });

    test('zoomed continuous column: the right edge moves it sideways until its edge, then stops', () {
      var view = const ContinuousView(box: _box, zoom: 2, extent: 0.4);
      final e = BoardEdgeScroll()..begin(const Offset(200, 300), _box);
      const at = Offset(388, 300);
      var x = boardStageToPage(at, view.pageRect).dx;
      for (var i = 0; i < 200; i++) {
        final v = e.velocity(at, _box, room: boardScrollRoom(view.shownRect, _box), dt: 1 / 60);
        if (v == Offset.zero) break;
        view = view.scrolledBy(v.dx / 60, v.dy / 60);
        final nx = boardStageToPage(at, view.pageRect).dx;
        expect(nx, greaterThanOrEqualTo(x));
        x = nx;
      }
      expect(view.pageRect.right, closeTo(_box.width, 1e-6), reason: 'the column\'s right edge reached the stage\'s');
      expect(x, closeTo(388 / 390 * 1, 0.02), reason: 'the pointer is over the right part of the page');
    });

    test('a zoomed fixed page: the page rect moves, the mapped point moves the opposite way on the page', () {
      var page = const Rect.fromLTWH(-200, -300, 800, 1000); // a 2× zoomed portrait page
      final e = BoardEdgeScroll()..begin(const Offset(200, 300), _box);
      const at = Offset(200, 598);
      final before = boardStageToPage(at, page);
      final v = e.velocity(at, _box, room: boardScrollRoom(page, _box), dt: 0.3);
      page = page.shift(-v / 10);
      final after = boardStageToPage(at, page);
      expect(after.dy, greaterThan(before.dy));
      expect(after.dx, before.dx);
    });
  });

  test('M picks the hand; V the select tool', () {
    expect(boardShortcutTool(LogicalKeyboardKey.keyM), BoardTool.hand);
    expect(boardShortcutTool(LogicalKeyboardKey.keyV), BoardTool.select);
  });
}
