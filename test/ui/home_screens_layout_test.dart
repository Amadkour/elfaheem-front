// Home screens (student · instructor · admin · org member) and the context switcher at 320x640 and 1400x900,
// Arabic + English, textScaler 1.3. Only widgets that render without the network.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/design/context_switcher.dart';
import 'package:flutter_education_app/design/home_kit.dart';
import 'package:flutter_education_app/features/org/org_member_today.dart';
import 'package:flutter_education_app/features/student/home/home_screen.dart';
import 'package:flutter_education_app/features/teacher/courses/component/teacher_stats.dart';
import 'package:flutter_education_app/features/teacher/home/home_screen.dart';
import 'package:flutter_education_app/features/teacher/home/teacher_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const longAr = 'إدارة شؤون الطلاب والدراسات العليا والبحث العلمي بكلية الهندسة والتكنولوجيا';
const longEn = 'Office of Student Affairs, Graduate Studies and Scientific Research, Faculty of Engineering';

ScheduleSession session(int id, String start, String end, {bool today = true, bool ongoing = false}) => ScheduleSession(
      scheduleId: id,
      courseId: id,
      courseName: '$longAr $longEn',
      day: 'monday',
      dayLabel: 'monday',
      startTime: start,
      endTime: end,
      durationMinutes: 90,
      isToday: today,
      isOngoing: ongoing,
      scheduledDate: DateTime.now(),
      minutesUntilStart: ongoing ? null : 75,
      minutesUntilEnd: ongoing ? 40 : null,
      maxStudents: 120,
      dayLabelStr: 'monday',
    );

final overview = {
  'items': [
    {
      'organization': {'id': 4, 'status': 'approved', 'type': 'university', 'name_ar': longAr, 'name_en': longEn},
      'roles': ['student', 'teacher'],
      'manage': null,
      'todo': {'total': 3},
      'approvals': {'total': 2},
    },
    {
      'organization': {'id': 9, 'status': 'approved', 'type': 'faculty', 'name_ar': longAr, 'name_en': longEn},
      'roles': ['teacher'],
      'manage': {'is_admin': true},
      'todo': {'total': 140},
    },
  ],
  'default_org_id': 4,
  'pending_total': 145,
};

void main() {
  setUp(() {
    AppModeController.applyContext = (_) {};
    AppConfig.orgsEnabled = true;
    homeAttentionBadge = (_, child) => child;
  });

  testWidgets('context switcher: personal, inside an organization, and its sheet', (tester) async {
    final ctl = AppModeController.instance;
    ctl.debugSet(overview, mode: AppMode.individual);
    await expectNoLayoutErrors(tester, () => const Center(child: ContextSwitcher()),
        act: (t) => t.tap(find.byKey(const ValueKey('ctx.pill'))));
    ctl.debugSet(overview, mode: AppMode.organization, orgId: 9);
    await expectNoLayoutErrors(tester, () => const Align(alignment: AlignmentDirectional.topStart, child: ContextSwitcher()));
    await expectNoLayoutErrors(tester, () => const SizedBox(width: 190, child: ContextSwitcher(allowPersonal: false, compact: true)));
  });

  testWidgets('exit to personal leaves the organization in one tap', (tester) async {
    final ctl = AppModeController.instance;
    ctl.debugSet(overview, mode: AppMode.organization, orgId: 4);
    await tester.pumpWidget(layoutHost(const Center(child: ContextSwitcher())));
    await tester.pump();
    expect(find.byKey(const ValueKey('ctx.exit')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ctx.exit')));
    await tester.pump();
    expect(ctl.isOrg, isFalse);
    expect(find.byKey(const ValueKey('ctx.exit')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('home kit: header, actions, agenda (items / empty / loading), shortcuts, ribbon', (tester) async {
    AppModeController.instance.debugSet(overview, mode: AppMode.individual);
    final items = [
      HomeAgendaItem(start: '8:00 AM', end: '9:30 AM', startMin: 480, endMin: 570, title: '$longAr $longEn', subtitle: longEn, tag: 'Lab'),
      const HomeAgendaItem(start: '10:00 AM', end: '11:30 AM', startMin: 600, endMin: 690, title: longEn, live: true),
      const HomeAgendaItem(start: '11:00 PM', end: '11:50 PM', startMin: 1380, endMin: 1430, title: longAr),
    ];
    await expectNoLayoutErrors(
      tester,
      () => ListView(children: [
        HomeHeader(name: '$longAr $longEn', subtitle: longEn, actions: const [Icon(Icons.notifications)], contextSwitcher: const ContextSwitcher()),
        HomeSectionTitle(longEn, count: 1234, actionLabel: 'Full timetable', onAction: () {}),
        HomeActionGrid(children: [
          for (var i = 0; i < 5; i++)
            HomeActionCard(icon: Icons.task_alt_rounded, title: '$longAr $longEn', subtitle: longEn, count: i * 999, onTap: () {}),
        ]),
        HomeAgenda(items: items, emptyTitle: 'x', nowMin: 620),
        const HomeAgenda(items: [], emptyTitle: longEn, emptyMessage: longAr, emptyActionLabel: 'Open', onEmptyAction: null),
        const HomeAgenda(items: [], loading: true, emptyTitle: 'x'),
        HomeShortcuts(items: [for (var i = 0; i < 7; i++) HomeShortcut(icon: Icons.menu_book_rounded, label: longEn, badge: i * 50, onTap: () {})]),
        HomeHeroCard(child: HomeDayRibbon(items: items, nowMin: 620)),
      ]),
    );
  });

  testWidgets('instructor home body (loading, data, empty)', (tester) async {
    AppModeController.instance.debugSet(overview, mode: AppMode.individual);
    Widget body({required bool loading, List<ScheduleSession> schedule = const []}) => SingleChildScrollView(
          child: TeacherHomeBody(
            loading: loading,
            stats: const TeacherStats(totalStudents: 123456, totalCourses: 42, overallRating: 4.85),
            schedule: schedule,
            pending: const {'attendance_missing': 3, 'grading': 1200, 'materials_missing': 0, 'enrollment_requests': 7},
            courses: const [],
            onTab: (_) {},
            onOpenCourse: (_) {},
            onOpenCourseId: (_) {},
            onNewCourse: () {},
            showFeeds: false,
          ),
        );
    await expectNoLayoutErrors(tester, () => body(loading: true));
    await expectNoLayoutErrors(tester, () => body(loading: false, schedule: [session(1, '08:00', '09:30'), session(2, '13:00', '14:30')]));
    await expectNoLayoutErrors(tester, () => body(loading: false));
  });

  testWidgets('student home body (next up, live, free day, guest-free)', (tester) async {
    AppModeController.instance.debugSet(overview, mode: AppMode.individual);
    Widget body(ScheduleSession? next, List<ScheduleSession> today, {bool loading = false}) => SingleChildScrollView(
          child: StudentHomeBody(
            guest: false,
            myCourses: const [],
            scheduleLoading: loading,
            today: today,
            next: next,
            onOpenCourse: (_) {},
            onTab: (_) {},
          ),
        );
    final a = session(1, '08:00', '09:30'), b = session(2, '10:00', '11:30', ongoing: true);
    await expectNoLayoutErrors(tester, () => body(a, [a, b]));
    await expectNoLayoutErrors(tester, () => body(b, [b]));
    await expectNoLayoutErrors(tester, () => body(null, const []));
    await expectNoLayoutErrors(tester, () => body(null, const [], loading: true));
  });

  test('org today: weekly slots of today unless an exam window pauses them, plus today\'s extras', () {
    final monday = DateTime(2026, 10, 19); // a Monday
    final tt = [
      {
        'items': [
          {'day': 'monday', 'start_time': '10:00', 'course': 'B'},
          {'day': 'monday', 'start_time': '08:00', 'course': 'A'},
          {'day': 'tuesday', 'start_time': '08:00', 'course': 'C'},
        ],
        'extras': [
          {'date': '2026-10-19', 'start_time': '09:00', 'title': 'Extra'},
          {'date': '2026-10-20', 'start_time': '09:00', 'title': 'Tomorrow'},
        ],
      },
    ];
    expect(orgTodaySessions(tt, monday).map((x) => x['course'] ?? x['title']).toList(), ['A', 'Extra', 'B']);
    expect(orgTodaySessions(tt, monday)[1]['_extra'], isTrue);

    final paused = [
      {
        ...tt.first,
        'exam_pauses': [
          {'exam_schedule_id': 1, 'start_date': '2026-10-18', 'end_date': '2026-10-22'},
        ],
      },
    ];
    // weekly classes paused for exams; the dated extra still happens
    expect(orgTodaySessions(paused, monday).map((x) => x['title']).toList(), ['Extra']);
    expect(orgTodaySessions(paused, DateTime(2026, 10, 26)).map((x) => x['course']).toList(), ['A', 'B']);
  });

  test('greeting follows the hour', () {
    expect(homeGreetingKey(7), 'home_greet_morning');
    expect(homeGreetingKey(14), 'home_greet_afternoon');
    expect(homeGreetingKey(21), 'home_greet_evening');
    expect(homeGreetingKey(2), 'home_greet_evening');
    expect(homeClockMinutes('08:30:00'), 510);
    expect(HomeDayRibbon.window(const [HomeAgendaItem(start: '', end: '', title: '', startMin: 330, endMin: 1410)]), (300, 1440));
  });
}
