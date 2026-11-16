// The course page's Overview (D-1090): the page block parses leniently, a student only gets their section's filter,
// and every card lays out at 320×640 and 1400×900, ar / en, textScaler 1.3 — empty, partial, partly full and full,
// for staff and a student, organization and personal courses.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/courses/course_profile/course_page_models.dart';
import 'package:flutter_education_app/features/courses/course_space/course_overview.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _long = 'محاضرة طويلة جداً عن المتغيرات والأنواع والدوال A very long lecture title about variables';

Map<String, dynamic> _page({required int level, bool staff = true, bool personal = false}) {
  final groups = [
    for (var g = 1; g <= (level == 3 ? 4 : level == 2 ? 2 : level); g++)
      {'group_no': g, 'label': 'سكشن $g · م$g', 'label_en': 'Section $g', 'ta': {'id': 50 + g, 'name': 'م. سارة علي عبد الرحمن $g'}, 'students': staff ? 50 + g : null},
  ];
  return {
    'counts': {
      'students': [0, 5, 40, 210][level],
      'sessions_total': [0, 6, 60, 210][level],
      'sessions_done': [0, 1, 20, 120][level],
      'lectures': [0, 2, 8, 15][level],
      'sections': [0, 4, 52, 195][level],
      'minutes': [0, 360, 4500, 22500][level],
      'hours': [0, 6.0, 75.0, 375.0][level],
      'price': {'amount': personal ? 450 : 0, 'currency': 'EGP', 'free': !personal},
    },
    'next': level == 0 ? null : {'id': 1, 'name': _long, 'track': 'lecture', 'group_no': null, 'scheduled_at': '2026-11-21T08:00:00', 'duration_minutes': 120, 'live_now': false},
    if (staff) 'setup': {
      'steps': [
        for (final (i, k) in ['cover', 'description', 'schedule', 'rules', 'first_exam'].indexed) {'key': k, 'done': i < [1, 2, 4, 5][level]},
      ],
    },
    'week': {
      'source': 'course',
      'slots': [
        if (level > 0) {'day': 'saturday', 'start': '10:00', 'end': '12:00', 'track': 'lecture', 'group_no': null},
        for (final g in groups) {'day': ['sunday', 'monday', 'tuesday', 'wednesday'][(g['group_no'] as int) - 1], 'start': '09:00', 'end': '10:30', 'track': 'section', 'group_no': g['group_no']},
      ],
    },
    'exams': {
      'total': [0, 0, 1, 3][level],
      'upcoming': [
        if (level >= 2) {'id': 1, 'name': 'امتحان منتصف الفصل $_long', 'start_date': '2026-11-30T08:00:00', 'end_date': null, 'duration': 60},
        if (level == 3) {'id': 2, 'name': 'كويز 3', 'start_date': '2026-11-20T08:00:00', 'end_date': null, 'duration': 15},
      ],
      'upcoming_count': [0, 0, 1, 2][level],
      if (staff) 'to_grade': level == 3 ? 18 : 0,
      if (!staff && level == 3) 'last_result': {'name': 'كويز 2', 'marks': 8, 'total': 10, 'percentage': 80, 'passed': true},
    },
    'rules': {
      'absence_limit': level >= 2 ? 6 : null,
      'grade_breakdown': level >= 2 ? [{'label': 'أعمال السنة', 'weight': 20}, {'label': 'السكاشن', 'weight': 20}, {'label': 'النهائي', 'weight': 60}] : null,
      'late_policy': level == 3 ? 'التسليم المتأخر يخصم 10% عن كل يوم، بحد أقصى 3 أيام $_long' : null,
      'items': [for (var i = 0; i < [0, 2, 3, 7][level]; i++) {'id': i + 1, 'text': 'قاعدة رقم ${i + 1}: $_long', 'order': i}],
      if (!staff && level >= 2) 'me': {'absences': level == 3 ? 7 : 2, 'limit': 6, 'left': 0, 'over': level == 3},
    },
    'sections': {
      'mode': 'teacher_assigns',
      'mode_source': personal ? 'course' : 'org',
      'source': 'course',
      'my_group': staff || level == 0 ? null : 1,
      'can_pick': false,
      'groups': staff ? groups : groups.take(1).toList(),
      if (staff) 'unassigned': level == 3 ? 3 : 0,
    },
    'team': {
      'instructor': {'id': 1, 'name': 'Ahmed Madkour أحمد مدكور'},
      if (staff) 'assistants': [for (final g in groups) g['ta']],
      if (!staff && level > 0) 'my_ta': groups.isEmpty ? null : groups.first['ta'],
    },
    'attendance': level == 0
        ? (staff ? {'rate': null, 'at_risk': 0} : {'attended': 0, 'expected': 0, 'absences': 0, 'absence_pct': null, 'limit': null})
        : (staff ? {'rate': [0, 80, 86, 91][level], 'at_risk': level == 3 ? 3 : 0} : {'attended': 11, 'expected': 12, 'absences': 1, 'absence_pct': 8, 'limit': 6}),
    if (personal)
      'personal': {
        'rating': level == 0 ? null : [0, 4.0, 4.7, 4.8][level],
        'reviews': [0, 3, 28, 120][level],
        'distribution': [[0, 0, 0, 0, 0], [1, 1, 1, 0, 0], [21, 5, 1, 1, 0], [98, 15, 4, 2, 1]][level],
        'path': [for (var i = 0; i < [0, 1, 2, 3][level]; i++) {'id': 10 + i, 'name_ar': 'بايثون للبيانات وتعلم الآلة $i', 'name_en': 'Python for data $i', 'image_url': null}],
        if (staff) 'earnings': {'currency': 'EGP', 'weeks': [0, 0, 0, 0, 0, 0, 250, 250], 'total': 500},
      },
  };
}

List<CourseApptRow> _rows(int level, {bool staff = true}) {
  final out = <CourseApptRow>[];
  final base = DateTime.utc(2026, 11, 16, 8);
  final n = [0, 6, 20, 60][level];
  for (var i = 0; i < n; i++) {
    final section = i % 3 != 0;
    final group = section ? (i % (level == 3 ? 4 : level == 2 ? 2 : 1)) + 1 : null;
    if (!staff && section && group != 1) continue;
    out.add(CourseApptRow(
      id: i + 1,
      name: section ? 'سكشن $group · $_long' : 'محاضرة ${i ~/ 3 + 1} · $_long',
      track: section ? 'section' : 'lecture',
      groupNo: group,
      at: base.add(Duration(days: i - (n ~/ 3))),
      minutes: section ? 90 : 120,
      hasMaterial: i.isEven,
    ));
  }
  return out;
}

Widget _host(Widget child) => SingleChildScrollView(child: child);

void main() {
  setUp(() => AppConfig.lang = 'ar');

  group('the page block', () {
    test('parses a full staff payload, and an older server leaves it null', () {
      final p = CoursePage.fromJson(_page(level: 3, personal: true));
      expect(p.counts.sessionsTotal, 210);
      expect(p.counts.hours, 375);
      expect(p.setup!.length, 5);
      expect(p.setupComplete, isTrue);
      expect(p.week.where((s) => s.isSection).length, 4);
      expect(p.exams!.toGrade, 18);
      expect(p.rules.count, 10);
      expect(p.rules.grades.map((g) => g.weight).fold<int>(0, (a, b) => a + b), 100);
      expect(p.sections.groups.length, 4);
      expect(p.sections.group(2)!.students, 52);
      expect(p.team.assistants.length, 4);
      expect(p.personal!.earningsWeeks, hasLength(8));
      expect(CoursePage.of({'course': {}}), isNull);
    });

    test('a student: own group, own TA, own absences; English labels for generated names', () {
      final p = CoursePage.fromJson(_page(level: 3, staff: false));
      expect(p.setup, isNull);
      expect(p.sections.myGroup, 1);
      expect(p.sections.groups.map((g) => g.groupNo), [1]);
      expect(p.team.myTa!.name, contains('سارة'));
      expect(p.rules.over, isTrue);
      expect(p.exams!.lastResult!.marks, 8);
      expect(const CourseSectionGroup(groupNo: 3, label: 'سكشن 3', labelEn: 'Section 3').labelFor(false), 'Section 3');
      expect(const CourseSectionGroup(groupNo: 3, label: 'Lab A', labelEn: 'Section 3').labelFor(false), 'Lab A');
    });

    test('lenient: junk and missing fields never throw', () {
      final p = CoursePage.fromJson({'counts': 'x', 'week': {'slots': 'nope'}, 'rules': {'items': [1, 'a']}, 'sections': null});
      expect(p.counts.sessionsTotal, 0);
      expect(p.week, isEmpty);
      expect(p.rules.isEmpty, isTrue);
    });
  });

  testWidgets('a student is never offered the section-group chips; staff are', (tester) async {
    AppConfig.lang = 'en';
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(layoutHost(_host(CourseOverview(page: CoursePage.fromJson(_page(level: 3, staff: false)), staff: false, sessions: _rows(3, staff: false)))));
    expect(find.text('All sections'), findsNothing);
    expect(find.textContaining('Your section: '), findsOneWidget);
    await tester.pumpWidget(layoutHost(_host(CourseOverview(page: CoursePage.fromJson(_page(level: 3)), staff: true, sessions: _rows(3)))));
    expect(find.text('All sections'), findsOneWidget);
  });

  for (final level in [0, 1, 2, 3]) {
    for (final staff in [true, false]) {
      for (final personal in [false, true]) {
        testWidgets('Overview lays out: level $level, ${staff ? 'staff' : 'student'}, ${personal ? 'personal' : 'org'}', (tester) async {
          final page = CoursePage.fromJson(_page(level: level, staff: staff, personal: personal));
          await expectNoLayoutErrors(
            tester,
            () => _host(CourseOverview(
              page: page,
              staff: staff,
              sessions: _rows(level, staff: staff),
              now: DateTime.utc(2026, 11, 16, 9),
              actions: CourseOverviewActions(
                onOpenSession: (_) {},
                onAllSessions: () {},
                onNewSession: () {},
                onEditSchedule: () {},
                onOpenExams: () {},
                onEditRules: staff ? () {} : null,
                onManageSections: staff ? () {} : null,
                onAttendance: () {},
                onTeam: () {},
                onReviews: () {},
                onOpenPathCourse: (_) {},
                onEditPath: staff ? () {} : null,
              ),
            )),
          );
        });
      }
    }
  }

  testWidgets('the Next card and the setup bar lay out', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => _host(Column(children: [
        CourseNextCard(title: _long, when: 'غدًا · 10:00 ص', caption: 'سكشن 2 · م9', section: true, actionLabel: 'انضم Join', actionIcon: Icons.login_rounded, onAction: () {}),
        CourseSetupBar(steps: const [CourseSetupStep('cover', true), CourseSetupStep('description', false), CourseSetupStep('schedule', false)], onStep: (_) {}),
      ])),
    );
  });
}
