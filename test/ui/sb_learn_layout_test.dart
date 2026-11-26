// S-B learn screens (Stu1Learn material, exam=retry, player, mode=end, code, pin=wrong, records): every new
// plain-values widget at 320x640 and 1400x900, ar / en, text scale 1.3, plus the code sheet's states and the quiz
// card's mapping from the exam gate.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/courses/student/details/course_access_sheet.dart';
import 'package:flutter_education_app/features/records/records_api.dart';
import 'package:flutter_education_app/features/records/records_page.dart';
import 'package:flutter_education_app/features/records/records_student_parts.dart';
import 'package:flutter_education_app/features/sessions/material/components/lesson_material_view.dart';
import 'package:flutter_education_app/features/sessions/video/vod_lesson_page.dart';
import 'package:flutter_education_app/features/sessions/video/vod_player_parts.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/redesign/sb_learn_fakes.dart';
import 'layout_harness.dart';

void main() {
  testWidgets('lesson content: video, files and every quiz state', (t) async {
    for (final q in LessonQuizState.values) {
      await expectNoLayoutErrors(
        t,
        () => AppAreaScope(area: AppArea.learn, child: SingleChildScrollView(child: sbLessonView(quiz: q))),
      );
    }
  });

  testWidgets('lesson content: nothing yet', (t) async {
    await expectNoLayoutErrors(
      t,
      () => const AppAreaScope(
        area: AppArea.learn,
        child: SingleChildScrollView(child: LessonMaterialView(empty: Text('—'))),
      ),
    );
  });

  testWidgets('player page: header, actions, lessons around a stage', (t) async {
    for (final wide in [false, true]) {
      await expectNoLayoutErrors(t, () => sbPlayerPage(wide: wide), scaffold: false);
    }
  });

  testWidgets('next lesson countdown and its cancelled state', (t) async {
    for (final s in [5, null]) {
      await expectNoLayoutErrors(
        t,
        () => Center(
          child: VodNextUpCard(next: sbMaterial(9, 'خصائص اللوغاريتمات'), seconds: s, onPlay: () {}, onCancel: () {}),
        ),
      );
    }
  });

  testWidgets('private course code: typing, wrong, locked', (t) async {
    for (final (code, err, msg) in [
      ('3714', null, null),
      ('371402', CourseCodeError.wrong, courseCodeWrongText(2)),
      ('', CourseCodeError.locked, courseCodeWaitText(15)),
    ]) {
      await expectNoLayoutErrors(
        t,
        () => AppAreaScope(
          area: AppArea.learn,
          child: CourseAccessSheet(
            courseId: 1,
            courseName: 'القدرات: مجموعة أ. خالد المطيري',
            onContact: () {},
            initialCode: code,
            initialError: err,
            initialMessage: msg,
          ),
        ),
      );
    }
  });

  testWidgets('a wrong code from the server shows its message and keeps the digits', (t) async {
    final api = SbLearnUnlock(statusCode: 403, detail: {'code': 'wrong_code', 'attempts_left': 2});
    await t.pumpWidget(layoutHost(
      AppAreaScope(area: AppArea.learn, child: CourseAccessSheet(courseId: 5, courseName: 'x', unlock: api.call, initialCode: '371402')),
      scale: 1,
    ));
    await t.pump();
    await t.tap(find.byType(AppButton).first);
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(api.calls, ['371402']);
    expect(find.text(courseCodeWrongText(2)), findsOneWidget);
  });

  testWidgets('student records: hero, groups and rows', (t) async {
    final items = sbRecords();
    await expectNoLayoutErrors(
      t,
      () => AppAreaScope(
        area: AppArea.learn,
        child: ListView(children: [
          AppHeroOverlap(
            hero: RecordsStudentHero(
              bottom: AppTabs(
                hug: true,
                index: 0,
                items: recordsStudentTabs(groupRecords(items), shared: true),
                onChanged: (_) {},
              ),
            ),
            body: RecordsStudentGroups(groups: groupRecords(items), showImages: false, onMore: (_) {}, onTap: (_) {}),
          ),
        ]),
      ),
    );
  });

  testWidgets('student records page draws the student look with the fake library', (t) async {
    await expectNoLayoutErrors(t, () => RecordsPage(api: SbLearnRecordsApi(sbRecords()), student: true), scaffold: false);
  });
}
