// The student's subject page (S-B, SubjectProfile rows 3-8) and the lessons page (Stu1Learn sessions): no layout
// error at any size / language / text scale, the privacy rule (no student counts), the path window, the fold, and
// the lesson panel's tabs over real materials.

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/courses/course_space/subject_lesson_panel.dart';
import 'package:flutter_education_app/features/courses/course_space/subject_lessons_page.dart';
import 'package:flutter_education_app/features/courses/course_space/subject_panel.dart';
import 'package:flutter_education_app/features/courses/course_space/subject_space.dart';
import 'package:flutter_education_app/features/sessions/material/session_material_model.dart';
import 'package:flutter_education_app/features/sessions/teacher/sessions_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../support/redesign/sb_subject_fakes.dart';
import 'layout_harness.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('subject page: live class', (t) async {
    await expectNoLayoutErrors(t, () => demoSubjectSpace());
  });

  testWidgets('subject page: next class', (t) async {
    await expectNoLayoutErrors(t, () => demoSubjectSpace(live: false));
  });

  testWidgets('subject page: the book opens (wide) and the sheet opens (phone)', (t) async {
    await expectNoLayoutErrors(
      t,
      () => demoSubjectSpace(),
      act: (t) async {
        await t.tap(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'sb_subj_tap_book_hint'.tr).first);
      },
    );
  });

  testWidgets('subject page: no student count anywhere', (t) async {
    AppConfig.lang = 'ar';
    t.view.physicalSize = const Size(1360, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(layoutHost(demoSubjectSpace()));
    await t.pump(const Duration(milliseconds: 500));
    for (final w in ['طالب', 'طلاب', 'students', 'Students']) {
      expect(find.textContaining(RegExp('\\d+ $w')), findsNothing, reason: w);
    }
    expect(find.byIcon(Icons.groups_rounded), findsNothing);
  });

  test('the path window starts one step before the current one', () {
    final steps = demoSubjectSteps(live: false, extra: 6);
    final w = SubjectSpace.pathWindow(steps);
    expect(w.length, kSubjectPathSteps);
    expect(w.first.number, 1);
    final live = demoSubjectSteps(extra: 6);
    expect(SubjectSpace.pathWindow(live).first.number, 1);
  });

  test('a finished start of three or more folds, keeping its last step', () {
    final done = [
      for (var i = 0; i < 5; i++) SubjectStep(id: '$i', number: i + 1, title: 't', meta: 'm', state: SubjectStepState.done),
      const SubjectStep(id: 'x', number: 6, title: 't', meta: 'm'),
    ];
    expect(subjectFoldCount(done), 4);
    expect(subjectFoldCount(done.sublist(3)), 0);
  });

  testWidgets('lessons page', (t) async {
    await expectNoLayoutErrors(
      t,
      () => SubjectLessonsPage(
        steps: [
          for (var i = 0; i < 5; i++)
            SubjectStep(id: 'f$i', number: i + 1, title: 'مدخل $i', meta: 'درس', state: SubjectStepState.done),
          ...demoSubjectSteps(extra: 3).skip(1),
        ],
        teacher: 'أ. ماجد الشهري',
        kicker: 'الرياضيات، ثاني ثانوي',
        done: 9,
        total: 24,
        onBack: () {},
      ),
      scaffold: false,
    );
  });

  testWidgets('lessons page: empty', (t) async {
    await expectNoLayoutErrors(t, () => const SubjectLessonsPage(steps: [], teacher: 'أ. ماجد الشهري'), scaffold: false);
  });

  group('lesson panel', () {
    late FakeApi fake;
    setUp(() {
      mockRequestPlugins();
      fake = FakeApi(lessonMaterialRoutes(), latency: Duration.zero)..install();
    });
    tearDown(() => fake.uninstall());

    test('materials fall into their tabs', () {
      expect(subjectLessonTabOf(SessionMaterialType.video), SubjectLessonTab.video);
      expect(subjectLessonTabOf(SessionMaterialType.pdf), SubjectLessonTab.book);
      expect(subjectLessonTabOf(SessionMaterialType.image), SubjectLessonTab.imgs);
      expect(subjectLessonTabOf(SessionMaterialType.recording), isNull);
    });

    for (final tab in [SubjectLessonTab.video, SubjectLessonTab.book, SubjectLessonTab.imgs]) {
      testWidgets('tab ${tab.name}', (t) async {
        await expectNoLayoutErrors(
          t,
          () => ChangeNotifierProvider(
            create: (_) => TeacherCourseScreenProvider(initialCourse: demoTeacherCourse()),
            child: SubjectPanelFrame(
              title: 'الدرس ١: الدوال',
              child: SubjectLessonPanel(session: demoLessonSession().toTeacher, initialTab: tab),
            ),
          ),
        );
        expect(fake.calls.any((c) => c.path.contains('/sessions/7/materials')), isTrue);
      });
    }
  });
}
