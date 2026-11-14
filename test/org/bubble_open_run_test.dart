// Bubble corrections for students in no course (D-672), against the REAL engine reply recorded by back
// tests/exam_engine/e2e_bubble_open_run.py with BUBBLE_DUMP (test/fixtures/payloads/bubble/run_open.json): the run's own
// students and where their ID comes from; the class list parser; Grade papers offering "Students in no course"; the
// new widgets at every size; review taking a new student.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/exams/hub/grade/grade_papers_sheet.dart';
import 'package:flutter_education_app/features/exams/hub/hub_logic.dart' show GradeKind;
import 'package:flutter_education_app/features/exams/paper/bubble/bubble_flow.dart';
import 'package:flutter_education_app/features/exams/paper/bubble/bubble_widgets.dart';
import 'package:flutter_education_app/features/exams/paper/review/omr_review.dart';
import 'package:flutter_education_app/features/exams/paper/review/omr_review_parts.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

Map<String, dynamic> _fx(String name) => Map<String, dynamic>.from(jsonDecode(File('test/fixtures/payloads/bubble/$name.json').readAsStringSync()) as Map);

OmrReviewItem _reviewItem(String name) => OmrReviewItem.fromJson(Map<String, dynamic>.from(
    (jsonDecode(File('test/fixtures/payloads/omr_review/$name.json').readAsStringSync()) as Map)['payload'] as Map));

// a 2 x 2 grey PNG
final _png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAAAAABX3VL4AAAADklEQVR4nGNgYGBgYAAAAAUAAXpeqz8AAAAASUVORK5CYII=');

void main() {
  setUp(() => AppConfig.lang = 'en');

  test('a run with no course: its own students (negative ids), where the ID comes from, the name area', () {
    final run = BubbleRun.fromJson(_fx('run_open'));
    expect(run.courseId, isNull);
    expect(run.students.open, isTrue);
    expect(run.students.idSource, BubbleIdSource.image);
    expect(run.idBox, [0.07, 0.24, 0.86, 0.05]);
    expect(run.templateId, isNotNull);
    expect(run.students.people, isNotEmpty);
    expect(run.students.people.every((p) => p.id < 0), isTrue);
    expect(run.students.people.map((p) => p.label), contains('Ali H. Hassan'));
  });

  test('the ID source travels by its server name', () {
    for (final s in BubbleIdSource.values) {
      expect(BubbleIdSourceWire.parse(s.wire), s);
    }
    expect(BubbleIdSource.fileName.wire, 'file_name');
    expect(BubbleIdSourceWire.parse(null), BubbleIdSource.bubble);
  });

  test('a pasted class list: the ID and the name in any order, Arabic digits, tabs and commas', () {
    final rows = parseClassList('2041 Ali Hassan\nSara Nabil, 2042\n\nسارة أحمد\t٢٠٤٣\nOmar Said\n   \n');
    expect(rows, [
      {'code': '2041', 'name': 'Ali Hassan'},
      {'code': '2042', 'name': 'Sara Nabil'},
      {'code': '2043', 'name': 'سارة أحمد'},
      {'code': '', 'name': 'Omar Said'},
    ]);
  });

  testWidgets('Grade papers: with no course, students in no course are offered, and bubble sheets only', (tester) async {
    (int?, String?, GradeKind?) picked = (null, null, null);
    await tester.pumpWidget(layoutHost(
        SingleChildScrollView(
            child: GradePapersBody(courses: const [], kinds: GradeKind.values, onPick: (p, k) => picked = (p.courseId, p.name, k))),
        scale: 1));
    await tester.tap(find.byKey(const ValueKey('grade.noCourse')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('grade.kind.essay')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('grade.kind.bubble')));
    expect(picked.$1, isNull);
    expect(picked.$3, GradeKind.bubble);
  });

  testWidgets('the new widgets fit at every size, in both languages', (tester) async {
    final many = BubbleStudents(open: true, idSource: BubbleIdSource.fileName, people: [
      for (var i = 1; i <= 30; i++) BubblePerson(id: -i, name: 'A student with a rather long full name number $i', code: '20${40 + i}'),
    ]);
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: BubbleIdSourceChoice(selected: BubbleIdSource.image, onPick: (_) {})));
    await expectNoLayoutErrors(tester, () => BubbleStudentsCard(students: const BubbleStudents(open: true), onPaste: () {}, onEdit: () {}));
    await expectNoLayoutErrors(tester, () => BubbleStudentsCard(students: many, onPaste: () {}, onEdit: () {}));
    await expectNoLayoutErrors(tester, () => BubbleIdSourceCard(source: BubbleIdSource.image, onChange: () {}, onMarkBox: () {}));
    await expectNoLayoutErrors(tester, () => BubbleIdSourceCard(source: BubbleIdSource.fileName, boxSet: true, onChange: () {}));
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: BubbleBoxPicker(image: _png, initial: const [0.1, 0.2, 0.5, 0.1], onDone: (_) {})));
  });

  testWidgets('review: a paper of a correction with no course can go to a new student, typed in', (tester) async {
    (String, String)? added;
    await tester.pumpWidget(layoutHost(
        ListView(padding: const EdgeInsets.all(16), children: [
          OmrReviewItemCard(
            item: _reviewItem('scan_item_4_no_match'),
            crop: null,
            fix: OmrFixCallbacks(onAssign: (_) {}, onFix: (_) {}, onNewStudent: (n, c) => added = (n, c)),
          ),
        ]),
        scale: 1));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(find.byKey(const ValueKey('omr.id.newAdd')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('omr.id.newName')), 'Huda Kamal');
    await tester.enterText(find.byKey(const ValueKey('omr.id.newCode')), '2060');
    await tester.tap(find.byKey(const ValueKey('omr.id.newAdd')));
    expect(added, ('Huda Kamal', '2060'));
  });
}
