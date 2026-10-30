// VISUAL review renders of the shared course page (CourseSpace): the student's course details and the teacher's
// course studio, with realistic data and the app's real fonts, at 390x844 and 1440x900, ar / en, light / dark, into
// test/visual/goldens/course_*.png. Not a CI suite; compared by eye.
//
//   flutter test test/visual/course_space_golden_test.dart --update-goldens
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/shared/course/course_space/course_space.dart';
import 'package:flutter_education_app/features/student/courses/details/components/about.dart' show CourseAboutView;
import 'package:flutter_education_app/features/student/courses/details/components/course_detail_parts.dart';
import 'package:flutter_education_app/features/shared/course/studend_course_roadmap_section.dart';
import 'package:flutter_education_app/features/shared/session/session_track_tabs.dart';
import 'package:flutter_education_app/features/shared/session/material/components/session_material_grid.dart';
import 'package:flutter_education_app/features/shared/session/material/session_material_model.dart';
import 'package:flutter_education_app/features/student/courses/details/course_detail_provider.dart';
import 'package:flutter_education_app/features/student/models.dart' show CourseModel, CourseSummary, SessionModel;
import 'package:provider/provider.dart';
import 'package:flutter_education_app/features/teacher/home/teacher_models.dart';
import 'package:flutter_education_app/features/teacher/sessions/components/teacher_course_parts.dart';
import 'package:flutter_test/flutter_test.dart';

import 'home_screens_golden_test.dart' show pubspecFonts;

String _sdkFonts() {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null && root.isNotEmpty) return '$root/bin/cache/artifacts/material_fonts';
  final exe = File(Platform.resolvedExecutable).absolute.path.replaceAll('\\', '/');
  return '${exe.substring(0, exe.indexOf('/bin/cache/'))}/bin/cache/artifacts/material_fonts';
}

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final p in paths) {
      loader.addFont(Future.value(ByteData.sublistView(File(p).readAsBytesSync())));
    }
    await loader.load();
  }

  for (final (family, assets) in pubspecFonts(File('pubspec.yaml').readAsStringSync())) {
    await load(family, assets);
  }
  final sdk = _sdkFonts();
  await load('Roboto', [for (final w in ['regular', 'medium', 'bold']) '$sdk/roboto-$w.ttf']);
  await load('MaterialIcons', ['$sdk/materialicons-regular.otf']);
}

final _shot = GlobalKey();
String tr(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

Widget _host(Widget child, {required bool dark}) {
  final theme = ThemeConfigProvider(api: ApiClient());
  final rtl = AppConfig.lang == 'ar';
  return ThemeConfigScope(
    provider: theme,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme.materialTheme(dark: false),
      darkTheme: theme.materialTheme(dark: true),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, w) => Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!),
      home: RepaintBoundary(
        key: _shot,
        child: Builder(builder: (context) => Scaffold(backgroundColor: context.colors.background, body: child)),
      ),
    ),
  );
}

Future<void> _frames(WidgetTester tester, [int n = 12]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _render(WidgetTester tester, String name, Widget Function() build) async {
  final prevLang = AppConfig.lang;
  debugDisableShadows = false;
  try {
    for (final size in const [Size(390, 844), Size(1440, 900)]) {
      for (final lang in const ['ar', 'en']) {
        for (final dark in const [false, true]) {
          AppConfig.lang = lang;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(_host(build(), dark: dark));
          await _frames(tester);
          // grow the window so the file shows the whole page
          for (var i = 0; i < 4; i++) {
            var extra = 0.0;
            for (final e in find.byType(Scrollable).evaluate()) {
              final s = (e as StatefulElement).state as ScrollableState;
              if (s.position.axis == Axis.vertical && s.position.hasContentDimensions) {
                extra = math.max(extra, s.position.maxScrollExtent);
              }
            }
            if (extra < 1) break;
            tester.view.physicalSize = Size(size.width, math.min(5000, tester.view.physicalSize.height + extra));
            await _frames(tester, 6);
          }
          expect(tester.takeException(), isNull);
          await expectLater(
            find.byKey(_shot),
            matchesGoldenFile('goldens/${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'),
          );
        }
      }
    }
  } finally {
    AppConfig.lang = prevLang;
    await tester.pumpWidget(const SizedBox());
    debugDisableShadows = true;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

/// A UTC instant [days] from today at [hour]:[minute] UTC.
DateTime _at(int days, int hour, [int minute = 0]) {
  final n = DateTime.now().toUtc();
  return DateTime.utc(n.year, n.month, n.day + days, hour, minute);
}

typedef _Row = ({String title, CourseSessionKind kind, int minutes, int files, int filesDone, DateTime? when});

/// The student's lessons: 5 done (folded), the next one under way, one on air, one scheduled, two locked.
List<_Row> _studentRows() => [
  (title: tr('مقدمة في بايثون', 'Intro to Python'), kind: CourseSessionKind.recorded, minutes: 35, files: 4, filesDone: 4, when: null),
  (title: tr('المتغيرات والأنواع', 'Variables and types'), kind: CourseSessionKind.recorded, minutes: 40, files: 3, filesDone: 3, when: null),
  (title: tr('التحكم في التدفق', 'Control flow'), kind: CourseSessionKind.recorded, minutes: 45, files: 3, filesDone: 3, when: null),
  (title: tr('الدوال', 'Functions'), kind: CourseSessionKind.recorded, minutes: 50, files: 5, filesDone: 5, when: null),
  (title: tr('أساسيات NumPy', 'NumPy essentials'), kind: CourseSessionKind.section, minutes: 60, files: 2, filesDone: 2, when: null),
  (title: tr('تحليل البيانات بـ Pandas', 'Data analysis with Pandas'), kind: CourseSessionKind.recorded, minutes: 55, files: 5, filesDone: 2, when: null),
  (title: tr('الشبكات العصبية', 'Neural networks'), kind: CourseSessionKind.live, minutes: 90, files: 1, filesDone: 0, when: null),
  (title: tr('الانحدار اللوجستي', 'Logistic regression'), kind: CourseSessionKind.live, minutes: 90, files: 0, filesDone: 0, when: _at(3, 15)),
  (title: tr('تقييم النماذج', 'Model evaluation'), kind: CourseSessionKind.recorded, minutes: 45, files: 4, filesDone: 0, when: null),
  (title: tr('المشروع النهائي', 'Final project'), kind: CourseSessionKind.recorded, minutes: 120, files: 2, filesDone: 0, when: null),
];

Widget _studentLessons(BuildContext context) {
  final c = context.colors;
  final rows = _studentRows();
  final states = courseStudentStates([
    for (final (i, r) in rows.indexed)
      (
        live: i == 6,
        locked: i >= 8,
        done: courseStudentSessionDone(serverDone: true, materials: r.files, materialsDone: r.filesDone, when: r.when, minutes: r.minutes),
        when: r.when,
      ),
  ]);
  final fold = courseSessionFoldCount(states);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      CourseSectionHeader(title: tr('الجلسات', 'Sessions'), count: rows.length),
      CourseSessionsTimeline(
        itemCount: rows.length,
        foldCount: fold,
        itemBuilder: (context, i) {
          final r = rows[i];
          var rail = courseSessionRail(states, i);
          if (fold > 0 && i == 0) rail = (top: CourseRailTone.done, bottom: rail.bottom);
          final s = states[i];
          return CourseSessionTile(
            data: CourseSessionView(
              number: i + 1,
              title: r.title,
              subtitle: tr('أمثلة عملية وتمارين قصيرة', 'Worked examples and short exercises'),
              kind: r.kind,
              state: s,
              when: r.when,
              durationMinutes: r.minutes,
              materials: r.files,
              materialsDone: r.filesDone,
              showProgress: true,
            ),
            rail: rail,
            wide: MediaQuery.sizeOf(context).width >= 900,
            onTap: () {},
            trailing: s == CourseSessionState.locked || r.files == 0 ? null : const CourseSessionChevron(open: false),
            below: switch (s) {
              CourseSessionState.live => CourseSessionAction(
                label: tr('انضم للبث', 'Join live'),
                icon: Icons.videocam_rounded,
                tone: c.danger,
                filled: true,
                onTap: () {},
              ),
              CourseSessionState.next => CourseSessionAction(
                label: tr('ابدأ الاختبار', 'Start exam'),
                icon: Icons.quiz_outlined,
                onTap: () {},
              ),
              _ => null,
            },
          );
        },
      ),
    ],
  );
}

/// The teacher's sessions: 4 delivered, one on air, the next scheduled, one later, an empty one, two recorded.
List<_Row> _teacherRows() => [
  (title: tr('مقدمة في بايثون', 'Intro to Python'), kind: CourseSessionKind.live, minutes: 60, files: 4, filesDone: 0, when: _at(-21, 15)),
  (title: tr('المتغيرات والأنواع', 'Variables and types'), kind: CourseSessionKind.live, minutes: 60, files: 3, filesDone: 0, when: _at(-14, 15)),
  (title: tr('الدوال', 'Functions'), kind: CourseSessionKind.live, minutes: 90, files: 5, filesDone: 0, when: _at(-7, 15)),
  (title: tr('أساسيات NumPy', 'NumPy essentials'), kind: CourseSessionKind.section, minutes: 60, files: 2, filesDone: 0, when: _at(-3, 15)),
  (title: tr('الشبكات العصبية', 'Neural networks'), kind: CourseSessionKind.live, minutes: 90, files: 1, filesDone: 0, when: null),
  (title: tr('الانحدار اللوجستي', 'Logistic regression'), kind: CourseSessionKind.live, minutes: 90, files: 2, filesDone: 0, when: _at(2, 15)),
  (title: tr('تقييم النماذج', 'Model evaluation'), kind: CourseSessionKind.live, minutes: 90, files: 0, filesDone: 0, when: _at(9, 15)),
  (title: tr('مشروع منتصف الفصل', 'Midterm project'), kind: CourseSessionKind.recorded, minutes: 0, files: 0, filesDone: 0, when: null),
  (title: tr('مراجعة شاملة', 'Full review'), kind: CourseSessionKind.recorded, minutes: 45, files: 6, filesDone: 0, when: null),
  (title: tr('المشروع النهائي', 'Final project'), kind: CourseSessionKind.recorded, minutes: 120, files: 2, filesDone: 0, when: null),
];

Widget _teacherSessions(BuildContext context) {
  final c = context.colors;
  final rows = _teacherRows();
  final states = courseTeacherStates([
    for (final (i, r) in rows.indexed) (live: i == 4, when: r.when, minutes: r.minutes),
  ]);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TeacherSessionsHeader(count: rows.length, onAdd: () {}),
      CourseSessionsSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, r) in rows.indexed)
              CourseSessionTile(
                data: CourseSessionView(
                  number: i + 1,
                  title: r.title,
                  subtitle: tr('الدرس مع التمارين والملفات', 'The lesson with its exercises and files'),
                  kind: r.kind,
                  state: states[i],
                  when: r.when,
                  durationMinutes: r.minutes,
                  materials: r.files,
                  hint: r.files == 0 ? tr('لا مواد بعد', 'No materials yet') : null,
                ),
                rail: courseSessionRail(states, i),
                wide: MediaQuery.sizeOf(context).width >= 900,
                onTap: () {},
                trailing: SizedBox(
                  width: 40,
                  height: 44,
                  child: Icon(Icons.more_vert_rounded, size: 20, color: c.textLight),
                ),
                below: states[i] == CourseSessionState.live
                    ? Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          CourseSessionAction(
                            label: tr('دخول الغرفة', 'Enter room'),
                            icon: Icons.videocam_rounded,
                            tone: c.danger,
                            filled: true,
                            onTap: () {},
                          ),
                          CourseSessionAction(
                            label: tr('إنهاء', 'End'),
                            icon: Icons.stop_circle_outlined,
                            tone: c.danger,
                            onTap: () {},
                          ),
                        ],
                      )
                    : null,
              ),
          ],
        ),
      ),
    ],
  );
}

Widget _student() => Builder(
  builder: (context) {
    final c = context.colors;
    return CourseSpace(
      hero: CourseSpaceHeroData(
        title: tr('أساسيات الذكاء الاصطناعي بلغة بايثون', 'AI Foundations with Python'),
        subtitle: tr(
          'من أول سطر بايثون حتى بناء نموذجك الأول — مشاريع عملية أسبوعية.',
          'From your first line of Python to your first model — a hands-on project every week.',
        ),
        category: tr('البرمجة', 'Programming'),
        badges: [
          CourseSpaceBadge(label: tr('بث مباشر', 'Live'), icon: Icons.sensors_rounded),
          CourseSpaceBadge(label: tr('شهادة', 'Certificate'), icon: Icons.workspace_premium_rounded),
        ],
        teacherName: tr('د. سارة الحسيني', 'Dr. Sara El-Husseini'),
        onTeacher: () {},
        stats: [
          CourseSpaceStat(icon: Icons.groups_rounded, value: '4', label: courseStatNoun(4, 'course_hero_students')),
          CourseSpaceStat(icon: Icons.play_circle_outline_rounded, value: '10', label: courseStatNoun(10, 'course_hero_lessons')),
          CourseSpaceStat(icon: Icons.schedule_rounded, value: '9', label: courseStatNoun(9, 'course_hero_hours')),
        ],
        progress: 0.58,
      ),
      onBack: () {},
      topActions: [
        CourseSpaceTopAction(icon: Icons.ios_share_rounded, tooltip: 'share', onTap: () {}),
        CourseSpaceTopAction(icon: Icons.favorite_rounded, tooltip: 'like', color: c.danger, onTap: () {}),
      ],
      spotlight: [
        CourseSpotlightCard(
          icon: Icons.sensors_rounded,
          title: tr('بث مباشر الآن', 'Live now'),
          subtitle: tr('المحاضرة 21: الشبكات العصبية', 'Lecture 21: Neural networks'),
          live: true,
          filled: true,
          color: c.danger,
          actionLabel: tr('انضم', 'Join'),
          onAction: () {},
        ),
        CourseSpotlightCard(
          icon: Icons.play_circle_fill_rounded,
          title: tr('تابع التعلّم', 'Continue learning'),
          subtitle: tr('التالي: الدرس 22 — الانحدار اللوجستي', 'Up next: Lesson 22 — Logistic regression'),
          progress: 0.58,
          actionLabel: tr('تابع', 'Resume'),
          onAction: () {},
        ),
      ],
      actions: [
        CourseSpaceAction(icon: Icons.dashboard_customize_rounded, label: tr('ملف المقرر', 'Course profile'), onTap: () {}),
        CourseSpaceAction(icon: Icons.insights_rounded, label: tr('تحليلاتي', 'My analytics'), color: c.purple, onTap: () {}),
        CourseSpaceAction(icon: Icons.workspace_premium_rounded, label: tr('شهاداتي', 'Certificates'), color: c.accent2, onTap: () {}),
        CourseSpaceAction(icon: Icons.headset_mic_rounded, label: tr('الدعم', 'Support'), color: c.success, onTap: () {}),
      ],
      tabs: [
        CourseSpaceTab(id: 'live', label: tr('مباشر', 'Live'), icon: Icons.sensors_rounded, live: true, builder: (_) => const SizedBox()),
        CourseSpaceTab(
          id: 'lessons',
          label: tr('الجلسات', 'Sessions'),
          icon: Icons.play_lesson_rounded,
          count: 10,
          builder: _studentLessons,
        ),
        CourseSpaceTab(id: 'exams', label: tr('الاختبارات', 'Exams'), icon: Icons.assignment_rounded, builder: (_) => const SizedBox()),
        CourseSpaceTab(id: 'about', label: tr('عن الكورس', 'About'), icon: Icons.info_outline_rounded, builder: (_) => const SizedBox()),
      ],
      activeTab: 'lessons',
      onTab: (_) {},
      aside: CourseSideCard(
        accent: c.success,
        child: Row(
          children: [
            Icon(Icons.verified_rounded, color: c.success),
            const SizedBox(width: 10),
            Expanded(child: Text(tr('أنت مشترك في الكورس', 'You are enrolled'), style: c.bodyBold)),
          ],
        ),
      ),
    );
  },
);

/// The quick-action row with more than fit ("More"), the lecture / section filter and the roadmap card.
Widget _parts() => Builder(
  builder: (context) => ListView(
    padding: const EdgeInsets.symmetric(vertical: 16),
    children: [
      CourseActionStrip(actions: [
        for (final (ar, en, i) in [
          ('جلسة جديدة', 'New session', Icons.add_rounded),
          ('الطلاب', 'Students', Icons.groups_rounded),
          ('ملف المقرر', 'Course profile', Icons.dashboard_customize_rounded),
          ('معمل البيانات', 'Data Lab', Icons.science_rounded),
          ('الجدول الأسبوعي', 'Weekly schedule', Icons.calendar_month_rounded),
          ('تعديل الكورس', 'Edit course', Icons.edit_rounded),
        ])
          CourseSpaceAction(icon: i, label: tr(ar, en), onTap: () {}),
      ]),
      const SizedBox(height: 16),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SessionTrackTabs(value: 'all', lectures: 16, sections: 16, onChanged: (_) {}),
      ),
      const SizedBox(height: 16),
      CourseRoadmapSection(
        currentCourseName: tr('أساسيات الخط العربي', 'Arabic calligraphy basics'),
        recentCompletedCourses: [CourseSummary(id: 1, name: tr('مدخل إلى الفنون الإسلامية', 'Intro to Islamic art'), finalPrice: 0)],
        nextCourses: [CourseSummary(id: 2, name: tr('خط الثلث المتقدم', 'Advanced Thuluth script'), finalPrice: 0)],
        recommendedCourses: const [],
        similarCourses: const [],
        onTapCourse: (_) {},
      ),
    ],
  ),
);

Widget _teacher() => Builder(
  builder: (context) {
    final c = context.colors;
    return CourseSpace(
      hero: CourseSpaceHeroData(
        title: tr('أساسيات الذكاء الاصطناعي بلغة بايثون', 'AI Foundations with Python'),
        category: tr('البرمجة', 'Programming'),
        badges: [CourseSpaceBadge(label: tr('مسودة', 'Draft'), icon: Icons.edit_note_rounded, color: c.warning)],
        stats: [
          CourseSpaceStat(icon: Icons.groups_rounded, value: '1,284', label: courseStatNoun(1284, 'course_hero_students'), onTap: () {}),
          CourseSpaceStat(icon: Icons.play_lesson_rounded, value: '36', label: tr('جلسة', 'Sessions')),
          CourseSpaceStat(icon: Icons.timer_rounded, value: '42', label: tr('ساعة', 'Hours')),
          CourseSpaceStat(icon: Icons.sell_rounded, value: '750 EGP', label: tr('السعر', 'Price')),
        ],
      ),
      onBack: () {},
      topActions: [
        CourseSpaceTopAction(icon: Icons.ios_share_rounded, tooltip: 'share', onTap: () {}),
        CourseSpaceTopAction(icon: Icons.edit_rounded, tooltip: 'edit', onTap: () {}),
      ],
      spotlight: [
        CourseReadinessCard(
          items: [
            const CourseReadinessItem(label: 'cover', done: true),
            CourseReadinessItem(label: tr('المواعيد الأسبوعية', 'Weekly schedule'), done: false, icon: Icons.calendar_month_rounded, onTap: () {}),
            CourseReadinessItem(label: tr('انشر الكورس', 'Publish'), done: false, icon: Icons.public_rounded, onTap: () {}),
            const CourseReadinessItem(label: 'session', done: true),
          ],
        ),
      ],
      actions: [
        CourseSpaceAction(icon: Icons.add_rounded, label: tr('جلسة جديدة', 'New session'), onTap: () {}),
        CourseSpaceAction(icon: Icons.people_alt_rounded, label: tr('الطلاب', 'Students'), color: c.purple, onTap: () {}),
        CourseSpaceAction(icon: Icons.dashboard_customize_rounded, label: tr('ملف المقرر', 'Course profile'), onTap: () {}),
        CourseSpaceAction(icon: Icons.science_rounded, label: tr('مختبر البيانات', 'Data Lab'), color: c.accent2, onTap: () {}),
        CourseSpaceAction(icon: Icons.calendar_month_rounded, label: tr('المواعيد', 'Schedule'), color: c.warning, onTap: () {}),
      ],
      tabs: [
        CourseSpaceTab(
          id: 'sessions',
          label: tr('الجلسات', 'Sessions'),
          icon: Icons.play_lesson_rounded,
          count: 10,
          live: true,
          builder: _teacherSessions,
        ),
        CourseSpaceTab(id: 'details', label: tr('التفاصيل', 'Details'), icon: Icons.info_outline_rounded, builder: (_) => const SizedBox()),
      ],
      activeTab: 'sessions',
      onTab: (_) {},
    );
  },
);

Widget _about() => Builder(
  builder: (context) {
    final c = context.colors;
    return CourseSpace(
      hero: CourseSpaceHeroData(title: tr('أساسيات الذكاء الاصطناعي', 'AI Foundations')),
      tabs: [
        CourseSpaceTab(id: 'lessons', label: tr('الدروس', 'Lessons'), icon: Icons.play_lesson_rounded, builder: (_) => const SizedBox()),
        CourseSpaceTab(
          id: 'about',
          label: tr('عن الكورس', 'About'),
          icon: Icons.info_outline_rounded,
          builder: (_) => Padding(
            padding: const EdgeInsets.all(kCourseGutter),
            child: Column(
              children: [
                CourseInfoSection(
                  title: tr('المواعيد الأسبوعية', 'Weekly schedule'),
                  icon: Icons.calendar_month_rounded,
                  trailing: TextButton(onPressed: () {}, child: Text(tr('إدارة', 'Manage'))),
                  children: [
                    CourseScheduleChips(
                      schedules: [
                        CourseSchedule(id: 1, courseId: 1, day: 'sunday', startTime: '18:00', endTime: '19:30'),
                        CourseSchedule(id: 2, courseId: 1, day: 'wednesday', startTime: '18:00', endTime: '19:30'),
                      ],
                    ),
                  ],
                ),
                CourseInfoSection(
                  title: tr('المتطلبات المسبقة', 'Prerequisites'),
                  icon: Icons.checklist_rounded,
                  color: c.accent2,
                  children: [
                    CourseInfoRow(title: tr('أساسيات الرياضيات', 'Basic math'), subtitle: tr('الجبر الخطي مفيد', 'Linear algebra helps')),
                    CourseInfoRow(title: tr('حاسوب شخصي', 'A laptop')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
      activeTab: 'about',
      onTab: (_) {},
    );
  },
);

// ── the real role pieces (buy card / bar, About, the teacher's Details + status card) ──

CourseModel _studentCourse() => CourseModel(
  id: '42',
  imageUrl: '',
  price: 1200,
  finalPrice: 750,
  discountActive: true,
  discountPercentage: 37,
  discountEndsAt: DateTime.now().add(const Duration(days: 2, hours: 5)),
  type: 'live',
  isEnrolled: false,
  isPublished: true,
  expectedHours: 48,
  totalHours: 42,
  sessionsCount: 36,
  studentsCount: 1284,
  certificates: [CourseCertificate(id: 1, courseId: 42, title: tr('شهادة إتمام', 'Certificate of completion'))],
  titleAr: 'أساسيات الذكاء الاصطناعي بلغة بايثون',
  titleEn: 'AI Foundations with Python',
);

Widget _studentReal() => Builder(
  builder: (context) {
    final course = _studentCourse();
    return CourseSpace(
      hero: CourseSpaceHeroData(
        title: tr(course.titleAr!, course.titleEn!),
        category: tr('البرمجة', 'Programming'),
        teacherName: tr('د. سارة الحسيني', 'Dr. Sara El-Husseini'),
        stats: [
          CourseSpaceStat(icon: Icons.groups_rounded, value: '1,284', label: tr('طالب', 'Students')),
          CourseSpaceStat(icon: Icons.play_circle_outline_rounded, value: '36', label: tr('درس', 'Lessons')),
          CourseSpaceStat(icon: Icons.schedule_rounded, value: '42', label: tr('ساعة', 'Hours')),
        ],
      ),
      tabs: [
        CourseSpaceTab(id: 'lessons', label: tr('الجلسات', 'Sessions'), icon: Icons.play_lesson_rounded, count: 4, builder: (_) => const SizedBox()),
        CourseSpaceTab(id: 'exams', label: tr('الاختبارات', 'Exams'), icon: Icons.assignment_rounded, builder: (_) => const SizedBox()),
        CourseSpaceTab(
          id: 'about',
          label: tr('عن الكورس', 'About'),
          icon: Icons.info_outline_rounded,
          builder: (_) => CourseAboutView(
            description: tr(
              'من أول سطر بايثون حتى بناء نموذجك الأول. ستتعلم الأساسيات ثم تبني مشروعاً عملياً كل أسبوع.',
              'From your first line of Python to your first model. Learn the basics, then build a project every week.',
            ),
            teacherName: tr('د. سارة الحسيني', 'Dr. Sara El-Husseini'),
            category: tr('البرمجة', 'Programming'),
            onTeacher: () {},
            rating: const CourseRatingStars(value: 4.6, count: 128),
            myCertificates: const [],
            schedules: [
              CourseSchedule(id: 1, courseId: 42, day: 'sunday', startTime: '18:00', endTime: '19:30'),
              CourseSchedule(id: 2, courseId: 42, day: 'wednesday', startTime: '18:00', endTime: '19:30'),
            ],
            certificates: [CourseCertificate(id: 1, courseId: 42, title: tr('شهادة إتمام', 'Certificate of completion'))],
            tools: [CourseTool(id: 1, courseId: 42, name: 'Python 3.12', description: tr('مع Jupyter', 'with Jupyter'))],
            prerequisites: [CoursePrerequisite(id: 1, courseId: 42, title: tr('أساسيات الرياضيات', 'Basic math'))],
          ),
        ),
      ],
      activeTab: 'about',
      onTab: (_) {},
      aside: CourseBuyCard(course: course, onEnroll: () {}),
      bottomBar: CourseBuyBar(course: course, onEnroll: () {}),
    );
  },
);

TeacherCourse _teacherCourse() => TeacherCourse.fromJson({
  'id': 7,
  'image_url': '',
  'name_ar': 'أساسيات الذكاء الاصطناعي بلغة بايثون',
  'name_en': 'AI Foundations with Python',
  'description_ar': 'من أول سطر بايثون حتى بناء نموذجك الأول.',
  'description_en': 'From your first line of Python to your first model.',
  'students_count': 1284,
  'sessions_count': 36,
  'total_hours': 42.0,
  'expected_hours': 48.0,
  'price': 1200,
  'final_price': 750.0,
  'discount_active': true,
  'discount_percentage': 37.0,
  'type': 'live',
  'is_published': false,
  'schedules': [
    {'id': 1, 'day': 'sunday', 'start_time': '18:00', 'end_time': '19:30'},
    {'id': 2, 'day': 'wednesday', 'start_time': '18:00', 'end_time': '19:30'},
  ],
  'certificates': [
    {'id': 3, 'title': 'Certificate of completion'},
  ],
});

Widget _teacherReal() => Builder(
  builder: (context) {
    final course = _teacherCourse();
    return CourseSpace(
      hero: CourseSpaceHeroData(title: tr(course.titleAr!, course.titleEn!)),
      tabs: [
        CourseSpaceTab(id: 'sessions', label: tr('الجلسات', 'Sessions'), icon: Icons.play_lesson_rounded, builder: (_) => const SizedBox()),
        CourseSpaceTab(
          id: 'details',
          label: tr('التفاصيل', 'Details'),
          icon: Icons.info_outline_rounded,
          builder: (_) => TeacherCourseDetails(
            course: course,
            rating: const CourseRatingStars(value: 4.6, count: 128),
            onManageSchedule: () {},
            onManageCertificate: (_) {},
          ),
        ),
      ],
      activeTab: 'details',
      onTab: (_) {},
      aside: TeacherCourseStatusCard(course: course, onAddSession: () {}, onEdit: () {}),
    );
  },
);

Widget _teacherEmpty() => Builder(
  builder: (context) => CourseSpace(
    hero: CourseSpaceHeroData(title: tr('كورس جديد', 'A new course')),
    tabs: [
      CourseSpaceTab(
        id: 'sessions',
        label: tr('الجلسات', 'Sessions'),
        icon: Icons.play_lesson_rounded,
        builder: (_) => Column(
          children: [
            TeacherSessionsHeader(count: 0, onAdd: () {}),
            Padding(padding: const EdgeInsets.all(kCourseGutter), child: TeacherSessionsEmpty(onAdd: () {})),
          ],
        ),
      ),
      CourseSpaceTab(id: 'details', label: tr('التفاصيل', 'Details'), icon: Icons.info_outline_rounded, builder: (_) => const SizedBox()),
    ],
    activeTab: 'sessions',
    onTab: (_) {},
  ),
);

void main() {
  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    await _loadFonts();
  });
  setUp(() => AppConfig.disableList = []);

  testWidgets('course student', (t) => _render(t, 'course_student', _student));
  testWidgets('course parts', (t) => _render(t, 'course_parts', _parts));
  testWidgets('course teacher', (t) => _render(t, 'course_teacher', _teacher));
  testWidgets('course about', (t) => _render(t, 'course_about', _about));
  testWidgets('course student real pieces', (t) => _render(t, 'course_student_real', _studentReal));
  testWidgets('course teacher real pieces', (t) => _render(t, 'course_teacher_real', _teacherReal));
  testWidgets('course materials', (t) => _render(t, 'course_materials', _materials));
  testWidgets('course teacher empty', (t) => _render(t, 'course_teacher_empty', _teacherEmpty));
}

/// N9: a session's files as the student sees them — one done mark, the recording titled "Session recording", stars
/// only where there are ratings.
Widget _materials() {
  final session = SessionModel.fromJson({
    'id': 11,
    'course_id': 42,
    'name': 'نن',
    'total_materials': 3,
    'complete_materials': 2,
    'completeness': false,
  }).toTeacher;
  final now = DateTime.now().toUtc();
  SessionMaterialModel m(int id, String name, String type, {bool done = false, int? size, Map<String, dynamic>? rate}) =>
      SessionMaterialModel.fromJson({
        'id': id,
        'session_id': 11,
        'name': name,
        'type': type,
        'file_size': size,
        'completed': done,
        'created_at': now.subtract(Duration(days: id)).toIso8601String(),
        if (rate != null) 'rate': rate,
      });
  final provider = CourseDetailProvider()..course = _studentCourse();
  return ChangeNotifierProvider<CourseDetailProvider>.value(
    value: provider,
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SessionMaterialGrid(
        session: session,
        isLoading: false,
        columns: 1,
        isTeacher: false,
        materials: [
          m(1, 'نن — تسجيل الحصة', 'recorded', done: true, size: 15938355),
          m(2, 'نن — تسجيل الحصة (لقاء 2)', 'recorded', size: 9938355),
          m(3, tr('ملخص المحاضرة الأولى', 'Lecture 1 summary'), 'document', done: true, size: 238355, rate: {'average': 4.5, 'total': 12, 'ratings': []}),
          m(4, tr('رابط المراجع', 'Further reading'), 'link'),
        ],
      ),
    ),
  );
}
