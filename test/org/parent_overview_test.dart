// GET /api/v1/parent/overview → ParentOverviewData (pure), plus the older-server detection and the teacher
// block of GET /me/home (TeacherHomeExtra).
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/parent/parent_overview.dart';
import 'package:flutter_education_app/features/teacher/home/teacher_home_extra.dart';
import 'package:flutter_test/flutter_test.dart';

final full = <String, dynamic>{
  'now': '2026-10-28T08:30:00+00:00',
  'today_date': '2026-10-28',
  'timezone': 'Africa/Cairo',
  'children': [
    {
      'child': {'id': 7, 'name': 'Omar', 'image_url': 'https://x/omar.png', 'is_active': true, 'linked_at': '2026-09-01T10:00:00Z'},
      'today_sessions': [
        {'id': 2, 'source': 'course_session', 'title': 'Physics', 'subtitle': 'Lecture 4', 'starts_at': '2026-10-28T11:00:00+00:00', 'ends_at': '2026-10-28T12:30:00+00:00', 'course_id': 3, 'kind': 'lecture', 'mode': 'online'},
        {'id': 1, 'source': 'timetable', 'title': 'Math', 'subtitle': null, 'starts_at': '2026-10-28T08:00:00+00:00', 'ends_at': '2026-10-28T09:30:00+00:00', 'course_id': 4, 'location': 'Room 2'},
      ],
      'attendance_pct_30d': 87,
      'latest_marks': [
        {'exam_id': 11, 'exam': 'Quiz 3', 'course_id': 3, 'course_ar': 'فيزياء', 'course_en': 'Physics', 'percentage': 92.5, 'passed': true, 'submitted_at': '2026-10-27T15:00:00'},
        {'exam_id': 10, 'exam': 'Midterm', 'course_id': 4, 'course_ar': 'رياضيات', 'course_en': 'Math', 'percentage': 41.0, 'passed': false, 'submitted_at': '2026-10-20T15:00:00'},
        {'exam_id': 9, 'exam': 'Quiz 2', 'course_id': 4, 'course_ar': null, 'course_en': 'Math', 'percentage': null, 'passed': null, 'submitted_at': null},
      ],
      'open_alerts': 2,
      'next_exam': {'id': 12, 'name': 'Final', 'course_id': 3, 'starts_at': '2026-11-02T09:00:00', 'ends_at': '2026-11-02T11:00:00', 'source': 'course'},
      'courses': 5,
    },
    {
      'child': {'id': 8, 'name': 'Sara', 'image_url': null, 'is_active': false, 'linked_at': null},
      'today_sessions': [],
      'attendance_pct_30d': null,
      'latest_marks': [],
      'open_alerts': 0,
      'next_exam': null,
      'courses': 0,
    },
  ],
  'alerts_total': 2,
  'requests': [
    {'id': 1, 'status': 'pending'},
    {'id': 2, 'status': 'approved'},
    {'id': 3, 'status': 'pending'},
  ],
  'link_config': {'mode': 'advanced', 'fields': []},
};

void main() {
  setUp(() => AppConfig.lang = 'ar');

  test('full payload: children, today sorted by time, attendance, marks, next exam, alerts, requests', () {
    final d = ParentOverviewData.fromJson(full);
    expect(d.now, DateTime.utc(2026, 10, 28, 8, 30));
    expect(d.todayDate, '2026-10-28');
    expect(d.timezone, 'Africa/Cairo');
    expect(d.children.length, 2);
    expect(d.alertsTotal, 2);
    expect(d.pendingRequests, 2);
    expect(d.requests.length, 3);
    expect(d.linkConfig['mode'], 'advanced');
    expect(d.hasChildren, isTrue);
    expect(d.sessionsToday, 2);

    final omar = d.children.first;
    expect(omar.id, 7);
    expect(omar.name, 'Omar');
    expect(omar.imageUrl, 'https://x/omar.png');
    expect(omar.isActive, isTrue);
    expect(omar.linkedAt, DateTime.utc(2026, 9, 1, 10));
    expect(omar.child['id'], 7); // the /parent/children row, kept for seeding the Link / Children tabs
    expect(omar.courses, 5);
    expect(omar.openAlerts, 2);
    expect(omar.attendancePct30d, 87);
    // sorted by starts_at even when the server sends them out of order
    expect(omar.todaySessions.map((e) => e.title).toList(), ['Math', 'Physics']);
    expect(omar.todaySessions.first.location, 'Room 2');
    expect(omar.todaySessions.first.subtitle, ''); // null → empty, never "null"
    expect(omar.todaySessions.last.mode, 'online');
    expect(omar.todaySessions.last.startsAt, DateTime.utc(2026, 10, 28, 11));
    expect(omar.todaySessions.first.wallMinutes((u) => u), 8 * 60);

    expect(omar.latestMarks.length, 3);
    final quiz = omar.latestMarks.first;
    expect(quiz.exam, 'Quiz 3');
    expect(quiz.percentage, 92.5);
    expect(quiz.passed, isTrue);
    expect(quiz.course, 'فيزياء');
    AppConfig.lang = 'en';
    expect(quiz.course, 'Physics');
    expect(omar.latestMarks.last.course, 'Math'); // missing Arabic → the other language
    expect(omar.latestMarks.last.percentage, isNull);
    expect(omar.latestMarks.last.passed, isNull);
    expect(omar.latestMarks.last.submittedAt, isNull);

    final exam = omar.nextExam!;
    expect(exam.name, 'Final');
    expect(exam.source, 'course');
    expect(exam.startsAt, DateTime.utc(2026, 11, 2, 9)); // naive timestamp = UTC

    final sara = d.children.last;
    expect(sara.imageUrl, '');
    expect(sara.isActive, isFalse);
    expect(sara.linkedAt, isNull);
    expect(sara.attendancePct30d, isNull);
    expect(sara.nextExam, isNull);
    expect(sara.latestMarks, isEmpty);
    expect(sara.todaySessions, isEmpty);
  });

  test('empty / partial payloads never throw', () {
    final e = ParentOverviewData.fromJson(const {});
    expect(e.children, isEmpty);
    expect(e.hasChildren, isFalse);
    expect(e.alertsTotal, 0);
    expect(e.pendingRequests, 0);
    expect(e.sessionsToday, 0);
    expect(e.linkConfig, isEmpty);
    expect(e.now, isNull);

    final odd = ParentOverviewData.fromJson({
      'children': [
        {'child': null, 'id': 3, 'attendance_pct_30d': 140, 'latest_marks': 'nope', 'today_sessions': null},
        'garbage',
      ],
      'alerts_total': '4',
      'requests': null,
    });
    expect(odd.children.length, 1);
    expect(odd.children.first.id, 3);
    expect(odd.children.first.name, '');
    expect(odd.children.first.attendancePct30d, 100); // clamped
    expect(odd.alertsTotal, 4);
  });

  test('parentUtc: naive timestamps are UTC, zoned ones are converted', () {
    expect(parentUtc('2026-10-28T09:00:00'), DateTime.utc(2026, 10, 28, 9));
    expect(parentUtc('2026-10-28T09:00:00Z'), DateTime.utc(2026, 10, 28, 9));
    expect(parentUtc('2026-10-28T11:00:00+02:00'), DateTime.utc(2026, 10, 28, 9));
    expect(parentUtc(null), isNull);
    expect(parentUtc('not a date'), isNull);
  });

  test('older server: only FastAPI\'s bare 404 / a 405 hide the Today tab', () {
    expect(parentOverviewUnsupported(const ApiException(statusCode: 404, message: 'x', body: {'detail': 'Not Found'})), isTrue);
    expect(parentOverviewUnsupported(const ApiException(statusCode: 405, message: 'x')), isTrue);
    expect(parentOverviewUnsupported(const ApiException(statusCode: 404, message: 'x', body: {'detail': {'code': 'NOT_FOUND'}})), isFalse);
    expect(parentOverviewUnsupported(const ApiException(statusCode: 403, message: 'x', body: {'detail': 'Not Found'})), isFalse);
    expect(parentOverviewUnsupported(const ApiException(statusCode: 500, message: 'x')), isFalse);
  });

  test('teacher block of /me/home: earnings, pending, inbox preview, unread, optional series', () {
    final x = TeacherHomeExtra.fromJson({
      'pending': {'attendance_missing': 2, 'grading': 5, 'materials_missing': 0, 'enrollment_requests': 1},
      'teaching_courses': 4,
      'earnings': {'month': 1234.5, 'pending_payout': '300'},
      'inbox_preview': [
        {'key': 'a', 'kind': 'form', 'title': 'Fill the form', 'segment': 'todo'},
        'junk',
      ],
      'notifications_unread': 7,
      'enrollments_series': [1, 2, 'x', 3.5],
    });
    expect(x.pending['grading'], 5);
    expect(x.teachingCourses, 4);
    expect(x.earningsMonth, 1234.5);
    expect(x.pendingPayout, 300);
    expect(x.hasEarnings, isTrue);
    expect(x.inboxPreview.length, 1);
    expect(x.inboxPreview.first['title'], 'Fill the form');
    expect(x.notificationsUnread, 7);
    expect(x.enrollmentSeries, [1.0, 2.0, 3.5]);

    final bare = TeacherHomeExtra.fromJson(const {});
    expect(bare.hasEarnings, isFalse);
    expect(bare.pendingPayout, isNull);
    expect(bare.inboxPreview, isEmpty);
    expect(bare.enrollmentSeries, isEmpty);
    expect(bare.notificationsUnread, isNull);

    expect(teacherHomeExtraMissing(const ApiException(statusCode: 404, message: 'x', body: {'detail': 'Not Found'})), isTrue);
    expect(teacherHomeExtraMissing(const ApiException(statusCode: 403, message: 'x', body: {'detail': 'role_not_supported'})), isFalse);
  });
}
