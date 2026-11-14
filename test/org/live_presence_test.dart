// Who is drawing now (D-093): lib/features/live/room/annotation/live_presence.dart (the tracker, its
// fade and glide, safe names, colours), presence_tags.dart (where a tag goes) and the controllers that feed it from
// the packets they already receive — with the REAL sender identity.
import 'dart:convert';
import 'dart:ui';

import 'package:flutter_education_app/features/live/room/annotation/annotation_controller.dart';
import 'package:flutter_education_app/features/live/room/annotation/annotation_protocol.dart';
import 'package:flutter_education_app/features/live/room/annotation/live_presence.dart';
import 'package:flutter_education_app/features/live/room/annotation/presence_tags.dart';
import 'package:flutter_education_app/features/live/room/whiteboard/board_controller.dart';
import 'package:flutter_education_app/features/live/room/whiteboard/board_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LivePresence', () {
    late DateTime clock;
    late LivePresence p;

    setUp(() {
      clock = DateTime(2026, 10, 29, 10);
      p = LivePresence(now: () => clock);
    });

    test('a tag stays while the pen is down, holds 1.5 s after it lifts, then fades out and goes', () {
      p.mark('s1', name: 'Mona', x: 0.2, y: 0.3, active: true);
      clock = clock.add(const Duration(seconds: 4));
      expect(p.opacity(p.markOf('s1')!), 1, reason: 'an open stroke does not fade');
      p.end('s1');
      clock = clock.add(const Duration(milliseconds: 1400));
      expect(p.opacity(p.markOf('s1')!), 1);
      clock = clock.add(const Duration(milliseconds: 275)); // 1.675 s: half way through the 350 ms fade
      expect(p.opacity(p.markOf('s1')!), closeTo(0.5, 0.01));
      clock = clock.add(const Duration(milliseconds: 200));
      expect(p.opacity(p.markOf('s1')!), 0);
      expect(p.step(), isFalse);
      expect(p.isEmpty, isTrue);
    });

    test('a stroke left open (its drawer left mid-stroke) still fades once no point came for 5 s', () {
      p.mark('s1', name: 'Mona', x: 0.2, y: 0.3, active: true);
      clock = clock.add(const Duration(milliseconds: 4900));
      expect(p.opacity(p.markOf('s1')!), 1);
      clock = clock.add(const Duration(seconds: 1));
      expect(p.opacity(p.markOf('s1')!), 0);
      expect(p.step(), isFalse);
    });

    test('activity restarts the hold; a mark without an open stroke fades on its own', () {
      p.mark('s1', name: 'Mona', x: 0.2, y: 0.3);
      clock = clock.add(const Duration(milliseconds: 1600));
      expect(p.opacity(p.markOf('s1')!), lessThan(1));
      p.mark('s1', name: 'Mona', x: 0.25, y: 0.3);
      expect(p.opacity(p.markOf('s1')!), 1);
    });

    test('the drawn position glides toward the reported one (no jump per batch)', () {
      p.mark('s1', name: 'A', x: 0.1, y: 0.1);
      p.step();
      p.mark('s1', name: 'A', x: 0.5, y: 0.1);
      clock = clock.add(const Duration(milliseconds: 16));
      p.step();
      final m = p.markOf('s1')!;
      expect(m.shownX, greaterThan(0.1));
      expect(m.shownX, lessThan(0.5));
      for (var i = 0; i < 30; i++) {
        clock = clock.add(const Duration(milliseconds: 16));
        p.step();
      }
      expect(m.shownX, closeTo(0.5, 1e-4));
    });

    test('a new page jumps (no glide across pages); the colour is the ink, else a stable one per person', () {
      p.mark('s1', name: 'A', x: 0.1, y: 0.1, page: 'p0', color: 0xFF2563EB);
      p.mark('s1', name: 'A', x: 0.8, y: 0.8, page: 'p1');
      final m = p.markOf('s1')!;
      expect(m.shownX, 0.8);
      expect(m.color, 0xFF2563EB, reason: 'kept until a new ink says otherwise');
      p.mark('s2', name: 'B', x: 0.1, y: 0.1);
      expect(p.markOf('s2')!.color, presenceColorFor('s2'));
      expect(presenceColorFor('s2'), presenceColorFor('s2'));
      expect(kPresencePalette, contains(presenceColorFor('student_42')));
    });

    test('at most maxMarks people: the oldest goes', () {
      final small = LivePresence(now: () => clock, maxMarks: 2);
      small.mark('a', name: 'A', x: 0, y: 0);
      clock = clock.add(const Duration(milliseconds: 1));
      small.mark('b', name: 'B', x: 0, y: 0);
      clock = clock.add(const Duration(milliseconds: 1));
      small.mark('c', name: 'C', x: 0, y: 0);
      expect(small.marks.map((m) => m.identity), unorderedEquals(['b', 'c']));
    });
  });

  group('safe names', () {
    test('bidi controls and control characters are removed, whitespace collapsed', () {
      expect(presenceSafeName('  Mona\u202E evil \u202C  '), 'Mona evil');
      expect(presenceSafeName('a\u2066b\u2069c\u200F\u061C'), 'abc');
      expect(presenceSafeName('line\none\ttwo'), 'line one two');
      expect(presenceSafeName('\u0000\u0007'), '');
      expect(presenceSafeName(null, fallback: 'Guest'), 'Guest');
      expect(presenceSafeName('   ', fallback: 'Guest'), 'Guest');
    });

    test('long names are cut at 24 characters with an ellipsis; Arabic stays as typed', () {
      final long = presenceSafeName('Abdelrahman Mohamed Abdelaziz El-Sayed');
      expect(long.runes.length, lessThanOrEqualTo(25));
      expect(long.endsWith('…'), isTrue);
      expect(presenceSafeName('د. منى السيد'), 'د. منى السيد');
      expect(presenceIsRtl('د. منى السيد'), isTrue);
      expect(presenceIsRtl('Mona'), isFalse);
      expect(presenceIsRtl('123', fallbackRtl: true), isTrue);
    });

    test('a label is dark on a light tag (chalk, yellow) and white on a saturated one', () {
      expect(presenceInkOn(0xFFF8FAFC), 0xFF111827);
      expect(presenceInkOn(0xFFFDE68A), 0xFF111827);
      expect(presenceInkOn(0xFF2563EB), 0xFFFFFFFF);
      expect(presenceInkOn(0xFF1F2937), 0xFFFFFFFF);
      expect(presenceTagColor(0x612563EB), 0xFF2563EB, reason: 'a tag is never translucent');
    });
  });

  group('where a tag goes', () {
    const bounds = Rect.fromLTWH(0, 0, 400, 300);
    const pill = Size(90, 22);

    test('below and after the tip, flipped near the end and the bottom, never outside', () {
      final r = presenceTagRect(const Offset(100, 100), pill, bounds);
      expect(r.left, greaterThan(100));
      expect(r.top, greaterThan(100));
      final end = presenceTagRect(const Offset(380, 100), pill, bounds);
      expect(end.right, lessThan(380));
      final bottom = presenceTagRect(const Offset(100, 295), pill, bounds);
      expect(bottom.bottom, lessThan(295));
      for (final tip in const [Offset(-50, -50), Offset(450, 350), Offset(0, 0)]) {
        final x = presenceTagRect(tip, pill, bounds);
        expect(bounds.contains(x.topLeft) && bounds.contains(x.bottomRight - const Offset(0.1, 0.1)), isTrue, reason: '$tip');
      }
    });

    test('the author chip stays inside the area', () {
      const area = Rect.fromLTWH(0, 0, 300, 200);
      final o = authorLabelOffset(const Offset(295, 5), area);
      expect(o.dx + 200, lessThanOrEqualTo(300));
      expect(o.dy, greaterThanOrEqualTo(0));
    });
  });

  group('the whiteboard feeds the tags from the packets it receives', () {
    late BoardController teacher, student, other;
    final drawers = <String>{};

    BoardController peer(String id, List<BoardController> all) {
      final c = BoardController(
        localIdentity: id,
        autoFlush: false,
        idPrefix: id.substring(0, 2),
        isHost: (i) => i == 'teacher_1',
        studentMayDraw: drawers.contains,
        nameOf: (i) => {'teacher_1': 'Dr. Mona', 'student_2': 'Omar', 'student_3': 'سارة'}[i] ?? '',
        othersMayDraw: () => drawers.isNotEmpty,
      );
      c.send = (topic, bytes, reliable, {to}) async {
        for (final o in all) {
          if (o.localIdentity != id && (to == null || to.contains(o.localIdentity))) o.receive(topic, bytes, sender: id);
        }
      };
      return c;
    }

    setUp(() {
      drawers.clear();
      final all = <BoardController>[];
      teacher = peer('teacher_1', all);
      student = peer('student_2', all);
      other = peer('student_3', all);
      all.addAll([teacher, student, other]);
      teacher.startPresenting();
    });

    test('a student drawing: everyone else (the presenter too) sees their tag at the pen tip; they never see their own', () {
      drawers.add('student_2');
      student.beginInk(0.2, 0.3);
      student.moveInk(0.4, 0.5);
      student.flush();
      final m = teacher.presence.markOf('student_2')!;
      expect(m.name, 'Omar');
      expect(m.x, closeTo(0.4, 1e-6));
      expect(m.y, closeTo(0.5, 1e-6));
      expect(m.active, isTrue);
      expect(m.page, teacher.scene.page);
      expect(other.presence.markOf('student_2'), isNotNull);
      expect(student.presence.markOf('student_2'), isNull);
      expect(teacher.presenceShownFor('student_2'), isTrue);
      student.endInk();
      expect(teacher.presence.markOf('student_2')!.active, isFalse);
    });

    test("the presenter's own tag shows only once others may draw", () {
      teacher.beginInk(0.1, 0.1);
      teacher.moveInk(0.2, 0.2);
      teacher.endInk();
      expect(student.presence.markOf('teacher_1'), isNotNull);
      expect(student.presenceShownFor('teacher_1'), isFalse, reason: 'only the teacher draws: no tag');
      drawers.add('student_3');
      expect(student.presenceShownFor('teacher_1'), isTrue);
    });

    test('a shape being dragged and a text box being typed carry the tag; the name comes from the room, safe', () {
      drawers.add('student_3');
      other.beginShape(BoardShapeKind.rect, 0.1, 0.1);
      other.moveShape(0.3, 0.4);
      other.flush();
      final m = teacher.presence.markOf('student_3')!;
      expect(m.name, 'سارة');
      expect(m.x, closeTo(0.3, 1e-4));
      expect(m.y, closeTo(0.4, 1e-4));
      other.endShape();
      final id = other.createText(0.5, 0.5)!;
      other.updateText(id, text: 'مرحبا');
      other.flush();
      final caret = teacher.presence.markOf('student_3')!;
      expect(caret.y, greaterThan(0.5), reason: 'on the line, under the caret');
      // Arabic runs right to left: the box is right-aligned, the caret after its last letter (0.82 − 5 letters).
      expect(caret.x, closeTo(0.82 - 5 * 0.025 * 0.52, 1e-3));
    });

    test('a forged author in the payload changes nothing: the tag is keyed by the LiveKit sender', () {
      drawers.add('student_2');
      final bytes = BoardCodec.encode(BoardInkStart(id: 'x1', page: teacher.scene.page, ink: AnnotInk.pen, color: 0xFF000000, width: 0.004, author: 'teacher_1'));
      teacher.receive(kBoardTopic, bytes, sender: 'student_2');
      teacher.receive(kBoardTopic, BoardCodec.encode(const BoardInkPoints(id: 'x1', points: [AnnotPoint(0.5, 0.5)])), sender: 'student_2');
      expect(teacher.presence.markOf('student_2'), isNotNull);
      expect(teacher.presence.markOf('teacher_1'), isNull);
    });
  });

  group('screen-share annotation', () {
    test('tags come from the points; "Show who drew what" travels on the permission packet (au)', () {
      late AnnotationController host, student;
      host = AnnotationController(localIdentity: 'teacher_1', autoFlush: false, nameOf: (i) => i == 'student_2' ? 'Omar' : 'Dr. Mona');
      student = AnnotationController(localIdentity: 'student_2', autoFlush: false, nameOf: (i) => i == 'teacher_1' ? 'Dr. Mona' : 'Omar');
      host.send = (topic, bytes, reliable, {to}) async => student.receive(topic, bytes, sender: 'teacher_1');
      student.send = (topic, bytes, reliable, {to}) async => host.receive(topic, bytes, sender: 'student_2');
      for (final c in [host, student]) {
        c.setRoles(hosts: {'teacher_1'}, presenter: 'teacher_1');
      }
      host.setAllowStudents(true);
      expect(student.showAuthors, isFalse);
      host.setShowAuthors(true);
      expect(student.showAuthors, isTrue);
      student.begin(0.2, 0.2);
      student.move(0.3, 0.35);
      student.flush();
      final m = host.presence.markOf('student_2')!;
      expect(m.name, 'Omar');
      expect(m.active, isTrue);
      expect(host.presenceShownFor('student_2'), isTrue);
      student.end();
      expect(host.presence.markOf('student_2')!.active, isFalse);
      expect(host.strokeAt(0.25, 0.27)?.author, 'student_2');
      // An older host's permission (no au) turns it off again.
      final old = utf8.encode(jsonEncode({'v': 1, 't': 'perm', 'all': true, 'ids': []}));
      student.receive(kAnnotTopic, old, sender: 'teacher_1');
      expect(student.showAuthors, isFalse);
      host.dispose();
      student.dispose();
    });
  });
}
