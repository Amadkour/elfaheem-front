// The instructor home body (Track B.5) at 320x640 and 1400x900, Arabic + English, textScaler 1.3:
// full (dashboard + the /me/home block), older server (no /me/home block), empty, loading, error.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/design/home_kit.dart';
import 'package:flutter_education_app/features/shared/inbox/unified_inbox.dart' show InboxEntry;
import 'package:flutter_education_app/features/courses/teacher/component/teacher_stats.dart';
import 'package:flutter_education_app/features/teacher/home/go_live_sheet.dart' show GoLiveButton;
import 'package:flutter_education_app/features/teacher/home/home_screen.dart';
import 'package:flutter_education_app/features/teacher/home/teacher_home_extra.dart';
import 'package:flutter_education_app/features/teacher/home/teacher_models.dart';
import 'package:flutter_education_app/features/teacher/schedules/schedules_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const longAr = 'إدارة شؤون الطلاب والدراسات العليا والبحث العلمي بكلية الهندسة والتكنولوجيا';
const longEn = 'Office of Student Affairs, Graduate Studies and Scientific Research, Faculty of Engineering';

ScheduleSession session(int id, String start, String end, {bool ongoing = false}) => ScheduleSession(
      scheduleId: id,
      courseId: id,
      courseName: '$longAr $longEn',
      day: 'monday',
      dayLabel: 'monday',
      startTime: start,
      endTime: end,
      durationMinutes: 90,
      isToday: true,
      isOngoing: ongoing,
      scheduledDate: DateTime.now(),
      minutesUntilStart: ongoing ? null : 75,
      minutesUntilEnd: ongoing ? 40 : null,
      maxStudents: 120,
      dayLabelStr: 'monday',
    );

final extra = TeacherHomeExtra.fromJson({
  'pending': {'attendance_missing': 3, 'grading': 1200, 'materials_missing': 0, 'enrollment_requests': 7},
  'teaching_courses': 6,
  'earnings': {'month': 1234567.89, 'pending_payout': 2500},
  'inbox_preview': [
    {'key': 'f1', 'kind': 'form', 'segment': 'todo', 'title': '$longAr $longEn', 'subtitle': longEn, 'due_at': '2026-10-29T10:00:00Z', 'urgency': 'due_soon', 'mandatory': true},
    {'key': 'r1', 'kind': 'requirement', 'segment': 'todo', 'title': longAr, 'subtitle': '', 'status': 'open'},
    {'key': 'e1', 'kind': 'exam', 'segment': 'todo', 'title': longEn, 'subtitle': longAr, 'due_at': '2026-10-01T10:00:00Z', 'blocking': true},
    {'key': 'n1', 'kind': 'news', 'segment': 'news', 'title': 'news'},
  ],
  'notifications_unread': 12,
  'enrollments_series': [1, 3, 2, 6, 5, 9, 12, 8, 14, 20],
});

TeacherCourse course(int id, {bool published = true, int students = 0}) => TeacherCourse(
      id: id,
      imageUrl: '',
      totalHours: 0,
      type: 'live',
      progress: 0,
      expectedHours: 0,
      isPublished: published,
      studentsCount: students,
      sessionsCount: 12345,
      titleAr: longAr,
      titleEn: longEn,
    );

final courses = [course(1, students: 5), course(2, published: false, students: 900), course(3, students: 123456), course(4, students: 40)];

void main() {
  test('course summary order: published by students, drafts last', () {
    expect(teacherCourseFocus(courses).map((c) => c.id).toList(), [3, 4, 1, 2]);
  });

  test('needs-you columns: one row from 560, no lone tile on phones', () {
    expect([for (var n = 1; n <= 7; n++) HomeStatStrip.columnsFor(n, 300)], [1, 2, 3, 2, 3, 3, 2]);
    expect(HomeStatStrip.columnsFor(5, 900), 5);
    expect(HomeStatStrip.columnsFor(8, 900), 6);
  });

  setUp(() {
    AppModeController.applyContext = (_) {};
    homeAttentionBadge = (_, child) => child;
  });

  Widget body({
    bool loading = false,
    String? error,
    String? staleError,
    TeacherHomeExtra? extra,
    List<ScheduleSession> schedule = const [],
    Map<String, int> pending = const {},
    List<TeacherCourse> courses = const [],
    Widget Function(bool wide)? hero,
  }) =>
      SingleChildScrollView(
        child: TeacherHomeBody(
          loading: loading,
          error: error,
          staleError: staleError,
          onRetry: () {},
          stats: const TeacherStats(totalStudents: 123456, totalCourses: 42, overallRating: 4.85),
          schedule: schedule,
          pending: pending,
          courses: courses,
          extra: extra,
          onTab: (_) {},
          onOpenCourse: (_) {},
          onOpenCourseId: (_) {},
          onNewCourse: () {},
          onOpenEarnings: () {},
          onOpenInbox: () {},
          showFeeds: false,
          hero: hero,
        ),
      );

  testWidgets('full: four hero figures, five needs-you tiles, agenda, live queue, course summary + sparkline, inbox preview', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => body(
        extra: extra,
        schedule: [session(1, '08:00', '09:30'), session(2, '13:00', '14:30', ongoing: true), session(3, '23:00', '23:50')],
        pending: const {'attendance_missing': 3, 'grading': 1200, 'materials_missing': 0, 'enrollment_requests': 7},
        courses: courses,
      ),
    );
    await expectNoLayoutErrors(tester, () => body(courses: courses.take(2).toList()));
    await tester.pumpWidget(layoutHost(body(extra: extra, schedule: [session(1, '08:00', '09:30')])));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(InboxEntry), findsOneWidget);
    expect(find.byType(TeacherHomeBody), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('older server: no /me/home block → three figures, four cards, no inbox preview', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => body(schedule: [session(1, '08:00', '09:30')], pending: const {'attendance_missing': 1}),
    );
    await tester.pumpWidget(layoutHost(body(schedule: [session(1, '08:00', '09:30')])));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(InboxEntry), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('empty day, no courses, no pending', (tester) async {
    await expectNoLayoutErrors(tester, () => body(extra: TeacherHomeExtra.fromJson(const {'earnings': {'month': 0, 'pending_payout': 0}})));
  });

  testWidgets('loading: one skeleton; error: retry; stale error: banner over the data', (tester) async {
    await expectNoLayoutErrors(tester, () => body(loading: true));
    await expectNoLayoutErrors(tester, () => body(error: '$longAr $longEn'));
    await expectNoLayoutErrors(tester, () => body(staleError: longEn, extra: extra, schedule: [session(1, '08:00', '09:30')]));
  });

  testWidgets('hero (D-631): the greeting card, a long switcher under Go live, centred; the ribbon sits in Today', (tester) async {
    final schedule = [session(1, '06:00', '07:30', ongoing: true), session(2, '09:00', '10:30'), session(3, '13:00', '14:00')];
    for (final centered in [false, true]) {
      await expectNoLayoutErrors(
        tester,
        () => SingleChildScrollView(
          child: TeacherHomeHero(
            name: '$longAr $longEn',
            subtitle: '$longEn $longAr',
            ring: 0.5,
            centered: centered,
            switcher: const Text('$longAr $longEn', maxLines: 1, overflow: TextOverflow.ellipsis),
            goLive: GoLiveButton(onHero: true, onTap: () {}),
          ),
        ),
      );
    }
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: TeacherHomeHero(name: longEn, goLive: GoLiveButton(live: true, onHero: true, onTap: () {}))));
    await expectNoLayoutErrors(tester, () => const SingleChildScrollView(child: TeacherHomeHero(name: longAr, switcher: Text(longEn))));
    // the hero beside Today (desktop) and above it (phone), with the day ribbon in Today; huge counts, long names
    await expectNoLayoutErrors(
      tester,
      () => body(
        schedule: schedule,
        pending: const {'attendance_missing': 3, 'grading': 1200, 'materials_missing': 0, 'enrollment_requests': 7},
        courses: courses,
        extra: extra,
        hero: (wide) => TeacherHomeHero(
          name: '$longAr $longEn',
          subtitle: longEn,
          centered: wide,
          ring: teacherDayProgress(schedule),
          padding: wide ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 20),
          goLive: GoLiveButton(onHero: true, onTap: () {}),
        ),
      ),
    );
    // nothing at all: no sessions, no courses, a lone hero
    await expectNoLayoutErrors(tester, () => body(hero: (wide) => TeacherHomeHero(name: 'A', centered: wide)));
    await expectNoLayoutErrors(tester, () => body(loading: true, hero: (wide) => const TeacherHomeHero(name: 'A')));
    await tester.pumpWidget(layoutHost(body(schedule: schedule)));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(HomeDayRibbon), findsOneWidget);
    await tester.pumpWidget(layoutHost(body(hero: (_) => const TeacherHomeHero(name: 'A'))));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(HomeDayRibbon), findsNothing, reason: 'a free day draws no ribbon');
    await tester.pumpWidget(const SizedBox());
  });

  test('day progress: the share of the sessions of the day that ended; null on a free day', () {
    expect(teacherDayProgress(const []), isNull);
    final now = DateTime.now().toUtc();
    String hhmm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final past = session(1, hhmm(now.subtract(const Duration(hours: 3))), hhmm(now.subtract(const Duration(hours: 2))));
    final later = session(2, hhmm(now.add(const Duration(hours: 2))), hhmm(now.add(const Duration(hours: 3))));
    if (now.hour >= 3 && now.hour <= 20) expect(teacherDayProgress([past, later], now: now), 0.5);
  });

  testWidgets('weekly appointments: week block, cards, empty, loading; the rating figures', (tester) async {
    const slots = [
      CourseSchedule(id: 1, courseId: 3, day: 'sunday', startTime: '08:00', endTime: '09:30'),
      CourseSchedule(id: 2, courseId: 3, day: 'tuesday', startTime: '10:00', endTime: '11:30'),
      CourseSchedule(id: 3, courseId: 3, day: 'tuesday', startTime: '14:00', endTime: '15:00'),
      CourseSchedule(id: 4, courseId: 3, day: 'wednesday', startTime: '23:30', endTime: '23:59'),
    ];
    await expectNoLayoutErrors(tester, () => TeacherSchedulesView(schedules: slots, onAdd: () {}, onDelete: (_) {}));
    await expectNoLayoutErrors(tester, () => TeacherSchedulesView(schedules: const [], onAdd: () {}));
    await expectNoLayoutErrors(tester, () => const TeacherSchedulesView(schedules: [], loading: true));
    expect(TeacherSchedulesView.sorted(slots).map((s) => s.id).toList(), [2, 3, 4, 1]);
    await expectNoLayoutErrors(
      tester,
      () => const SingleChildScrollView(
        child: StatsRow(stats: TeacherStats(totalStudents: 1234567, totalCourses: 42, overallRating: 4.85, doctorRating: 4.9), isFull: true),
      ),
    );
  });
}
