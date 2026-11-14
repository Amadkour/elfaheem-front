// VISUAL review renders of the course page's header (D-940 – D-943): every role (teacher, enrolled student, visitor,
// guest on a free course) and the edge cases (long title, no cover, a square cover, zero students, a draft), at
// 390 (phone), 820 (tablet) and 1440 (desktop), ar / en, light / dark, into test/visual/goldens/header_*.png.
// Not a CI suite; compared by eye.
//
//   flutter test test/visual/course_header_golden_test.dart --update-goldens
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/courses/course_space/course_space.dart';
import 'package:flutter_education_app/features/courses/student/details/components/course_detail_parts.dart';
import 'package:flutter_education_app/features/home/student/models.dart' show CourseModel;
import 'package:flutter_test/flutter_test.dart';

import 'home_screens_golden_test.dart' show pubspecFonts;

String tr(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

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

/// A busy course thumbnail whose words run to its edges (the kind the old 16:10 frame cut), [w]×[h].
Future<MemoryImage> _coverPng(int w, int h) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  final size = Size(w.toDouble(), h.toDouble());
  final r = Offset.zero & size;
  canvas.drawRect(
    r,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF1B2A4A), Color(0xFF2E6F95), Color(0xFFE8794A)],
      ).createShader(r),
  );
  for (var i = 0; i < 9; i++) {
    canvas.drawCircle(
      Offset(size.width * (0.1 + i * 0.11), size.height * (0.25 + (i % 3) * 0.2)),
      size.height * 0.07,
      Paint()..color = Color(0x33FFFFFF + i * 0x00010203),
    );
  }
  void text(String s, double y, double fs, Color color) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w700, fontSize: fs, color: color)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset((size.width - tp.width) / 2, y));
  }

  text('HANDS-ON COURSE', size.height * 0.08, size.width * 0.105, const Color(0xFFFFFFFF));
  text('PYTHON  ·  MACHINE LEARNING  ·  AI', size.height * 0.62, size.width * 0.055, const Color(0xFFFFE2C2));
  text('12 PROJECTS', size.height * 0.80, size.width * 0.06, const Color(0xFFFFFFFF));
  final img = await rec.endRecording().toImage(w, h);
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  return MemoryImage(bytes!.buffer.asUint8List());
}

final _shot = GlobalKey();

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

MemoryImage? _wide, _square;

Future<void> _render(WidgetTester tester, String name, Widget Function() build) async {
  final prevLang = AppConfig.lang;
  debugDisableShadows = false;
  if (_wide == null) {
    await tester.runAsync(() async {
      _wide = await _coverPng(1280, 720);
      _square = await _coverPng(800, 800);
    });
  }
  try {
    for (final size in const [Size(390, 1000), Size(820, 1000), Size(1440, 900)]) {
      for (final lang in const ['ar', 'en']) {
        for (final dark in const [false, true]) {
          AppConfig.lang = lang;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(_host(build(), dark: dark));
          await tester.runAsync(() async {
            final ctx = tester.element(find.byType(Scaffold));
            for (final i in [_wide!, _square!]) {
              await precacheImage(i, ctx);
            }
          });
          for (var i = 0; i < 14; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(tester.takeException(), isNull);
          await expectLater(
            find.byKey(_shot),
            matchesGoldenFile('goldens/header_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'),
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

CourseModel _course({bool enrolled = false, double price = 150, int students = 95}) => CourseModel(
  id: '42',
  imageUrl: '',
  price: price,
  finalPrice: price,
  type: 'recorded',
  isEnrolled: enrolled,
  isPublished: true,
  totalHours: 6,
  expectedHours: 6,
  sessionsCount: 6,
  studentsCount: students,
  titleAr: 'أساسيات الذكاء الاصطناعي بلغة بايثون',
  titleEn: 'AI Foundations with Python',
);

const _longAr = 'الدليل العملي الشامل للذكاء الاصطناعي وتعلّم الآلة بلغة بايثون: من الصفر حتى بناء ونشر مشاريع حقيقية';
const _longEn = 'The complete hands-on guide to AI and machine learning with Python: from zero to building and shipping real projects';

enum _Role { teacher, enrolled, visitor, guestFree, teacherDraftLong, squareCover }

Widget _page(_Role role) => Builder(
  builder: (context) {
    final c = context.colors;
    final teacher = role == _Role.teacher || role == _Role.teacherDraftLong;
    final course = _course(
      enrolled: role == _Role.enrolled,
      price: role == _Role.guestFree ? 0 : 150,
      students: role == _Role.teacherDraftLong ? 0 : 95,
    );
    final long = role == _Role.teacherDraftLong;
    final cover = switch (role) {
      _Role.teacherDraftLong => null,
      _Role.squareCover => _square,
      _ => _wide,
    };
    final price = role == _Role.guestFree ? tr('مجاناً', 'Free') : tr('150 ج.م', 'EGP 150');
    final students = long ? 0 : 95;
    final stats = [
      CourseSpaceStat(
        icon: Icons.groups_rounded,
        value: '$students',
        label: courseStatNoun(students, 'course_hero_students'),
        onTap: teacher ? () {} : null,
      ),
      CourseSpaceStat(icon: Icons.play_lesson_rounded, value: '6', label: tr('الجلسات', 'Sessions')),
      CourseSpaceStat(icon: Icons.schedule_rounded, value: '6', label: courseStatNoun(6, 'course_hero_hours')),
      if (teacher) CourseSpaceStat(icon: Icons.sell_rounded, value: price, label: tr('السعر', 'Price')),
      if (!long)
        CourseSpaceStat(icon: Icons.star_rounded, tone: c.accent2, value: '5.0', label: courseRatingCount(12)),
    ];
    final CourseSpaceCta? cta = switch (role) {
      _Role.teacher || _Role.teacherDraftLong || _Role.squareCover => CourseSpaceCta(
        primary: CourseSpaceButton(label: tr('جلسة جديدة', 'New session'), icon: Icons.add_rounded, onTap: () {}),
        secondary: CourseSpaceButton(label: tr('تعديل الكورس', 'Edit course'), icon: Icons.edit_rounded, onTap: () {}),
        icons: [CourseSpaceTopAction(icon: Icons.ios_share_rounded, tooltip: tr('مشاركة', 'Share'), onTap: () {})],
        caption: long ? tr('الطلاب لا يرون الكورس حتى تنشره.', 'Students cannot see the course until you publish it.') : null,
      ),
      _Role.enrolled => CourseSpaceCta(
        primary: CourseSpaceButton(label: tr('تابع التعلم', 'Continue learning'), icon: Icons.play_arrow_rounded, onTap: () {}),
        caption: tr('التالي: الدرس 4 — الدوال', 'Up next: Lesson 4 — Functions'),
      ),
      _Role.visitor || _Role.guestFree => courseBuyCta(course, onEnroll: () {}),
    };
    return CourseSpace(
      hero: CourseSpaceHeroData(
        title: long ? tr(_longAr, _longEn) : tr('أساسيات الذكاء الاصطناعي بلغة بايثون', 'AI Foundations with Python'),
        subtitle: tr(
          'من أول سطر بايثون حتى بناء نموذجك الأول — مشروع عملي كل أسبوع، ومراجعة لكل درس.',
          'From your first line of Python to your first model — a hands-on project every week.',
        ),
        coverImage: cover,
        category: tr('الذكاء الاصطناعي', 'Artificial intelligence'),
        badges: [
          if (teacher)
            long
                ? CourseSpaceBadge(label: tr('مسودة', 'Draft'), icon: Icons.edit_note_rounded, color: c.warning)
                : CourseSpaceBadge(label: tr('منشور', 'Published'), icon: Icons.public_rounded),
          CourseSpaceBadge(label: tr('دروس مسجّلة', 'Recorded lessons'), icon: Icons.play_circle_outline_rounded),
        ],
        teacherName: tr('د. سارة الحسيني', 'Dr. Sara El-Husseini'),
        onTeacher: teacher ? null : () {},
        stats: stats,
        progress: role == _Role.enrolled ? 0.38 : null,
        progressLabel: tr('تقدّمك · 3/8', 'Your progress · 3/8'),
        cta: cta,
      ),
      onBack: () {},
      topActions: [
        if (!teacher) CourseSpaceTopAction(icon: Icons.ios_share_rounded, tooltip: 'share', onTap: () {}),
        if (!teacher) CourseSpaceTopAction(icon: Icons.favorite_border_rounded, tooltip: 'like', onTap: () {}),
        CourseSpaceTopAction(icon: Icons.refresh_rounded, tooltip: 'refresh', overflow: true, onTap: () {}),
      ],
      spotlight: [
        if (teacher)
          CourseReadinessCard(
            items: [
              CourseReadinessItem(label: tr('صورة الغلاف', 'Cover image'), done: !long, icon: Icons.image_rounded, onTap: () {}),
              CourseReadinessItem(label: tr('أضف أول جلسة', 'Add the first session'), done: true, icon: Icons.add_rounded, onTap: () {}),
              CourseReadinessItem(label: tr('انشر الكورس', 'Publish the course'), done: !long, icon: Icons.public_rounded, onTap: () {}),
            ],
          ),
      ],
      actions: [
        if (teacher) ...[
          CourseSpaceAction(icon: Icons.groups_rounded, label: tr('الطلاب', 'Students'), color: c.textMedium, onTap: () {}),
          CourseSpaceAction(icon: Icons.quiz_rounded, label: tr('الاختبارات', 'Exams'), color: c.textMedium, onTap: () {}),
          CourseSpaceAction(icon: Icons.workspace_premium_rounded, label: tr('الشهادات', 'Certificates'), color: c.accent2, onTap: () {}),
        ] else
          CourseSpaceAction(icon: Icons.headset_mic_rounded, label: tr('الدعم', 'Support'), color: c.success, onTap: () {}),
      ],
      actionsTitle: tr('اختصارات الكورس', 'Course shortcuts'),
      tabs: [
        CourseSpaceTab(id: 's', label: tr('الجلسات', 'Sessions'), icon: Icons.play_lesson_rounded, count: 6, builder: (_) => const SizedBox(height: 300)),
        CourseSpaceTab(id: 'n', label: tr('الإعلانات', 'Announcements'), icon: Icons.campaign_rounded, builder: (_) => const SizedBox()),
        CourseSpaceTab(id: 'a', label: tr('عن الكورس', 'About'), icon: Icons.info_outline_rounded, builder: (_) => const SizedBox()),
      ],
      activeTab: 's',
      onTab: (_) {},
      aside: switch (role) {
        _Role.enrolled => CourseEnrolledCard(course: course),
        _Role.visitor || _Role.guestFree => CourseBuyCard(course: course, purchase: false, onEnroll: () {}),
        _ => null,
      },
      bottomBar: role == _Role.visitor || role == _Role.guestFree ? CourseBuyBar(course: course, onEnroll: () {}) : null,
    );
  },
);

void main() {
  setUpAll(() async {
    await _loadFonts();
    translation = json.decode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
  });

  for (final r in _Role.values) {
    testWidgets('header ${r.name}', (t) => _render(t, r.name, () => _page(r)));
  }
}
