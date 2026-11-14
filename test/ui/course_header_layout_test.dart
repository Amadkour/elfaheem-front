// The course page's header (D-940 – D-943): every role's call to action, long titles, no cover, a free course and zero
// students, at 320×640 and 1400×900, ar / en, textScaler 1.3 — no overflow; plus the rules the redesign set: the
// cover sits in a 16:9 frame on desktop, Students is a button (no underline), a phone with a bottom bar leaves the
// call to action to the bar, and New session / Edit course / the price each appear once.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/courses/course_space/course_space.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _long =
    'دورة شاملة ومتقدمة في الذكاء الاصطناعي وتعلم الآلة بلغة بايثون مع مشاريع عملية أسبوعية ومراجعات مكثفة';

/// A 1×1 PNG: a cover "in hand" that decodes without the network.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00,
  0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0D, 0x49,
  0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0, 0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89, 0x99, 0x3D,
  0x1D, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

List<CourseSpaceStat> _stats({int students = 95, VoidCallback? onStudents, bool rating = true}) => [
  CourseSpaceStat(icon: Icons.groups_rounded, value: '$students', label: 'طلاب مسجلون', onTap: onStudents),
  const CourseSpaceStat(icon: Icons.play_lesson_rounded, value: '6', label: 'الجلسات'),
  const CourseSpaceStat(icon: Icons.schedule_rounded, value: '6', label: 'ساعات المحتوى'),
  const CourseSpaceStat(icon: Icons.sell_rounded, value: '150 ج.م', label: 'السعر'),
  if (rating) const CourseSpaceStat(icon: Icons.star_rounded, value: '5.0', label: '12 تقييمًا'),
];

CourseSpaceCta _teacherCta() => CourseSpaceCta(
  primary: CourseSpaceButton(label: 'جلسة جديدة', icon: Icons.add_rounded, onTap: () {}),
  secondary: CourseSpaceButton(label: 'تعديل الكورس', icon: Icons.edit_rounded, onTap: () {}),
  icons: [CourseSpaceTopAction(icon: Icons.ios_share_rounded, tooltip: 'مشاركة', onTap: () {})],
  caption: 'الطلاب لا يرون الكورس حتى تنشره.',
);

CourseSpaceCta _visitorCta() => CourseSpaceCta(
  price: const Text('150 ج.م', key: ValueKey('cta_price'), style: TextStyle(fontSize: 28)),
  primary: CourseSpaceButton(label: 'انضم الآن', onTap: () {}),
);

CourseSpaceCta _studentCta() => CourseSpaceCta(
  primary: CourseSpaceButton(label: 'تابع التعلم', icon: Icons.play_arrow_rounded, onTap: () {}),
  caption: 'التالي: $_long',
);

CourseSpaceHeroData _hero({
  String title = _long,
  CourseSpaceCta? cta,
  bool cover = true,
  double? progress,
  int students = 95,
  VoidCallback? onStudents,
}) => CourseSpaceHeroData(
  title: title,
  subtitle: '$_long $_long',
  category: 'الذكاء الاصطناعي',
  coverImage: cover ? MemoryImage(_png) : null,
  badges: const [
    CourseSpaceBadge(label: 'منشور', icon: Icons.public_rounded),
    CourseSpaceBadge(label: 'دروس مسجّلة', icon: Icons.play_circle_outline_rounded),
  ],
  teacherName: 'د. سارة الحسيني عبد الرحمن',
  onTeacher: () {},
  stats: _stats(students: students, onStudents: onStudents),
  progress: progress,
  progressLabel: 'تقدّمك · 3/8',
  cta: cta,
);

Widget _page(CourseSpaceHeroData hero, {Widget? bottomBar}) => CourseSpace(
  hero: hero,
  onBack: () {},
  topActions: [CourseSpaceTopAction(icon: Icons.favorite_border_rounded, tooltip: 'like', onTap: () {})],
  tabs: [
    CourseSpaceTab(id: 'a', label: 'الجلسات', icon: Icons.play_lesson_rounded, builder: (_) => const SizedBox(height: 200)),
    CourseSpaceTab(id: 'b', label: 'عن الكورس', icon: Icons.info_outline_rounded, builder: (_) => const SizedBox()),
  ],
  activeTab: 'a',
  onTab: (_) {},
  aside: const SizedBox(height: 120),
  bottomBar: bottomBar,
);

void main() {
  setUp(() => AppConfig.lang = 'ar');

  testWidgets('header: teacher, enrolled student, visitor — long titles, at every size', (t) async {
    for (final hero in [
      _hero(cta: _teacherCta(), onStudents: () {}),
      _hero(cta: _studentCta(), progress: 0.4),
      _hero(cta: _visitorCta()),
    ]) {
      await expectNoLayoutErrors(t, () => _page(hero));
    }
  });

  testWidgets('header: no cover, short title, free course, zero students', (t) async {
    await expectNoLayoutErrors(
      t,
      () => _page(_hero(title: 'بايثون', cover: false, students: 0, cta: _visitorCta())),
    );
    await expectNoLayoutErrors(t, () => _page(const CourseSpaceHeroData(title: 'X')));
  });

  testWidgets('header: a phone with a bottom bar leaves the call to action to the bar', (t) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(390, 844);
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(layoutHost(_page(_hero(cta: _visitorCta()), bottomBar: const Text('BAR')), scale: 1));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('انضم الآن'), findsNothing);
    expect(find.byKey(const ValueKey('cta_price')), findsNothing);
    expect(find.text('BAR'), findsOneWidget);
    // without a bar (the teacher) the header carries it
    await t.pumpWidget(layoutHost(_page(_hero(cta: _teacherCta())), scale: 1));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('جلسة جديدة'), findsOneWidget);
    expect(find.text('تعديل الكورس'), findsOneWidget);
  });

  testWidgets('header: desktop — the cover framed at 16:9, the CTA once, Students a button without underline', (t) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(1440, 900);
    addTearDown(t.view.resetPhysicalSize);
    var opened = 0;
    await t.pumpWidget(layoutHost(
      _page(_hero(cta: _teacherCta(), onStudents: () => opened++), bottomBar: const Text('BAR')),
      scale: 1,
    ));
    await t.pump(const Duration(milliseconds: 500));
    final ratio = t.widgetList<AspectRatio>(find.byType(AspectRatio)).map((a) => a.aspectRatio);
    expect(ratio, contains(16 / 9));
    expect(find.text('جلسة جديدة'), findsOneWidget);
    expect(find.text('BAR'), findsNothing);
    final label = t.widget<Text>(find.text('طلاب مسجلون'));
    expect(label.style?.decoration, isNot(TextDecoration.underline));
    await t.tap(find.text('طلاب مسجلون'));
    expect(opened, 1);
    expect(find.bySemanticsLabel('95 طلاب مسجلون'), findsOneWidget);
  });
}
