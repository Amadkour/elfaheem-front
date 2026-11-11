// Student home (Track B.4): StudentHomeBody at 320x640 and 1400x900, Arabic + English, textScaler 1.3 — full
// payload (live event, this week, courses, inbox rows), an empty day, loading, failure, guest.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/home/me_home.dart';
import 'package:flutter_education_app/design/home_kit.dart';
import 'package:flutter_education_app/features/student/home/home_continue.dart';
import 'package:flutter_education_app/features/student/home/home_event_rows.dart';
import 'package:flutter_education_app/features/student/home/home_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const longAr = 'إدارة شؤون الطلاب والدراسات العليا والبحث العلمي بكلية الهندسة والتكنولوجيا';
const longEn = 'Office of Student Affairs, Graduate Studies and Scientific Research, Faculty of Engineering';

final now = DateTime.utc(2026, 10, 28, 9, 0);

String iso(DateTime d) => d.toUtc().toIso8601String().replaceAll('Z', '');

Map<String, dynamic> event(String id, Duration from, Duration to,
        {String source = 'course_session', int? orgId, String? kind, String? mode, String? location}) =>
    {
      'id': id,
      'source': source,
      'title': '$longAr $longEn',
      'subtitle': longEn,
      'starts_at': iso(now.add(from)),
      'ends_at': iso(now.add(to)),
      'org_id': orgId,
      'org': orgId == null ? null : {'id': orgId, 'name_ar': longAr, 'name_en': longEn},
      'course_id': 1,
      'kind': kind,
      'mode': mode,
      'location': location,
    };

Map<String, dynamic> inboxRow(String key, {String segment = 'todo', bool mandatory = false}) => {
      'key': key,
      'kind': 'form',
      'segment': segment,
      'title': '$longAr $longEn',
      'subtitle': longEn,
      'organization': {'name_ar': longAr, 'name_en': longEn},
      'due_at': iso(now.add(const Duration(hours: 30))),
      'created_at': iso(now.subtract(const Duration(hours: 1))),
      'mandatory': mandatory,
    };

MeHome full() => MeHome.fromJson({
      'now': iso(now),
      'today_date': '2026-10-28',
      'timezone': 'Africa/Cairo',
      'role': 'student',
      'today': [
        event('a', const Duration(hours: -3), const Duration(hours: -2)),
        event('b', const Duration(minutes: -10), const Duration(minutes: 50), source: 'timetable', orgId: 4, kind: 'lab', location: 'Room 1'),
        event('c', const Duration(hours: 3), const Duration(hours: 4), source: 'exam', orgId: 4),
        event('d', const Duration(hours: 6), const Duration(hours: 7), source: 'meeting', orgId: 9, mode: 'online'),
      ],
      'upcoming': [
        for (var i = 1; i <= 10; i++)
          event('u$i', Duration(days: (i + 1) ~/ 2, hours: i), Duration(days: (i + 1) ~/ 2, hours: i + 1),
              source: i % 3 == 0 ? 'exam' : 'timetable', orgId: 4, kind: i.isEven ? 'lab' : null),
      ],
      'attention': {
        'counts': {'home': 1234},
        'total': 1234,
        'items': [
          {'key': 'forms', 'tab': 'home', 'count': 1234},
        ],
      },
      'inbox_preview': [inboxRow('f1', mandatory: true), inboxRow('f2'), inboxRow('n1', segment: 'news'), inboxRow('f3'), inboxRow('f4')],
      'inbox_counts': {'todo': 999, 'news': 1, 'overdue': 12, 'due_soon': 345},
      'notifications_unread': 56789,
      'courses_progress': [
        {
          'course_id': 11,
          'name_ar': longAr,
          'name_en': longEn,
          'progress': 42.5,
          'next_lecture': {'id': 7, 'name': longEn, 'scheduled_at': iso(now.add(const Duration(days: 1))), 'duration_minutes': 90},
        },
        {'course_id': 12, 'name_ar': 'ر', 'name_en': 'P', 'progress': 100, 'next_lecture': null},
        {'course_id': 13, 'name_ar': longAr, 'name_en': longEn, 'progress': 0},
      ],
    });

MeHome emptyDay() => MeHome.fromJson({
      'now': iso(now),
      'today': [],
      'upcoming': [],
      'attention': {'items': []},
      'inbox_preview': [],
      'inbox_counts': {},
      'notifications_unread': 0,
      'courses_progress': [],
    });

Widget body(StudentHomeData data) => SingleChildScrollView(child: StudentHomeBody(data: data, onTab: (_) {}));

void main() {
  setUp(() => AppConfig.lang = 'en');

  testWidgets('student home body: full payload (live now · this week · continue learning · inbox rows)', (tester) async {
    await expectNoLayoutErrors(tester, () => body(StudentHomeData(home: full(), now: now, orgWaiting: 145)));
    // later in the day: the exam is next (countdown), the lab is done
    await expectNoLayoutErrors(tester, () => body(StudentHomeData(home: full(), now: now.add(const Duration(hours: 1)))));
    // the day is over: every row is done (no note, nothing tinted)
    await expectNoLayoutErrors(tester, () => body(StudentHomeData(home: full(), now: now.add(const Duration(hours: 8)))));
  });

  testWidgets('student home body: empty day, loading, failure, guest', (tester) async {
    await expectNoLayoutErrors(tester, () => body(StudentHomeData(home: emptyDay(), now: now)));
    await expectNoLayoutErrors(tester, () => body(const StudentHomeData(loading: true)));
    await expectNoLayoutErrors(tester, () => body(const StudentHomeData(error: longEn)));
    await expectNoLayoutErrors(tester, () => body(const StudentHomeData(guest: true)));
  });

  testWidgets('pieces on their own: today (running row with its note · next row), this week, courses', (tester) async {
    final h = full();
    await expectNoLayoutErrors(
      tester,
      () => ListView(children: [
        Builder(
          builder: (context) => HomeAgenda(
            nowMin: 9 * 60 + 5,
            items: [for (final e in h.today) homeAgendaItemOf(context, e, now)],
            emptyTitle: longEn,
          ),
        ),
        Builder(
          builder: (context) => HomeAgenda(
            nowMin: 10 * 60 + 5,
            items: [for (final e in h.today) homeAgendaItemOf(context, e, now.add(const Duration(hours: 1)))],
            emptyTitle: longEn,
          ),
        ),
        UpcomingList(events: h.upcoming, onTap: (_) {}),
        StudentCourseSummary(courses: h.coursesProgress, onOpen: (_) {}, onShowAll: () {}),
        StudentCourseSummary(courses: h.coursesProgress.take(1).toList()),
        StudentCourseSummary(courses: h.coursesProgress, featuredId: 11, onOpen: (_) {}, onShowAll: () {}),
      ]),
    );
  });

  // D-631 worst cases (break-ui): long course names, a huge course count, every course done, none — through the
  // phone tiles, the shortcut grid and the desktop stat row (the harness renders both widths)
  testWidgets('premium pieces: course tiles, shortcuts and the stat row under worst-case data', (tester) async {
    final many = full();
    await expectNoLayoutErrors(tester, () => body(StudentHomeData(home: many, now: now, orgWaiting: 99999)));
    final huge = MeHome.fromJson({
      'today': const [],
      'upcoming': const [],
      'courses_progress': [
        for (var i = 0; i < 240; i++)
          {'course_id': i + 1, 'name_ar': '$longAr $i', 'name_en': '$longEn $i', 'progress': i.isEven ? 100 : 37.5},
      ],
    });
    await expectNoLayoutErrors(tester, () => body(StudentHomeData(home: huge, now: now)));
    await expectNoLayoutErrors(
      tester,
      () => ListView(children: [
        StudentCourseTiles(courses: huge.coursesProgress, onOpen: (_) {}),
        StudentCourseTiles(courses: huge.coursesProgress.take(1).toList(), featuredId: 1),
        const StudentCourseTiles(courses: []),
      ]),
    );
  });

  testWidgets('the editorial blocks: Continue learning (phone and wide), a free day with and without a next class', (tester) async {
    final h = full();
    final x = h.coursesProgress.first;
    await expectNoLayoutErrors(
      tester,
      () => ListView(children: [
        StudentContinueBlock(course: x, line: '$longEn $longAr', onOpen: () {}),
        StudentContinueBlock(course: h.coursesProgress.last, line: longEn),
        StudentFreeDayBlock(next: h.upcoming.first, onOpenNext: () {}, onTimetable: () {}),
        const StudentFreeDayBlock(),
      ]),
    );
  });

  test('the Continue block offers the first unfinished course of the focus order, none when all are done', () {
    final h = full();
    expect(homeContinueCourse(h.coursesProgress)!.courseId, 11);
    expect(homeContinueCourse([for (final x in h.coursesProgress) if (x.progress >= 100) x]), isNull);
    expect(homeContinueCourse(const []), isNull);
  });

  test('course summary order: the soonest next lecture, then the furthest along, finished last', () {
    final order = homeCourseFocus(MeHome.fromJson({
      'courses_progress': [
        {'course_id': 1, 'name_en': 'done', 'progress': 100},
        {'course_id': 2, 'name_en': 'half', 'progress': 50},
        {'course_id': 3, 'name_en': 'later', 'progress': 10, 'next_lecture': {'id': 1, 'name': 'x', 'scheduled_at': iso(now.add(const Duration(days: 3)))}},
        {'course_id': 4, 'name_en': 'soon', 'progress': 5, 'next_lecture': {'id': 2, 'name': 'y', 'scheduled_at': iso(now.add(const Duration(days: 1)))}},
        {'course_id': 5, 'name_en': 'new', 'progress': 0},
      ],
    }).coursesProgress);
    expect(order.map((x) => x.courseId).toList(), [4, 3, 2, 5, 1]);
  });

  test('event tags and the next-up choice follow the payload', () {
    final h = full();
    expect(h.nextUp(now)!.event.id, 'b');
    expect(h.nextUp(now)!.live, isTrue);
    expect(h.nextUp(now.add(const Duration(hours: 1)))!.event.id, 'c');
    expect(h.nextUp(now.add(const Duration(hours: 8))), isNull);
    expect(homeEventTag(h.today[1]), 'home_lab'); // translations aren't loaded: the key tells the choice
    expect(homeEventTag(h.today[2]), 'home_exam');
    expect(homeEventTag(h.today[3]), 'home_meeting');
    expect(homeEventTag(h.today[0]), isNull);
    expect(homeDuration(80), 'home_h_min');
    expect(homeDuration(5), 'home_min');
    expect(homeDuration(120), 'home_h');
  });

  test('no next-up card: the running row says when it ends and where, the next one when it starts', () {
    const running = HomeAgendaItem(start: '9:50', end: '10:50', title: 'Lab', startMin: 590, endMin: 650, live: true, place: 'Lab 3');
    const next = HomeAgendaItem(start: '13:00', end: '14:00', title: 'Quiz', startMin: 780, endMin: 840);
    const later = HomeAgendaItem(start: '16:00', end: '17:00', title: 'Meeting', startMin: 960, endMin: 1020, place: 'Hall');
    // translations aren't loaded: the keys tell the choice
    expect(homeAgendaNote(running, 600), 'home_ends_in · Lab 3');
    expect(homeAgendaNote(running, 650), 'Lab 3'); // the very last minute: no "ends in 0"
    expect(homeAgendaNote(next, 600, next: true), 'home_starts_in');
    expect(homeAgendaNote(later, 600), isNull); // only the next one speaks
    expect(homeAgendaNote(later, 600, next: true), 'home_starts_in · Hall');
    expect(homeAgendaNote(const HomeAgendaItem(start: '', end: '', title: 'x'), 600, next: true), isNull);
  });

  test('an empty Today names what comes next', () {
    final h = full();
    expect(homeFreeDaySummary('Free', null), 'Free');
    expect(homeFreeDaySummary('Free', h.firstUpcoming), startsWith('Free · home_next_on'));
  });

  testWidgets('the running row is drawn tinted with its note; with nothing running the next row has one', (tester) async {
    final h = full();
    await tester.pumpWidget(layoutHost(SingleChildScrollView(
      child: Builder(
        builder: (context) => HomeAgenda(nowMin: 9 * 60 + 5, items: [for (final e in h.today) homeAgendaItemOf(context, e, now)], emptyTitle: 'e'),
      ),
    )));
    await tester.pump();
    final lines = tester.widgetList<HomeAgendaLine>(find.byType(HomeAgendaLine)).toList();
    expect(lines.first.item.live, isTrue);
    expect(lines.first.focus, isTrue);
    expect(lines.first.note, contains('Room 1'));
    expect(lines.where((l) => l.note != null), hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });
}
