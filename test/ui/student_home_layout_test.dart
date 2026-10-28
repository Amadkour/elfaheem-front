// Student home (Track B.4): StudentHomeBody at 320x640 and 1400x900, Arabic + English, textScaler 1.3 — full
// payload (live event, this week, courses, inbox rows), an empty day, loading, failure, guest.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/home/me_home.dart';
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
    // the day is over: the free-day hero names the first upcoming event
    await expectNoLayoutErrors(tester, () => body(StudentHomeData(home: full(), now: now.add(const Duration(hours: 8)))));
  });

  testWidgets('student home body: empty day, loading, failure, guest', (tester) async {
    await expectNoLayoutErrors(tester, () => body(StudentHomeData(home: emptyDay(), now: now)));
    await expectNoLayoutErrors(tester, () => body(const StudentHomeData(loading: true)));
    await expectNoLayoutErrors(tester, () => body(const StudentHomeData(error: longEn)));
    await expectNoLayoutErrors(tester, () => body(const StudentHomeData(guest: true)));
  });

  testWidgets('pieces on their own: hero (next · live · free), this week, continue learning', (tester) async {
    final h = full();
    await expectNoLayoutErrors(
      tester,
      () => ListView(children: [
        NextUpHero(next: h.nextUp(now), now: now, upcoming: h.firstUpcoming),
        NextUpHero(next: h.nextUp(now.add(const Duration(hours: 1))), now: now.add(const Duration(hours: 1))),
        NextUpHero(next: null, now: now, upcoming: h.firstUpcoming),
        NextUpHero(next: null, now: now),
        UpcomingList(events: h.upcoming, onTap: (_) {}),
        CourseProgressList(courses: h.coursesProgress, now: now, onTap: (_) {}),
      ]),
    );
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
  });
}
