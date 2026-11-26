// Review renders of the student's subject page (SubjectProfile rows 3-8) and the lessons page (Stu1Learn
// sessions), with CAST.md data, to compare by eye with D:/platform/redesign-ref/ref/subject/003-008 and
// ref/student/042. Not a CI suite.
//
//   flutter test test/visual/redesign/sb/subject_golden_test.dart --update-goldens
@Tags(['visual'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/config/theme/kit_palette.dart' show AppArea;
import 'package:flutter_education_app/design/app_kit.dart' show AppAreaScope;
import 'package:flutter_education_app/features/courses/course_space/subject_lesson_panel.dart';
import 'package:flutter_education_app/features/courses/course_space/subject_lessons_page.dart';
import 'package:flutter_education_app/features/courses/course_space/subject_panel.dart';
import 'package:flutter_education_app/features/courses/course_space/subject_space.dart';
import 'package:flutter_education_app/features/sessions/teacher/sessions_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../../support/fake_api.dart';
import '../../../support/redesign/sb_subject_fakes.dart';
import '../kit_golden_harness.dart';

Widget _panel(SubjectLessonTab tab) => AppAreaScope(
      area: AppArea.learn,
      child: ChangeNotifierProvider(
        create: (_) => TeacherCourseScreenProvider(initialCourse: demoTeacherCourse()),
        child: SubjectPanelFrame(
          title: sbT('الدرس ١: الدوال', 'Lesson 1: Functions'),
          child: SubjectLessonPanel(session: demoLessonSession().toTeacher, initialTab: tab),
        ),
      ),
    );

Widget _lessons() => SubjectLessonsPage(
      steps: [
        for (var i = 0; i < 5; i++)
          SubjectStep(id: 'f$i', number: i + 1, title: sbT('مدخل $i', 'Intro $i'), meta: sbT('درس', 'Lesson'), state: SubjectStepState.done),
        SubjectStep(
          id: 'r6',
          number: 6,
          title: sbT('مراجعة الوحدة الأولى', 'Unit 1 review'),
          meta: sbT('اجتزت اختبارها ٩٠٪', 'Passed its quiz at 90%'),
          state: SubjectStepState.done,
        ),
        SubjectStep(
          id: 'l7',
          number: 7,
          title: sbT('الدوال الأسية', 'Exponential functions'),
          meta: sbT('حصة مباشرة الحين مع أ. ماجد', 'Live now with Mr Majed'),
          kind: SubjectStepKind.live,
          state: SubjectStepState.live,
          onJoin: () {},
        ),
        SubjectStep(
          id: 'c8',
          number: 8,
          title: sbT('الدوال اللوغاريتمية', 'Logarithmic functions'),
          meta: sbT('درس، ٣٨ دقيقة واختبار قصير', 'Lesson, 38 minutes and a short quiz'),
          state: SubjectStepState.current,
        ),
        SubjectStep(id: 'k9', number: 9, title: sbT('خصائص اللوغاريتمات', 'Log properties'), meta: sbT('درس، ٣٢ دقيقة', 'Lesson, 32 minutes'), state: SubjectStepState.locked),
        SubjectStep(
          id: 'k10',
          number: 10,
          title: sbT('حل المعادلات الأسية', 'Solving exponential equations'),
          meta: sbT('حصة مباشرة، الأحد ٧:٣٠ م', 'Live class, Sunday 7:30 pm'),
          kind: SubjectStepKind.live,
          state: SubjectStepState.locked,
        ),
        SubjectStep(
          id: 'e11',
          number: 11,
          title: sbT('اختبار الوحدة الثانية', 'Unit 2 test'),
          meta: sbT('اختبار، ٢٠ سؤال', 'Quiz, 20 questions'),
          kind: SubjectStepKind.exam,
          chip: sbT('الخميس', 'Thursday'),
        ),
      ],
      teacher: sbT('أ. ماجد الشهري', 'Mr Majed Alshehri'),
      kicker: sbT('الرياضيات، ثاني ثانوي', 'Mathematics, grade 11'),
      done: 9,
      total: 24,
      onBack: () {},
    );

void main() {
  late StorageService storage;
  setUpAll(() async => storage = await kitGoldenSetUp());

  testWidgets('subject main, live', (t) async {
    await kitRender(t, 'sb_subject_main_live', () => demoSubjectSpace(), storage: storage, modes: const [false]);
  });

  testWidgets('subject main, next class', (t) async {
    await kitRender(t, 'sb_subject_main_next', () => demoSubjectSpace(live: false), storage: storage,
        modes: const [false], langs: const ['ar']);
  });

  testWidgets('subject book open', (t) async {
    await kitRender(
      t,
      'sb_subject_book_open',
      () => demoSubjectSpace(),
      storage: storage,
      modes: const [false],
      langs: const ['ar'],
      sizes: const [Size(1360, 900)],
      grow: false,
      act: (t) async => t.tap(find.bySemanticsLabel(RegExp('اضغط على الكتاب')).first),
    );
  });

  group('lesson panel', () {
    late FakeApi fake;
    setUp(() {
      mockRequestPlugins();
      fake = FakeApi(lessonMaterialRoutes(), latency: Duration.zero)..install();
    });
    tearDown(() => fake.uninstall());

    testWidgets('video', (t) async {
      await kitRender(t, 'sb_subject_lesson_video', () => _panel(SubjectLessonTab.video), storage: storage,
          modes: const [false], grow: false);
    });

    testWidgets('book', (t) async {
      await kitRender(t, 'sb_subject_lesson_book', () => _panel(SubjectLessonTab.book), storage: storage,
          modes: const [false], langs: const ['ar'], grow: false);
    });
  });

  testWidgets('lessons page', (t) async {
    await kitRender(t, 'sb_subject_lessons', _lessons, storage: storage, modes: const [false], scaffold: false);
  });
}
