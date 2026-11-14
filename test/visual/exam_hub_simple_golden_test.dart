// VISUAL review renders (not a CI suite): the plain Exam Hub (D-700 – D-703) — the opening Running tab with "Needs you
// now", Drafts, Finished, a card's narrowed list, the phone's exam page and the empty hub — at 390x844 and 1440x900,
// ar / en (light; the opening scene in dark too), into test/visual/goldens/exam_hub_simple_*.png. Compared by eye.
//
//   flutter test test/visual/exam_hub_simple_golden_test.dart --update-goldens [--plain-name running]
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/exams/exam_all.dart';
import 'package:flutter_education_app/features/exams/hub/exam_hub_screen.dart';
import 'package:flutter_education_app/features/exams/hub/hub_logic.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
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
final _now = DateTime.utc(2026, 11, 13, 8);

Map<String, dynamic> _g({bool ended = true, String state = 'waiting', int papers = 0, int review = 0, int answers = 0, int submitted = 0, bool degrees = false, String? source, bool published = false}) => {
      'ended': ended,
      'state': state,
      'papers': papers,
      'review_open': review,
      'answers_open': answers,
      'submitted': submitted,
      'has_degrees': degrees,
      'degrees_source': source,
      'results_published': published,
      'data_lab_column': null,
    };

const _paper = {'mode': 'offline'};

AllExam _e(int id, String title,
        {String status = 'closed', Map<String, dynamic>? g, int? course = 10, Map<String, dynamic>? settings, String? starts, String? ends, int q = 12, int attempts = 30}) =>
    AllExam({
      'id': id,
      'title': title,
      'status': status,
      'course_id': course,
      'org_id': null,
      'settings': settings,
      'starts_at': starts,
      'ends_at': ends,
      'created_at': '2026-11-0${id % 9 + 1}T09:00:00',
      'duration_minutes': 30,
      'question_count': q,
      'attempts': {'total': attempts},
      'grading': ?g,
    });

/// Every state the hub can show, with two exams of the same name in two courses.
AllExamsData hubSample() {
  final ar = AppConfig.lang == 'ar';
  String x(String a, String e) => ar ? a : e;
  return AllExamsData(exams: [
    // drafts: one with questions (and the 2020 placeholder start that used to show), one empty, one on paper
    _e(1, x('تصحيح هندسة الذكاء الاصطناعي', 'Production AI Engineering check'), status: 'draft', q: 17, starts: '2020-01-01T00:00:00', g: _g(state: 'not_applicable', ended: false)),
    _e(2, x('اختبار قصير بلا أسئلة', 'Blank quiz'), status: 'draft', q: 0, course: 11, g: _g(state: 'not_applicable', ended: false)),
    _e(3, x('امتحان الوحدة الثانية الورقي', 'Unit 2 paper exam'), status: 'draft', q: 25, settings: _paper, g: _g(state: 'not_applicable', ended: false)),
    // running: online open with answers, paper open, scheduled; a duplicate name in another course
    _e(4, 'E-business Quiz', status: 'published', starts: '2026-11-12T08:00:00', ends: '2026-11-20T10:00:00', attempts: 12, g: _g(ended: false, submitted: 12)),
    _e(5, 'E-business Quiz', status: 'published', course: 11, settings: _paper, starts: '2026-11-13T07:00:00', ends: '2026-11-15T12:00:00', g: _g(ended: false)),
    _e(6, x('اختبار نهاية الفصل الدراسي الأول في الرياضيات للصف الثاني الثانوي', 'End of term exam in mathematics for the second year of secondary school'),
        status: 'published', starts: '2026-11-18T09:00:00', ends: '2026-11-18T11:00:00', attempts: 0, g: _g(ended: false)),
    // finished: papers to grade, grading part-way, graded but unpublished, results out, nobody answered, archived
    _e(7, x('امتحان منتصف الفصل الورقي', 'Midterm paper exam'), settings: _paper, ends: '2026-11-10T10:00:00', g: _g(papers: 30, submitted: 30)),
    _e(8, x('اختبار الأسبوع السادس', 'Week 6 quiz'), ends: '2026-11-09T10:00:00', g: _g(state: 'in_progress', answers: 3, review: 1, submitted: 28, degrees: true, source: 'exam')),
    _e(9, x('مراجعة الفصل الثالث', 'Chapter 3 review'), ends: '2026-11-08T10:00:00', g: _g(state: 'corrected', submitted: 30, degrees: true, source: 'exam')),
    _e(10, x('اختبار قصير في الهندسة', 'Short geometry quiz'), course: null, ends: '2026-11-02T10:00:00', g: _g(state: 'corrected', degrees: true, source: 'import', published: true)),
    _e(11, x('تمرين سريع على المتتابعات', 'Quick drill on sequences'), ends: '2026-11-01T10:00:00', attempts: 0, g: _g()),
    _e(12, x('اختبار تجريبي قديم', 'Old trial exam'), status: 'archived', ends: '2026-10-01T10:00:00', g: _g(state: 'not_applicable')),
  ], courseNames: {10: x('الرياضيات للصف الثاني الثانوي', 'Mathematics, second secondary'), 11: x('التجارة الإلكترونية', 'E-commerce basics')}, orgNames: const {});
}

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
      home: child,
    ),
  );
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 20; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _render(WidgetTester tester, String name, Widget Function() build,
    {Future<void> Function(WidgetTester)? act, List<Size> sizes = const [Size(390, 844), Size(1440, 900)], bool withDark = false}) async {
  final prevLang = AppConfig.lang;
  debugDisableShadows = false;
  final fake = FakeApi(const {}, latency: const Duration(milliseconds: 5))..install();
  try {
    for (final size in sizes) {
      for (final lang in const ['ar', 'en']) {
        for (final dark in [false, if (withDark) true]) {
          AppConfig.lang = lang;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(_host(build(), dark: dark));
          await _settle(tester);
          if (act != null) await act(tester);
          final e = tester.takeException();
          expect(e, isNull, reason: '$name ${size.width.toInt()} $lang ${dark ? 'dark' : 'light'}: $e');
          await expectLater(find.byKey(_shot), matchesGoldenFile('goldens/exam_hub_simple_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'));
        }
      }
    }
  } finally {
    fake.uninstall();
    AppConfig.lang = prevLang;
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
    debugDisableShadows = true;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

Future<void> Function(WidgetTester) _tapStage(HubStage s) => (t) async {
      final f = find.descendant(of: find.byKey(const ValueKey('exam.hub.stages')), matching: find.text(hubStageLabel(s)));
      await t.tap(f.first, warnIfMissed: false);
      await _settle(t);
    };

Future<void> _tapCard(WidgetTester t) async {
  await t.tap(find.byKey(const ValueKey('exam.hub.attention.unpublished')), warnIfMissed: false);
  await _settle(t);
}

void main() {
  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    final extra = Directory('assets/translation_extra');
    if (extra.existsSync()) {
      for (final f in extra.listSync().whereType<File>()) {
        translation.addAll(jsonDecode(f.readAsStringSync()) as Map<String, dynamic>);
      }
    }
    await _loadFonts();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    AppConfig.disableList = [];
  });

  ExamHubScreen hub({int tab = 0, AllExamsData Function()? data}) => ExamHubScreen(initialTab: tab, now: _now, loader: () async => (data ?? hubSample)());

  testWidgets('running', (t0) => _render(t0, 'running', () => hub(), withDark: true));
  testWidgets('drafts', (t0) => _render(t0, 'drafts', () => hub(), act: _tapStage(HubStage.drafts)));
  testWidgets('finished', (t0) => _render(t0, 'finished', () => hub(tab: 1)));
  testWidgets('focus', (t0) => _render(t0, 'focus', () => hub(), act: _tapCard));
  testWidgets('page', (t0) => _render(t0, 'page', sizes: const [Size(390, 844)], () {
        final d = hubSample();
        final e = d.exams.firstWhere((x) => x.id == 8);
        return HubExamPage(
          examId: e.id,
          changes: ValueNotifier(0),
          exam: () => e,
          course: () => d.courseName(e),
          org: () => null,
          busy: () => false,
          now: _now,
          onAction: (_, _, _) {},
        );
      }));
  testWidgets('empty', (t0) => _render(t0, 'empty', () => hub(data: () => const AllExamsData(exams: []))));
}
