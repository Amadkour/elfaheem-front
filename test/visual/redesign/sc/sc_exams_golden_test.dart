// VISUAL review renders of the S-C student exam screens (redesign, Stu2Exams): the list, Review, the consent, the
// hand-in sheet and the result, with the CAST.md demo data, at 390x844 and 1360x900, Arabic and English, light.
// Compared by eye with D:/platform/redesign-ref/ref/student/068_* … 092_*. Not a CI suite.
//
//   flutter test test/visual/redesign/sc --update-goldens [--plain-name list]
@Tags(['visual'])
library;

import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/features/analytics/student/flags/student_flags_provider.dart';
import 'package:flutter_education_app/features/analytics/student/flags/student_flags_screen.dart';
import 'package:flutter_education_app/features/exams/exam_consent_screen.dart';
import 'package:flutter_education_app/features/exams/exam_result_screen.dart';
import 'package:flutter_education_app/features/exams/legacy/student/student_exam_list_screen.dart';
import 'package:flutter_education_app/features/exams/legacy/student/student_exam_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../../support/redesign/sc_fakes.dart';
import '../kit_golden_harness.dart';

void main() {
  late StorageService storage;
  setUpAll(() async => storage = await kitGoldenSetUp());

  testWidgets('list', (tester) async {
    await kitRender(tester, 'sc_exams_list', () => ChangeNotifierProvider(
          create: (_) => StudentExamProvider(api: ScFakeExamApi()),
          child: StudentExamListScreen(flagsApi: ScFakeFlagsApi(), showOffline: false),
        ), storage: storage, modes: const [false]);
  });

  testWidgets('review', (tester) async {
    await kitRender(tester, 'sc_exams_review', () => StudentFlagsScreen(
          courseNames: scCourseNames,
          provider: StudentFlagsProvider(api: ScFakeFlagsApi())..load(),
        ), storage: storage, modes: const [false]);
  });

  testWidgets('consent', (tester) async {
    await kitRender(tester, 'sc_exams_consent', () => ConsentBody(
          title: 'إقرار قبل الاختبار', body: 'نص الإقرار', version: 2, requires: const {}, capabilities: const [],
          accepted: false, busy: false, onAccept: () {}, examTitle: 'اختبار الدوال الأسية', subtitle: 'الرياضيات، أ. ماجد الشهري',
          closes: 'يقفل بكرة ٩:٠٠ م', firstName: 'فيصل', questions: 20, minutes: 45, attempts: 2,
        ), storage: storage, modes: const [false], grow: false);
  });

  testWidgets('result', (tester) async {
    await kitRender(tester, 'sc_exams_result_pass', () => const ExamResultBody(
          examTitle: 'اختبار الدوال الأسية، الرياضيات', firstName: 'فيصل',
          result: {'visible': true, 'state': 'graded', 'score': 44, 'max_score': 50, 'percentage': 88, 'passed': true},
        ), storage: storage, modes: const [false]);
    await kitRender(tester, 'sc_exams_result_pending', () => const ExamResultBody(
          examTitle: 'مقال: My weekend', result: {'visible': false, 'state': 'submitted', 'needs_review': true},
        ), storage: storage, modes: const [false], langs: const ['ar']);
  });
}
