// The board ink, smooth and realistic (D-314). Regression tests for what made a stroke look discrete:
//   • every pen sample rebuilt the whole board (~500 widgets) and re-measured every stroke on the page, so on a busy
//     page the stroke under the pen advanced in jumps — now a sample repaints the live ink layer alone;
//   • the centre line cut every corner (quadratic Béziers through the samples' midpoints): at the 60 Hz a phone or a
//     tablet delivers, a quick loop came out flattened — now a centripetal Catmull–Rom spline goes through them;
//   • a stylus stroke was a circle + a band per node (thousands of sub-paths filled every frame) — now ONE outline,
//     the same pixels;
//   • a viewer's stroke jumped one network batch at a time — now it is revealed at the drawer's pace;
//   • a continuous page's y travelled with 5 decimals of its 20-width length (0.4 px steps on a full-width laptop
//     page) — now 6.
// `INK_RENDER=<dir>` writes before / after PNGs of a fast loop at 2× for a look.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/live/room/annotation/annotation_controller.dart' show AnnotStroke;
import 'package:flutter_education_app/features/live/room/annotation/annotation_ink.dart';
import 'package:flutter_education_app/features/live/room/annotation/annotation_painter.dart';
import 'package:flutter_education_app/features/live/room/annotation/annotation_protocol.dart';
import 'package:flutter_education_app/features/live/room/whiteboard/board_controller.dart';
import 'package:flutter_education_app/features/live/room/whiteboard/board_export.dart';
import 'package:flutter_education_app/features/live/room/whiteboard/board_format.dart';
import 'package:flutter_education_app/features/live/room/whiteboard/board_painter.dart';
import 'package:flutter_education_app/features/live/room/whiteboard/board_protocol.dart';
import 'package:flutter_education_app/features/live/room/whiteboard/board_stage.dart';
import 'package:flutter_education_app/features/live/room/whiteboard/board_view.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

/// A loop of radius [r] traced [f] times a second while moving right, sampled at [hz] (what Flutter delivers on a phone).
Offset _loop(double t, {double f = 6, double r = 25}) =>
    Offset(60 + 100 * f * t + r * math.sin(2 * math.pi * f * t), 200 - r * math.cos(2 * math.pi * f * t));

/// The D-083 centre line (before D-314): quadratic Béziers through the midpoints of the samples.
Path _midpointChain(List<Offset> o) {
  final path = Path()..moveTo(o[0].dx, o[0].dy);
  for (var i = 1; i < o.length - 1; i++) {
    final mid = (o[i] + o[i + 1]) / 2;
    path.quadraticBezierTo(o[i].dx, o[i].dy, mid.dx, mid.dy);
  }
  path.lineTo(o.last.dx, o.last.dy);
  return path;
}

/// The largest distance from a sample to the drawn line (how far the ink strays from where the pen was).
double _maxMiss(Path path, List<Offset> samples) {
  final dense = <Offset>[];
  for (final m in path.computeMetrics()) {
    for (var d = 0.0; d <= m.length; d += 0.25) {
      dense.add(m.getTangentForOffset(d)!.position);
    }
  }
  var worst = 0.0;
  for (final s in samples) {
    var best = double.infinity;
    for (final p in dense) {
      best = math.min(best, (p - s).distance);
    }
    worst = math.max(worst, best);
  }
  return worst;
}

Future<Uint8List> _alpha(Path p, int w, int h) async {
  final rec = ui.PictureRecorder();
  Canvas(rec).drawPath(p, Paint()..color = const Color(0xFF000000));
  final img = await rec.endRecording().toImage(w, h);
  final bytes = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
  img.dispose();
  return bytes;
}

Future<void> _png(String name, void Function(Canvas c) paint) async {
  final dir = Platform.environment['INK_RENDER'];
  if (dir == null) return;
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec)..scale(2);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 700, 300), Paint()..color = const Color(0xFFFFFFFF));
  paint(canvas);
  final img = await rec.endRecording().toImage(1400, 600);
  final png = await img.toByteData(format: ui.ImageByteFormat.png);
  File('$dir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
}

void main() {
  group('the stroke under the pen', () {
    for (final format in [BoardFormat.landscape, BoardFormat.continuous]) {
      testWidgets('a pen sample on a full page rebuilds no widget ($format)', (t) async {
        t.view.physicalSize = const Size(1400, 900);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final c = BoardController(localIdentity: 'teacher_1', autoFlush: false, idPrefix: 't1', isHost: (i) => true);
        addTearDown(c.dispose);
        c.send = (topic, bytes, reliable, {to}) async {};
        c.startPresenting(format: format);
        final r = math.Random(3);
        final cont = format == BoardFormat.continuous;
        for (var s = 0; s < 120; s++) {
          final x0 = r.nextDouble() * 0.8 + 0.1, y0 = r.nextDouble() * (cont ? 0.04 : 0.8) + 0.05;
          c.beginInk(x0, y0, stylus: true);
          for (var i = 1; i < 200; i++) {
            c.moveInk(x0 + 0.05 * math.sin(i / 10) + i * 0.0003, y0 + (cont ? 0.002 : 0.05) * math.cos(i / 7),
                p: 0.4 + 0.2 * math.sin(i / 13));
          }
          c.endInk();
        }
        await t.pumpWidget(layoutHost(WhiteboardRoomView(controller: c, onStop: () {}, keyboard: false), scale: 1));
        await t.pump(const Duration(milliseconds: 100));
        final stage = t.getRect(find.byType(WhiteboardStage));
        final g = await t.startGesture(stage.center, kind: PointerDeviceKind.stylus, pointer: 7);
        // A few samples first: the first stylus touch may show the one-time "stylus only?" offer.
        for (var i = 0; i < 5; i++) {
          await g.moveBy(const Offset(2, 1));
          await t.pump(const Duration(milliseconds: 16));
        }
        final before = c.scene.items.whereType<BoardInk>().length;
        var rebuilds = 0;
        final who = <String>{};
        debugOnRebuildDirtyWidget = (e, builtOnce) {
          rebuilds++;
          who.add(e.widget.runtimeType.toString());
        };
        const n = 60;
        final sw = Stopwatch()..start();
        for (var i = 0; i < n; i++) {
          await g.moveBy(Offset(3 * math.cos(i / 8), 3 * math.sin(i / 8)));
          await t.pump(const Duration(milliseconds: 8));
        }
        sw.stop();
        debugOnRebuildDirtyWidget = null;
        final open = c.scene.items.whereType<BoardInk>().lastWhere((s) => s.open);
        expect(open.points.length, greaterThan(n ~/ 2), reason: 'the samples reached the stroke');
        // Before D-314: ~500 widgets rebuilt per sample (22 – 55 ms a frame in this debug test). Now none.
        expect(rebuilds, lessThanOrEqualTo(4), reason: '$rebuilds widgets rebuilt over $n samples: $who');
        // ignore: avoid_print
        print('D-314 $format: ${(sw.elapsedMicroseconds / n / 1000).toStringAsFixed(2)} ms per sample, $rebuilds rebuilds');
        await g.up();
        await t.pump();
        expect(c.scene.items.whereType<BoardInk>().length, before);
        expect(c.scene.items.whereType<BoardInk>().last.open, isFalse);
        await t.pumpWidget(const SizedBox());
      });
    }
  });

  group('geometry', () {
    test('a quick loop at 60 Hz: the spline goes through every sample; the midpoint chain missed them by px', () async {
      final samples = [for (var i = 0; i <= 60; i++) _loop(i / 60)];
      final before = _maxMiss(_midpointChain(samples), samples);
      final after = _maxMiss(annotSmoothPath(samples), samples);
      expect(after, lessThan(before / 5), reason: 'after $after px, before $before px');
      expect(after, lessThan(0.3), reason: 'through the samples: $after px');
      expect(before, greaterThan(1), reason: 'the old chain cut the corners: $before px');
      // The drawn loop vs the real one: the spline is closer.
      double offTrue(Path p) {
        var worst = 0.0;
        for (final m in p.computeMetrics()) {
          for (var d = 0.0; d <= m.length; d += 1) {
            final q = m.getTangentForOffset(d)!.position;
            var best = double.infinity;
            for (var k = 0; k <= 2000; k++) {
              best = math.min(best, (_loop(k / 2000) - q).distance);
            }
            worst = math.max(worst, best);
          }
        }
        return worst;
      }

      final trueBefore = offTrue(_midpointChain(samples)), trueAfter = offTrue(annotSmoothPath(samples));
      expect(trueAfter, lessThan(trueBefore * 0.6), reason: 'off the real loop: before $trueBefore px, after $trueAfter px');
      await _png('loop_before', (c) {
        c.drawPath(_midpointChain(samples), Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);
      });
      await _png('loop_after', (c) {
        c.drawPath(annotSmoothPath(samples), Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);
      });
    });

    test('the spline never moves a piece behind the pen (pieces 1 .. n − 2 are final)', () {
      final pts = [for (var i = 0; i < 14; i++) _loop(i / 60)];
      for (var n = 4; n < pts.length; n++) {
        final a = annotSmoothPath(pts.sublist(0, n)).computeMetrics().first;
        final b = annotSmoothPath(pts.sublist(0, n + 1)).computeMetrics().first;
        // Arc length up to point n − 2 is the same, and the point there is the same.
        final la = annotInkCenterline(pts.sublist(0, n), List.filled(n, 1), toPiece: n - 2);
        final lb = annotInkCenterline(pts.sublist(0, n + 1), List.filled(n + 1, 1), toPiece: n - 2);
        expect(la.length, lb.length);
        expect(la.last.offset, lb.last.offset);
        expect(a.length, lessThan(b.length));
      }
    });

    testWidgets('a stylus stroke is ONE outline with exactly the pixels of the old circles-and-bands union', (t) async {
      await t.runAsync(() async {
        final rnd = math.Random(5);
        var holes = 0, extra = 0, inside = 0, subPathsBefore = 0, subPathsAfter = 0;
        for (var trial = 0; trial < 12; trial++) {
          final pts = <Offset>[const Offset(200, 200)];
          var dir = rnd.nextDouble() * 2 * math.pi;
          for (var i = 0; i < 25; i++) {
            dir += (rnd.nextDouble() * 2 - 1) * (trial.isEven ? 3.0 : 1.2); // even trials: hairpin turns
            pts.add(pts.last + Offset(math.cos(dir), math.sin(dir)) * (3 + rnd.nextDouble() * 20));
          }
          final radii = annotInkRadii([for (var i = 0; i < pts.length; i++) 0.5 + 0.4 * math.sin(i / 3)], 10);
          final nodes = annotInkTapered(annotInkCenterline(pts, radii, spacing: 1.5), 10, taperEnd: true);
          final union = Path();
          annotInkAppend(union, nodes);
          final outline = Path();
          annotInkOutline(outline, nodes);
          subPathsBefore += union.computeMetrics().length;
          subPathsAfter += outline.computeMetrics().length;
          final a = await _alpha(union, 400, 400), b = await _alpha(outline, 400, 400);
          for (var i = 3; i < a.length; i += 4) {
            if (a[i] > 200) inside++;
            if (a[i] > 200 && b[i] < 56) holes++;
            if (a[i] < 56 && b[i] > 200) extra++;
          }
        }
        expect(inside, greaterThan(10000));
        expect(holes, 0, reason: 'no pixel of the stroke missing (round joins at hairpins)');
        expect(extra, 0, reason: 'nothing outside it');
        expect(subPathsAfter, lessThan(subPathsBefore / 10), reason: 'sub-paths: $subPathsBefore → $subPathsAfter');
      });
    });

    test('the outline is clockwise like the circles it appends to (non-zero keeps crossings filled)', () {
      final path = Path();
      final x = [
        for (var i = 0; i <= 20; i++) AnnotInkNode(i * 5.0, i * 5.0, 4),
        for (var i = 0; i <= 20; i++) AnnotInkNode(100 - i * 5.0, i * 5.0, 4),
      ];
      annotInkOutline(path, x);
      expect(path.contains(const Offset(50, 50)), isTrue, reason: 'the crossing is filled');
      expect(path.contains(const Offset(25, 27)), isTrue);
      expect(path.contains(const Offset(50, 20)), isFalse);
      // Two chunks appended one after another (cached part + tail) overlap without a hole.
      final two = Path();
      annotInkOutline(two, x.sublist(0, 12));
      annotInkOutline(two, x.sublist(11, 21));
      expect(two.contains(const Offset(55, 55)), isTrue);
      expect(two.contains(const Offset(57.5, 57.5)), isTrue);
    });

    testWidgets('an open stroke drawn part of the way, then whole, then part again: never more than asked', (t) async {
      await t.runAsync(() async {
        final s = AnnotStroke(author: 'a', id: 's', ink: AnnotInk.pen, color: 0xFF000000, width: 0.01, pressured: true,
            points: [for (var i = 0; i < 30; i++) AnnotPoint(0.1 + i * 0.02, 0.5 + 0.1 * math.sin(i / 4), 0.6)]);
        const rect = Rect.fromLTWH(0, 0, 400, 300);
        Future<int> inkLeftOf(double x, {double? shown}) async {
          final rec = ui.PictureRecorder();
          AnnotationPainter.paintStroke(Canvas(rec), s, rect, shown: shown);
          final img = await rec.endRecording().toImage(400, 300);
          final px = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
          var right = 0;
          for (var y = 0; y < 300; y++) {
            for (var xx = (x * 400).ceil(); xx < 400; xx++) {
              if (px[(y * 400 + xx) * 4 + 3] > 0) right++;
            }
          }
          return right;
        }

        expect(await inkLeftOf(0.5, shown: 10.5), 0, reason: 'point 10.5 is at x 0.31');
        expect(await inkLeftOf(0.5), greaterThan(0));
        expect(await inkLeftOf(0.5, shown: 10.5), 0, reason: 'the cache of the whole stroke is not reused');
      });
    });
  });

  group('a viewer', () {
    test('reveals a remote stroke at the drawer\'s pace, never ahead of what arrived, whole once it ends', () {
      var clock = DateTime(2026, 11, 8, 10);
      late BoardController teacher, viewer;
      teacher = BoardController(localIdentity: 'teacher_1', autoFlush: false, idPrefix: 't1', isHost: (i) => i == 'teacher_1', now: () => clock);
      viewer = BoardController(localIdentity: 'student_2', autoFlush: false, idPrefix: 's2', isHost: (i) => i == 'teacher_1', now: () => clock);
      teacher.send = (topic, bytes, reliable, {to}) async => viewer.receive(topic, bytes, sender: 'teacher_1');
      teacher.startPresenting();
      teacher.beginInk(0.1, 0.1);
      teacher.flush();
      final mine = teacher.scene.items.whereType<BoardInk>().single;
      final theirs = viewer.scene.items.whereType<BoardInk>().single;
      expect(viewer.inkShown(theirs), 1);
      clock = clock.add(const Duration(milliseconds: 33));
      // A batch of 4 points every 33 ms (120 Hz input, the 33 ms batches).
      var k = 1;
      for (var batch = 0; batch < 5; batch++) {
        for (var j = 0; j < 4; j++) {
          teacher.moveInk(0.1 + 0.01 * k, 0.1 + 0.005 * k);
          k++;
        }
        teacher.flush();
        expect(teacher.inkShown(mine), mine.points.length, reason: 'the drawer sees every point at once');
        final arrived = theirs.points.length.toDouble();
        final start = viewer.inkShown(theirs);
        expect(start, lessThan(arrived), reason: 'the batch does not appear at once');
        expect(viewer.revealing, isTrue);
        var last = start;
        for (final step in const [8, 8, 8, 8, 1]) {
          clock = clock.add(Duration(milliseconds: step));
          final now = viewer.inkShown(theirs);
          expect(now, greaterThanOrEqualTo(last), reason: 'it only moves forward');
          expect(now, lessThanOrEqualTo(arrived), reason: 'never ahead of what arrived');
          last = now;
        }
        expect(last, arrived, reason: 'caught up by the next batch (33 ms later)');
      }
      expect(viewer.stepReveal(), isFalse);
      teacher.moveInk(0.9, 0.9);
      teacher.endInk();
      expect(viewer.inkShown(theirs), theirs.points.length, reason: 'a finished stroke is whole');
      teacher.dispose();
      viewer.dispose();
    });
  });

  group('wire', () {
    BoardController presenter(BoardFormat f, List<Map<String, Object?>> out) {
      final c = BoardController(localIdentity: 'teacher_1', autoFlush: false, idPrefix: 't1', isHost: (i) => true);
      c.send = (topic, bytes, reliable, {to}) async => out.add(jsonDecode(utf8.decode(bytes)) as Map<String, Object?>);
      c.startPresenting(format: f);
      return c;
    }

    test('a continuous page\'s y travels with 6 decimals; a fixed page\'s points are byte for byte as before', () {
      final out = <Map<String, Object?>>[];
      final c = presenter(BoardFormat.continuous, out);
      c.beginInk(0.123456789, 0.0123456789);
      c.endInk();
      final pts = out.firstWhere((m) => m['t'] == 'm')['p'] as List;
      expect((pts.first as List)[1], 0.012346);
      expect((pts.first as List)[0], 0.12346);
      // An older app rounds that y to the 5 decimals it knows: 0.01235 — within 1e-5 of the length, as before.
      final older = AnnotPoint.parse(pts.first);
      expect(older!.y, 0.01235);
      final out2 = <Map<String, Object?>>[];
      final f = presenter(BoardFormat.landscape, out2);
      f.beginInk(0.123456789, 0.0123456789);
      f.endInk();
      expect(jsonEncode((out2.firstWhere((m) => m['t'] == 'm')['p'] as List).first), '[0.12346,0.01235,0.5]');
      c.dispose();
      f.dispose();
    });

    test('bytes per point of a continuous stroke stay sane (≤ 26)', () {
      final out = <Map<String, Object?>>[];
      final c = presenter(BoardFormat.continuous, out);
      final r = math.Random(1);
      c.beginInk(0.3, 0.02);
      for (var i = 0; i < 400; i++) {
        c.moveInk(0.3 + r.nextDouble() * 0.4, 0.02 + r.nextDouble() * 0.03, p: r.nextDouble());
      }
      c.endInk();
      var bytes = 0, points = 0;
      for (final m in out.where((m) => m['t'] == 'm')) {
        bytes += utf8.encode(jsonEncode(m['p'])).length;
        points += (m['p'] as List).length;
      }
      final per = bytes / points;
      // ignore: avoid_print
      print('D-314 bytes per point (continuous, 6-decimal y): ${per.toStringAsFixed(1)}');
      expect(per, lessThanOrEqualTo(26));
      c.dispose();
    });
  });

  group('the board fills the stage (D-314)', () {
    test("a continuous page is as wide as every stage; the presenter's view is one whole page width", () {
      for (final box in const [Size(1920, 950), Size(1366, 640), Size(390, 780), Size(820, 1180)]) {
        final v = ContinuousView(box: box, extent: 0.3).clamped();
        expect(v.pageRect.left, 0);
        expect(v.pageRect.width, box.width);
        expect(v.viewport.left, 0);
        expect(v.viewport.width, closeTo(1, 1e-9));
        expect(v.viewport.height, closeTo(box.height / (box.width * kBoardContinuousLength), 1e-9));
      }
    });

    test("the recording shows the presenter's full-width view (a wide laptop: more page below, never narrower)", () {
      const box = Size(1920, 950);
      final vp = const ContinuousView(box: box, scroll: 0.1, extent: 0.4).clamped().viewport;
      final win = boardRecordingWindow(view: vp, spanX: (0, 1), aspect: 1 / kBoardContinuousLength, extent: 0.4);
      expect(win.left, 0);
      expect(win.width, 1, reason: 'the whole width the presenter sees');
      expect(win.top, closeTo(vp.top, 1e-9));
      expect(win.height, greaterThanOrEqualTo(vp.height - 1e-9));
      // 16:9 of page widths.
      expect(win.width / (win.height * kBoardContinuousLength), closeTo(16 / 9, 1e-6));
    });

    test('the pen keeps its pixel size on a wide screen: new strokes are thinner in page widths', () {
      final c = BoardController(localIdentity: 'teacher_1', autoFlush: false, idPrefix: 't1', isHost: (i) => true);
      c.send = (topic, bytes, reliable, {to}) async {};
      c.startPresenting(format: BoardFormat.continuous);
      final phoneW = c.styleScale;
      c.viewStyleFactor = boardContinuousStyleFactor(const Size(1920, 950));
      // Old column 760 px → full 1920 px: the same pixels.
      expect(c.styleScale * 1920, closeTo(phoneW * 760, 1e-6));
      expect(c.defaultTextWidth * 1920, closeTo(kBoardDefaultTextWidth * 760, 1e-6));
      c.dispose();
    });
  });

  test('the live layer draws open strokes over the settled one; a pen sample notifies the scene, not settled', () {
    final c = BoardController(localIdentity: 'teacher_1', autoFlush: false, idPrefix: 't1', isHost: (i) => true);
    c.send = (topic, bytes, reliable, {to}) async {};
    c.startPresenting();
    var all = 0, settled = 0;
    c.scene.addListener(() => all++);
    c.scene.settled.addListener(() => settled++);
    c.beginInk(0.1, 0.1);
    expect(settled, 0, reason: 'nothing finished changed (D-317)');
    for (var i = 0; i < 50; i++) {
      c.moveInk(0.1 + i * 0.005, 0.2);
    }
    expect(settled, 0, reason: 'its points are not');
    expect(all, 51);
    c.pointLaser(0.5, 0.5);
    expect(settled, 0);
    c.endInk();
    expect(settled, 1);
    c.dispose();
  });

  test('BoardItemsPainter passes the reveal on for open strokes only', () {
    final ink = BoardInk(id: 'i', author: 'a', page: 'p', ink: AnnotInk.pen, color: 0xFF000000, width: 0.01, points: [
      for (var i = 0; i < 10; i++) AnnotPoint(i / 10, 0.5),
    ]);
    final asked = <String>[];
    final painter = BoardItemsPainter(
      items: () => [ink],
      lasers: () => const [],
      laserColor: const Color(0xFF000000),
      laserOpacity: (_) => 0,
      shownPoints: (i) {
        asked.add(i.id);
        return 3;
      },
    );
    painter.paint(Canvas(ui.PictureRecorder()), const Size(100, 100));
    expect(asked, ['i']);
    ink.open = false;
    painter.paint(Canvas(ui.PictureRecorder()), const Size(100, 100));
    expect(asked, ['i']);
  });
}
