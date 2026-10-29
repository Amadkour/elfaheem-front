// The whiteboard's page formats (D-093): the wire (fm / bv / vp, and what an older app gets), the coordinate space
// per format, a continuous page's growth and its per-device view, following the presenter, the remap on a format
// change, and the palm-safe held finger stroke.
import 'dart:convert';
import 'dart:ui';

import 'package:flutter_education_app/features/teacher/sessions/live/annotation/annotation_protocol.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/whiteboard/board_controller.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/whiteboard/board_export.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/whiteboard/board_format.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/whiteboard/board_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _json(List<int> b) => jsonDecode(utf8.decode(b)) as Map<String, Object?>;

class _Room {
  final Map<String, BoardController> peers = {};
  final List<(String from, String topic, Map<String, Object?> msg, bool reliable, List<String>? to)> log = [];
  DateTime clock = DateTime(2026, 10, 29, 9);

  BoardController join(String id) {
    final c = BoardController(
      localIdentity: id,
      autoFlush: false,
      idPrefix: '${id[0]}${peers.length}',
      isHost: (i) => i == 'teacher_1',
      now: () => clock,
    );
    c.send = (topic, bytes, reliable, {to}) async {
      log.add((id, topic, _json(bytes), reliable, to));
      for (final e in peers.entries) {
        if (e.key == id || (to != null && !to.contains(e.key))) continue;
        e.value.receive(topic, bytes, sender: id);
      }
    };
    peers[id] = c;
    return c;
  }

  Iterable<Map<String, Object?>> sent(String type) => log.where((l) => l.$3['t'] == type).map((l) => l.$3);
}

void main() {
  group('wire', () {
    test('a landscape board is the D-087 packet: bv 1, no fm (every app since D-087 draws it)', () {
      final m = _json(BoardCodec.encode(const BoardState(background: BoardBackground.grid, pages: ['p0'], page: 'p0')));
      expect(m['bv'], 1);
      expect(m.containsKey('fm'), isFalse);
    });

    test('portrait / continuous: fm + bv 2, so an app from before D-093 shows "update the app"', () {
      for (final f in [BoardFormat.portrait, BoardFormat.continuous]) {
        final bytes = BoardCodec.encode(BoardState(background: BoardBackground.white, pages: const ['p0'], page: 'p0', format: f));
        final m = _json(bytes);
        expect(m['fm'], boardFormatCode(f));
        expect(m['bv'], 2);
        final back = BoardCodec.decode(bytes) as BoardState;
        expect(back.format, f);
        // An app whose board feature version is 1 compares bv with it: 2 > 1 → its "update the app" overlay.
        expect(back.featureVersion > 1, isTrue);
        expect(back.featureVersion > kBoardFeatureVersion, isFalse, reason: 'this app draws it');
      }
    });

    test('an unknown format reads as landscape; a newer bv still asks for an update', () {
      final raw = utf8.encode(jsonEncode({'v': 1, 't': 'on', 'bv': 3, 'fm': 'z', 'bg': 'w', 'pages': ['p0'], 'pg': 'p0'}));
      final s = BoardCodec.decode(raw) as BoardState;
      expect(s.format, BoardFormat.landscape);
      final c = BoardController(localIdentity: 'student_2', autoFlush: false);
      c.receive(kBoardTopic, raw, sender: 'teacher_1');
      expect(c.needsUpdate, isTrue);
    });

    test('vp: lossy on board.laser, reliable on board; malformed is dropped; laser keeps 5 decimals', () {
      final lossy = BoardCodec.encode(const BoardViewport(top: 0.123456, height: 0.05));
      expect(const BoardViewport(top: 0, height: 0.1).topic, kBoardLaserTopic);
      expect(const BoardViewport(top: 0, height: 0.1, lossy: false).topic, kBoardTopic);
      final a = BoardCodec.decode(lossy, topic: kBoardLaserTopic) as BoardViewport;
      expect(a.lossy, isTrue);
      expect(a.top, closeTo(0.12346, 1e-9));
      final b = BoardCodec.decode(lossy, topic: kBoardTopic) as BoardViewport;
      expect(b.lossy, isFalse);
      expect(BoardCodec.decode(lossy, topic: kAnnotTopic), isNull);
      expect(BoardCodec.decode(utf8.encode('{"v":1,"t":"vp","y":0.1,"h":0}'), topic: kBoardTopic), isNull);
      expect(BoardCodec.decode(utf8.encode('{"v":1,"t":"vp","y":"x","h":0.1}'), topic: kBoardTopic), isNull);
      final laser = _json(BoardCodec.encode(const BoardLaser(x: 0.123456, y: 0.654321)));
      expect(laser['y'], 0.65432);
    });
  });

  group('coordinate space', () {
    test('aspects; a fitted page fills a portrait phone stage by its width', () {
      expect(boardFormatAspect(BoardFormat.landscape), kBoardAspect);
      expect(boardPageHeightW(BoardFormat.portrait), closeTo(4 / 3, 1e-9));
      expect(boardPageHeightW(BoardFormat.continuous), kBoardContinuousLength);
      final r = boardFitPage(const Size(382, 560), kBoardPortraitAspect);
      expect(r.width, 382);
      expect(r.height, closeTo(382 * 4 / 3, 1e-6));
      final l = boardFitPage(const Size(382, 560), kBoardAspect);
      expect(l.height, closeTo(382 * 9 / 16, 1e-6));
    });

    test('a circle stays round: hit tests and Shift-squares measure dy in page widths on every format', () {
      final room = _Room();
      final t = room.join('teacher_1');
      t.startPresenting(format: BoardFormat.continuous);
      t.setTool(BoardTool.rect);
      t.beginShape(BoardShapeKind.ellipse, 0.2, 0.01);
      t.moveShape(0.4, 0.015, square: true); // 0.2 widths across, 0.1 down: Shift makes both 0.2
      t.endShape();
      final s = t.scene.visibleItems.single as BoardShape;
      // 0.2 widths across → 0.2 widths down = 0.2 / 20 of the page's length.
      expect(s.x2 - s.x1, closeTo(0.2, 1e-4));
      expect(s.y2 - s.y1, closeTo(0.2 / kBoardContinuousLength, 1e-4));
      expect(t.hitTest(0.2, (s.y1 + s.y2) / 2), isNotEmpty);
    });
  });

  group('continuous page', () {
    const w = 1 / kBoardContinuousLength;

    test('the extent: a screen and a half at first, then one width (or 60 % of a screen) below the lowest content', () {
      expect(boardContinuousExtent(contentBottom: 0, visible: 0.1), closeTo(0.15, 1e-9));
      expect(boardContinuousExtent(contentBottom: 0.3, visible: 0.02), closeTo(0.3 + w, 1e-9));
      expect(boardContinuousExtent(contentBottom: 0.3, visible: 0.2), closeTo(0.3 + 0.12, 1e-9));
      expect(boardContinuousExtent(contentBottom: 0.1, visible: 0.02, presenterBottom: 0.6), 0.6);
      expect(boardContinuousExtent(contentBottom: 0.99, visible: 0.1), 1.0);
    });

    test('drawing near the end grows it', () {
      final before = boardContinuousExtent(contentBottom: 0.10, visible: 0.05);
      final after = boardContinuousExtent(contentBottom: 0.14, visible: 0.05);
      expect(after, greaterThan(before));
    });

    test('the view: width-filled column (a reading width on a laptop), scroll kept inside the extent', () {
      expect(ContinuousView.columnWidth(const Size(390, 600)), 390);
      expect(ContinuousView.columnWidth(const Size(1440, 640)), 512);
      expect(ContinuousView.columnWidth(const Size(1440, 500)), 480);
      final v = const ContinuousView(box: Size(390, 600), scroll: 0.9, extent: 0.2).clamped();
      expect(v.pageHeight, 390 * kBoardContinuousLength);
      expect(v.visible, closeTo(600 / 7800, 1e-9));
      expect(v.scroll, closeTo(0.2 - 600 / 7800, 1e-9));
      expect(v.pageRect.top, closeTo(-v.scroll * 7800, 1e-6));
      final up = v.scrolledBy(0, -100000);
      expect(up.scroll, 0);
    });

    test('zooming about a point keeps that page point under the fingers', () {
      const v = ContinuousView(box: Size(390, 600), scroll: 0.05, extent: 0.5);
      const focal = Offset(200, 300);
      final before = v.toPage(focal);
      final z = v.zoomedAt(2, focal, focal);
      expect(z.zoom, 2);
      final after = z.toPage(focal);
      expect(after.dx, closeTo(before.dx, 1e-6));
      expect(after.dy, closeTo(before.dy, 1e-6));
      expect(z.zoomedAt(9, focal, focal).zoom, 4);
    });

    test('follow: centred on the presenter when the viewer sees more, their top when less, inside the page', () {
      const p = BoardViewportPos(0.3, 0.02);
      expect(boardFollowTop(presenter: p, visible: 0.08, extent: 1), closeTo(0.31 - 0.04, 1e-9));
      expect(boardFollowTop(presenter: p, visible: 0.01, extent: 1), 0.3);
      expect(boardFollowTop(presenter: const BoardViewportPos(0, 0.02), visible: 0.08, extent: 1), 0);
      expect(boardFollowTop(presenter: p, visible: 0.08, extent: 0.32), closeTo(0.24, 1e-9));
    });

    test("the presenter's view goes out lossy at most 10 times a second, then once reliably; a joiner gets it", () {
      final room = _Room();
      final t = room.join('teacher_1');
      final s = room.join('student_2');
      t.startPresenting(format: BoardFormat.continuous);
      expect(s.format, BoardFormat.continuous);
      for (var i = 0; i < 10; i++) {
        t.reportViewport(BoardViewportPos(0.01 * i, 0.04));
        room.clock = room.clock.add(const Duration(milliseconds: 30));
      }
      final lossy = room.log.where((l) => l.$3['t'] == 'vp' && !l.$4).length;
      expect(lossy, inInclusiveRange(3, 4), reason: '300 ms of scrolling at ≤ 10 Hz');
      expect(s.presenterViewport.value, isNotNull);
      t.flushViewport();
      final last = room.log.lastWhere((l) => l.$3['t'] == 'vp');
      expect(last.$4, isTrue);
      expect(last.$2, kBoardTopic);
      expect(s.presenterViewport.value!.top, closeTo(0.09, 1e-5));
      final late = room.join('student_9');
      t.onParticipantJoined('student_9');
      expect(late.presenterViewport.value!.top, closeTo(0.09, 1e-5));
      // Only the presenter's view counts.
      late.receive(kBoardTopic, BoardCodec.encode(const BoardViewport(top: 0.7, height: 0.1, lossy: false)), sender: 'student_2');
      expect(late.presenterViewport.value!.top, closeTo(0.09, 1e-5));
    });
  });

  group('format change', () {
    test('landscape → portrait keeps the geometry in page widths (nothing needs to shrink)', () {
      final ink = BoardInk(id: 'i', author: 'a', page: 'p0', ink: AnnotInk.pen, color: 0, width: 0.004, points: [const AnnotPoint(0.5, 1.0)], open: false);
      final out = boardRemapItems([ink], BoardFormat.landscape, BoardFormat.portrait).single as BoardInk;
      // y 1.0 of a 16:9 page = 0.5625 widths = 0.5625 / (4/3) of the portrait page.
      expect(out.points.single.y, closeTo(0.5625 * 0.75, 1e-4));
      expect(out.points.single.x, 0.5);
      expect(out.width, 0.004);
    });

    test('portrait → landscape: content past the new bottom is scaled down evenly and centred', () {
      const tall = BoardShape(id: 's', author: 'a', page: 'p0', kind: BoardShapeKind.rect, x1: 0, y1: 0, x2: 1, y2: 1, color: 0, width: 0.004);
      final out = boardRemapItems([tall], BoardFormat.portrait, BoardFormat.landscape).single as BoardShape;
      expect(out.y2, lessThanOrEqualTo(1.0));
      expect(out.y2, greaterThan(0.95));
      final span = out.x2 - out.x1;
      expect(span, lessThan(1));
      expect(out.x1, closeTo((1 - span) / 2, 1e-4), reason: 'centred');
      expect(out.rev, 1);
      expect(out.width, lessThan(0.004));
    });

    test('pages are fitted one by one; continuous → landscape keeps a short page as it is', () {
      const a = BoardShape(id: 'a', author: 'x', page: 'p0', kind: BoardShapeKind.line, x1: 0.1, y1: 0.0, x2: 0.9, y2: 0.01, color: 0, width: 0.004);
      const b = BoardShape(id: 'b', author: 'x', page: 'p1', kind: BoardShapeKind.line, x1: 0.1, y1: 0.0, x2: 0.9, y2: 0.2, color: 0, width: 0.004);
      final out = {for (final i in boardRemapItems([a, b], BoardFormat.continuous, BoardFormat.landscape)) i.id: i as BoardShape};
      expect(out['a']!.x1, closeTo(0.1, 1e-6), reason: '0.2 widths of content fit a 16:9 page');
      expect(out['a']!.y2, closeTo(0.01 * 20 / (9 / 16), 1e-3));
      expect(out['b']!.x1, greaterThan(0.1), reason: '4 widths of content are scaled into 0.5625');
    });

    test('the presenter changes the format: viewers rebuild the remapped board from a fresh snapshot', () {
      final room = _Room();
      final t = room.join('teacher_1');
      final s = room.join('student_2');
      t.startPresenting();
      t.beginInk(0.1, 0.5);
      t.moveInk(0.3, 0.9);
      t.endInk();
      t.setTool(BoardTool.rect);
      t.beginShape(BoardShapeKind.rect, 0.5, 0.2);
      t.moveShape(0.8, 0.8);
      t.endShape();
      expect(s.scene.itemCount, 2);
      t.setFormat(BoardFormat.continuous);
      expect(s.format, BoardFormat.continuous);
      expect(s.scene.itemCount, 2);
      final ti = {for (final i in t.scene.items) i.id: i};
      for (final i in s.scene.items) {
        if (i is BoardInk) expect(i.points.last.y, (ti[i.id] as BoardInk).points.last.y);
        if (i is BoardShape) expect(i, ti[i.id]);
      }
      // 0.9 of a 16:9 page = 0.506 widths → 0.0253 of a 20-width page.
      final ink = s.scene.items.whereType<BoardInk>().single;
      expect(ink.points.last.y, closeTo(0.9 * 0.5625 / 20, 1e-4));
      expect(t.canUndo, isFalse, reason: 'a format change starts a new history');
      // A late joiner gets the format with the board.
      final late = room.join('student_9');
      t.onParticipantJoined('student_9');
      expect(late.format, BoardFormat.continuous);
      expect(late.scene.itemCount, 2);
    });

    test('a board presented again in another format comes back remapped', () {
      final room = _Room();
      final t = room.join('teacher_1');
      t.startPresenting(format: BoardFormat.portrait);
      t.beginInk(0.5, 0.9);
      t.moveInk(0.5, 0.95);
      t.endInk();
      t.stopPresenting();
      t.startPresenting(format: BoardFormat.landscape);
      final ink = t.scene.items.whereType<BoardInk>().single;
      expect(ink.points.last.y, lessThanOrEqualTo(1));
      expect(t.format, BoardFormat.landscape);
    });
  });

  group('palm-safe finger strokes', () {
    test('a finger stroke is held: a pinch in the first 70 ms sends nothing at all', () {
      final room = _Room();
      final t = room.join('teacher_1');
      final s = room.join('student_2');
      t.startPresenting();
      room.log.clear();
      t.beginInk(0.2, 0.2, hold: true);
      room.clock = room.clock.add(const Duration(milliseconds: 30));
      t.moveInk(0.25, 0.25);
      t.cancelInk(); // the second finger came down
      expect(room.log, isEmpty);
      expect(s.scene.itemCount, 0);
      expect(t.scene.itemCount, 0);
    });

    test('after the hold the stroke goes out whole (start + every point so far); a tap is a dot', () {
      final room = _Room();
      final t = room.join('teacher_1');
      final s = room.join('student_2');
      t.startPresenting();
      t.beginInk(0.2, 0.2, hold: true);
      room.clock = room.clock.add(const Duration(milliseconds: 40));
      t.moveInk(0.25, 0.25);
      expect(room.sent('s'), isEmpty);
      room.clock = room.clock.add(const Duration(milliseconds: 40));
      t.moveInk(0.3, 0.3);
      expect(room.sent('s'), hasLength(1));
      t.endInk();
      final ink = s.scene.items.whereType<BoardInk>().single;
      expect(ink.points.length, 3);
      expect(ink.open, isFalse);
      t.beginInk(0.6, 0.6, hold: true);
      t.endInk();
      expect(s.scene.itemCount, 2, reason: 'a quick tap still leaves its dot for everyone');
    });
  });

  group('export', () {
    test('the span: a fixed page whole; continuous the view or down to the last content; tall images are capped', () {
      final room = _Room();
      final t = room.join('teacher_1');
      t.startPresenting(format: BoardFormat.continuous);
      t.beginInk(0.1, 0.01);
      t.moveInk(0.2, 0.4);
      t.endInk();
      final vis = boardExportSpan(t, BoardExportRegion.visible, view: const BoardViewportPos(0.05, 0.03));
      expect(vis.$1, 0.05);
      expect(vis.$2, closeTo(0.08, 1e-9));
      final whole = boardExportSpan(t, BoardExportRegion.whole);
      expect(whole.$1, 0);
      expect(whole.$2, greaterThan(0.4));
      final size = boardExportSize(t.aspect, whole, width: 1600);
      expect(size.height, kBoardExportMaxHeight, reason: '8 widths at 1600 px = 13 000+ px: capped at the limit');
      expect(size.width, lessThan(1600));
      final land = boardExportSize(kBoardAspect, (0, 1));
      expect(land, const Size(1920, 1080));
    });
  });
}
