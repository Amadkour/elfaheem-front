// Review renders of the S-A home and discover screens (StuHome, Stu1Discover) with the CAST demo data (Faisal,
// الثاني ثانوي; maths with أ. ماجد الشهري live 7:30 م), 390x844 and 1360x900, next to
// D:/platform/redesign-ref/ref/student/001_*, 033_* … 041_*. Not a CI suite.
//
//   flutter test test/visual/redesign/sa/sa_home_golden_test.dart --update-goldens
@Tags(['visual'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/core/home/me_home.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/chrome_button.dart' show ChromeIconButton;
import 'package:flutter_education_app/features/auth/account_approval_page.dart';
import 'package:flutter_education_app/features/auth/auth_shell.dart';
import 'package:flutter_education_app/features/courses/category/categories_provider.dart' show CategoryModel;
import 'package:flutter_education_app/features/courses/category/subject_tiles.dart';
import 'package:flutter_education_app/features/courses/course_list_card.dart';
import 'package:flutter_education_app/features/home/student/home_hero.dart';
import 'package:flutter_education_app/features/home/student/home_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../kit_golden_harness.dart';

late StorageService _storage;
final _now = DateTime.utc(2026, 11, 25, 16, 42); // Wednesday, 7:42 م in Riyadh

bool get _ar => AppConfig.lang == 'ar';

MeHome _home() => MeHome.fromJson({
      'courses_progress': [
        {
          'course_id': 1,
          'name_ar': 'الرياضيات',
          'name_en': 'Mathematics',
          'progress': 38,
          'next_lecture': {'id': 11, 'name': _ar ? 'الدوال الأسية' : 'Exponential functions'},
        },
        {
          'course_id': 2,
          'name_ar': 'الفيزياء',
          'name_en': 'Physics',
          'progress': 64,
          'next_lecture': {'id': 21, 'name': _ar ? 'قوانين نيوتن' : "Newton's laws"},
        },
        {
          'course_id': 3,
          'name_ar': 'الإنجليزي من الصفر',
          'name_en': 'English from zero',
          'progress': 81,
          'next_lecture': {'id': 31, 'name': 'Unit 4: Daily routines'},
        },
        {'course_id': 4, 'name_ar': 'القدرات: القسم الكمي', 'name_en': 'Qudurat: quantitative', 'progress': 100},
      ],
    });

List<MeLiveRoom> _live() => [
      MeLiveRoom.fromJson({
        'id': 7,
        'kind': 'session',
        'title': _ar ? 'الرياضيات: الدوال الأسية' : 'Maths: exponential functions',
        'course_id': 1,
        'host': {'id': 9, 'name': _ar ? 'أ. ماجد الشهري' : 'Mr. Majed Al-Shehri'},
        'live_started_at': '2026-11-25T16:30:00',
      })!,
    ];

Widget _homePage({bool live = true}) {
  final h = _home();
  return AppAreaScope(
    area: AppArea.home,
    child: SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Builder(
          builder: (context) => MediaQuery.sizeOf(context).width < 700
              ? StudentHomeTopBar(actions: [
                  ChromeIconButton(icon: Icons.chat_bubble_outline_rounded, label: 'chat', badge: 2, onTap: () {}),
                  ChromeIconButton(icon: Icons.notifications_none_rounded, label: 'bell', badge: 5, onTap: () {}),
                ])
              : const SizedBox.shrink(),
        ),
        AppHeroOverlap(
          hero: StudentHomeHero(
            name: _ar ? 'فيصل' : 'Faisal',
            home: h,
            now: _now,
            line: studentHeroLine(live: live ? _live() : const [], featured: h.coursesProgress.first),
            daySummary: _ar ? 'بعدها اختبار الدوال، يقفل ٩ المساء' : 'Then the functions quiz, it closes at 9 pm',
          ),
          body: StudentHomeBody(
            data: StudentHomeData(home: h, now: _now, liveNow: live ? _live() : const []),
            onTab: (_) {},
          ),
        ),
      ]),
    ),
  );
}

Widget _courses() {
  CourseListCard card(String title, String who, Widget footer, {bool live = false}) => CourseListCard(
        shape: CourseCardShape.row,
        title: title,
        imageUrl: '',
        meta: [who, _ar ? '٢٤ درس' : '24 lessons'],
        chip: live ? const CourseCoverChip(label: 'مباشر اليوم') : null,
        footer: footer,
      );
  return AppAreaScope(
    area: AppArea.learn,
    child: SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppHero(kicker: _ar ? 'دوراتي' : 'My courses', title: _ar ? 'عندك ٤ دورات شغّالة' : 'You have 4 courses going'),
        Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Column(children: [
            for (final (t, w, p) in [
              ('الرياضيات ٢ ثانوي، الفصل الأول', 'أ. ماجد الشهري', 38),
              ('الفيزياء: الحركة والقوى', 'أ. فهد المطيري', 64),
              ('الإنجليزي من الصفر', 'أ. خالد العتيبي', 81),
            ]) ...[
              card(t, w, CourseProgressFooter(progress: p), live: p == 38),
              const SizedBox(height: AppSpace.sm),
            ],
          ]),
        ),
      ]),
    ),
  );
}

Widget _explore() {
  final cats = [
    for (final n in ['الرياضيات', 'الفيزياء', 'الكيمياء', 'الأحياء', 'اللغة الإنجليزية', 'لغتي', 'البرمجة', 'القدرات'])
      CategoryModel(id: n, nameAr: n, nameEn: n, imageUrl: null, description: ''),
  ];
  return AppAreaScope(
    area: AppArea.learn,
    child: SingleChildScrollView(
      child: AppHeroOverlap(
        hero: AppHero(
          kicker: 'sa_explore_kicker'.tr,
          title: 'sa_explore_title'.tr,
          bottom: CourseSearchField(controller: TextEditingController(), hint: 'sa_explore_search_hint', onChanged: (_) {}),
        ),
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
          child: SubjectsCard(categories: cats, onOpen: (_) {}, onAll: () {}),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() async => _storage = await kitGoldenSetUp());

  testWidgets('home', (tester) async {
    await kitRender(tester, 'sa_home', () => _homePage(), storage: _storage, modes: const [false]);
  });

  testWidgets('my courses', (tester) async {
    await kitRender(tester, 'sa_mycourses', _courses, storage: _storage, modes: const [false], langs: const ['ar']);
  });

  testWidgets('explore', (tester) async {
    await kitRender(tester, 'sa_explore', _explore, storage: _storage, modes: const [false], langs: const ['ar']);
  });

  testWidgets('approval', (tester) async {
    await kitRender(
      tester,
      'sa_approval',
      () => AuthLayout(
        kicker: 'sa_appr_kicker'.tr,
        heroTitle: 'sa_appr_hero'.tr,
        squiggle: 'sa_appr_squiggle'.tr,
        glyph: Icons.hourglass_top_rounded,
        title: 'sa_appr_title'.tr,
        subtitle: 'sa_appr_sub'.tr,
        body: (context, wide) => AccountApprovalView(rejected: false, onCheck: () {}, onContact: () {}, onSignOut: () {}),
      ),
      storage: _storage,
      modes: const [false],
      langs: const ['ar'],
    );
  });
}
