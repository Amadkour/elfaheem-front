// Premium exports (grid, summary, Excel, Word, PDF), the wizard's student count.
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/org/org_schedule_export.dart';
import 'package:flutter_education_app/features/org/org_schedule_planning.dart';
import 'package:flutter_education_app/features/org/org_schedule_versions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

Map<String, dynamic> slot(int id, int course, String day, int period, {int? room, int? teacher, int? asst, String kind = 'lecture', int group = 1, String? block}) => {
      'id': id,
      'course_id': course,
      'day': day,
      'period_id': period,
      'room_id': room,
      'teacher_id': teacher,
      'assistant_id': asst,
      'kind': kind,
      'group_no': group,
      'block_id': ?block,
    };

const periods = [
  {'id': 3, 'label': 'P3', 'start_time': '10:00:00', 'end_time': '11:00:00'},
  {'id': 1, 'label': 'P1', 'start_time': '08:00', 'end_time': '09:00'},
  {'id': 2, 'label': 'P2', 'start_time': '09:00', 'end_time': '10:30'},
];

const names = TimetableNames(courses: {7: 'Math & <Logic>', 8: 'Physics'}, people: {10: 'Dr. A', 11: 'Dr. B', 20: 'Eng. C'}, rooms: {1: 'Hall 1', 2: 'Lab 2'});

final slots = [
  slot(1, 7, 'sunday', 1, room: 1, teacher: 10, block: 'b1'),
  slot(2, 7, 'sunday', 2, room: 1, teacher: 10, block: 'b1'), // a double session: P1 + P2
  slot(3, 8, 'sunday', 3, room: 2, teacher: 11),
  slot(4, 8, 'monday', 1, room: 2, asst: 20, kind: 'lab', group: 1),
  slot(5, 8, 'monday', 1, room: 1, asst: 20, kind: 'lab', group: 2), // parallel groups share the cell
];

Map<String, String> unzip(Uint8List bytes) => {for (final f in ZipDecoder().decodeBytes(bytes)) if (f.isFile) f.name: String.fromCharCodes(f.content)};

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('grid & summary', () {
    test('a session over consecutive periods is one merged cell; parallel sessions are stacked; spans fill the week', () {
      final g = TimetableGrid.build(slots, periods, days: const ['sunday', 'monday', 'tuesday']);
      expect(g.periods.map((p) => p['id']), [1, 2, 3]); // ordered by start time
      expect(g.days, ['sunday', 'monday', 'tuesday']);
      final sun = g.rows['sunday']!;
      expect(sun.map((e) => e.span), [2, 1]);
      expect(sun.first.sessions.single['id'], 1);
      final mon = g.rows['monday']!;
      expect(mon.first.sessions.map((s) => s['group_no']), [1, 2]);
      for (final d in g.days) {
        expect(g.rows[d]!.fold(0, (a, e) => a + e.span), periods.length);
      }
      expect(g.rows['tuesday']!.every((e) => e.isEmpty), isTrue);
    });

    test('summary counts sessions by block, real hours, the busiest day and each course', () {
      final s = TimetableSummary.of(slots, periods);
      expect(s.sessions, 4); // b1 is one session
      expect(s.periods, 5);
      expect(s.minutes, 60 + 90 + 60 + 60 + 60);
      expect(s.busiestDay, 'sunday');
      expect(s.byDay, {'sunday': 3, 'monday': 2});
      expect([s.first, s.last], ['08:00', '11:00']);
      final physics = s.courses.firstWhere((c) => c.courseId == 8);
      expect([physics.lectures, physics.labs, physics.periods], [1, 2, 3]);
    });

    test('scopes: one sheet per member with only their sessions; one member; the whole timetable', () {
      final teachers = exportSheets(slots, names, periods, scope: 'teachers');
      expect(teachers.map((s) => s.title), ['Dr. A', 'Dr. B']);
      expect(teachers.first.slots.map((s) => s['id']), [1, 2]);
      final asst = exportSheets(slots, names, periods, scope: 'member', member: const TimetableMember('assistant', 20));
      expect(asst.single.slots, hasLength(2));
      expect(asst.single.view, ExportView.assistant);
      expect(exportSheets(slots, names, periods, scope: 'rooms'), hasLength(2));
      expect(exportSheets(slots, names, periods, scope: 'full').single.slots, hasLength(5));
      expect(exportSheets(slots, names, periods, scope: 'member'), isEmpty);
    });

    test('a cell shows what its reader needs: a teacher sees the room, a room sees the staff', () {
      expect(sessionLines(slots.first, ExportView.teacher, names), ['Math & <Logic>', 'Lecture · G1', 'Hall 1']);
      expect(sessionLines(slots[3], ExportView.room, names), ['Physics', 'Lab · G1', 'Eng. C']);
    });
  });

  group('files', () {
    ExportBook book(String scope) =>
        ExportBook(title: 'Term 1', subtitle: 'version 4', sheets: exportSheets(slots, names, periods, scope: scope, days: const ['sunday', 'monday']), names: names, generatedAt: DateTime(2026, 10, 22, 9));

    test('Excel: an overview sheet + one per member, merged cells, escaped text, every part well-formed', () {
      final files = unzip(timetableXlsx(book('teachers')));
      for (final e in files.entries) {
        expect(() => XmlDocument.parse(e.value), returnsNormally, reason: e.key);
      }
      final wb = XmlDocument.parse(files['xl/workbook.xml']!);
      expect(wb.findAllElements('sheet').map((s) => s.getAttribute('name')), ['Overview', 'Dr. A', 'Dr. B']);
      final a = files['xl/worksheets/sheet2.xml']!;
      expect(a, contains('<mergeCell ref="B5:C5"/>')); // Sunday P1–P2, the double session
      expect(a, contains('Math &amp; &lt;Logic&gt;'));
      expect(files['xl/worksheets/sheet1.xml'], contains('location="\'Dr. A\'!A1"'));
      final styles = XmlDocument.parse(files['xl/styles.xml']!);
      final xfs = styles.findAllElements('cellXfs').single.findElements('xf').length;
      final used = RegExp(r' s="(\d+)"').allMatches(files.entries.where((e) => e.key.startsWith('xl/worksheets')).map((e) => e.value).join()).map((m) => int.parse(m[1]!));
      expect(used.every((s) => s < xfs), isTrue);
    });

    test('Excel in Arabic is right-to-left; sheet names stay valid and unique', () {
      AppConfig.lang = 'ar';
      expect(unzip(timetableXlsx(book('full')))['xl/worksheets/sheet1.xml'], contains('rightToLeft="1"'));
      final taken = <String>{};
      expect(sheetName('a/b:c*d?[e]', taken), 'a b c d  e');
      expect(sheetName('A B C D  E', taken), 'A B C D  E (2)');
      expect(sheetName('x' * 40, taken).length, lessThanOrEqualTo(31));
    });

    test('Word: landscape, merged cells by grid span, a page per member after the overview', () {
      final files = unzip(timetableDocx(book('teachers')));
      final doc = files['word/document.xml']!;
      expect(() => XmlDocument.parse(doc), returnsNormally);
      expect(doc, contains('w:orient="landscape"'));
      expect(doc, contains('<w:gridSpan w:val="2"/>'));
      expect(RegExp('w:type="page"').allMatches(doc).length, 2); // overview | Dr. A | Dr. B
      expect(files.keys, containsAll(['[Content_Types].xml', '_rels/.rels', 'word/styles.xml']));
    });

    test('PDF: built with the bundled Arabic fonts', () async {
      AppConfig.lang = 'ar';
      final bytes = await timetablePdf(book('rooms'),
          regular: ByteData.sublistView(File('assets/fonts/Tajawal-Regular.ttf').readAsBytesSync()), bold: ByteData.sublistView(File('assets/fonts/Bahij_TheSansArabic-Bold.ttf').readAsBytesSync()));
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, greaterThan(2000));
      final out = Platform.environment['EXPORT_SAMPLES'];
      if (out != null) {
        File('$out/sample.pdf').writeAsBytesSync(bytes);
        AppConfig.lang = 'en';
        File('$out/sample.xlsx').writeAsBytesSync(timetableXlsx(book('teachers')));
        File('$out/sample.docx').writeAsBytesSync(timetableDocx(book('teachers')));
      }
    });
  });

  group('wizard student count', () {
    test('one count for every selected course keeps each course\'s groups; subscribed sends no estimate', () {
      const existing = {7: CoursePlan(courseId: 7, lectureGroupSize: 40, labGroups: 3, countSource: 'history', expectedStudents: 64)};
      final manual = applyStudentCount(existing, [7, 8], source: 'manual', count: 120);
      expect(manual.map((p) => p.toBody()['expected_students']), [120, 120]);
      expect(manual.first.lectureGroupSize, 40);
      expect(manual.first.labGroups, 3);
      final enrolled = applyStudentCount(existing, [7], source: 'enrolled');
      expect(enrolled.single.toBody()['expected_students'], isNull);
      expect(enrolled.single.toBody()['count_source'], 'enrolled');
    });

    test('the term\'s courses are the ones planned for it', () {
      expect(termCourseIds([
        {'id': 7, 'term_id': 3},
        {'id': 8, 'term_id': 4},
        {'id': 9, 'term_id': null},
      ], 3), {7});
    });
  });
}
