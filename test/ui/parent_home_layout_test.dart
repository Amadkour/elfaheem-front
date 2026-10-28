// The parent's Today tab body (Track B.5) at 320x640 and 1400x900, Arabic + English, textScaler 1.3:
// full (two children, sessions, marks, exam, alerts), empty (no children, pending requests), loading, error.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/home_kit.dart';
import 'package:flutter_education_app/features/parent/parent_overview.dart';
import 'package:flutter_education_app/features/parent/parent_overview_page.dart';
import 'package:flutter_test/flutter_test.dart';

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

  Widget body({ParentOverviewData? data, bool loading = false, String? error}) => SingleChildScrollView(
        child: ParentOverviewBody(
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
