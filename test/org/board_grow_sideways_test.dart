// A continuous whiteboard page that grows sideways (D-107): the wire (x past the column, `vp` x / w, `bv: 3` once
// something is drawn outside the column — and what an app from before gets), the page's reach
// ([boardContinuousSpanX]), one device's view of a grown page (growing without moving anything, the cap, the
// viewport that goes out), following the presenter sideways, the remap to a fixed page, the export's width and the
// recording window.
import 'dart:convert';
import 'dart:ui';

import 'package:flutter_education_app/features/live/room/annotation/annotation_protocol.dart';
import 'package:flutter_education_app/features/live/room/whiteboard/board_controller.dart';
import 'package:flutter_education_app/features/live/room/whiteboard/board_edge_scroll.dart';
import 'package:flutter_education_app/features/live/room/whiteboard/board_export.dart';
import 'package:flutter_education_app/features/live/room/whiteboard/board_format.dart';
import 'package:flutter_education_app/features/live/room/whiteboard/board_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _json(List<int> b) => jsonDecode(utf8.decode(b)) as Map<String, Object?>;

class _Room {
  final Map<String, BoardController> peers = {};
  final List<(String from, String topic, Map<String, Object?> msg)> log = [];

  BoardController join(String id) {
    final c = BoardController(localIdentity: id, autoFlush: false, idPrefix: '${id[0]}${peers.length}', isHost: (i) => i == 'teacher_1');
    c.send = (topic, bytes, reliable, {to}) async {
      log.add((id, topic, _json(bytes)));
      for (final e in peers.entries) {
        if (e.key == id || (to != null && !to.contains(e.key))) continue;
        e.value.receive(topic, bytes, sender: id);
      }
    };
    peers[id] = c;
    return c;
  }

  List<Map<String, Object?>> get msgs => [for (final l in log) l.$3];
}

/// How an app from before D-107 reads a point: [AnnotPoint.parse] (x and y kept in 0..1).
AnnotPoint _oldPoint(List<num> p) => AnnotPoint.parse(p)!;

void main() {
  group('wire', () {
    test('x past the column travels for ink, shapes, text boxes and the laser; the widest reach is the limit', () {
      final ink = BoardCodec.decode(BoardCodec.encode(BoardInkPoints(id: 'k1', points: [boardPoint(-0.4, 0.01), boardPoint(2.2, 0.02)])))
          as BoardInkPoints;
      expect(ink.points.map((p) => p.x), [-0.4, 2.2]);
      expect(boardPoint(-3, 0.5).x, -kBoardSideMax);
      expect(boardPoint(9, 0.5).x, 1 + kBoardSideMax);
      expect(boardPoint(0.3, 1.4).y, 1, reason: 'y stays a fraction of the length');
      // The annotation over a shared screen keeps its 0..1 (one point of the shared protocol unchanged).
      expect(AnnotPoint.wire(1.3, 0.2).x, 1);

      const sh = BoardShape(
          id: 'k2', author: 't', page: 'p0', kind: BoardShapeKind.rect, x1: -0.3, y1: 0.01, x2: 1.4, y2: 0.02, color: 1, width: 0.004);
      final sb = (BoardCodec.decode(BoardCodec.encode(const BoardPut(sh))) as BoardPut).item as BoardShape;
      expect((sb.x1, sb.x2), (-0.3, 1.4));
      const tx = BoardText(id: 'k3', author: 't', page: 'p0', x: 1.6, y: 0.03, boxWidth: 0.3, size: 0.03, color: 1, text: 'x');
      expect(((BoardCodec.decode(BoardCodec.encode(const BoardPut(tx))) as BoardPut).item as BoardText).x, 1.6);
      final l = BoardCodec.decode(BoardCodec.encode(const BoardLaser(x: -0.25, y: 0.1)), topic: kBoardLaserTopic) as BoardLaser;
      expect(l.x, -0.25);
    });

    test('a moved shape / text keeps the range it is given: 0..1 on a fixed page, the widest on a continuous one', () {
      const sh = BoardShape(
          id: 'k2', author: 't', page: 'p0', kind: BoardShapeKind.line, x1: 0.8, y1: 0.1, x2: 0.9, y2: 0.2, color: 1, width: 0.004);
      expect(sh.moved(0.5, 0).x2, 1);
      expect(sh.moved(0.5, 0, minX: -kBoardSideMax, maxX: 1 + kBoardSideMax).x2, closeTo(1.4, 1e-9));
    });

    test('vp: the column view is the D-093 packet; a sideways view adds x / w, which an older app ignores', () {
      final col = _json(BoardCodec.encode(const BoardViewport(top: 0.1, height: 0.05)));
      expect(col.keys.toSet(), {'v', 't', 'y', 'h'});
      final side = BoardCodec.encode(const BoardViewport(top: 0.1, height: 0.05, left: 0.62, width: 1));
      final j = _json(side);
      expect((j['x'], j['w']), (0.62, 1));
      final back = BoardCodec.decode(side, topic: kBoardTopic) as BoardViewport;
      expect((back.left, back.width), (0.62, 1.0));
      // The D-093 reader takes y and h only (the rest of the map is never looked at).
      expect((j['y'], j['h']), (0.1, 0.05));
      // A malformed x / w is the column, not a dropped view.
      final odd = BoardCodec.decode(utf8.encode('{"v":1,"t":"vp","y":0.1,"h":0.05,"x":"a","w":1}'), topic: kBoardTopic) as BoardViewport;
      expect((odd.top, odd.left, odd.width), (0.1, 0.0, 1.0));
    });

    test('bv: a continuous board stays 2 until something is drawn outside the column, then the presenter says 3', () {
      expect(boardFeatureVersionFor(BoardFormat.continuous), 2);
      expect(boardFeatureVersionFor(BoardFormat.continuous, wide: true), 3);
      expect(boardFeatureVersionFor(BoardFormat.portrait, wide: true), 2);
      expect(boardFeatureVersionFor(BoardFormat.landscape, wide: true), 1);
      expect(kBoardFeatureVersion, 3);

      final room = _Room();
      final t = room.join('teacher_1'), v = room.join('student_2');
      t.startPresenting(format: BoardFormat.continuous);
      t.beginInk(0.2, 0.01);
      t.moveInk(0.98, 0.012); // at the column's edge: still the column
      t.endInk();
      expect(t.isWide, isFalse);
      expect(room.msgs.where((m) => m['t'] == 'on').map((m) => m['bv']).toSet(), {2});

      t.beginInk(0.9, 0.02);
      t.moveInk(1.15, 0.021); // the page grew to the right
      t.flush();
      expect(t.isWide, isTrue);
      final states = [for (final (i, m) in room.msgs.indexed) if (m['t'] == 'on') (i, m['bv'])];
      expect(states.last.$2, 3);
      // The state with bv 3 goes before the first point outside the column (an older app covers the board first).
      final firstOut = room.msgs.indexWhere((m) => m['t'] == 'm' && (m['p'] as List).any((p) => (p as List)[0] as num > 1));
      expect(states.last.$1, lessThan(firstOut));
      t.endInk();
      // A receiver of this version draws it whole; an app whose board version is 2 shows "update the app".
      expect(v.needsUpdate, isFalse);
      expect(states.last.$2 as int > 2, isTrue);
      final outside = v.scene.items.whereType<BoardInk>().last.points.last;
      expect(outside.x, 1.15, reason: 'kept, not clamped');
      // What an app from before D-107 would have made of that point: squashed onto the column's edge.
      expect(_oldPoint([1.15, 0.021]).x, 1);
      // Sticky for the board: a late joiner gets bv 3 first.
      final late = room.join('student_9');
      late.requestSnapshot();
      expect(room.msgs.lastWhere((m) => m['t'] == 'on')['bv'], 3);
      expect(late.scene.items.whereType<BoardInk>().last.points.last.x, 1.15);
    });

    test('a student\'s line outside the column makes the presenter announce bv 3; a fixed page never leaves 0..1', () {
      final room = _Room();
      final t = room.join('teacher_1'), s = room.join('student_2');
      t.startPresenting(format: BoardFormat.continuous);
      // The host lets the student draw (the controller asks studentMayDraw).
      t.studentMayDraw = (i) => i == 'student_2';
      s.studentMayDraw = (i) => i == 'student_2';
      s.beginInk(0.5, 0.01);
      s.moveInk(-0.3, 0.012);
      s.endInk();
      expect(t.isWide, isTrue);
      expect(room.msgs.lastWhere((m) => m['t'] == 'on')['bv'], 3);

      final room2 = _Room();
      final l = room2.join('teacher_1');
      l.startPresenting(format: BoardFormat.portrait);
      l.beginInk(0.5, 0.5);
      l.moveInk(1.4, 0.5);
      l.endInk();
      l.beginShape(BoardShapeKind.line, -0.2, 0.1);
      l.moveShape(1.2, 0.2);
      l.endShape();
      expect(l.scene.items.whereType<BoardInk>().single.points.last.x, 1);
      expect(l.scene.items.whereType<BoardShape>().single.x1, 0);
      expect(l.isWide, isFalse);
      expect(room2.msgs.where((m) => m['t'] == 'on').map((m) => m['bv']).toSet(), {2});
    });

    test('the presenter\'s sideways view reaches viewers', () {
      final room = _Room();
      final t = room.join('teacher_1'), v = room.join('student_2');
      t.startPresenting(format: BoardFormat.continuous);
      t.reportViewport(const BoardViewportPos(0.1, 0.04, left: 0.7, width: 1));
      t.flushViewport();
      expect(v.presenterViewport.value, const BoardViewportPos(0.1, 0.04, left: 0.7, width: 1));
    });
  });

  group('the page\'s reach sideways', () {
    test('content inside the column never widens it; outside it does, with a margin; capped', () {
      expect(boardContinuousSpanX(), (0.0, 1.0));
      expect(boardContinuousSpanX(content: (0.02, 0.999)), (0.0, 1.0));
      final (lo, hi) = boardContinuousSpanX(content: (-0.3, 1.2));
      expect(lo, closeTo(-0.3 - kBoardSideMargin, 1e-9));
      expect(hi, closeTo(1.2 + kBoardSideMargin, 1e-9));
      expect(boardContinuousSpanX(content: (-9, 9)), (-kBoardSideMax, 1 + kBoardSideMax));
      expect(boardContinuousSpanX(presenter: const BoardViewportPos(0, 0.04, left: 0.9, width: 1)), (0.0, 1.9));
      expect(boardContinuousSpanX(grown: (-0.5, 1)), (-0.5, 1.0));
    });

    test('the content span: ink points, shape corners, a text box\'s sides', () {
      final items = <BoardItem>[
        BoardInk(id: 'a', author: 't', page: 'p', ink: AnnotInk.pen, color: 1, width: 0.01, points: [boardPoint(0.2, 0), boardPoint(1.3, 0)]),
        const BoardShape(id: 'b', author: 't', page: 'p', kind: BoardShapeKind.line, x1: -0.2, y1: 0, x2: 0.4, y2: 0, color: 1, width: 0.01),
        const BoardText(id: 'c', author: 't', page: 'p', x: 1.2, y: 0, boxWidth: 0.32, size: 0.03, color: 1, text: 'hi'),
      ];
      final s = boardContentSpanX(items)!;
      expect(s.$1, -0.2);
      expect(s.$2, closeTo(1.52, 1e-9));
      expect(boardContentSpanX(const []), isNull);
    });
  });

  group('a grown page on one device', () {
    const phone = Size(390, 600);
    const laptop = Size(1440, 800);

    test('a phone: the column fills the screen; growing right extends the page and moves the view with the pointer', () {
      const v0 = ContinuousView(box: phone, extent: 0.2);
      expect(v0.grown, isFalse);
      expect(v0.clamped().scrolledBy(80, 0).panX, 0, reason: 'an ungrown column does not move sideways');
      final v1 = v0.scrolledBy(80, 0, grow: true);
      expect(v1.xMax, closeTo(1 + 80 / 390, 1e-9));
      expect(v1.pageRect.left, closeTo(-80, 1e-9), reason: 'the page moved left under a still pointer');
      expect(v1.viewport.left, closeTo(80 / 390, 1e-9));
      expect(v1.viewport.width, closeTo(1, 1e-9));
      // Growing further only to the cap.
      var v = v1;
      for (var i = 0; i < 100; i++) {
        v = v.scrolledBy(80, 0, grow: true);
      }
      expect(v.xMax, 1 + kBoardSideMax);
      expect(v.shownRect.right, closeTo(phone.width, 1e-6), reason: 'the page still covers the screen');
      // The hand drags it back; never past the page.
      final back = v.scrolledBy(-5000, 0);
      expect(back.viewLeft, closeTo(0, 1e-9));
      expect(back.xMax, 1 + kBoardSideMax, reason: 'a pan never shrinks the page');
    });

    test('growing to the left never moves what is drawn: x 0 moves only with the view', () {
      // D-314: a laptop's column fills its width like a phone's, so the page always covers the stage.
      const v0 = ContinuousView(box: laptop, extent: 0.2);
      final col = v0.clamped().pageRect;
      expect(col.left, 0);
      // Held at the left edge: the view moves with the pointer, and x 0 with it, by the same.
      final v1 = v0.clamped().scrolledBy(-200, 0, grow: true);
      expect(v1.xMin, closeTo(-200 / 1440, 1e-9));
      expect(v1.shownRect.left, closeTo(0, 1e-6));
      expect(v1.pageRect.left, closeTo(200, 1e-6));
      // A viewer whose page grows because content arrived (no pan): the clamp keeps every point where it was.
      final grown = v0.clamped().copyWith(xMin: -0.4).clamped();
      expect(grown.pageRect.left, col.left);
    });

    test('a wider page than the stage always covers it; a narrower grown one stays on it', () {
      const wide = ContinuousView(box: phone, extent: 0.2, xMin: -0.5, xMax: 1.5, panX: 9999);
      final c = wide.clamped();
      expect(c.shownRect.left, closeTo(0, 1e-9));
      expect(c.viewLeft, closeTo(-0.5, 1e-9));
      final c2 = wide.copyWith(panX: -9999).clamped();
      expect(c2.shownRect.right, closeTo(phone.width, 1e-9));
      // D-314: a laptop too (its column is its whole width): the grown page covers it, the viewport is one width.
      const lap = ContinuousView(box: laptop, extent: 0.2, xMax: 1.4, panX: 9999);
      final c3 = lap.clamped();
      expect(c3.shownRect.left, closeTo(0, 1e-9));
      final c4 = lap.copyWith(panX: -9999).clamped();
      expect(c4.shownRect.right, closeTo(laptop.width, 1e-9));
      expect(c3.viewport.left, closeTo(0, 1e-9));
      expect(c3.viewport.width, closeTo(1, 1e-9));
    });

    test('the edge auto-scroll has room to grow into on the plain column', () {
      const v = ContinuousView(box: phone, extent: 0.2);
      final shown = v.clamped().shownRect;
      expect(boardScrollRoom(shown, phone).right, 0, reason: 'nothing beside the column yet');
      final cap = v.clamped().capRect;
      final room = boardScrollRoom(Rect.fromLTRB(cap.left, shown.top, cap.right, shown.bottom), phone);
      expect(room.right, closeTo(kBoardSideMax * 390, 1e-6));
      expect(room.left, closeTo(kBoardSideMax * 390, 1e-6));
      final edge = BoardEdgeScroll()..begin(const Offset(200, 300), phone);
      edge.track(const Offset(388, 300), phone);
      expect(edge.velocity(const Offset(388, 300), phone, room: room, dt: 0.016).dx, greaterThan(0));
    });

    test('zoom keeps the reach; withViewLeft moves the view sideways inside it', () {
      const v = ContinuousView(box: phone, extent: 0.2, xMin: -0.5, xMax: 1.5);
      final z = v.zoomedAt(2, const Offset(195, 300), const Offset(195, 300));
      expect((z.xMin, z.xMax), (-0.5, 1.5));
      final m = v.withViewLeft(0.8);
      expect(m.viewLeft, closeTo(0.5, 1e-9), reason: 'kept on the page: its right edge is 1.5');
      expect(v.withViewLeft(-0.2).viewLeft, closeTo(-0.2, 1e-9));
    });
  });

  group('following sideways', () {
    test('centred on the presenter\'s view, inside the page; nothing to do when the whole width shows', () {
      const p = BoardViewportPos(0.1, 0.04, left: 0.8, width: 1);
      expect(boardFollowLeft(presenter: p, visibleW: 1, xMin: 0, xMax: 1.8), closeTo(0.8, 1e-9));
      expect(boardFollowLeft(presenter: p, visibleW: 0.5, xMin: 0, xMax: 1.8), closeTo(1.05, 1e-9));
      expect(boardFollowLeft(presenter: p, visibleW: 1, xMin: 0, xMax: 1.5), closeTo(0.5, 1e-9));
      expect(boardFollowLeft(presenter: p, visibleW: 2.25, xMin: 0, xMax: 1.8), isNull);
    });
  });

  group('remap and export', () {
    test('a grown page changed to a fixed one fits in its width, centred', () {
      final items = <BoardItem>[
        BoardInk(id: 'a', author: 't', page: 'p', ink: AnnotInk.pen, color: 1, width: 0.01, points: [boardPoint(-0.5, 0.01), boardPoint(1.5, 0.02)]),
        const BoardText(id: 'c', author: 't', page: 'p', x: 0.9, y: 0.01, boxWidth: 0.3, size: 0.03, color: 1, text: 'hi'),
      ];
      final out = boardRemapItems(items, BoardFormat.continuous, BoardFormat.landscape);
      final ink = out.whereType<BoardInk>().single;
      expect(ink.points.first.x, closeTo(0.01, 1e-4));
      expect(ink.points.last.x, closeTo(0.99, 1e-4));
      final tx = out.whereType<BoardText>().single;
      expect(tx.x, greaterThan(0.6));
      expect(tx.x + tx.boxWidth, lessThanOrEqualTo(1.0 + 1e-6));
      // A column page is remapped exactly as before.
      final plain = boardRemapItems(
          [BoardInk(id: 'b', author: 't', page: 'p', ink: AnnotInk.pen, color: 1, width: 0.01, points: [boardPoint(0.2, 0.01)])],
          BoardFormat.continuous,
          BoardFormat.landscape);
      expect((plain.single as BoardInk).points.single.x, 0.2);
    });

    test('Save as PNG: a grown page is as wide as what is drawn; the view is the presenter\'s', () {
      final t = BoardController(localIdentity: 'teacher_1', autoFlush: false, isHost: (_) => true);
      addTearDown(t.dispose);
      t.startPresenting(format: BoardFormat.continuous);
      t.beginInk(0.2, 0.01);
      t.moveInk(0.6, 0.02);
      t.endInk();
      expect(boardExportSpanX(t, BoardExportRegion.whole), (0.0, 1.0));
      t.beginInk(0.8, 0.02);
      t.moveInk(1.7, 0.03);
      t.endInk();
      final w = boardExportSpanX(t, BoardExportRegion.whole);
      expect(w.$1, 0);
      expect(w.$2, closeTo(1.7 + kBoardSideMargin, 1e-9));
      final vis = boardExportSpanX(t, BoardExportRegion.visible, view: const BoardViewportPos(0, 0.04, left: 0.6, width: 1));
      expect(vis, (0.6, 1.6));
      final size = boardExportSize(t.aspect, (0, 0.1), width: 1600, spanX: w);
      expect(size.width, closeTo(1600 * w.$2, 1e-6));
      // The widest page (4 widths) fits the width cap; a taller one scales both sides evenly.
      final capped = boardExportSize(t.aspect, (0, 0.5), width: 1600, spanX: (-kBoardSideMax, 1 + kBoardSideMax));
      expect(capped.height, kBoardExportMaxHeight);
      expect(capped.width / capped.height, closeTo((1 + 2 * kBoardSideMax) / (0.5 * kBoardContinuousLength), 1e-9));
    });

    test('the recording window: a phone\'s narrow view widened to 16:9 over the page beside it, kept on the page', () {
      const aspect = 1 / kBoardContinuousLength;
      // A 390×700 phone view (1 width × 1.8 widths) on the column of a page grown to its whole reach.
      final view = BoardViewportPos(0.2, 1.8 / kBoardContinuousLength);
      final w = boardRecordingWindow(view: view, spanX: (-kBoardSideMax, 1 + kBoardSideMax), aspect: aspect);
      expect(w.width, closeTo(1.8 * 16 / 9, 1e-9));
      expect(w.left + w.width / 2, closeTo(0.5, 1e-9), reason: 'centred on the view');
      expect(w.top, view.top);
      // The plain column: as wide as the page is (the frame keeps a margin).
      final col = boardRecordingWindow(view: BoardViewportPos(0, view.height), spanX: (0, 1), aspect: aspect);
      expect((col.left, col.width), (0.0, 1.0));
      // Near the page's right edge: shifted back onto it.
      final edge = boardRecordingWindow(view: BoardViewportPos(0.2, view.height, left: 1.5, width: 1), spanX: (-0.5, 2.5), aspect: aspect);
      expect(edge.right, closeTo(2.5, 1e-9));
      // A laptop's wide view (2 widths × 1.1 widths): more of the page below.
      final lap = boardRecordingWindow(view: BoardViewportPos(0.1, 1.1 / kBoardContinuousLength, left: -0.5, width: 2), spanX: (-0.5, 1.5), aspect: aspect);
      expect(lap.width, 2);
      expect(lap.height / aspect, closeTo(2 * 9 / 16, 1e-9));
    });
  });
}
