// GET /me/home (Track B.4): payload parsing (student + teacher block passthrough), next-up selection, the
// organization slices, the older-server decision and the legacy composition of MeHomeService.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/home/me_home.dart';
import 'package:flutter_test/flutter_test.dart';

String iso(DateTime d) => d.toUtc().toIso8601String().replaceAll('Z', ''); // the server sends naive UTC

final now = DateTime.utc(2026, 10, 28, 9, 0);

Map<String, dynamic> event(String id, DateTime s, DateTime e,
        {String source = 'course_session', int? orgId, int? courseId, String? status, String? kind, String title = 'T'}) =>
    {
      'id': id,
      'source': source,
      'title': title,
      'subtitle': null,
      'starts_at': iso(s),
      'ends_at': iso(e),
      'org_id': orgId,
      'org': orgId == null ? null : {'id': orgId, 'name_ar': 'ج', 'name_en': 'U'},
      'course_id': courseId,
      'meeting_id': source == 'meeting' ? 5 : null,
      'kind': kind,
      'my_status': status,
    };

Map<String, dynamic> studentPayload() => {
      'now': iso(now),
      'today_date': '2026-10-28',
      'timezone': 'Africa/Cairo',
      'role': 'student',
      'orgs_enabled': true,
      'today': [
        event('c', now.add(const Duration(hours: 3)), now.add(const Duration(hours: 4)), source: 'exam', orgId: 4),
        event('a', now.subtract(const Duration(hours: 2)), now.subtract(const Duration(hours: 1)), courseId: 1),
        event('b', now.subtract(const Duration(minutes: 10)), now.add(const Duration(minutes: 50)), source: 'timetable', orgId: 4, kind: 'lab'),
      ],
      'upcoming': [
        event('u2', now.add(const Duration(days: 2)), now.add(const Duration(days: 2, hours: 1))),
        event('u1', now.add(const Duration(days: 1)), now.add(const Duration(days: 1, hours: 1)), source: 'meeting', orgId: 9),
      ],
      'attention': {
        'counts': {'home': 3, 'org.people': 2},
        'total': 5,
        'items': [
          {'key': 'forms', 'tab': 'home', 'count': 2},
          {'key': 'exam', 'tab': 'home', 'count': 1, 'org_id': 4},
          {'key': 'join', 'tab': 'org.people', 'count': 2, 'org_id': 9},
        ],
      },
      'inbox_preview': [
        {'key': 'f1', 'kind': 'form', 'segment': 'todo', 'title': 'Form', 'org_id': 4},
        {'key': 'n1', 'kind': 'announcement', 'segment': 'news', 'title': 'News', 'org_id': 9},
      ],
      'inbox_counts': {'todo': 1, 'news': 1, 'offers': 0, 'done': 2, 'overdue': 0, 'due_soon': 1, 'mandatory': 1},
      'notifications_unread': 4,
      'org_overview': {
        'items': [
          {'organization': {'id': 4, 'status': 'approved', 'name_en': 'U'}, 'roles': ['student'], 'manage': null, 'todo': {'total': 1}},
          {'organization': {'id': 9, 'status': 'approved', 'name_en': 'F'}, 'roles': ['teacher'], 'manage': {'is_admin': true}},
        ],
        'default_org_id': 4,
        'pending_total': 1,
      },
      'courses_progress': [
        {
          'course_id': 11,
          'name_ar': 'رياضيات',
          'name_en': 'Maths',
          'image_url': null,
          'progress': 42.5,
          'plan': 'monthly',
          'expires_at': null,
          'next_lecture': {'id': 7, 'name': 'Limits', 'scheduled_at': iso(now.add(const Duration(days: 1))), 'duration_minutes': 90, 'track': 'lecture'},
        },
        {'course_id': 12, 'name_ar': '', 'name_en': 'Physics', 'progress': 130, 'next_lecture': null},
      ],
    };

ApiException err(int status, {dynamic body, String? code}) => ApiException(statusCode: status, message: 'x', body: body, code: code);

void main() {
  setUp(() => AppConfig.lang = 'en');

  test('parses the student payload', () {
    final h = MeHome.fromJson(studentPayload());
    expect(h.now, now);
    expect(h.todayDate, '2026-10-28');
    expect(h.timezone, 'Africa/Cairo');
    expect(h.role, 'student');
    expect(h.orgsEnabled, isTrue);
    expect(h.legacy, isFalse);
    // sorted by start
    expect(h.today.map((e) => e.id).toList(), ['a', 'b', 'c']);
    expect(h.upcoming.map((e) => e.id).toList(), ['u1', 'u2']);
    expect(h.today[1].kind, 'lab');
    expect(h.today[1].orgName, 'U');
    expect(h.upcoming.first.meetingId, 5);
    expect(h.attentionCount('home'), 3);
    expect(h.attentionCount('home', orgId: 4), 1);
    expect(h.attentionCount('org.people'), 2);
    expect(h.attentionTotal, 5);
    expect(h.inboxTodo, 1);
    expect(h.inboxDueSoon, 1);
    expect(h.inboxOverdue, 0);
    expect(h.inboxPreview.length, 2);
    expect(h.notificationsUnread, 4);
    expect(h.coursesProgress.length, 2);
    expect(h.coursesProgress.first.progress, 42.5);
    expect(h.coursesProgress.first.nextLecture?.name, 'Limits');
    expect(h.coursesProgress.first.nextLecture?.durationMinutes, 90);
    expect(h.coursesProgress.first.name('ar'), 'رياضيات');
    expect(h.coursesProgress.first.name('en'), 'Maths');
    expect(h.coursesProgress[1].progress, 100); // clamped
    expect(h.coursesProgress[1].name('ar'), 'Physics'); // falls back to the other language
    expect(h.coursesProgress[1].nextLecture, isNull);
    expect(h.teacher, isNull);
    AppConfig.lang = 'ar';
    expect(MeHome.fromJson(studentPayload()).today[1].orgName, 'ج');
  });

  test('an empty / malformed payload never throws', () {
    final h = MeHome.fromJson({'today': 'nope', 'attention': 3, 'courses_progress': [1, 2], 'inbox_counts': {'todo': 'x'}});
    expect(h.today, isEmpty);
    expect(h.coursesProgress, isEmpty);
    expect(h.inboxTodo, 0);
    expect(h.orgOverview, isNull);
    expect(h.orgEntries, isEmpty);
    expect(h.nextUp(now), isNull);
    expect(MeHome.empty.legacy, isTrue);
  });

  test('the teacher block passes through', () {
    final p = studentPayload()
      ..remove('courses_progress')
      ..['role'] = 'teacher'
      ..['teaching_today'] = [event('b', now, now.add(const Duration(hours: 1)), courseId: 3)]
      ..['pending'] = {'attendance_missing': 2, 'materials_missing': 0, 'grading': 7, 'enrollment_requests': 1}
      ..['teaching_courses'] = 5
      ..['earnings'] = {'month': 1250.5, 'pending_payout': 300};
    final h = MeHome.fromJson(p);
    expect(h.coursesProgress, isEmpty);
    final tch = h.teacher!;
    expect(tch.teachingToday.single.courseId, 3);
    expect(tch.pending, {'attendance_missing': 2, 'materials_missing': 0, 'grading': 7, 'enrollment_requests': 1});
    expect(tch.teachingCourses, 5);
    expect(tch.earningsMonth, 1250.5);
    expect(tch.pendingPayout, 300);
  });

  test('next up: the running event, else the next to start; declined meetings skipped; none once the day is over', () {
    final h = MeHome.fromJson(studentPayload());
    final live = h.nextUp(now)!;
    expect(live.event.id, 'b');
    expect(live.live, isTrue);
    final later = h.nextUp(now.add(const Duration(hours: 1)))!;
    expect(later.event.id, 'c');
    expect(later.live, isFalse);
    expect(h.nextUp(now.add(const Duration(hours: 5))), isNull);
    expect(h.firstUpcoming?.id, 'u1');

    final declined = MeHome.fromJson({
      'today': [
        event('m', now.add(const Duration(hours: 1)), now.add(const Duration(hours: 2)), source: 'meeting', status: 'declined'),
        event('s', now.add(const Duration(hours: 2)), now.add(const Duration(hours: 3))),
      ],
    });
    expect(declined.nextUp(now)!.event.id, 's');
  });

  test('organization slices: entry, today, inbox preview', () {
    final h = MeHome.fromJson(studentPayload());
    expect(h.orgEntry(4)?['roles'], ['student']);
    expect(h.orgEntry(9)?['manage'], {'is_admin': true});
    expect(h.orgEntry(77), isNull);
    expect(h.todayOf(4).map((e) => e.id).toList(), ['b', 'c']);
    expect(h.todayOf(9), isEmpty);
    expect(h.upcomingOf(9).single.id, 'u1');
    expect(h.inboxPreviewOf(4).single['key'], 'f1');
    expect(h.inboxPreviewOf(9).single['key'], 'n1');
    expect(h.inboxPreviewOf(1), isEmpty);
  });

  test('older-server decision: bare 404 / 405 → legacy, 403 role_not_supported → unsupported, else failed', () {
    expect(meHomeOutcomeOf(err(404, body: {'detail': 'Not Found'})), MeHomeOutcome.legacy);
    expect(meHomeOutcomeOf(err(404, body: '{"detail":"Not Found"}')), MeHomeOutcome.legacy);
    expect(meHomeOutcomeOf(err(405)), MeHomeOutcome.legacy);
    expect(meHomeOutcomeOf(err(404, body: {'detail': {'code': 'not_found', 'message': 'x'}}, code: 'not_found')), MeHomeOutcome.failed);
    expect(meHomeOutcomeOf(err(403, code: 'role_not_supported')), MeHomeOutcome.unsupported);
    expect(meHomeOutcomeOf(err(403, code: 'orgs_disabled')), MeHomeOutcome.failed);
    expect(meHomeOutcomeOf(err(0)), MeHomeOutcome.failed);
    expect(meHomeOutcomeOf(err(500)), MeHomeOutcome.failed);
  });

  test('service: the payload is kept, a failed refresh keeps the last home, a signed-out user makes no call', () async {
    var calls = 0;
    var fail = false;
    final svc = MeHomeService(
      fetch: (p, {query}) async {
        calls++;
        if (fail) throw err(500);
        return studentPayload();
      },
      token: () async => 'tok',
      clock: () => now,
    );
    expect(svc.home, isNull);
    await svc.ensure();
    expect(calls, 1);
    expect(svc.home?.notificationsUnread, 4);
    expect(svc.outcome, MeHomeOutcome.ok);
    await svc.ensure(); // cached and fresh → no call
    expect(calls, 1);
    fail = true;
    await svc.refresh();
    expect(calls, 2);
    expect(svc.home, isNotNull, reason: 'a failed refresh never blanks the screen');
    expect(svc.error?.statusCode, 500);
    expect(svc.failed, isFalse);
    svc.clear();
    await svc.refresh();
    expect(svc.failed, isTrue);

    final guest = MeHomeService(fetch: (p, {query}) async => throw StateError('no call'), token: () async => null);
    await guest.ensure();
    expect(guest.home, isNull);
    expect(guest.error, isNull);
  });

  test('service: parents (403 role_not_supported) get no home and no error', () async {
    final svc = MeHomeService(fetch: (p, {query}) async => throw err(403, code: 'role_not_supported'), token: () async => 't');
    await svc.ensure();
    expect(svc.unsupported, isTrue);
    expect(svc.home, isNull);
    expect(svc.failed, isFalse);
  });

  test('service: an older server composes the same home from the calendar, attention and inbox calls', () async {
    final paths = <String>[];
    final svc = MeHomeService(
      fetch: (p, {query}) async {
        paths.add(p);
        switch (p) {
          case MeHomeService.path:
            throw err(404, body: {'detail': 'Not Found'});
          case MeHomeService.calendarPath:
            expect(query?['start'], isNotNull);
            expect(query?['end'], isNotNull);
            return {
              'items': [
                event('later', now.add(const Duration(days: 3)), now.add(const Duration(days: 3, hours: 1))),
                event('today', now.add(const Duration(hours: 1)), now.add(const Duration(hours: 2)), orgId: 4),
                event('tmrw', now.add(const Duration(days: 1)), now.add(const Duration(days: 1, hours: 1))),
              ],
            };
          case MeHomeService.attentionPath:
            return {'counts': {'home': 2}, 'total': 2, 'items': [{'key': 'k', 'tab': 'home', 'count': 2}]};
          case MeHomeService.inboxPath:
            return {
              'items': [
                {'key': 'news', 'segment': 'news'},
                {'key': 'todo', 'segment': 'todo'},
              ],
              'counts': {'todo': 1, 'news': 1},
            };
        }
        return null;
      },
      token: () async => 't',
      clock: () => now,
    );
    await svc.ensure();
    expect(svc.legacy, isTrue);
    expect(paths, [MeHomeService.path, MeHomeService.calendarPath, MeHomeService.attentionPath, MeHomeService.inboxPath]);
    final h = svc.home!;
    expect(h.legacy, isTrue);
    expect(h.today.map((e) => e.id).toList(), ['today']);
    expect(h.upcoming.map((e) => e.id).toList(), ['tmrw', 'later']);
    expect(h.todayOf(4).single.id, 'today');
    expect(h.attentionCount('home'), 2);
    expect(h.inboxPreview.map((x) => x['key']).toList(), ['todo', 'news']); // to-dos first
    expect(h.inboxTodo, 1);
    expect(h.orgOverview, isNull); // AppModeController keeps it on an older server
    expect(h.nextUp(now)?.event.id, 'today');

    // one of the separate calls failing leaves that block empty, never the whole home
    final partial = MeHomeService(
      fetch: (p, {query}) async => p == MeHomeService.inboxPath ? {'items': [], 'counts': {}} : throw err(404, body: {'detail': 'Not Found'}),
      token: () async => 't',
      clock: () => now,
    );
    await partial.ensure();
    expect(partial.legacy, isTrue);
    expect(partial.home?.today, isEmpty);
    expect(partial.failed, isFalse);
  });
}
