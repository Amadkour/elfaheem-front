// AnnotationController (D-079) over a fake data channel: controllers on several "devices" stay in sync through
// draw / undo / erase / clear / laser expiry / late-joiner snapshot, permission enforcement with a forged
// sender (the LiveKit identity decides, never the payload), and burned-in mode.
import 'dart:convert';

import 'package:flutter_education_app/features/teacher/sessions/live/annotation/annotation_controller.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/annotation/annotation_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

class _Packet {
  _Packet(this.from, this.topic, this.bytes, this.reliable, this.to);

  final String from;
  final String topic;
  final List<int> bytes;
  final bool reliable;
  final List<String>? to;
}

/// The room: every controller publishes into a queue; [pump] delivers until quiet, with the real sender.
class _Net {
  final Map<String, AnnotationController> peers = {};
  final List<_Packet> queue = [];
  final List<_Packet> sent = [];
  DateTime clock = DateTime(2026, 10, 29, 10);

  /// Drop lossy packets (the laser) to see that nothing depends on them.
  bool dropLossy = false;

  AnnotationController join(String id, {Set<String> hosts = const {'teacher_1'}, String? presenter}) {
    final c = AnnotationController(localIdentity: id, now: () => clock, autoFlush: false, idPrefix: '${id}_');
    c.send = (topic, bytes, reliable, {to}) async {
      final p = _Packet(id, topic, bytes, reliable, to);
      queue.add(p);
      sent.add(p);
    };
    peers[id] = c;
    c.setRoles(hosts: hosts, presenter: presenter);
    return c;
  }

  void roles(Set<String> hosts, {String? presenter}) {
    for (final c in peers.values) {
      c.setRoles(hosts: hosts, presenter: presenter);
    }
  }

  void pump() {
    var guard = 0;
    while (queue.isNotEmpty) {
      if (++guard > 10000) fail('packet storm');
      final p = queue.removeAt(0);
      if (dropLossy && !p.reliable) continue;
      for (final c in peers.values) {
        if (c.localIdentity == p.from) continue;
        if (p.to != null && !p.to!.contains(c.localIdentity)) continue;
        c.receive(p.topic, p.bytes, sender: p.from);
      }
    }
  }

  /// One device's board as comparable data (author/id → points).
  static Map<String, List<AnnotPoint>> board(AnnotationController c) => {
        for (final s in c.board.strokes) '${s.author}/${s.id}': List.of(s.points),
      };

  void expectInSync() {
    final ref = board(peers.values.first);
    for (final c in peers.values.skip(1)) {
      final b = board(c);
      expect(b.keys.toList(), ref.keys.toList(), reason: '${c.localIdentity}: strokes / order');
      for (final k in ref.keys) {
        expect(b[k], ref[k], reason: '${c.localIdentity}: points of $k');
      }
    }
  }
}

void _draw(AnnotationController c, List<(double, double)> pts, {double p = 0.5, _Net? net}) {
  expect(c.begin(pts.first.$1, pts.first.$2, p: p), isTrue);
  for (final (x, y) in pts.skip(1)) {
    c.move(x, y, p: p);
  }
  c.end();
  net?.pump();
}

List<(double, double)> _line(double x0, double y0, double x1, double y1, {int n = 20, double wobble = 0}) => [
      for (var i = 0; i <= n; i++) (x0 + (x1 - x0) * i / n, y0 + (y1 - y0) * i / n + (i.isOdd ? wobble : 0)),
    ];

void main() {
  late _Net net;
  setUp(() => net = _Net());

  test('a stroke drawn by the host appears on every device, simplified the same way', () {
    final host = net.join('teacher_1');
    final a = net.join('student_2');
    final b = net.join('student_3');
    host.begin(0.1, 0.1, p: 0.4);
    for (final (x, y) in _line(0.1, 0.1, 0.6, 0.4, n: 40, wobble: 0.01).skip(1)) {
      host.move(x, y, p: 0.6);
    }
    host.flush();
    net.pump();
    // Mid-stroke: viewers already see it open.
    expect(a.board.strokes.single.open, isTrue);
    expect(a.board.strokes.single.points.length, host.board.strokes.single.points.length);
    host.end();
    net.pump();
    expect(host.board.strokes.single.open, isFalse);
    expect(b.board.strokes.single.open, isFalse);
    net.expectInSync();
    expect(a.board.strokes.single.author, 'teacher_1');
  });

  test('every packet is under the size limit; points go in ~33 ms batches', () {
    final host = AnnotationController(localIdentity: 'teacher_1', now: () => net.clock, autoFlush: false);
    final sent = <List<int>>[];
    host.send = (topic, bytes, reliable, {to}) async => sent.add(bytes);
    host.setRoles(hosts: {'teacher_1'});
    host.begin(0, 0);
    for (var i = 1; i <= 100; i++) {
      net.clock = net.clock.add(const Duration(milliseconds: 8)); // a 120 Hz pen
      host.move(i / 100, (i % 7) / 7);
    }
    host.end();
    final kinds = [for (final b in sent) (jsonDecode(utf8.decode(b)) as Map)['t']];
    expect(kinds.first, 's');
    expect(kinds.last, 'x');
    final batches = kinds.where((k) => k == 'm').length;
    expect(batches, inInclusiveRange(15, 25)); // 800 ms of drawing in batches of >= 33 ms (8 ms samples: 40 ms)
    for (final b in sent) {
      expect(b.length, lessThan(kAnnotMaxReliableBytes));
    }
  });

  test('undo is per author: a student undoes their own stroke, never the host\'s', () {
    final host = net.join('teacher_1');
    final s = net.join('student_2');
    host.setAllowStudents(true);
    net.pump();
    _draw(host, _line(0.1, 0.1, 0.9, 0.1), net: net);
    _draw(s, _line(0.1, 0.5, 0.9, 0.5), net: net);
    expect(host.board.strokeCount, 2);
    expect(s.canUndo, isTrue);
    s.undo();
    net.pump();
    net.expectInSync();
    expect(host.board.strokes.single.author, 'teacher_1');
    expect(s.canUndo, isFalse);
    s.undo(); // nothing of theirs left: no-op
    net.pump();
    expect(host.board.strokeCount, 1);
    host.undo();
    net.pump();
    expect(s.board.isEmpty, isTrue);
  });

  test('the eraser removes what it touches: any stroke for the host, own strokes for a student', () {
    final host = net.join('teacher_1');
    final s = net.join('student_2');
    final v = net.join('student_3');
    host.setAllowStudents(true);
    net.pump();
    _draw(host, _line(0.1, 0.2, 0.9, 0.2), net: net);
    _draw(s, _line(0.1, 0.6, 0.9, 0.6), net: net);

    // Student over the host's stroke: nothing.
    s.setTool(AnnotTool.eraser);
    _draw(s, [(0.5, 0.2), (0.52, 0.2)], net: net);
    expect(v.board.strokeCount, 2);
    // Student over their own: gone everywhere.
    _draw(s, [(0.5, 0.6), (0.5, 0.61)], net: net);
    expect(v.board.strokes.single.author, 'teacher_1');
    net.expectInSync();

    // Far from any stroke: nothing. Then the host erases the student's stroke… there is none left; draw again.
    _draw(s..setTool(AnnotTool.pen), _line(0.1, 0.8, 0.9, 0.8), net: net);
    host.setTool(AnnotTool.eraser);
    _draw(host, [(0.5, 0.95)], net: net);
    expect(v.board.strokeCount, 2);
    _draw(host, [(0.3, 0.8)], net: net);
    expect(v.board.strokes.single.author, 'teacher_1');
    net.expectInSync();
  });

  test('a forged erase / undo of someone else\'s stroke is ignored', () {
    final host = net.join('teacher_1');
    final v = net.join('student_3');
    _draw(host, _line(0.1, 0.2, 0.9, 0.2), net: net);
    final id = host.board.strokes.single.id;
    // A student "undoes" the host's stroke by naming the host as the author: the payload author is not the sender.
    expect(v.receive(kAnnotTopic, AnnotCodec.encode(AnnotUndo(author: 'teacher_1', id: id)), sender: 'student_9'), isFalse);
    expect(v.receive(kAnnotTopic, AnnotCodec.encode(AnnotErase([AnnotRef('teacher_1', id)])), sender: 'student_9'),
        isFalse);
    expect(v.board.strokeCount, 1);
  });

  test('clear all: hosts only', () {
    final host = net.join('teacher_1');
    final s = net.join('student_2');
    final v = net.join('student_3');
    _draw(host, _line(0.1, 0.2, 0.9, 0.2), net: net);
    s.clearAll(); // not a host: nothing sent
    net.pump();
    expect(v.board.strokeCount, 1);
    expect(v.receive(kAnnotTopic, AnnotCodec.encode(const AnnotClear()), sender: 'student_2'), isFalse);
    expect(v.board.strokeCount, 1);
    host.clearAll();
    net.pump();
    expect(v.board.isEmpty && s.board.isEmpty && host.board.isEmpty, isTrue);
  });

  test('laser: shown on the others, fades out after the TTL, lossy and throttled', () {
    final host = net.join('teacher_1');
    final v = net.join('student_3');
    host.setTool(AnnotTool.laser);
    host.begin(0.5, 0.5);
    host.move(0.51, 0.5); // same instant: throttled, not sent
    net.clock = net.clock.add(const Duration(milliseconds: 40));
    host.move(0.6, 0.5);
    host.end();
    final lasers = net.queue.where((p) => p.topic == kAnnotLaserTopic).toList();
    expect(lasers, hasLength(2));
    expect(lasers.every((p) => !p.reliable), isTrue);
    net.pump();
    final dot = v.board.lasers.single;
    expect([dot.author, dot.x], ['teacher_1', 0.6]);
    expect(v.laserOpacity(dot), 1);
    net.clock = net.clock.add(const Duration(milliseconds: 1200));
    expect(v.laserOpacity(dot), inExclusiveRange(0, 1));
    expect(v.pruneLasers(), isTrue);
    net.clock = net.clock.add(const Duration(milliseconds: 400));
    expect(v.pruneLasers(), isFalse);
    expect(v.board.hasLasers, isFalse);
    expect(v.board.isEmpty, isTrue); // the laser never leaves a stroke
  });

  test('a late joiner gets the board (snapshot) — on request and on join', () {
    final host = net.join('teacher_1');
    final s = net.join('student_2');
    host.setAllowStudents(true);
    net.pump();
    for (var i = 0; i < 30; i++) {
      _draw(i.isEven ? host : s, _line(0.05, i / 31, 0.95, i / 31 + 0.01, n: 60, wobble: 0.003), net: net);
    }
    // A long stroke still in progress.
    host.begin(0.2, 0.9);
    for (var i = 1; i < 50; i++) {
      host.move(0.2 + i / 100, 0.9);
    }
    host.flush();
    net.pump();

    final late = net.join('student_7');
    late.requestSnapshot();
    net.pump();
    expect(late.board.strokeCount, 31);
    expect(late.allowStudents, isTrue); // the permission came with it
    // The open stroke continues on the live stream.
    host.move(0.8, 0.9);
    host.end();
    net.pump();
    net.expectInSync();

    // On join, unasked: the responder (host, no presenter) sends it to the new identity only.
    final before = net.sent.length;
    final late2 = net.join('student_8');
    host.onParticipantJoined('student_8');
    s.onParticipantJoined('student_8'); // not the responder: sends nothing
    final snaps = net.sent.skip(before).where((p) => (jsonDecode(utf8.decode(p.bytes)) as Map)['t'] == 'snap');
    expect(snaps.every((p) => p.from == 'teacher_1' && p.to!.single == 'student_8'), isTrue);
    net.pump();
    expect(late2.board.strokeCount, 31);
    net.expectInSync();
  });

  test('a snapshot does not bring back what was erased or cleared after the request', () {
    final host = net.join('teacher_1');
    _draw(host, _line(0.1, 0.2, 0.9, 0.2), net: net);
    _draw(host, _line(0.1, 0.4, 0.9, 0.4), net: net);
    final late = net.join('student_7');
    final first = host.board.strokes.first;
    // The snapshot was built before the erase, but the erase reaches the joiner first.
    final chunks = AnnotCodec.snapshotChunks([for (final s in host.board.strokes) s.toData()], sid: 'x');
    late.requestSnapshot();
    net.queue.clear();
    late.receive(kAnnotTopic, AnnotCodec.encode(AnnotErase([first.ref])), sender: 'teacher_1');
    for (final c in chunks) {
      late.receive(kAnnotTopic, c, sender: 'teacher_1');
    }
    expect(late.board.strokeCount, 1);

    final late2 = net.join('student_8');
    late2.requestSnapshot();
    net.queue.clear();
    late2.receive(kAnnotTopic, AnnotCodec.encode(const AnnotClear()), sender: 'teacher_1');
    for (final c in chunks) {
      late2.receive(kAnnotTopic, c, sender: 'teacher_1');
    }
    expect(late2.board.isEmpty, isTrue);
  });

  test('a snapshot from a student is ignored', () {
    net.join('teacher_1');
    final late = net.join('student_7');
    final chunks = AnnotCodec.snapshotChunks([
      AnnotStrokeData(author: 'teacher_1', id: 'fake', ink: AnnotInk.pen, color: 1, width: 0.01, points: [AnnotPoint.wire(0.5, 0.5)]),
    ], sid: 'f');
    expect(late.receive(kAnnotTopic, chunks.single, sender: 'student_2'), isFalse);
    expect(late.board.isEmpty, isTrue);
  });

  group('permission', () {
    test('students draw only when allowed; packets from others are dropped (real sender, not payload)', () {
      final host = net.join('teacher_1');
      final s = net.join('student_2');
      final v = net.join('student_3');
      expect(s.canDrawLocal, isFalse);
      expect(s.begin(0.5, 0.5), isFalse);
      // A forged start claiming to be the host, sent by a student.
      final forged = AnnotCodec.encode(const AnnotStart(id: 'f1', author: 'teacher_1', ink: AnnotInk.pen, color: 1, width: 0.004));
      expect(v.receive(kAnnotTopic, forged, sender: 'student_2'), isFalse);
      expect(v.receive(kAnnotLaserTopic, AnnotCodec.encode(const AnnotLaser(x: 0.5, y: 0.5, author: 'teacher_1')),
          sender: 'student_2'), isFalse);
      expect(v.board.isEmpty && !v.board.hasLasers, isTrue);
      // A forged permission from a student changes nothing.
      expect(v.receive(kAnnotTopic, AnnotCodec.encode(const AnnotPermission(allowStudents: true)), sender: 'student_2'),
          isFalse);
      expect(v.allowStudents, isFalse);

      // Named students only.
      host.setAllowedIdentities({'student_2'});
      net.pump();
      expect(s.canDrawLocal, isTrue);
      expect(v.canDrawLocal, isFalse);
      _draw(s, _line(0.1, 0.1, 0.5, 0.5), net: net);
      expect(v.board.strokes.single.author, 'student_2');

      // Everyone.
      host.setAllowStudents(true);
      net.pump();
      expect(v.canDrawLocal, isTrue);

      // Revoked mid-stroke: the student's stroke ends, further points are dropped, draw mode goes off.
      host.setAllowedIdentities({});
      net.pump();
      v.setDrawMode(true);
      expect(v.drawMode, isTrue);
      v.begin(0.2, 0.8);
      v.move(0.3, 0.8);
      v.flush();
      net.pump();
      host.setAllowStudents(false);
      net.pump();
      expect(v.drawMode, isFalse);
      expect(v.isDrawing, isFalse);
      expect(v.begin(0.4, 0.4), isFalse);
      final before = host.board.strokes.firstWhere((x) => x.author == 'student_3').points.length;
      final late = AnnotCodec.encode(AnnotPoints(id: host.board.strokes.firstWhere((x) => x.author == 'student_3').id,
          points: [AnnotPoint.wire(0.9, 0.9)]));
      expect(host.receive(kAnnotTopic, late, sender: 'student_3'), isFalse);
      expect(host.board.strokes.firstWhere((x) => x.author == 'student_3').points.length, before);
    });

    test('the presenter draws without being a host; a stranger cannot pose as the presenter', () {
      net.join('teacher_1');
      final p = net.join('student_5');
      final v = net.join('student_3');
      net.roles({'teacher_1'}, presenter: 'student_5');
      expect(p.canDrawLocal, isTrue);
      expect(p.isSnapshotResponder, isTrue);
      _draw(p, _line(0.1, 0.1, 0.9, 0.9), net: net);
      expect(v.board.strokes.single.author, 'student_5');
      net.roles({'teacher_1'});
      expect(p.canDrawLocal, isFalse);
    });

    test('server packets (no sender) and own echoes are ignored', () {
      final v = net.join('student_3');
      final start = AnnotCodec.encode(const AnnotStart(id: 'a', author: 'teacher_1', ink: AnnotInk.pen, color: 1, width: 0.01));
      expect(v.receive(kAnnotTopic, start, sender: null), isFalse);
      expect(v.receive(kAnnotTopic, start, sender: 'student_3'), isFalse);
      expect(v.receive(kAnnotTopic, utf8.encode('garbage'), sender: 'teacher_1'), isFalse);
    });
  });

  group('burned-in mode (Android whole-screen share)', () {
    test('the presenter\'s strokes stay local, students cannot draw, the mode reaches everyone', () {
      final host = net.join('teacher_1');
      final v = net.join('student_3');
      host.setAllowStudents(true);
      net.pump();
      expect(v.canDrawLocal, isTrue);
      net.roles({'teacher_1'}, presenter: 'teacher_1');
      host.setBurnedIn(true);
      net.pump();
      expect(v.burnedIn, isTrue);
      expect(v.canDrawLocal, isFalse);
      final before = net.sent.length;
      _draw(host, _line(0.1, 0.1, 0.9, 0.9));
      expect(net.sent.length, before, reason: 'no vectors in burned-in mode');
      expect(host.board.strokeCount, 1);
      net.pump();
      expect(v.board.isEmpty, isTrue);
      // A student packet is dropped even though "allow students" is on.
      final forged = AnnotCodec.encode(const AnnotStart(id: 'z', author: 'student_3', ink: AnnotInk.pen, color: 1, width: 0.01));
      expect(host.receive(kAnnotTopic, forged, sender: 'student_3'), isFalse);
      // A late joiner learns the mode with the snapshot.
      final late = net.join('student_8', presenter: 'teacher_1');
      late.requestSnapshot();
      net.pump();
      expect(late.burnedIn, isTrue);
      // Off again: students may draw.
      host.setBurnedIn(false);
      net.pump();
      expect(v.burnedIn, isFalse);
      expect(v.canDrawLocal, isTrue);
    });

    test('only a host or the presenter switches it', () {
      net.join('teacher_1');
      final v = net.join('student_3');
      expect(v.receive(kAnnotTopic, AnnotCodec.encode(const AnnotMode(burnedIn: true)), sender: 'student_2'), isFalse);
      expect(v.burnedIn, isFalse);
      v.setBurnedIn(true); // a student cannot
      expect(v.burnedIn, isFalse);
    });
  });

  test('palm rejection cancel removes the stroke everywhere', () {
    final host = net.join('teacher_1');
    final v = net.join('student_3');
    host.begin(0.1, 0.1);
    host.move(0.2, 0.2);
    host.flush();
    net.pump();
    expect(v.board.strokeCount, 1);
    host.cancel();
    net.pump();
    expect(v.board.isEmpty && host.board.isEmpty, isTrue);
  });
}

