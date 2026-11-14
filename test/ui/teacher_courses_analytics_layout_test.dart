// The Warm Editorial pieces of the analytics tabs and the course form (analytics_editorial.dart, the course report,
// the form's progress / currency / list cards) at 320x640 and 1400x900, ar / en, text x 1.3: no overflow, no layout
// exception, long texts included.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/analytics/analytics_summary.dart';
import 'package:flutter_education_app/features/shared/analytics/analytics_summary_ui.dart';
import 'package:flutter_education_app/features/student/analysis/analytics_editorial.dart';
import 'package:flutter_education_app/features/student/analysis/student_course_analytics_screen.dart';
import 'package:flutter_education_app/features/student/models.dart' show AppCurrency, CourseStatus;
import 'package:flutter_education_app/features/courses/teacher/component/course_progress_status_card.dart';
import 'package:flutter_education_app/features/courses/teacher/component/currency_selector.dart';
import 'package:flutter_education_app/features/courses/teacher/component/section_card.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import 'layout_harness.dart';

const _long = 'A very long sentence that keeps going to see how the block wraps a headline over several lines';

Widget _hero({bool lone = false}) => SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        AnalyticsMasthead(
          title: 'Analytics with a long title that wraps',
          subtitle: _long,
          actions: [AnalyticsHeaderAction(icon: Icons.refresh_rounded, tooltip: 'Refresh', onTap: () {})],
        ),
        const SizedBox(height: 16),
        AnalyticsHeroBlock(
          headline: _long,
          rings: [
            for (final m in lone ? const [AnMetric.progress] : AnMetric.values)
              AnRingSpec(metric: m, value: 64, delta: m == AnMetric.attendance ? -7 : 3, detail: '36 of 44 sessions'),
          ],
          overall: 100,
          footer: AnShowAllRow(label: 'My full analytics profile', onTap: () {}),
        ),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, children: [
          AnalyticsShortcut(icon: Icons.quiz_rounded, label: 'Exams and quizzes', color: Colors.teal, badge: 12, onTap: () {}),
          AnalyticsShortcut(icon: Icons.bookmark_rounded, label: 'Review bank', color: Colors.orange, onTap: () {}),
          const AnalyticsCourseMark(courseId: 3),
          const AnalyticsFact(icon: Icons.people_rounded, text: _long),
        ]),
      ]),
    );

Widget _formPieces() => SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        CourseProgressStatusCard(status: CourseStatus.inProgress, onChanged: (_) {}),
        const SizedBox(height: 16),
        CourseProgressStatusCard(status: CourseStatus.completed, editable: false, onChanged: (_) {}),
        const SizedBox(height: 16),
        CurrencySelector(label: 'Currency', selected: AppCurrency.values.first, onChanged: (_) {}),
        const SizedBox(height: 16),
        SectionCard(
          icon: Icons.build_rounded,
          title: 'Tools and software you will need for this course',
          items: const ['Visual Studio Code', _long],
          onAdd: () {},
          onRemove: (_) {},
        ),
        const SizedBox(height: 16),
        SectionCard(icon: Icons.checklist_rounded, title: 'Prerequisites', items: const [], onAdd: () {}, onRemove: (_) {}),
      ]),
    );

FakeApi _api() => FakeApi({
      'GET /api/v1/sessions/5/course_attendance/me': (_) => [
            for (var i = 1; i <= 14; i++)
              {
                'session': {'id': i, 'name': '$_long $i', 'scheduled_at': '2026-10-0${i % 9 + 1}T10:00:00Z', 'type': 'live'},
                'students': [
                  {'student_id': 1, 'student_name': 'S', 'is_attended': i.isEven, 'join_date': '2026-10-01T10:00:00Z', 'leave_date': '2026-10-01T11:00:00Z'},
                ],
              },
          ],
      'GET /api/v1/student/exams': (_) => [
            for (var i = 1; i <= 9; i++)
              {
                'id': i,
                'name': '$_long $i',
                'course_id': 5,
                'duration': 120,
                'total_marks': 100,
                'marks_obtained': i * 11,
                'percentage': i * 11.0,
                'passed': i > 4,
                'attempted': i != 9,
              },
          ],
      'GET /api/v1/data-lab/me/profile': (_) => {
            'student': {'id': 1, 'name': 'S'},
            'overall': {'progress': 50},
            'courses': [
              {
                'course': {'id': 5, 'title': _long},
                'progress': 50,
                'attendance': {'rate': 50, 'attended': 7, 'held': 14},
                'exams': {'avg': 49, 'items': []},
                'flags': {'review': 120, 'read': 3},
                'columns': [
                  {'key': 'progress', 'class_avg': 60},
                  {'key': 'project', 'label': _long, 'kind': 'manual', 'value': 18, 'max_value': 20, 'class_avg': 15},
                ],
              },
            ],
          },
    });

void main() {
  setUp(() {
    AppConfig.disableList = [];
    mockRequestPlugins();
  });

  testWidgets('the analytics hero block, masthead and shortcuts', (tester) async {
    await expectNoLayoutErrors(tester, _hero);
  });

  testWidgets('the analytics hero block with a lone ring', (tester) async {
    await expectNoLayoutErrors(tester, () => _hero(lone: true));
  });

  testWidgets('the course form cards', (tester) async {
    await expectNoLayoutErrors(tester, _formPieces);
  });

  for (final tab in [0, 1, 2, 3]) {
    testWidgets('the course report, tab $tab', (tester) async {
      final api = _api()..install();
      addTearDown(api.uninstall);
      await expectNoLayoutErrors(
        tester,
        () => StudentCourseAnalyticsScreen(courseId: 5, courseTitle: _long, initialTab: tab, progress: 50),
        frames: 8,
      );
    });
  }
}
