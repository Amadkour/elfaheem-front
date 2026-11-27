// The parent pulse (D-305): parsing of children[].pulse (parent_pulse.dart) and the plain-language findings
// (parentInsightText), in Arabic and English.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/parent/parent_overview.dart';
import 'package:flutter_education_app/features/parent/parent_pulse.dart';
import 'package:flutter_education_app/features/parent/parent_pulse_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> pulseJson() => {
      'status': 'needs_you',
      'week': {'scheduled': 4, 'attended': 2, 'missed': 2, 'rate': 50, 'homework_due': 1, 'homework_missing': 1, 'homework_due_soon': 0, 'active_days': 3, 'last_active_days': 0},
      'missed_sessions': [
        {'session': 'M1', 'course_id': 1, 'course_ar': 'رياضيات', 'course_en': 'Maths', 'at': '2026-11-06T10:00:00'},
      ],
      'attendance_trend': [for (final r in [null, null, 100, null, 100, 50]) {'start': '2026-10-01T00:00:00', 'rate': r}],
      'grades': {'avg': 72.5, 'prev_avg': 80.0, 'class_avg': 75.0, 'mine_vs_class': 50.0, 'count': 2, 'failed': 1, 'trend': [for (final a in [null, 80, null, null, null, 72.5]) {'start': 'x', 'avg': a}]},
      'subjects': [
        {'course_id': 1, 'name_ar': 'رياضيات', 'name_en': 'Maths', 'progress': 30.0, 'avg': 50.0, 'class_avg': 75.0, 'missed': 2, 'weak_open': 0, 'tone': 'focus', 'teacher': {'id': 9, 'name': 'Mr T', 'image_url': null}},
        {'course_id': 2, 'name_ar': 'رسم', 'name_en': 'Arts', 'progress': 30.0, 'avg': 95.0, 'class_avg': null, 'missed': 0, 'weak_open': 0, 'tone': 'strength', 'teacher': null},
      ],
      'upcoming': [
        {'id': 'exam:3', 'source': 'exam', 'title': 'Midterm', 'starts_at': '2026-11-10T09:00:00'},
        {'id': 'session:4', 'source': 'course_session', 'title': 'L4', 'starts_at': '2026-11-09T09:00:00'},
      ],
      'roadmap': {'field': {'name_ar': 'برمجة', 'name_en': 'Programming'}, 'done': 1, 'total': 4, 'next': {'id': 5, 'name_ar': 'بايثون', 'name_en': 'Python', 'progress': 20, 'kind': 'continue'}},
      'insights': [
        {'code': 'missed_week', 'level': 'warn', 'params': {'count': 2, 'scheduled': 4}, 'action': {'kind': 'message_teacher', 'course_id': 1, 'teacher_id': 9}},
        {'code': 'homework_missing', 'level': 'warn', 'params': {'count': 1}, 'action': {'kind': 'open_report'}},
        {'code': 'focus_subject', 'level': 'info', 'params': {'course_ar': 'رياضيات', 'course_en': 'Maths', 'avg': 50}, 'action': null},
        {'code': 'strength', 'level': 'good', 'params': {'course_ar': 'رسم', 'course_en': 'Arts'}, 'action': null},
      ],
      'teachers': [
        {'id': 9, 'name': 'Mr T', 'image_url': null, 'course_id': 1, 'course_ar': 'رياضيات', 'course_en': 'Maths'},
      ],
    };

void main() {
  setUpAll(() => translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>);
  setUp(() => AppConfig.lang = 'en');
  tearDownAll(() => translation = {});

  test('parses every block', () {
    final p = ParentPulse.tryParse(pulseJson())!;
    expect(p.status, PulseStatus.needsYou);
    expect((p.week.scheduled, p.week.missed, p.week.rate, p.week.homeworkMissing), (4, 2, 50, 1));
    expect(p.attendanceTrend, [null, null, 100, null, 100, 50]);
    expect(p.grades!.delta, -7.5);
    expect(p.grades!.trend, [null, 80, null, null, null, 72.5]);
    expect(p.focus.single.name, 'Maths');
    expect(p.strengths.single.teacher, isNull);
    expect(p.upcoming.first.title, 'L4', reason: 'sorted by start');
    expect((p.roadmap!.field, p.roadmap!.next, p.roadmap!.ratio), ('Programming', 'Python', 0.25));
    expect(p.insights.first.action!.kind, PulseActionKind.messageTeacher);
    expect(p.insights.first.action!.courseId, 1);
    expect(p.insights[2].action, isNull);
    expect(p.teacherOf(1)!.name, 'Mr T');
    expect(p.teacherOf(2), isNull);
  });

  test('null / older server → no pulse; unknown status → quiet', () {
    expect(ParentPulse.tryParse(null), isNull);
    final row = ParentChildOverview.fromJson({'child': {'id': 3, 'name': 'A'}});
    expect(row.pulse, isNull);
    expect(ParentPulse.tryParse({'status': 'brand_new'})!.status, PulseStatus.quiet);
    expect(ParentPulse.tryParse(const {})!.insights, isEmpty);
  });

  test('findings read as sentences, with plural forms, in both languages', () {
    final p = ParentPulse.tryParse(pulseJson())!;
    expect(parentInsightText(p.insights[0], 'Ahmed Ali'), allOf(contains('Ahmed'), contains('2 classes'), isNot(contains('{'))));
    expect(parentInsightText(p.insights[1], 'Ahmed'), contains('1 homework'));
    expect(parentInsightText(p.insights[2], 'Ahmed'), allOf(contains('Maths'), contains('50%')));
    AppConfig.lang = 'ar';
    expect(parentInsightText(p.insights[0], 'أحمد علي'), allOf(contains('أحمد'), contains('حصتين'), isNot(contains('{'))));
    expect(parentInsightText(p.insights[2], 'أحمد'), contains('رياضيات'));
    expect(parentInsightText(const PulseInsight(code: 'from_the_future'), 'x'), 'from_the_future');
  });
}
