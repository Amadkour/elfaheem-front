// The Analytics summary widgets (lib/features/shared/analytics/analytics_summary_ui.dart) and the student's real
// Analytics tab over a fake data source, at 320x640 and 1400x900, Arabic + English, textScaler 1.3: no overflow, no
// layout exception — with long course names, a lone ring (no Data Lab), the skeleton, the segmented switch and the
// "Show all" that unfolds in place.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/analytics/analytics_summary.dart';
import 'package:flutter_education_app/features/shared/analytics/analytics_summary_ui.dart';
import 'package:flutter_education_app/features/attendance/analysis/student/student_attendance_model.dart';
import 'package:flutter_education_app/features/student/analysis/student_analytics_api.dart';
import 'package:flutter_education_app/features/student/analysis/student_analytics_provider.dart';
import 'package:flutter_education_app/features/student/analysis/student_analytics_screen.dart';
import 'package:flutter_education_app/features/teacher/data_lab/data_lab_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'layout_harness.dart';

const longAr = 'إدارة شؤون الطلاب والدراسات العليا والبحث العلمي بكلية الهندسة';
const longEn = 'Office of Student Affairs, Graduate Studies and Scientific Research';

String _t() => AppConfig.lang == 'ar' ? longAr : longEn;

Widget _gallery({bool lone = false}) => SingleChildScrollView(
      child: AnSummaryLayout(
        header: AnPageHeader(
          title: _t(),
          subtitle: _t(),
          actions: [AnHeaderIcon(icon: Icons.refresh_rounded, tooltip: 'Refresh', onTap: () {})],
        ),
        hero: AnSummaryHero(
          headline: '${_t()} ${_t()}',
          overall: 73,
          rings: lone
              ? const [AnRingSpec(metric: AnMetric.progress, value: 65)]
              : const [
                  AnRingSpec(metric: AnMetric.progress, value: 65, delta: 12),
                  AnRingSpec(metric: AnMetric.attendance, value: 83, delta: -4, detail: '36 of 44 sessions'),
                  AnRingSpec(metric: AnMetric.exams, value: null, delta: 0),
                ],
          footer: AnShowAllRow(label: _t(), onTap: () {}),
        ),
        tiles: AnStatTiles(tiles: [
          for (var i = 0; i < 4; i++) AnTileSpec(icon: Icons.menu_book_rounded, label: _t(), value: '1284/2000', onTap: () {}),
        ]),
        insights: AnInsightCard(title: _t(), rows: [
          AnInsightRowData(tone: AnTone.warn, text: '${_t()} ${_t()}', onTap: () {}),
          const AnInsightRowData(tone: AnTone.info, text: 'x'),
          AnInsightRowData(tone: AnTone.good, text: _t()),
        ]),
        chart: AnCourseBars(
          title: _t(),
          metric: AnMetric.attendance,
          metrics: AnMetric.values,
          onMetric: (_) {},
          rows: [
            for (var i = 0; i < 7; i++)
              AnBarRowData(title: _t(), value: i * 16.0, classValue: i.isEven ? 50 : null, detail: '12/14', flag: i == 2, onTap: () {}),
            const AnBarRowData(title: 'none', value: null),
          ],
          onShowAll: () {},
        ),
        lists: [
          AnCompactList(title: _t(), subtitle: _t(), rows: [
            for (var i = 0; i < 5; i++) AnExamRow(name: _t(), course: _t(), score: 30.0 + i * 15, passed: i > 0, onTap: () {}),
          ]),
          AnCompactList(title: _t(), rows: [
            for (var i = 0; i < 2; i++) AnPersonRow(name: _t(), course: _t(), attendance: 41, exams: 88, onTap: () {}),
          ]),
          const AnCompactList(title: 'empty', rows: [], empty: 'Nothing yet'),
          const AnCompactList(title: 'hidden', rows: []),
        ],
      ),
    );

class _FakeApi extends StudentAnalyticsApi {
  _FakeApi({this.profile = true});
  final bool profile;

  @override
  Future<List<EnrolledCourse>> fetchMyEnrollments() async => [
        for (var i = 1; i <= 6; i++) EnrolledCourse(id: i, title: '${_t()} $i', teacherName: _t(), sessionsCount: 12, progress: i * 15),
      ];

  @override
  Future<DlProfile?> fetchMyProfile({int? courseId}) async => !profile
      ? null
      : DlProfile.fromJson({
          'student': {'id': 1, 'name': _t()},
          'overall': {'progress': 50, 'attendance': 70, 'exam_avg': 61, 'review_flags': 3},
          'courses': [
            for (var i = 1; i <= 6; i++)
              {
                'course': {'id': i, 'title': '${_t()} $i'},
                'progress': i * 15,
                'attendance': {'rate': 40.0 + i * 9, 'attended': 4 + i, 'held': 12},
                'exams': {
                  'avg': 30.0 + i * 10,
                  'items': [
                    {'name': _t(), 'best_percentage': 30.0 + i * 10, 'attempts': 1, 'passed': i > 2},
                  ],
                },
                'flags': {'review': i.isEven ? 2 : 0, 'read': 0},
                'columns': [
                  {'key': 'progress', 'class_avg': 60},
                  {'key': 'attendance', 'class_avg': 75},
                  {'key': 'exam_avg', 'class_avg': 64},
                ],
              },
          ],
        });
}

Widget _screen({bool profile = true}) => ChangeNotifierProvider<StudentAnalyticsProvider>(
      create: (_) => StudentAnalyticsProvider(api: _FakeApi(profile: profile)),
      child: const StudentAnalyticsScreen(),
    );

void main() {
  setUp(() => AppConfig.disableList = []);

  testWidgets('summary widgets fit with long texts', (tester) async {
    await expectNoLayoutErrors(tester, _gallery);
  });

  testWidgets('a lone ring (no Data Lab profile)', (tester) async {
    await expectNoLayoutErrors(tester, () => _gallery(lone: true));
  });

  testWidgets('"Show all" unfolds the list in place', (tester) async {
    await expectNoLayoutErrors(tester, _gallery, act: (tester) async {
      expect(find.byType(AnExamRow), findsNWidgets(3));
      final all = find.textContaining('(5)');
      await tester.ensureVisible(all.first);
      await tester.pump();
      await tester.tap(all.first);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AnExamRow), findsNWidgets(5));
    });
  });

  testWidgets('skeleton', (tester) async {
    await expectNoLayoutErrors(tester, () => const SingleChildScrollView(child: AnSummarySkeleton()));
  });

  testWidgets('the student Analytics tab, and its metric switch', (tester) async {
    await expectNoLayoutErrors(tester, _screen, frames: 6, act: (tester) async {
      final seg = find.text(anMetricLabel(AnMetric.attendance));
      expect(seg, findsWidgets);
      await tester.ensureVisible(seg.last);
      await tester.pump();
      await tester.tap(seg.last);
      await tester.pump(const Duration(milliseconds: 300));
      // attendance mode shows "attended/held" next to each course
      expect(find.text('10/12'), findsOneWidget); // the best attendance leads
    });
  });

  testWidgets('the student Analytics tab without the profile', (tester) async {
    await expectNoLayoutErrors(tester, () => _screen(profile: false), frames: 6);
  });
}
