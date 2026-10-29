// Live annotation wire format (annotation_protocol.dart, D-079): every message round-trips, unknown versions /
// types / malformed packets are ignored, snapshots are chunked under the reliable packet limit and reassemble
// (also a stroke longer than one chunk, chunks out of order), the batcher, and RDP simplification.
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_education_app/features/teacher/sessions/live/annotation/annotation_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

AnnotMsg _rt(AnnotMsg m) {
  final d = AnnotCodec.decode(AnnotCodec.encode(m), topic: m.topic);
  expect(d, isNotNull, reason: '${m.runtimeType} did not decode');
  return d!;
}

List<int> _raw(Object o) => utf8.encode(jsonEncode(o));

AnnotStrokeData _stroke(String author, String id, int n, {int seed = 1}) {
  final r = math.Random(seed);
  return AnnotStrokeData(
    author: author,
    id: id,
    ink: AnnotInk.pen,
    color: 0xFFE53935,
    width: 0.004,
    points: [for (var i = 0; i < n; i++) AnnotPoint.wire(r.nextDouble(), r.nextDouble(), r.nextDouble())],
  );
}

void main() {
  group('round trip', () {
    test('stroke start / points / end', () {
      final s = _rt(const AnnotStart(id: 'ab1', author: 'teacher_7', ink: AnnotInk.highlighter, color: 0x80FFB300, width: 0.02))
          as AnnotStart;
      expect([s.id, s.author, s.ink, s.color, s.width], ['ab1', 'teacher_7', AnnotInk.highlighter, 0x80FFB300, 0.02]);

      final pts = [AnnotPoint.wire(0.123456, 0.987654, 0.33333), AnnotPoint.wire(1.2, -0.1, 2)];
      final m = _rt(AnnotPoints(id: 'ab1', points: pts)) as AnnotPoints;
      expect(m.points, [const AnnotPoint(0.1235, 0.9877, 0.3333), const AnnotPoint(1, 0, 1)]);

      expect((_rt(const AnnotEnd('ab1')) as AnnotEnd).id, 'ab1');
    });

    test('undo, erase, clear, request, permission, mode, laser', () {
      final u = _rt(const AnnotUndo(author: 'student_4', id: 'q1')) as AnnotUndo;
      expect([u.author, u.id], ['student_4', 'q1']);
      final e = _rt(const AnnotErase([AnnotRef('a', '1'), AnnotRef('b', '2')])) as AnnotErase;
      expect(e.refs, const [AnnotRef('a', '1'), AnnotRef('b', '2')]);
      expect(_rt(const AnnotClear()), isA<AnnotClear>());
      expect(_rt(const AnnotSnapshotRequest()), isA<AnnotSnapshotRequest>());
      final p = _rt(const AnnotPermission(allowStudents: false, allowed: {'student_4', 'student_2'})) as AnnotPermission;
      expect(p.allowStudents, isFalse);
      expect(p.allowed, {'student_2', 'student_4'});
      expect((_rt(const AnnotMode(burnedIn: true)) as AnnotMode).burnedIn, isTrue);
      final l = _rt(const AnnotLaser(x: 0.25, y: 0.75, author: 'teacher_7')) as AnnotLaser;
      expect([l.x, l.y], [0.25, 0.75]);
      expect(const AnnotLaser(x: 0, y: 0).reliable, isFalse);
      expect(const AnnotLaser(x: 0, y: 0).topic, kAnnotLaserTopic);
    });

    test('compact: 4 decimals, integral values without ".0", versioned', () {
      final s = utf8.decode(AnnotCodec.encode(AnnotPoints(id: 'x', points: [AnnotPoint.wire(1 / 3, 1, 0)])));
      expect(s, '{"v":1,"t":"m","id":"x","p":[[0.3333,1,0]]}');
    });
  });

  group('ignored', () {
    test('unknown version or type, broken JSON, missing fields', () {
      expect(AnnotCodec.decode(_raw({'v': 2, 't': 'c'})), isNull);
      expect(AnnotCodec.decode(_raw({'t': 'c'})), isNull);
      expect(AnnotCodec.decode(_raw({'v': 1, 't': 'zz'})), isNull);
      expect(AnnotCodec.decode(utf8.encode('{"v":1,"t":"c"')), isNull);
      expect(AnnotCodec.decode(const [0xff, 0xfe, 0x00]), isNull);
      expect(AnnotCodec.decode(const []), isNull);
      expect(AnnotCodec.decode(_raw([1, 2, 3])), isNull);
      expect(AnnotCodec.decode(_raw({'v': 1, 't': 's', 'id': 'a', 'tl': 'p', 'c': 1})), isNull); // no width
      expect(AnnotCodec.decode(_raw({'v': 1, 't': 's', 'id': 'a', 'tl': 'z', 'c': 1, 'w': 0.1})), isNull);
      expect(AnnotCodec.decode(_raw({'v': 1, 't': 's', 'id': 'a', 'tl': 'p', 'c': -1, 'w': 0.1})), isNull);
      expect(AnnotCodec.decode(_raw({'v': 1, 't': 'm', 'id': 'a', 'p': [['x', 1]]})), isNull);
      expect(AnnotCodec.decode(_raw({'v': 1, 't': 'm', 'id': 'a', 'p': []})), isNull);
      expect(AnnotCodec.decode(_raw({'v': 1, 't': 'm', 'id': 'x' * 100, 'p': [[0, 0]]})), isNull);
      expect(AnnotCodec.decode(_raw({'v': 1, 't': 'e', 'ids': [['a']]})), isNull);
      expect(AnnotCodec.decode(_raw({'v': 1, 't': 'perm', 'all': 'yes'})), isNull);
      expect(AnnotCodec.decode(_raw({'v': 1, 't': 'snap', 'sid': 's', 'i': 3, 'n': 2, 's': []})), isNull);
    });

    test('too many points in one packet', () {
      final pts = [for (var i = 0; i <= kAnnotMaxPointsPerPacket; i++) [0.5, 0.5]];
      expect(AnnotCodec.decode(_raw({'v': 1, 't': 'm', 'id': 'a', 'p': pts})), isNull);
    });

    test('wrong topic: a laser on the reliable topic, a stroke on the laser topic', () {
      expect(AnnotCodec.decode(AnnotCodec.encode(const AnnotLaser(x: 0.1, y: 0.1))), isNull);
      expect(AnnotCodec.decode(AnnotCodec.encode(const AnnotClear()), topic: kAnnotLaserTopic), isNull);
    });

    test('a width above the cap is clamped, coordinates clamped to 0..1', () {
      final s = AnnotCodec.decode(_raw({'v': 1, 't': 's', 'id': 'a', 'tl': 'p', 'c': 1, 'w': 9})) as AnnotStart;
      expect(s.width, 0.1);
      final m = AnnotCodec.decode(_raw({'v': 1, 't': 'm', 'id': 'a', 'p': [[-3, 7, 0.5]]})) as AnnotPoints;
      expect(m.points.single, const AnnotPoint(0, 1, 0.5));
    });
  });

  group('snapshot chunks', () {
    test('an empty board is one chunk with no strokes', () {
      final chunks = AnnotCodec.snapshotChunks(const [], sid: 's1');
      expect(chunks, hasLength(1));
      final c = AnnotCodec.decode(chunks.single) as AnnotSnapshotChunk;
      expect([c.index, c.count, c.strokes.length], [0, 1, 0]);
      expect(AnnotSnapshotAssembler().add('teacher_1', c), isEmpty);
    });

    test('a big board: every chunk under the reliable limit, reassembled exactly (also out of order)', () {
      final strokes = [
        for (var i = 0; i < 60; i++) _stroke(i.isEven ? 'teacher_1' : 'student_${i % 5}', 's$i', 50 + i * 7, seed: i),
        _stroke('teacher_1', 'huge', 3000, seed: 99), // ~60 KB on its own: split into pieces
      ];
      final chunks = AnnotCodec.snapshotChunks(strokes, sid: 'big');
      expect(chunks.length, greaterThan(4));
      for (final c in chunks) {
        expect(c.length, lessThanOrEqualTo(kAnnotMaxReliableBytes));
      }
      final decoded = [for (final c in chunks) AnnotCodec.decode(c) as AnnotSnapshotChunk];
      final asm = AnnotSnapshotAssembler();
      final order = [for (var i = decoded.length - 1; i >= 0; i--) i]; // reversed
      List<AnnotStrokeData>? out;
      for (final i in order) {
        final r = asm.add('teacher_1', decoded[i]);
        if (i != order.last) expect(r, isNull);
        out = r ?? out;
      }
      expect(out, isNotNull);
      expect(out!.length, strokes.length);
      final byKey = {for (final s in out) s.ref.key: s};
      for (final s in strokes) {
        final got = byKey[s.ref.key]!;
        expect(got.points, s.points, reason: s.id);
        expect([got.author, got.ink, got.color, got.width], [s.author, s.ink, s.color, s.width]);
      }
      expect(asm.isEmpty, isTrue);
    });

    test('a smaller limit makes more chunks and still fits', () {
      final strokes = [for (var i = 0; i < 10; i++) _stroke('teacher_1', 's$i', 200, seed: i)];
      final chunks = AnnotCodec.snapshotChunks(strokes, sid: 'x', maxBytes: 2000);
      for (final c in chunks) {
        expect(c.length, lessThanOrEqualTo(2000));
      }
      final asm = AnnotSnapshotAssembler();
      List<AnnotStrokeData>? out;
      for (final c in chunks) {
        out = asm.add('teacher_1', AnnotCodec.decode(c) as AnnotSnapshotChunk) ?? out;
      }
      expect(out!.fold<int>(0, (n, s) => n + s.points.length), 2000);
    });

    test('a newer snapshot from the same sender replaces an incomplete one', () {
      final a = AnnotCodec.snapshotChunks([for (var i = 0; i < 6; i++) _stroke('t', 'a$i', 400, seed: i)],
          sid: 'old', maxBytes: 4000);
      expect(a.length, greaterThan(1));
      final asm = AnnotSnapshotAssembler();
      expect(asm.add('t', AnnotCodec.decode(a.first) as AnnotSnapshotChunk), isNull);
      final b = AnnotCodec.snapshotChunks([_stroke('t', 'b', 3)], sid: 'new');
      final out = asm.add('t', AnnotCodec.decode(b.single) as AnnotSnapshotChunk);
      expect(out!.single.id, 'b');
    });
  });

  group('batcher', () {
    test('due after the interval, or when a packet is full', () {
      final t0 = DateTime(2026);
      final b = AnnotPointBatcher(maxPoints: 3);
      expect(b.due(t0), isFalse);
      b.add(const AnnotPoint(0, 0), t0);
      expect(b.due(t0.add(const Duration(milliseconds: 10))), isFalse);
      expect(b.due(t0.add(kAnnotBatchInterval)), isTrue);
      b.add(const AnnotPoint(0.1, 0), t0);
      b.add(const AnnotPoint(0.2, 0), t0);
      b.add(const AnnotPoint(0.3, 0), t0);
      expect(b.due(t0), isTrue);
      expect(b.take(), hasLength(3));
      expect(b.take(), hasLength(1));
      expect(b.hasPending, isFalse);
    });
  });

  group('RDP', () {
    test('a straight line keeps its two ends', () {
      final pts = [for (var i = 0; i <= 50; i++) AnnotPoint.wire(i / 50, i / 100)];
      expect(annotSimplify(pts), [pts.first, pts.last]);
    });

    test('a corner is kept, the noise below epsilon is not', () {
      final pts = [
        for (var i = 0; i <= 20; i++) AnnotPoint.wire(i / 40, 0.5 + (i.isEven ? 0.0001 : -0.0001)),
        for (var i = 1; i <= 20; i++) AnnotPoint.wire(0.5, 0.5 + i / 40),
      ];
      final s = annotSimplify(pts);
      expect(s.length, 3);
      expect(s[1].x, closeTo(0.5, 1e-9));
      expect(s[1].y, closeTo(0.5, 0.001));
    });

    test('a pressure change is kept even on a straight line', () {
      final pts = [
        for (var i = 0; i <= 10; i++) AnnotPoint.wire(i / 10, 0.5, 0.5),
        for (var i = 11; i <= 20; i++) AnnotPoint.wire(i / 20, 0.5, 0.95),
      ];
      expect(annotSimplify(pts).length, greaterThan(2));
    });

    test('deterministic and never longer; short strokes unchanged', () {
      final r = math.Random(3);
      final pts = [for (var i = 0; i < 500; i++) AnnotPoint.wire(r.nextDouble(), r.nextDouble(), r.nextDouble())];
      final a = annotSimplify(pts), b = annotSimplify(List.of(pts));
      expect(a, b);
      expect(a.length, lessThanOrEqualTo(pts.length));
      expect(annotSimplify(pts.take(2).toList()), pts.take(2).toList());
    });
  });
}
