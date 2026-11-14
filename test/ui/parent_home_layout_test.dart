// The parent's Today tab body (Track B.5) at 320x640 and 1400x900, Arabic + English, textScaler 1.3:
// full (two children, sessions, marks, exam, alerts), empty (no children, pending requests), loading, error.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/home_kit.dart';
import 'package:flutter_education_app/features/parent/parent_overview.dart';
import 'package:flutter_education_app/features/parent/parent_message_teacher.dart';
import 'package:flutter_education_app/features/parent/parent_overview_page.dart';
import 'package:flutter_education_app/features/parent/parent_pulse.dart';
import 'package:flutter_education_app/features/parent/parent_pulse_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../org/parent_pulse_test.dart' show pulseJson;
import 'layout_harness.dart';

const longAr = 'إدارة شؤون الطلاب والدراسات العليا والبحث العلمي بكلية الهندسة والتكنولوجيا';
const longEn = 'Office of Student Affairs, Graduate Studies and Scientific Research, Faculty of Engineering';

String _iso(DateTime d) => d.toUtc().toIso8601String();

ParentOverviewData full() {
  final now = DateTime.now().toUtc();
  final day = DateTime.utc(now.year, now.month, now.day);
  return ParentOverviewData.fromJson({
    'now': _iso(now),
    'children': [
      {
        'child': {'id': 7, 'name': '$longAr $longEn', 'image_url': null, 'is_active': true},
        'today_sessions': [
          {'id': 1, 'source': 'timetable', 'title': longEn, 'subtitle': longAr, 'starts_at': _iso(day.add(const Duration(hours: 8))), 'ends_at': _iso(day.add(const Duration(hours: 9, minutes: 30))), 'location': 'Room 2', 'mode': 'offline'},
          {'id': 2, 'source': 'course_session', 'title': longAr, 'subtitle': '', 'starts_at': _iso(now.subtract(const Duration(minutes: 10))), 'ends_at': _iso(now.add(const Duration(minutes: 50))), 'mode': 'online'},
          {'id': 3, 'source': 'exam', 'title': 'Exam', 'subtitle': null, 'starts_at': _iso(day.add(const Duration(hours: 23))), 'ends_at': null},
        ],
        'attendance_pct_30d': 87,
        'latest_marks': [
          {'exam_id': 11, 'exam': '$longAr $longEn', 'course_ar': longAr, 'course_en': longEn, 'percentage': 92.5, 'passed': true},
          {'exam_id': 10, 'exam': 'Midterm', 'course_ar': 'رياضيات', 'course_en': 'Math', 'percentage': 41.0, 'passed': false},
          {'exam_id': 9, 'exam': 'Quiz', 'course_ar': null, 'course_en': null, 'percentage': null, 'passed': null},
        ],
        'open_alerts': 1234,
        'next_exam': {'id': 12, 'name': '$longAr $longEn', 'starts_at': _iso(now.add(const Duration(days: 3))), 'source': 'course'},
        'courses': 12,
      },
      {
        'child': {'id': 8, 'name': 'Sara', 'image_url': 'https://example.invalid/sara.png'},
        'today_sessions': [],
        'attendance_pct_30d': null,
        'latest_marks': [],
        'open_alerts': 0,
        'next_exam': null,
        'courses': 0,
      },
    ],
    'alerts_total': 1234,
    'requests': [
      {'id': 1, 'status': 'pending'},
      {'id': 2, 'status': 'approved'},
    ],
    'link_config': {'mode': 'easy'},
  });
}

void main() {
  setUp(() => homeAttentionBadge = (_, child) => child);

  Widget body({ParentOverviewData? data, bool loading = false, String? error, ParentHomeGreeting? greeting}) => SingleChildScrollView(
        child: ParentOverviewBody(
          greeting: greeting,
          data: data,
          loading: loading,
          error: error,
          onRetry: () {},
          onOpenAlerts: (_) {},
          onOpenLink: () {},
          onOpenChildren: () {},
          onOpenChild: (_) {},
        ),
      );

  testWidgets('full: two children with sessions, marks, next exam, alerts', (tester) async {
    await expectNoLayoutErrors(tester, () => body(data: full()));
    await tester.pumpWidget(layoutHost(body(data: full())));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(ParentChildOverviewCard), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox());
  });

  // D-305: the pulse layout — two children (switcher), long names, every block, and a child without marks
  ParentOverviewData withPulse() {
    final j = Map<String, dynamic>.from(full().children.first.child);
    final p = pulseJson();
    (p['subjects'] as List).add({'course_id': 3, 'name_ar': longAr, 'name_en': longEn, 'progress': 100.0, 'avg': null, 'class_avg': null, 'missed': 12, 'weak_open': 30, 'tone': 'focus', 'teacher': {'id': 4, 'name': longEn}});
    (p['insights'] as List).insert(0, {'code': 'exam_soon', 'level': 'info', 'params': {'title': '$longAr $longEn', 'at': '2026-11-10T09:00:00'}, 'action': null});
    (p['upcoming'] as List).add({'id': 'x', 'source': 'timetable', 'title': '$longAr $longEn', 'subtitle': longEn, 'location': longAr, 'starts_at': DateTime.now().toUtc().toIso8601String()});
    return ParentOverviewData.fromJson({
      'children': [
        {'child': j, 'pulse': p, 'latest_marks': [{'exam': longEn, 'course_en': longEn, 'percentage': 41.0, 'passed': false}], 'next_exam': {'name': longEn, 'starts_at': '2026-11-20T09:00:00'}},
        {'child': {'id': 8, 'name': 'Sara'}, 'pulse': {'status': 'quiet'}},
      ],
      'alerts_total': 3,
      'requests': [],
    });
  }

  testWidgets('pulse: switcher · hero · needs your attention · this week · subjects · roadmap · marks', (tester) async {
    await expectNoLayoutErrors(tester, () => body(data: withPulse()));
    await tester.pumpWidget(layoutHost(body(data: withPulse())));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(ParentChildSwitcher), findsOneWidget);
    expect(find.byType(ParentPulseHero), findsOneWidget);
    expect(find.byType(ParentSubjectsCard), findsOneWidget);
    expect(find.byType(ParentChildOverviewCard), findsNothing);
    await tester.tap(find.text('Sara'));
    // switching children crossfades the pulse in place: the old child's picture leaves once the fade has ended
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(ParentSubjectsCard), findsNothing, reason: 'Sara has no subjects');
    expect(find.byType(ParentInsightsCard), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  // D-631 (break-ui): the premium layout with the greeting hero — a very long parent name, three children with long
  // names (the switcher in the hero's footer), huge counts on every stat card and shortcut, an empty week, no marks
  ParentOverviewData worst() {
    final p = pulseJson();
    p['week'] = {'scheduled': 99999, 'attended': 12345, 'missed': 87654, 'rate': 100, 'homework_due': 99999, 'homework_missing': 99999, 'homework_due_soon': 0, 'active_days': 7};
    p['upcoming'] = [];
    p['roadmap'] = {'field': {'name_ar': longAr, 'name_en': longEn}, 'done': 9999, 'total': 10000, 'next': {'id': 9, 'name_ar': longAr, 'name_en': longEn, 'progress': 99}};
    final j = Map<String, dynamic>.from(full().children.first.child);
    return ParentOverviewData.fromJson({
      'children': [
        {'child': j, 'pulse': p, 'courses': 123456, 'latest_marks': [], 'next_exam': {'name': '$longAr $longEn'}},
        {'child': {'id': 8, 'name': '$longEn $longAr'}, 'pulse': {'status': 'needs_you'}},
        {'child': {'id': 9, 'name': 'S'}, 'pulse': {'status': 'watch'}},
      ],
      'alerts_total': 987654,
      'requests': [for (var i = 0; i < 120; i++) {'id': i, 'status': 'pending'}],
    });
  }

  const greeting = ParentHomeGreeting(name: '$longAr $longEn', helpPageId: 'home.parent');

  testWidgets('premium: greeting hero, shortcuts, stat cards — worst case', (tester) async {
    await expectNoLayoutErrors(tester, () => body(data: worst(), greeting: greeting));
    await expectNoLayoutErrors(tester, () => body(data: withPulse(), greeting: greeting));
    await expectNoLayoutErrors(tester, () => body(data: full(), greeting: greeting));
    await expectNoLayoutErrors(tester, () => body(data: ParentOverviewData.fromJson(const {}), greeting: const ParentHomeGreeting(name: '')));
    await expectNoLayoutErrors(tester, () => body(loading: true, greeting: greeting));
    await expectNoLayoutErrors(tester, () => body(error: '$longAr $longEn', greeting: greeting));
  });

  testWidgets('message the teacher sheet', (tester) async {
    final teachers = [
      for (final t in [(1, 'Mr T', 'Maths'), (2, longEn, longEn)]) PulseTeacher(id: t.$1, name: t.$2, courseId: t.$1, courseEn: t.$3, courseAr: t.$3),
    ];
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(
          child: ParentMessageTeacherSheet(childId: 7, childName: '$longAr $longEn', teachers: teachers, courseId: 2),
        ));
  });

  testWidgets('empty: no children yet (with and without pending requests)', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => body(data: ParentOverviewData.fromJson({'children': [], 'alerts_total': 0, 'requests': [{'status': 'pending'}]})),
    );
    await expectNoLayoutErrors(tester, () => body(data: ParentOverviewData.fromJson(const {})));
  });

  testWidgets('loading: skeleton; error: retry', (tester) async {
    await expectNoLayoutErrors(tester, () => body(loading: true));
    await expectNoLayoutErrors(tester, () => body(error: '$longAr $longEn'));
  });
}
