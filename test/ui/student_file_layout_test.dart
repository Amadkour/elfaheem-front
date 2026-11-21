// Layout of the unified student file (D-1400 phase 1): StudentFileView with every tab, a thin file, and
// StudentTimelineView with one item of every kind — 320×640 and 1400×900, ar / en, text × 1.3.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/org/students/student_file_models.dart';
import 'package:flutter_education_app/features/org/students/student_file_page.dart';
import 'package:flutter_education_app/features/org/students/student_file_tabs.dart';
import 'package:flutter_education_app/features/org/students/student_timeline.dart';
import 'package:flutter_education_app/features/org/students/students_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../org/student_file_models_test.dart' show sampleFileJson, sampleTimeline;
import 'layout_harness.dart';

const _longName = 'عبد الرحمن محمد عبد الرحيم عبد العزيز السيد الشناوي المنصوري';
const _longNameEn = 'Abdelrahman Mohamed Abdelrahim Abdelaziz Elsayed Elshenawy Elmansoury';

List<AccessLogEntry> _accessRows() => [
      for (final (i, s) in ['file', 'academic', 'documents', 'nid', 'advising', 'access_log', 'export'].indexed)
        AccessLogEntry(
          at: DateTime.utc(2026, 11, 21, 10, i),
          actorId: 44,
          actorName: i.isEven ? 'منى السيد عبد الحميد المصري' : 'Mona Elsayed Abdelhamid',
          actorRole: 'org-staff',
          section: s,
          ip: '196.2.x.x',
        ),
    ];

Widget _bodyFor(BuildContext context, StudentFile f, StudentFileTab tab) => switch (tab) {
      StudentFileTab.overview => StudentOverviewTab(file: f, onMissing: () {}, onOpenTab: (_) {}),
      StudentFileTab.timeline => StudentTimelineView(items: sampleTimeline(), hiddenKinds: const ['complaints'], hasMore: true),
      StudentFileTab.academic => StudentAcademicTab(academic: f.academic, standing: f.row.acadStanding, onOpenRecord: () {}),
      StudentFileTab.documents => StudentDocumentsTab(intake: f.intake, missingCount: f.row.missingCount, onOpenCase: () {}, onMissing: () {}),
      StudentFileTab.requests => StudentRequestsTab(open: f.open, can: f.can, onOpenComplaints: () {}, onOpenRequests: () {}),
      StudentFileTab.advising => StudentAdvisingTab(advisorName: f.academic?.advisorName, onOpen: () {}),
      StudentFileTab.accessLog => StudentAccessLogView(rows: _accessRows(), total: 14, hasMore: true),
    };

Widget _view(StudentFile f, StudentFileTab tab, {bool notice = true}) => StudentFileView(
      file: f,
      tab: tab,
      onTab: (_) {},
      bodyFor: (context, t) => _bodyFor(context, f, t),
      showRecordedNotice: notice,
      onMissing: () {},
    );

StudentFile _thin() {
  final j = sampleFileJson(can: const {}, name: 'س', nameEn: '');
  final s = j['student'] as Map<String, dynamic>;
  for (final k in ['email', 'phone', 'birth_date', 'nationality', 'intake', 'missing_count', 'program', 'level', 'student_code', 'nid_last4']) {
    s[k] = null;
  }
  s['flags'] = const [];
  s['chip'] = {'dimension': 'enrolment', 'value': 'withdrawn'};
  j['intake'] = null;
  j['academic'] = null;
  j['journey'] = const [];
  j['open'] = {'asks': 0, 'requests': 0, 'complaints': null, 'next_meeting': null};
  return StudentFile.fromJson(j);
}

void main() {
  final full = StudentFile.fromJson(sampleFileJson());
  final long = StudentFile.fromJson(sampleFileJson(name: _longName, nameEn: _longNameEn));

  for (final tab in StudentFileTab.values) {
    testWidgets('StudentFileView · ${tab.name}', (tester) async {
      await expectNoLayoutErrors(tester, () => _view(tab == StudentFileTab.overview ? long : full, tab));
    });
  }

  testWidgets('StudentFileView · a thin file (no rights, no case, a student who left)', (tester) async {
    final f = _thin();
    expect(studentFileTabs(f.can), [StudentFileTab.overview, StudentFileTab.timeline]);
    await expectNoLayoutErrors(tester, () => _view(f, StudentFileTab.overview, notice: false));
    await expectNoLayoutErrors(tester, () => _view(f, StudentFileTab.timeline, notice: false));
  });

  testWidgets('StudentFileView · a tab the caller may not see falls back to the first', (tester) async {
    await expectNoLayoutErrors(tester, () => _view(_thin(), StudentFileTab.accessLog));
    expect(find.byKey(const ValueKey('student-file-tab-accessLog')), findsNothing);
  });

  testWidgets('StudentTimelineView · one item of every kind', (tester) async {
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: StudentTimelineView(items: sampleTimeline(), hasMore: true)));
  });

  testWidgets('StudentTimelineView · loading, empty, error, one kind chosen', (tester) async {
    await expectNoLayoutErrors(tester, () => const SingleChildScrollView(child: StudentTimelineView(items: [], loading: true)));
    await expectNoLayoutErrors(tester, () => const SingleChildScrollView(child: StudentTimelineView(items: [], kind: 'results')));
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: StudentTimelineView(items: const [], error: 'Could not load', onRetry: () {})));
  });

  testWidgets('StudentAccessLogView · empty and loading', (tester) async {
    await expectNoLayoutErrors(tester, () => const SingleChildScrollView(child: StudentAccessLogView(rows: [])));
    await expectNoLayoutErrors(tester, () => const StudentAccessLogView(rows: [], loading: true));
  });

  testWidgets('StudentDocumentsTab · no admission case', (tester) async {
    await expectNoLayoutErrors(tester, () => const StudentDocumentsTab());
  });
}
