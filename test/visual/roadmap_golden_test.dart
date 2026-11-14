// Visual review renders of the course roadmap + recommendations (D-120), compared by eye like the other test/visual
// files (NOT a CI suite):
//
//   flutter test test/visual/roadmap_golden_test.dart --update-goldens [--plain-name path]
//
// → test/visual/goldens/roadmap_<scene>_<width>_<lang>_<light|dark>.png
//   path_student   the Path tab: two courses taken, You are here, three next steps (one with prerequisites)
//   path_teacher   the owner's Path tab: Edit path, a draft next course
//   editor         the Edit path sheet's body
//   home_card      the home's journey card under a "My courses" stand-in
//   journey        the journey page
//   recs           the profile's "Recommended for you" + the interests sheet body
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/courses/roadmap/journey_page.dart';
import 'package:flutter_education_app/features/courses/roadmap/recommendations.dart';
import 'package:flutter_education_app/features/courses/roadmap/roadmap_api.dart';
import 'package:flutter_education_app/features/courses/roadmap/roadmap_editor.dart';
import 'package:flutter_education_app/features/courses/roadmap/roadmap_tab.dart';
import 'package:flutter_education_app/features/student/home/home_journey.dart';
import 'package:flutter_education_app/features/student/models.dart' show CourseSummary;
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
  final cfg = jsonDecode(File('.dart_tool/package_config.json').readAsStringSync()) as Map<String, dynamic>;
  for (final p in (cfg['packages'] as List).cast<Map<String, dynamic>>()) {
    if (p['name'] != 'cupertino_icons') continue;
    final root = Uri.parse('${p['rootUri']}');
    final dir = root.isAbsolute ? root.toFilePath() : File('.dart_tool/${p['rootUri']}').absolute.path;
    final font = File('$dir/assets/CupertinoIcons.ttf');
    if (font.existsSync()) await load('packages/cupertino_icons/CupertinoIcons', [font.path]);
  }
}

final _shot = GlobalKey();

const _py = RmField(id: 7, nameAr: 'البرمجة بلغة بايثون', nameEn: 'Python programming');

RmCourse _c(int id, String ar, String en, {RmState? state, double progress = 0, String? level, List<RmPrereq> pre = const [], bool published = true, double price = 450, bool current = false}) =>
    RmCourse(
      id: id,
      nameAr: ar,
      nameEn: en,
      level: level,
      field: _py,
      teacherName: 'منى عبد الرحمن',
      isPublished: published,
      finalPrice: price,
      state: state,
      progress: progress,
      prerequisites: pre,
      prereqsMet: pre.isEmpty ? null : pre.every((p) => p.done == true),
      current: current,
    );

final _student = Roadmap(
  course: _c(3, 'تحليل البيانات باستخدام بايثون', 'Data analysis with Python', state: RmState.inProgress, progress: 64, level: 'intermediate'),
  previous: [
    _c(1, 'أساسيات البرمجة بلغة بايثون', 'Python programming basics', state: RmState.completed, progress: 100, level: 'beginner'),
    _c(2, 'هياكل البيانات', 'Data structures', state: RmState.completed, progress: 100, level: 'beginner'),
  ],
  next: [
    _c(4, 'تعلم الآلة للمبتدئين', 'Machine learning for beginners', state: RmState.notStarted, level: 'intermediate', price: 600, pre: const [
      RmPrereq(id: 3, nameAr: 'تحليل البيانات باستخدام بايثون', nameEn: 'Data analysis with Python', done: false),
      RmPrereq(id: 2, nameAr: 'هياكل البيانات', nameEn: 'Data structures', done: true),
    ]),
    _c(5, 'الرياضيات لتعلم الآلة', 'Math for machine learning', state: RmState.notStarted, level: 'intermediate', price: 0),
    _c(6, 'التعلم العميق', 'Deep learning', state: RmState.notStarted, level: 'advanced', price: 900),
  ],
);

final _teacher = Roadmap(
  course: _c(3, 'تحليل البيانات باستخدام بايثون', 'Data analysis with Python', level: 'intermediate'),
  previous: [_c(1, 'أساسيات البرمجة بلغة بايثون', 'Python programming basics', level: 'beginner')],
  next: [
    _c(4, 'تعلم الآلة للمبتدئين', 'Machine learning for beginners', level: 'intermediate',
        pre: const [RmPrereq(id: 3, nameAr: 'تحليل البيانات باستخدام بايثون', nameEn: 'Data analysis with Python')]),
    _c(6, 'التعلم العميق', 'Deep learning', level: 'advanced', published: false),
  ],
  canEdit: true,
);

final _journey = Journey(
  source: 'roadmap',
  field: _py,
  next: RmCourse(id: 4, nameAr: 'تعلم الآلة للمبتدئين', nameEn: 'Machine learning for beginners', kind: 'start'),
  done: 3,
  total: 6,
  steps: [
    _c(1, 'أساسيات البرمجة بلغة بايثون', 'Python programming basics', state: RmState.completed, level: 'beginner'),
    _c(2, 'هياكل البيانات', 'Data structures', state: RmState.completed, level: 'beginner'),
    _c(3, 'تحليل البيانات باستخدام بايثون', 'Data analysis with Python', state: RmState.completed, level: 'intermediate'),
    _c(4, 'تعلم الآلة للمبتدئين', 'Machine learning for beginners', state: RmState.notStarted, level: 'intermediate', current: true),
    _c(5, 'الرياضيات لتعلم الآلة', 'Math for machine learning', state: RmState.notStarted, level: 'intermediate'),
    _c(6, 'التعلم العميق', 'Deep learning', state: RmState.notStarted, level: 'advanced'),
  ],
);

final _recs = RecPage(total: 12, items: [
  RecItem(
    course: _c(10, 'تصوّر البيانات بمكتبة Matplotlib', 'Data visualization with Matplotlib'),
    reason: 'because_completed',
    reasonAr: 'لأنك أكملت «هياكل البيانات»',
    reasonEn: 'Because you completed “Data structures”',
  ),
  RecItem(course: _c(11, 'بايثون للأتمتة', 'Python for automation'), reason: 'same_teacher', reasonAr: 'من نفس المدرّس، منى عبد الرحمن', reasonEn: 'From the same instructor, Mona Abdelrahman'),
  RecItem(course: _c(12, 'قواعد البيانات SQL', 'SQL databases'), reason: 'similar_students', reasonAr: 'طلاب مثلك درسوه', reasonEn: 'Students like you took this'),
]);

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
      builder: (context, w) => RepaintBoundary(
        key: _shot,
        child: Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!),
      ),
      home: Builder(
        builder: (context) => Scaffold(
          backgroundColor: context.colors.background,
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: child)),
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _sheetLike(Widget child) => Builder(
  builder: (context) => Container(
    decoration: BoxDecoration(color: context.colors.cardBg, borderRadius: BorderRadius.circular(20)),
    clipBehavior: Clip.antiAlias,
    child: child,
  ),
);

Future<void> _render(WidgetTester tester, String name, Widget Function() build, {List<Size> sizes = const [Size(390, 844)]}) async {
  final prevLang = AppConfig.lang;
  debugDisableShadows = false;
  try {
    for (final size in sizes) {
      for (final lang in const ['ar', 'en']) {
        for (final dark in const [false, true]) {
          AppConfig.lang = lang;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(_host(build(), dark: dark));
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          final e = tester.takeException();
          expect(e, isNull, reason: '$name ${size.width.toInt()} $lang ${dark ? 'dark' : 'light'}: $e');
          await expectLater(
            find.byKey(_shot),
            matchesGoldenFile('goldens/roadmap_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'),
          );
        }
      }
    }
  } finally {
    AppConfig.lang = prevLang;
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    debugDisableShadows = true;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

void main() {
  setUpAll(_loadFonts);
  setUp(() => AppConfig.disableList = []);

  final picks = [
    CourseSummary(id: 30, name: 'Pandas in practice', imageUrl: '', price: 350, finalPrice: 350),
    CourseSummary(id: 31, name: 'Clean code in Python', imageUrl: '', price: 0, finalPrice: 0),
  ];

  testWidgets('path_student', (t) => _render(
    t,
    'path_student',
    () => RoadmapTabContent(roadmap: _student, staff: false, onOpenCourse: (_) {}, onEnrollAll: () {}, teacherPicks: picks, onOpenPick: (_) {}),
    sizes: const [Size(390, 844), Size(1440, 900)],
  ));
  testWidgets('path_teacher', (t) => _render(t, 'path_teacher', () => RoadmapTabContent(roadmap: _teacher, staff: true, onEdit: () {}, onOpenCourse: (_) {})));
  testWidgets('editor', (t) => _render(
    t,
    'editor',
    () => _sheetLike(RoadmapEditorForm(
      draft: RoadmapDraft(
        next: [_teacher.next[0], _teacher.next[1], _c(5, 'الرياضيات لتعلم الآلة', 'Math for machine learning', level: 'intermediate')],
        prereqs: [_c(1, 'أساسيات البرمجة بلغة بايثون', 'Python programming basics')],
        level: 'intermediate',
        tags: ['Python', 'Pandas', 'تحليل البيانات'],
      ),
      onAddNext: () {},
      onAddPrereq: () {},
      onChanged: () {},
    )),
  ));
  testWidgets('home_card', (t) => _render(
    t,
    'home_card',
    () => Builder(
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 180,
            decoration: BoxDecoration(color: context.colors.cardBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: context.colors.divider)),
            alignment: Alignment.center,
            child: Text('My courses (stand-in)', style: TextStyle(color: context.colors.textLight)),
          ),
          const SizedBox(height: 24),
          HomeJourneyCard(journey: _journey, onTap: () {}),
        ],
      ),
    ),
  ));
  testWidgets('journey', (t) => _render(t, 'journey', () => JourneyContent(journey: _journey, onOpenCourse: (_) {})));
  testWidgets('recs', (t) => _render(
    t,
    'recs',
    () => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RecommendationsSectionView(page: _recs, onOpen: (_) {}, onDismiss: (_) {}, onInterests: () {}, onSeeAll: () {}),
        const SizedBox(height: 24),
        RecommendationsSectionView(page: const RecPage(hidden: true), onOpen: (_) {}, onDismiss: (_) {}, onInterests: () {}),
        const SizedBox(height: 24),
        _sheetLike(InterestsForm(
          fields: const [
            RmField(id: 1, nameAr: 'البرمجة', nameEn: 'Programming'),
            RmField(id: 2, nameAr: 'التصميم', nameEn: 'Design'),
            RmField(id: 3, nameAr: 'اللغات', nameEn: 'Languages'),
            RmField(id: 4, nameAr: 'إدارة الأعمال', nameEn: 'Business'),
            _py,
          ],
          picked: const {1, 7},
          show: true,
          inferred: true,
          onToggle: (_) {},
          onShow: (_) {},
        )),
      ],
    ),
  ));
}
