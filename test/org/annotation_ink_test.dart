// The ink of live annotation (annotation_ink.dart, D-083): the One Euro input filter smooths a slow pen's jitter
// without holding a fast one back, pressure is averaged and spike-limited, near-duplicate samples are dropped;
// the drawn centre line never changes behind the pen (prefix-stable pieces and causal radii), a pressure stroke
// is one union shape (filled where it crosses itself, no gaps), the ends taper, and the wire keeps 5 decimals.
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_education_app/features/live/room/annotation/annotation_controller.dart';
import 'package:flutter_education_app/features/live/room/annotation/annotation_ink.dart';
import 'package:flutter_education_app/features/live/room/annotation/annotation_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

/// RMS distance of [ys] from 0 (the ideal horizontal line).
double _rms(Iterable<double> ys) {
  var s = 0.0, n = 0;
  for (final y in ys) {
    s += y * y;
    n++;
  }
  return math.sqrt(s / n);
}

/// A horizontal stroke at [speed] px/s, sampled at 120 Hz, with ±[noise] px of uniform jitter on y.
List<(double x, double y, double t)> _stroke({required double speed, double noise = 0, int n = 120, int seed = 1}) {
  final r = math.Random(seed);
  return [
    for (var i = 0; i < n; i++)
      (i * speed / 120, noise == 0 ? 0.0 : (r.nextDouble() * 2 - 1) * noise, i / 120),
  ];
}

void main() {
  group('One Euro', () {
    test('a still input stays put; a step is followed', () {
      final f = OneEuroFilter();
      for (var i = 0; i < 10; i++) {
        expect(f.filter(5, i / 120), 5);
      }
      double last = 5;
      for (var i = 10; i < 400; i++) {
        last = f.filter(15, i / 120);
      }
      expect(last, closeTo(15, 0.05));
    });

    test('a repeated time stamp (coalesced events) does not divide by zero', () {
      final f = OneEuroFilter();
      f.filter(0, 1);
      final v = f.filter(10, 1);
      expect(v.isFinite, isTrue);
      expect(v, inExclusiveRange(0, 10));
    });
  });

  group('input filter', () {
    test('a slow pen: the jitter is mostly gone (the old wobble)', () {
      final raw = _stroke(speed: 60, noise: 0.8);
      final f = AnnotInkFilter(minDistance: 0);
      final out = <double>[f.start(raw[0].$1, raw[0].$2, raw[0].$3).y];
      for (final (x, y, t) in raw.skip(1)) {
        final s = f.add(x, y, t);
        if (s != null) out.add(s.y);
      }
      final before = _rms(raw.map((e) => e.$2));
      final after = _rms(out.skip(10));
      expect(after, lessThan(before * 0.5), reason: 'raw rms $before, filtered rms $after');
    });

    test('a fast pen is not held back: the ink stays within a few px of the nib, and ends on it', () {
      final raw = _stroke(speed: 1500, n: 40);
      final f = AnnotInkFilter();
      f.start(raw[0].$1, raw[0].$2, raw[0].$3);
      AnnotInkSample? last;
      for (final (x, y, t) in raw.skip(1)) {
        last = f.add(x, y, t) ?? last;
      }
      final nib = raw.last.$1;
      expect(nib - last!.x, lessThan(8), reason: 'lag ${nib - last.x} px at 1500 px/s');
      final end = f.finish(nib, 0);
      expect(end, isNotNull);
      expect(end!.x, nib);
    });

    test('samples closer than minDistance are dropped; the first is kept as is', () {
      final f = AnnotInkFilter(minDistance: 2);
      expect(f.start(10, 10, 0).x, 10);
      expect(f.add(10.3, 10, 1 / 120), isNull);
      expect(f.add(10.5, 10.2, 2 / 120), isNull);
      var got = false;
      for (var i = 3; i < 60 && !got; i++) {
        got = f.add(10 + i * 1.0, 10, i / 120) != null;
      }
      expect(got, isTrue);
    });

    test('pressure: a spike moves the width by at most one step; alternating noise is averaged', () {
      final f = AnnotInkFilter(minDistance: 0);
      f.start(0, 0, 0, 0.5);
      final spike = f.add(1, 0, 1 / 120, 1.0)!;
      expect(spike.p, closeTo(0.5 + f.maxPressureStep, 1e-9));
      final ps = <double>[];
      for (var i = 2; i < 80; i++) {
        ps.add(f.add(i.toDouble(), 0, i / 120, i.isEven ? 0.3 : 0.7)!.p);
      }
      final tail = ps.skip(30).toList();
      final spread = tail.reduce(math.max) - tail.reduce(math.min);
      expect(spread, lessThan(0.16), reason: 'raw spread 0.4');
    });

    test('a finger never carries pressure', () {
      final f = AnnotInkFilter(pressure: false, minDistance: 0);
      expect(f.start(0, 0, 0, 0.9).p, 0.5);
      expect(f.add(5, 0, 1 / 120, 0.1)!.p, 0.5);
    });
  });

  group('geometry', () {
    final pts = [for (var i = 0; i < 12; i++) Offset(i * 9.0, 20 * math.sin(i / 2))];
    final pressures = [for (var i = 0; i < 12; i++) 0.3 + 0.05 * i];

    test('radii are causal: a new point never changes the width already drawn', () {
      final full = annotInkRadii(pressures, 6);
      final prefix = annotInkRadii(pressures.sublist(0, 7), 6);
      expect(full.sublist(0, 7), prefix);
      expect(full.first, closeTo(3 * annotPressureFactor(0.3), 1e-9));
    });

    test('the centre line is prefix-stable: pieces 1 .. n − 2 do not move when a point is added', () {
      for (var n = 3; n < pts.length; n++) {
        final a = annotInkCenterline(pts.sublist(0, n), annotInkRadii(pressures.sublist(0, n), 6), toPiece: n - 2);
        final b = annotInkCenterline(pts.sublist(0, n + 1), annotInkRadii(pressures.sublist(0, n + 1), 6), toPiece: n - 2);
        expect(a.length, b.length);
        for (var i = 0; i < a.length; i++) {
          expect(a[i].x, b[i].x);
          expect(a[i].y, b[i].y);
          expect(a[i].r, b[i].r);
        }
      }
    });

    test('the centre line starts on the first point, ends on the last, and is dense', () {
      final nodes = annotInkCenterline(pts, annotInkRadii(pressures, 6), spacing: 1);
      expect(nodes.first.offset, pts.first);
      expect(nodes.last.offset, pts.last);
      for (var i = 1; i < nodes.length; i++) {
        expect((nodes[i].offset - nodes[i - 1].offset).distance, lessThan(1.6));
      }
      // Two points: the straight line between them.
      final two = annotInkCenterline([Offset.zero, const Offset(10, 0)], [1, 1], spacing: 2);
      expect(two.every((n) => n.y == 0), isTrue);
      expect(two.last.x, 10);
    });

    test('taper: thin at the start, full after it, and at the end only when finished', () {
      final line = [for (var i = 0; i <= 100; i++) AnnotInkNode(i.toDouble(), 0, 2)];
      final open = annotInkTapered(line, 4);
      expect(open.first.r, closeTo(2 * kAnnotTaperMin, 1e-9));
      expect(open[50].r, 2);
      expect(open.last.r, 2);
      final done = annotInkTapered(line, 4, taperEnd: true);
      expect(done.last.r, closeTo(2 * kAnnotTaperMin, 1e-9));
      // A tail continues the arc of the cached part: no second taper in the middle of a stroke.
      final tail = annotInkTapered(line.sublist(60), 4, startArc: 60);
      expect(tail.first.r, 2);
    });

    test('a pressure stroke is ONE shape: filled where it crosses itself, inside its band, nothing outside', () {
      // An X: down-right, then back across.
      final x = [
        for (var i = 0; i <= 20; i++) AnnotInkNode(i * 5.0, i * 5.0, 4),
        for (var i = 0; i <= 20; i++) AnnotInkNode(100 - i * 5.0, i * 5.0, 4),
      ];
      final path = Path();
      annotInkAppend(path, x);
      expect(path.contains(const Offset(50, 50)), isTrue, reason: 'the crossing is filled (no even-odd hole)');
      expect(path.contains(const Offset(52.5, 50)), isTrue);
      expect(path.contains(const Offset(25, 27)), isTrue, reason: 'inside the band between two nodes');
      expect(path.contains(const Offset(50, 20)), isFalse);
      expect(path.contains(const Offset(5, 30)), isFalse);
    });

    test('every band is clockwise (the same winding as the circles)', () {
      expect(annotSignedArea(annotClockwise([Offset.zero, const Offset(0, 10), const Offset(10, 10)])), greaterThan(0));
      expect(annotSignedArea(annotClockwise([Offset.zero, const Offset(10, 10), const Offset(0, 10)])), greaterThan(0));
      // A circle and an overlapping band: the overlap stays filled under non-zero.
      final p = Path()..addOval(Rect.fromCircle(center: const Offset(10, 10), radius: 5));
      annotInkAppend(p, const [AnnotInkNode(10, 10, 5), AnnotInkNode(30, 10, 5)]);
      expect(p.contains(const Offset(12, 10)), isTrue);
      expect(p.contains(const Offset(20, 13)), isTrue);
    });
  });

  group('wire', () {
    test('5 decimals for x / y: the grid step is far under a pixel on a 4K frame', () {
      final r = math.Random(7);
      for (var i = 0; i < 200; i++) {
        final x = r.nextDouble(), y = r.nextDouble();
        final w = AnnotPoint.wire(x, y);
        expect((w.x - x).abs() * 3840, lessThan(0.02));
        expect((w.y - y).abs() * 2160, lessThan(0.02));
      }
    });

    test('a stylus stroke says so (pr); an older sender without it is guessed and the guess sticks', () {
      final start = AnnotCodec.decode(AnnotCodec.encode(
              const AnnotStart(id: 'a', author: 't', ink: AnnotInk.pen, color: 0xFF000000, width: 0.004, pressured: true)))
          as AnnotStart;
      expect(start.pressured, isTrue);
      final old = AnnotCodec.decode(AnnotCodec.encode(
          const AnnotStart(id: 'a', author: 't', ink: AnnotInk.pen, color: 0xFF000000, width: 0.004))) as AnnotStart;
      expect(old.pressured, isNull);

      final s = AnnotStroke(author: 't', id: 'a', ink: AnnotInk.pen, color: 0, width: 0.004);
      s.points.add(const AnnotPoint(0, 0));
      expect(s.isPressured, isFalse);
      s.points.add(const AnnotPoint(0.1, 0, 0.8));
      expect(s.isPressured, isTrue);
      s.points.add(const AnnotPoint(0.2, 0));
      expect(s.isPressured, isTrue);
      final finger = AnnotStroke(author: 't', id: 'b', ink: AnnotInk.pen, color: 0, width: 0.004, pressured: false)
        ..points.add(const AnnotPoint(0, 0, 0.9));
      expect(finger.isPressured, isFalse);
    });

    test('the local stroke is the wire stroke: a stylus stroke drawn here and received there match', () {
      final a = AnnotationController(localIdentity: 'teacher_1', autoFlush: false, idPrefix: 'a');
      final b = AnnotationController(localIdentity: 'student_2', autoFlush: false, idPrefix: 'b');
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      a.send = (topic, bytes, reliable, {to}) async => b.receive(topic, bytes, sender: 'teacher_1');
      a.setRoles(hosts: {'teacher_1'});
      b.setRoles(hosts: {'teacher_1'});
      a.begin(0.1, 0.1, p: 0.3, stylus: true);
      for (var i = 1; i < 30; i++) {
        a.move(0.1 + i / 97, 0.1 + i / 211, p: 0.3 + i / 60);
      }
      a.end();
      final sa = a.board.strokes.single, sb = b.board.strokes.single;
      expect(sb.pressured, isTrue);
      expect(sb.points, sa.points);
      expect(sb.open, isFalse);
    });
  });
}
