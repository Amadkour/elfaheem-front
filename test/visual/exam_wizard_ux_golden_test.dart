// VISUAL review renders (not a CI suite): the new-exam wizard's UX round (D-716, D-717) — the Copies step of a paper
// exam on the teacher's own bubble form with no course (one copy per student, what each student gets), and the
// Questions step with questions from several sources in one list — at 390x844 and 1440x900, ar / en, light / dark,
// into test/visual/goldens/exam_wizard_*.png. Compared by eye.
//
//   flutter test test/visual/exam_wizard_ux_golden_test.dart --update-goldens [--plain-name copies]
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/exams/exam_quick.dart';
import 'package:flutter_education_app/features/exams/hub/create/exam_create_logic.dart';
import 'package:flutter_education_app/features/exams/hub/create/exam_create_wizard.dart';
import 'package:flutter_education_app/features/exams/paper/exam_setup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import 'golden_sizes.dart';
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

Future<void> _render(WidgetTester tester, String name, Widget Function() build, {Future<void> Function(WidgetTester)? act}) async {
  final prevLang = AppConfig.lang;
  debugDisableShadows = false;
  final fake = FakeApi(const {}, latency: const Duration(milliseconds: 5))..install();
  try {
    for (final size in goldenSizes(const [Size(390, 844), Size(1440, 900)])) {
      for (final lang in const ['ar', 'en']) {
        for (final dark in goldenThemes()) {
          AppConfig.lang = lang;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(_host(build(), dark: dark));
          for (var i = 0; i < 20; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          if (act != null) await act(tester);
          final e = tester.takeException();
          expect(e, isNull, reason: '$name ${size.width.toInt()} $lang ${dark ? 'dark' : 'light'}: $e');
          await expectLater(find.byKey(_shot), matchesGoldenFile('goldens/exam_wizard_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'));
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

String _x(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

QuickQuestion _mcq(String prompt) {
  final q = QuickQuestion.ofType('mcq_single')
    ..prompt = prompt
    ..correct = 'a';
  for (var i = 0; i < q.options.length; i++) {
    q.options[i].text = ['2', '3', '4', '5'][i];
  }
  return q;
}

/// No course, a paper exam on the teacher's own bubble form (150 questions), one copy per student.
ExamCreatePlan _copiesPlan() {
  final p = ExamCreatePlan(place: (courseId: null, orgId: null, name: _x('بدون مقرر (اختبار شخصي)', 'No course (personal exam)')), title: _x('اختبار قصير', 'Quiz'))..setOffline(true);
  for (var i = 0; i < 17; i++) {
    p.exam.questions.add(_mcq('Q$i'));
  }
  p
    ..setLayout(PaperLayout.bubbleObjective)
    ..template = const OmrTemplateItem(id: 3, version: 1, name: 'Mine', questions: 150, kind: 'auto_bubble')
    ..bubbleForm = BubbleFormSource.imported
    ..setCopies(SheetCopies.personal);
  return p;
}

/// A course exam whose questions came from four sources: written, generated, Google Forms and Excel.
ExamCreatePlan _questionsPlan() {
  final p = ExamCreatePlan(place: (courseId: 7, orgId: null, name: _x('الرياضيات', 'Mathematics')), title: _x('اختبار الوحدة الرابعة', 'Unit 4 check'))..setOffline(true);
  final a = _mcq(_x('كم يساوي ٢ + ٢؟', 'What is 2 + 2?'));
  p.exam.questions.add(a);
  p.setHeld([
    HeldQuestion(placementId: 41, sectionId: 1, type: 'mcq_single', prompt: _x('ما عاصمة مصر؟', 'What is the capital of Egypt?'), points: 1),
    HeldQuestion(placementId: 42, sectionId: 1, type: 'short_answer', prompt: _x('اذكر قانون نيوتن الأول.', "State Newton's first law."), points: 2),
  ], QuestionOrigin.forms);
  p.setHeld([
    ...p.held,
    HeldQuestion(placementId: 43, sectionId: 1, type: 'true_false', prompt: _x('الماء يغلي عند ١٠٠ درجة مئوية.', 'Water boils at 100 °C.'), points: 1),
  ], QuestionOrigin.excel);
  final g = QuickQuestion.ofType('true_false')..prompt = _x('الضوء أسرع من الصوت.', 'Light is faster than sound.');
  g.engine!.tfCorrect = true;
  p.markOrigin(g, QuestionOrigin.generated);
  p.exam.questions.add(g);
  return p;
}

void main() {
  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    await _loadFonts();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    AppConfig.disableList = [];
  });

  testWidgets('copies', (t0) => _render(t0, 'copies', () => ExamCreateWizard(initialPlan: _copiesPlan(), initialStep: CreateStep.sheets)));
  testWidgets('questions', (t0) => _render(t0, 'questions', () => ExamCreateWizard(initialPlan: _questionsPlan(), initialStep: CreateStep.questions, startedQuestions: true)));
  testWidgets('questions_end', (t0) => _render(t0, 'questions_end', () => ExamCreateWizard(initialPlan: _questionsPlan(), initialStep: CreateStep.questions, startedQuestions: true), act: (t) async {
        final list = find.byType(Scrollable).evaluate().map((e) => e.widget as Scrollable).where((s) => s.axisDirection == AxisDirection.down).length;
        expect(list, greaterThan(0));
        await t.drag(find.byKey(const ValueKey('create.title')), const Offset(0, -5000));
        for (var i = 0; i < 10; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
      }));
  testWidgets('ways', (t0) => _render(t0, 'ways', () => ExamCreateWizard(initialPlan: ExamCreatePlan(place: (courseId: 7, orgId: null, name: 'x'), title: 'x')..setOffline(true), initialStep: CreateStep.questions, startedQuestions: false)));
}
