// S-B learn screens for review by eye next to D:/platform/redesign-ref/ref/student/043..049, 055: the lesson content
// (start and retry), the player page (playing, the next-lesson countdown, audio only), the private-course code
// (typing, wrong) and the student's Records. 390x844 and 1360x900, ar + en, light. Not a CI suite.
//
//   flutter test test/visual/redesign/sb/learn_golden_test.dart --update-goldens
@Tags(['visual'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/courses/student/details/course_access_sheet.dart';
import 'package:flutter_education_app/features/records/records_page.dart';
import 'package:flutter_education_app/features/sessions/material/components/lesson_material_view.dart';
import 'package:flutter_education_app/features/sessions/video/vod_player_parts.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/redesign/sb_learn_fakes.dart';
import '../kit_golden_harness.dart';

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

Widget _material(LessonQuizState q) => Builder(
      builder: (context) => AppAreaScope(
        area: AppArea.learn,
        child: Column(children: [
          ScreenAppBar(title: _t('الدرس ٨', 'Lesson 8')),
          Expanded(
            child: ListView(children: [
              AppHeroOverlap(
                hero: AppHero(
                  kicker: _t('الدرس ٨', 'Lesson 8'),
                  title: _t('الدوال اللوغاريتمية', 'Logarithmic functions'),
                  subtitle: _t('فيديو، ملخص، واختبار قصير', 'Video, summary and a short quiz'),
                  wipe: false,
                ),
                body: sbLessonView(quiz: q),
              ),
            ]),
          ),
        ]),
      ),
    );

Widget _sheet(Widget child) => Builder(
      builder: (context) => Stack(children: [
        Positioned.fill(child: ColoredBox(color: context.colors.background)),
        Align(
          alignment: MediaQuery.sizeOf(context).width < 700 ? Alignment.bottomCenter : Alignment.center,
          child: Container(
            constraints: BoxConstraints(maxWidth: AppWidth.form.max - AppSpace.xxxl * 2),
            decoration: BoxDecoration(
              color: context.colors.cardBg,
              borderRadius: BorderRadius.circular(AppRadius.sheet),
            ),
            child: AppAreaScope(area: AppArea.learn, child: child),
          ),
        ),
      ]),
    );

Widget _countdownStage() => Builder(
      builder: (context) => ColoredBox(
        color: context.colors.kit.deep,
        child: Center(
          child: VodNextUpCard(
            next: sbMaterial(9, _t('٩. خصائص اللوغاريتمات', '9. Properties of logarithms')),
            seconds: 5,
            maxWidth: 320,
            onPlay: () {},
            onCancel: () {},
          ),
        ),
      ),
    );

Widget _audioStage() => Builder(
      builder: (context) => ColoredBox(
        color: context.colors.kit.deep,
        child: Center(child: Icon(Icons.headphones_rounded, size: AppIconSize.hero * 2, color: context.colors.onHeroMuted)),
      ),
    );

void main() {
  late StorageService storage;
  setUpAll(() async => storage = await kitGoldenSetUp());

  testWidgets('sb learn material', (t) async {
    await kitRender(t, 'sb_material', () => _material(LessonQuizState.start), storage: storage, modes: const [false]);
  });

  testWidgets('sb learn material retry', (t) async {
    await kitRender(t, 'sb_material_retry', () => _material(LessonQuizState.retry), storage: storage, modes: const [false], langs: const ['ar']);
  });

  testWidgets('sb learn player', (t) async {
    await kitRender(t, 'sb_player', () => sbPlayerPage(wide: true), storage: storage, modes: const [false], grow: false, scaffold: false);
  });

  testWidgets('sb learn player end', (t) async {
    await kitRender(t, 'sb_player_end', () => sbPlayerPage(wide: true, stage: _countdownStage()),
        storage: storage, modes: const [false], langs: const ['ar'], grow: false, scaffold: false);
  });

  testWidgets('sb learn player audio', (t) async {
    await kitRender(t, 'sb_player_audio', () => sbPlayerPage(wide: true, stage: _audioStage()),
        storage: storage, modes: const [false], langs: const ['ar'], grow: false, scaffold: false);
  });

  testWidgets('sb learn code', (t) async {
    await kitRender(
      t,
      'sb_code',
      () => _sheet(CourseAccessSheet(courseId: 1, courseName: _t('القدرات: مجموعة أ. خالد المطيري', 'Qudurat: Mr Khalid Almutairi group'), onContact: () {}, initialCode: '3714')),
      storage: storage,
      modes: const [false],
      grow: false,
    );
  });

  testWidgets('sb learn code wrong', (t) async {
    await kitRender(
      t,
      'sb_code_wrong',
      () => _sheet(CourseAccessSheet(
        courseId: 1,
        courseName: _t('القدرات: مجموعة أ. خالد المطيري', 'Qudurat: Mr Khalid Almutairi group'),
        onContact: () {},
        initialCode: '371402',
        initialError: CourseCodeError.wrong,
        initialMessage: courseCodeWrongText(2),
      )),
      storage: storage,
      modes: const [false],
      langs: const ['ar'],
      grow: false,
    );
  });

  testWidgets('sb learn records', (t) async {
    await kitRender(t, 'sb_records', () => RecordsPage(api: SbLearnRecordsApi(sbRecords()), student: true),
        storage: storage, modes: const [false], scaffold: false);
  });
}
