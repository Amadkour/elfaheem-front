// VISUAL review renders (not a CI suite), exam flow round 3 (D-1135): the screens earlier rounds never drew.
//   - every step of the new-exam wizard, for a paper exam on a bubble sheet and for an online exam;
//   - the teacher's appeals list, the appeal decision and the student's regrade request (grade review);
//   - an answer in the grading queue;
//   - the result of a paper import;
//   - the submit confirmation.
// Default sizes are 320x640 and 1400x900, ar / en, light (GOLDEN_SIZES / GOLDEN_THEMES override them). Output goes to
// test/visual/goldens/exam_r3_*.png and is compared by eye.
//
//   flutter test test/visual/exam_round3_golden_test.dart --update-goldens [--plain-name appeals]
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/exams/exam_all.dart' show NewExamPlace;
import 'package:flutter_education_app/features/exams/exam_insights.dart';
import 'package:flutter_education_app/features/exams/exam_insights_screen.dart';
import 'package:flutter_education_app/features/exams/exam_paper_flow.dart';
import 'package:flutter_education_app/features/exams/exam_quick.dart';
import 'package:flutter_education_app/features/exams/exam_review.dart';
import 'package:flutter_education_app/features/exams/exam_review_screen.dart';
import 'package:flutter_education_app/features/exams/hub/create/exam_create_logic.dart';
import 'package:flutter_education_app/features/exams/hub/create/exam_create_sync.dart';
import 'package:flutter_education_app/features/exams/hub/create/exam_create_wizard.dart';
import 'package:flutter_education_app/features/exams/paper/exam_setup.dart';
import 'package:flutter_education_app/main.dart' show navigatorKey;
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

Future<void> _render(WidgetTester tester, String name, Widget Function() build, {Future<void> Function(WidgetTester)? act}) async {
  final prevLang = AppConfig.lang;
  debugDisableShadows = false;
  final fake = FakeApi(const {}, latency: const Duration(milliseconds: 5))..install();
  try {
    for (final size in goldenSizes(const [Size(320, 640), Size(1400, 900)])) {
      for (final lang in const ['ar', 'en']) {
        for (final dark in goldenThemes().where((d) => Platform.environment['GOLDEN_THEMES'] != null || !d)) {
          AppConfig.lang = lang;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          await tester.pumpWidget(const SizedBox());
          final theme = ThemeConfigProvider(api: ApiClient());
          await tester.pumpWidget(ThemeConfigScope(
            provider: theme,
            child: MaterialApp(
              navigatorKey: navigatorKey,
              debugShowCheckedModeBanner: false,
              theme: theme.materialTheme(dark: false),
              darkTheme: theme.materialTheme(dark: true),
              themeMode: dark ? ThemeMode.dark : ThemeMode.light,
              builder: (context, w) => RepaintBoundary(
                key: _shot,
                child: Directionality(textDirection: lang == 'ar' ? TextDirection.rtl : TextDirection.ltr, child: w!),
              ),
              home: build(),
            ),
          ));
          for (var i = 0; i < 20; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          if (act != null) {
            await act(tester);
            for (var i = 0; i < 8; i++) {
              await tester.pump(const Duration(milliseconds: 100));
            }
          }
          final e = tester.takeException();
          if (e is Error) debugPrint('STACK ${e.stackTrace}');
          expect(e, isNull, reason: '$name ${size.width.toInt()} $lang ${dark ? 'dark' : 'light'}: $e');
          await expectLater(find.byKey(_shot), matchesGoldenFile('goldens/exam_r3_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'));
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

Future<(List<NewExamPlace>, Map<int, String>)> _places() async => (
      <NewExamPlace>[
        (courseId: 7, orgId: null, name: _x('الرياضيات — الصف الثالث', 'Mathematics — grade 3')),
        (courseId: 8, orgId: 2, name: _x('الكيمياء العامة', 'General chemistry')),
        (courseId: null, orgId: null, name: _x('بدون مقرر (اختبار شخصي)', 'No course (personal exam)')),
      ],
      {2: _x('كلية العلوم', 'Faculty of Science')},
    );

Future<CreateTemplates> _templates() async => (
      items: const [
        OmrTemplateItem(id: 3, version: 1, name: 'Bubble 60', questions: 60, kind: 'bubble'),
        OmrTemplateItem(id: 4, version: 2, name: 'NB2 answer sheet', questions: 100, kind: 'auto_bubble'),
      ],
      error: null,
    );

/// A paper exam on a bubble sheet with 12 questions and a key.
ExamCreatePlan _paperPlan() {
  final p = ExamCreatePlan(place: (courseId: 7, orgId: null, name: _x('الرياضيات — الصف الثالث', 'Mathematics — grade 3')),
      title: _x('اختبار الوحدة الرابعة', 'Unit 4 check'))
    ..setOffline(true);
  for (var i = 0; i < 12; i++) {
    p.exam.questions.add(_mcq(_x('سؤال $i', 'Question $i')));
  }
  p
    ..setLayout(PaperLayout.bubbleObjective)
    ..template = const OmrTemplateItem(id: 3, version: 1, name: 'Bubble 60', questions: 60, kind: 'bubble');
  return p;
}

/// An online exam with three questions.
ExamCreatePlan _onlinePlan() {
  final p = ExamCreatePlan(place: (courseId: 7, orgId: null, name: _x('الرياضيات — الصف الثالث', 'Mathematics — grade 3')),
      title: _x('اختبار قصير ٢', 'Quiz 2'))
    ..setOffline(false);
  for (var i = 0; i < 3; i++) {
    p.exam.questions.add(_mcq(_x('كم يساوي ٢ + $i؟', 'What is 2 + $i?')));
  }
  return p;
}

// the steps after the questions work on the saved draft (the wizard saves it before opening them): one is "saved"
Widget _wizard(ExamCreatePlan plan, CreateStep step) => ExamCreateWizard(
    initialPlan: plan, initialStep: step, startedQuestions: true, placesLoader: _places, templatesLoader: _templates,
    sync: const {CreateStep.where, CreateStep.answer, CreateStep.questions, CreateStep.layout, CreateStep.template}.contains(step) ? null : (ExamCreateSync()..examId = 501));

List<Appeal> _appeals() => [
      Appeal(id: 1, attemptId: 4, questionId: 4821, position: 3, max: 5, state: 'open', studentId: 31, scoreBefore: 2,
          reason: _x('شرحت خطوة الطاقة الضوئية بوضوح في السطر الثاني، أرجو إعادة النظر.', 'I explained the light-energy step clearly in line two, please have another look.')),
      Appeal(id: 2, attemptId: 5, questionId: 4822, position: 7, max: 2, state: 'in_review', studentCode: 'A-17', scoreBefore: 0,
          reason: _x('الإجابة صحيحة بصيغة مختلفة.', 'The answer is right, written another way.')),
      Appeal(id: 3, attemptId: 6, questionId: 4823, position: 1, max: 1, state: 'accepted', studentId: 33, scoreBefore: 0, scoreAfter: 1,
          note: _x('إعادة قراءة: الدرجة كاملة', 'Re-read: full marks'), reason: _x('اخترت (ب) وظُلّلت بوضوح.', 'I chose (b) and it was clearly shaded.')),
    ];

ReviewItem _review() => ReviewItem.fromJson({
      'answer_id': 9, 'attempt_id': 4, 'question_id': 4821, 'type': 'essay', 'student_id': 31, 'points': 5,
      'prompt': _x('اشرح عملية البناء الضوئي ودور الكلوروفيل فيها.', 'Explain photosynthesis and the role of chlorophyll in it.'),
      'answer': {'text': _x('يمتص الكلوروفيل الضوء فيحوّل النبات الماء وثاني أكسيد الكربون إلى جلوكوز وأكسجين.',
          'Chlorophyll absorbs light, so the plant turns water and carbon dioxide into glucose and oxygen.'), 'source': 'online'},
      'review_state': 'needs_review', 'proposed_score': 3.5, 'confidence': 0.62,
      'proposal': {'scale': 1, 'criteria': [], 'flags': ['memory_wrong', 'other_language']},
      'key': {'model': _x('الكلوروفيل يمتص الضوء؛ ثاني أكسيد الكربون + ماء ← جلوكوز + أكسجين.', 'Chlorophyll absorbs light; CO2 + water → glucose + oxygen.')},
      'marks': [],
    });

class _Page extends StatelessWidget {
  const _Page({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: context.colors.background,
        appBar: AppHeader(title: title),
        body: ListView(padding: const EdgeInsets.all(AppSpace.md), children: children),
      );
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

  for (final step in const [CreateStep.where, CreateStep.answer, CreateStep.layout, CreateStep.template, CreateStep.sheets, CreateStep.identify,
    CreateStep.attributes, CreateStep.design, CreateStep.review]) {
    testWidgets('paper ${step.name}', (t0) => _render(t0, 'paper_${step.name}', () => _wizard(_paperPlan(), step)));
  }
  for (final step in const [CreateStep.where, CreateStep.questions, CreateStep.publish, CreateStep.review]) {
    testWidgets('online ${step.name}', (t0) => _render(t0, 'online_${step.name}', () => _wizard(_onlinePlan(), step)));
  }
  testWidgets('appeals', (t0) => _render(t0, 'appeals', () => _Page(title: _x('التظلمات', 'Appeals'), children: [
        for (final a in _appeals()) AppealCard(appeal: a, onClaim: a.state == 'open' ? () {} : null, onDecide: a.open ? () {} : null),
      ])));
  testWidgets('appeal decision', (t0) => _render(t0, 'appeal_decision', () => Scaffold(
        body: AppealDecisionSheet(appeal: _appeals().first, points: 5, onSave: ({required bool accept, double? score, required String note}) async => null),
      )));
  testWidgets('appeal request', (t0) => _render(t0, 'appeal_request', () => Scaffold(
        body: StudentAppealSheet(questionLabel: _x('السؤال 3', 'Question 3'), onSubmit: (_) async => null),
      )));
  testWidgets('student appeals', (t0) => _render(t0, 'student_appeals', () => _Page(title: _x('تظلماتي', 'My appeals'), children: [
        for (final a in _appeals()) AppealCard(appeal: a, onWithdraw: a.state == 'open' ? () {} : null),
      ])));
  testWidgets('grading queue', (t0) => _render(t0, 'grading', () => _Page(title: _x('مراجعة التصحيح', 'Review grading'), children: [
        ReviewAnswerCard(item: _review(), threshold: 0.8, studentName: _x('مريم أحمد', 'Mariam Ahmed'), onAccept: () {}, onEdit: () {}),
      ])));
  testWidgets('paper result', (t0) => _render(t0, 'paper_result', () => _Page(title: _x('استيراد الدرجات', 'Import marks'), children: [
        PaperResultView(
          summary: _x('أُضيفت 27 درجة من 30', '27 of 30 marks were added'),
          problems: const [
            PaperProblem(row: 4, code: 'not_a_student', extra: {'student_id': 412}),
            PaperProblem(row: 11, code: 'score_out_of_range', extra: {'value': '42', 'max': 40}),
            PaperProblem(row: 19, code: 'bad_row'),
          ],
        ),
      ])));
  testWidgets('submit confirm', (t0) => _render(t0, 'submit_confirm',
      () => Builder(builder: (c) => Scaffold(body: Center(child: AppButton.primary(onPressed: () {}, label: 'x')))),
      act: (t) async {
        final ctx = navigatorKey.currentContext!;
        appConfirm(ctx,
            message: _x('لديك 3 أسئلة بلا إجابة. تسليم الاختبار؟', 'You have 3 questions unanswered. Submit the exam?'),
            confirmLabel: _x('تسليم', 'Submit'));
      }));
}
