// The shared course page (CourseSpace) and its parts at 320×640 and 1400×900, ar / en, textScaler 1.3.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/course/course_space/course_space.dart';
import 'package:flutter_education_app/features/teacher/home/teacher_models.dart' show CourseSchedule;
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _long = 'مقدمة شاملة جداً في الذكاء الاصطناعي وتعلم الآلة للمبتدئين والمحترفين A complete introduction';

CourseSpaceHeroData _hero({double? progress}) => CourseSpaceHeroData(
  title: _long,
  subtitle: '$_long $_long',
  category: 'البرمجة وعلوم الحاسب',
  isPrivate: true,
  privateLabel: 'خاص',
  badges: const [
    CourseSpaceBadge(label: 'بث مباشر Live sessions', icon: Icons.sensors_rounded),
    CourseSpaceBadge(label: 'شهادة Certificate', icon: Icons.workspace_premium_rounded),
  ],
  teacherName: 'د. عبد الرحمن محمد عبد الله الحسيني Dr. Abdelrahman',
  onTeacher: () {},
  stats: [
    const CourseSpaceStat(icon: Icons.groups_rounded, value: '12,480', label: 'طالب Students'),
    const CourseSpaceStat(icon: Icons.play_circle_outline_rounded, value: '148', label: 'درس Lessons'),
    CourseSpaceStat(icon: Icons.schedule_rounded, value: '96.5', label: 'ساعة Hours', onTap: () {}),
  ],
  progress: progress,
);

List<CourseSpaceAction> _actions() => [
  for (final (i, l) in ['ملف المقرر', 'الحضور والغياب', 'الطلاب المسجلون', 'المواعيد', 'الدعم الفني', 'مختبر البيانات'].indexed)
    CourseSpaceAction(icon: Icons.dashboard_customize_rounded, label: '$l Course profile', badge: i == 1 ? '12' : null, onTap: () {}),
];

List<CourseSpaceTab> _tabs() => [
  CourseSpaceTab(
    id: 'live',
    label: 'مباشر Live',
    icon: Icons.sensors_rounded,
    live: true,
    builder: (_) => const SizedBox(height: 40),
  ),
  CourseSpaceTab(
    id: 'lessons',
    label: 'الدروس Lessons',
    icon: Icons.play_lesson_rounded,
    count: 148,
    builder: (_) => Column(
      children: [
        CourseSectionHeader(title: 'الدروس $_long', count: 148, trailing: FilledButton(onPressed: () {}, child: const Text('Add'))),
        for (var i = 0; i < 6; i++) Container(height: 80, margin: const EdgeInsets.all(8), color: Colors.black12),
      ],
    ),
  ),
  CourseSpaceTab(id: 'exams', label: 'الاختبارات Exams', icon: Icons.assignment_rounded, builder: (_) => const SizedBox()),
  CourseSpaceTab(id: 'about', label: 'عن الكورس About', icon: Icons.info_outline_rounded, builder: (_) => _about()),
];

Widget _about() => Padding(
  padding: const EdgeInsets.all(kCourseGutter),
  child: Column(
    children: [
      CourseInfoSection(
        title: 'المواعيد الأسبوعية $_long',
        icon: Icons.calendar_month_rounded,
        trailing: TextButton(onPressed: () {}, child: const Text('Manage schedule')),
        children: [
          CourseScheduleChips(
            schedules: [
              for (var i = 0; i < 5; i++)
                CourseSchedule(id: i, courseId: 1, day: 'wednesday', startTime: '09:00', endTime: '10:30'),
            ],
          ),
        ],
      ),
      CourseInfoSection(
        title: 'الشهادات',
        icon: Icons.workspace_premium_rounded,
        children: [
          CourseInfoRow(
            title: _long,
            subtitle: '$_long $_long',
            trailing: TextButton(onPressed: () {}, child: const Text('إدارة الشهادة Manage certificate')),
          ),
        ],
      ),
    ],
  ),
);

List<Widget> _spotlight() => [
  const SizedBox.shrink(),
  CourseSpotlightCard(
    icon: Icons.sensors_rounded,
    title: 'بث مباشر الآن: $_long',
    subtitle: _long,
    live: true,
    filled: true,
    actionLabel: 'انضم الآن Join now',
    onAction: () {},
  ),
  CourseSpotlightCard(
    icon: Icons.play_circle_fill_rounded,
    title: 'تابع التعلم Continue learning',
    subtitle: 'الدرس 14: $_long',
    progress: 0.42,
    actionLabel: 'تابع Continue',
    onAction: () {},
  ),
  CourseReadinessCard(
    items: [
      const CourseReadinessItem(label: 'صورة الغلاف Cover image', done: true),
      CourseReadinessItem(label: 'الوصف والتفاصيل Description', done: false, onTap: () {}),
      CourseReadinessItem(label: 'المواعيد الأسبوعية Weekly schedule', done: false, onTap: () {}),
      CourseReadinessItem(label: 'أضف أول درس Add the first lesson', done: false, onTap: () {}),
    ],
  ),
];

Widget _space({String active = 'lessons', double? progress}) => StatefulBuilder(
  builder: (context, setState) => CourseSpace(
    hero: _hero(progress: progress),
    onBack: () {},
    topActions: [
      CourseSpaceTopAction(icon: Icons.refresh_rounded, tooltip: 'refresh', onTap: () {}),
      CourseSpaceTopAction(icon: Icons.ios_share_rounded, tooltip: 'share', onTap: () {}),
      CourseSpaceTopAction(icon: Icons.favorite_border_rounded, tooltip: 'like', onTap: () {}),
      CourseSpaceTopAction(icon: Icons.edit_rounded, tooltip: 'edit', onTap: () {}),
    ],
    onRefresh: () async {},
    spotlight: _spotlight(),
    actions: _actions(),
    tabs: _tabs(),
    activeTab: active,
    onTab: (_) {},
    aside: const CourseSideCard(child: SizedBox(height: 160)),
    bottomBar: Container(height: 72, color: Colors.black12),
    footer: const SizedBox(height: 200),
  ),
);

void main() {
  setUp(() => AppConfig.lang = 'ar');

  testWidgets('CourseSpace: every tab, enrolled and not', (t) async {
    for (final tab in ['lessons', 'about', 'live']) {
      await expectNoLayoutErrors(t, () => _space(active: tab, progress: tab == 'lessons' ? 0.64 : null));
    }
  });

  testWidgets('CourseSpace: scrolled with the tab bar pinned', (t) async {
    await expectNoLayoutErrors(
      t,
      () => _space(),
      act: (t) async {
        await t.drag(find.byType(CustomScrollView).first, const Offset(0, -900));
      },
    );
  });

  testWidgets('CourseSpace: a single tab draws no tab bar, no actions / spotlight', (t) async {
    await expectNoLayoutErrors(
      t,
      () => CourseSpace(
        hero: const CourseSpaceHeroData(title: 'X'),
        tabs: [CourseSpaceTab(id: 'a', label: 'A', icon: Icons.abc, builder: (_) => const Text('body'))],
        activeTab: 'a',
        onTab: (_) {},
      ),
    );
    expect(find.byType(CourseSpaceTabBar), findsNothing);
  });

  testWidgets('CourseReadinessCard hides itself when every step is done', (t) async {
    await t.pumpWidget(
      layoutHost(const CourseReadinessCard(items: [CourseReadinessItem(label: 'a', done: true)])),
    );
    expect(find.text('a'), findsNothing);
  });

  testWidgets('CourseSpaceSkeleton', (t) async {
    await expectNoLayoutErrors(t, () => const CourseSpaceSkeleton());
  });
}
