// A course's students page (D-870 – D-874) against REAL server payloads (test/fixtures/payloads/course_students*.json,
// written by ../back/tests/org_v2/e2e_course_students.py with CS_DUMP=<this folder>): the page, the summary, the
// counts, each student's verdict and reason, the nudge's answer; an older server's page still parses; and the
// sentences the cards draw from them, in both languages.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/teacher/sessions/students/course_student_provider.dart';
import 'package:flutter_education_app/features/teacher/sessions/students/course_student_screen.dart' show courseStudentsExport;
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _payload(String name) {
  final f = File('test/fixtures/payloads/$name.json');
  expect(f.existsSync(), isTrue, reason: '$name.json missing: run ../back/tests/org_v2/e2e_course_students.py with CS_DUMP');
  return Map<String, dynamic>.from(jsonDecode(f.readAsStringSync())['payload'] as Map);
}

void main() {
  setUp(() => AppConfig.lang = 'en');

  test('the page: items, verdicts, reasons, summary, counts', () {
    final p = CourseStudentsPage.fromJson(_payload('course_students'));
    expect(p.total, 5);
    expect(p.items, hasLength(5));
    expect(p.nudgeEnabled, isTrue);
    expect(p.cooldownHours, 24);
    final s = p.summary!;
    expect([s.enrolled, s.activeWeek, s.atRisk, s.completed, s.lowNudgeable, s.lowWithParent], [5, 1, 2, 1, 2, 1]);
    expect(s.avgProgress, 40.0);
    expect(p.counts[StudentFilter.low], 2);
    expect(p.counts[StudentFilter.completed], 1);

    final byName = {for (final x in p.items) x.name.split(' ').first: x};
    final amal = byName['Amal']!;
    expect(amal.state, 'active');
    expect(amal.lessonsDone, 3);
    expect(amal.lessonsTotal, 4);
    expect(amal.examAvg, 90.0);
    expect(amal.lastActiveAt!.isUtc, isTrue);
    expect(amal.atRisk, isFalse);
    expect(amal.parentCount, 1);

    final basel = byName['Basel']!;
    expect(basel.atRisk, isTrue);
    expect(basel.risk!.code, 'no_activity');
    expect(basel.risk!.days, 10);
    expect(riskText(basel.risk!), 'No activity for 10 days');
    expect(basel.canNudge, isTrue);
    expect(basel.parentCount, 2);

    expect(byName['Cyrine']!.state, 'completed');
    expect(byName['Ehab']!.state, 'new');
    expect(byName['Ehab']!.lastActiveAt, isNull);
    expect(byName['Farah']!.state, 'inactive');
  });

  test('the nudge answer: sent, parents, skipped with the next time', () {
    final one = NudgeResult.fromJson(_payload('course_students_nudge'));
    expect((one.sent, one.parents, one.skipped.length), (1, 2, 0));
    expect(one.nudgedAt, isNotNull);
    expect(nudgeResultText(one), 'Nudge sent to 1 student · 2 parents told');

    final r = NudgeResult.fromJson(_payload('course_students_nudge_skipped'));
    expect(r.sent, 1);
    expect([for (final s in r.skipped) s.code], ['nudged_recently', 'not_enrolled']);
    expect(r.skipped.first.nextAt, isNotNull);
    expect(nudgeResultText(r), contains('1 skipped (nudged in the last 24 h)'));
  });

  test('an older server\'s page still parses (no summary, no verdicts)', () {
    final p = CourseStudentsPage.fromJson({
      'items': [
        {'id': 1, 'name': 'Sara', 'gmail': 's@x.io', 'enrolled_at': '2026-10-01T10:00:00', 'status': 'active', 'progress_percentage': 100},
        {'id': 2, 'name': 'Omar', 'gmail': 'o@x.io', 'enrolled_at': '2026-10-01T10:00:00', 'status': 'active', 'progress_percentage': 30},
      ],
      'total': 2,
      'avg_progress': 65,
      'completed_count': 1,
    });
    expect(p.summary, isNull);
    expect(p.nudgeEnabled, isFalse);
    expect(p.items.first.state, 'completed');
    expect(p.items.last.state, 'active');
    expect(p.items.last.atRisk, isFalse);
    final s = CourseStudentsSummaryFallback.of(p);
    expect((s.enrolled, s.avgProgress, s.completed), (2, 65.0, 1));
  });

  test('server times are UTC; sentences in both languages', () {
    expect(parseServerUtc('2026-11-13T10:00:00')!.isUtc, isTrue);
    expect(parseServerUtc('2026-11-13T10:00:00')!.hour, 10);
    expect(parseServerUtc('2026-11-13T12:00:00+02:00')!.hour, 10);
    expect(parseServerUtc(null), isNull);
    expect(parseServerUtc('nope'), isNull);

    final now = DateTime.utc(2026, 11, 13, 12);
    expect(agoText(now.subtract(const Duration(hours: 3)), now), '3 h ago');
    expect(nudgedText(now.subtract(const Duration(hours: 3)), now), 'Nudged 3 h ago');
    expect(lastActiveText(null, now), 'Never active');
    expect(lastActiveText(now.subtract(const Duration(days: 2)), now), 'Active 2 days ago');
    expect(riskText(const StudentRisk(code: 'behind_pace', expected: 60, progress: 20)), 'Behind the plan: 20% of 60%');
    expect(riskText(const StudentRisk(code: 'never_started', days: 1)), 'Not started · enrolled 1 day ago');
    expect(lessonsText(3, 4), 'Lessons 3/4');
    expect(lessonsText(0, 0), '');
    expect(nudgePreview('Hi {name}, back to {course}!', name: 'Basel Idle', course: 'Physics'), 'Hi Basel, back to Physics!');

    AppConfig.lang = 'ar';
    expect(riskText(const StudentRisk(code: 'no_activity', days: 12)), 'لا نشاط منذ 12 يومًا');
    expect(riskText(const StudentRisk(code: 'no_activity', days: 2)), 'لا نشاط منذ يومين');
    expect(agoText(now.subtract(const Duration(hours: 3)), now), 'منذ 3 ساعات');
    expect(nudgeTemplate(), contains('{name}'));
    expect(nudgeTemplate(), contains('{course}'));
  });

  test('the export carries both languages\' headers and every student', () {
    final p = CourseStudentsPage.fromJson(_payload('course_students'));
    final e = courseStudentsExport(p.items, courseName: 'Physics', filter: StudentFilter.low);
    expect(e.rows, hasLength(5));
    expect(e.column('name')!.labelIn('ar'), 'الطالب');
    expect(e.column('name')!.labelIn('en'), 'Student');
    expect(e.filters.values, contains('Low progress'));
    expect(e.rows.firstWhere((r) => r['name'] == 'Basel Idle')['reason'], 'No activity for 10 days');
  });
}
