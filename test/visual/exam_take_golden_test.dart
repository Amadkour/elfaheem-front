// VISUAL review renders (not a CI suite): sitting an Exam Engine exam and its result in the Warm Editorial theme —
// the question sheet with its options, the progress strip and the nav bar; the result's score block and the marked
// answers; the consent page; the course's exam cards — at 390x844 and 1440x900, ar / en, light / dark, into
// test/visual/goldens/exam_take_*.png. Compared by eye.
//
//   flutter test test/visual/exam_take_golden_test.dart --update-goldens [--plain-name taking]
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/exams/engine_exams_section.dart';
import 'package:flutter_education_app/features/exams/exam_consent_screen.dart';
import 'package:flutter_education_app/features/exams/exam_result_screen.dart';
import 'package:flutter_education_app/features/exams/exam_quick.dart';
import 'package:flutter_education_app/features/exams/exam_quick_screen.dart';
import 'package:flutter_education_app/features/exams/exam_taking.dart';
import 'package:flutter_education_app/features/exams/exam_taking_screen.dart';
import 'package:flutter_education_app/features/exams/offline/offline_exam_core.dart' show OfflineStage;
import 'package:flutter_education_app/features/exams/offline/offline_exam_screen.dart';
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
  await load('MaterialIcons', ['$sdk/materialicons-regular.otf']);
}

final _shot = GlobalKey();
String _tr(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

Paper _paper() => Paper.fromJson({
      'sections': [
        {
          'section_id': 1, 'title': _tr('القسم الأول: الكيمياء العضوية', 'Part one: organic chemistry'), 'mode': 'online', 'navigation': 'free',
          'questions': [
            {'question_id': 1, 'type': 'mcq_single', 'points': 2, 'answer': {'option': 'b'}, 'body': {
              'prompt': _tr('أي من المركبات التالية يُعدّ ألكيناً؟', 'Which of the following compounds is an alkene?'),
              'options': [
                {'id': 'a', 'text': _tr('الميثان CH4', 'Methane, CH4')},
                {'id': 'b', 'text': _tr('الإيثين C2H4', 'Ethene, C2H4')},
                {'id': 'c', 'text': _tr('الإيثانول C2H5OH', 'Ethanol, C2H5OH')},
                {'id': 'd', 'text': _tr('البنزين العطري C6H6 في حالته السائلة عند درجة حرارة الغرفة', 'Benzene, C6H6, a liquid at room temperature')},
              ]}},
            {'question_id': 2, 'type': 'true_false', 'points': 1, 'answer': null, 'body': {'prompt': _tr('الماء مركب قطبي.', 'Water is a polar molecule.')}},
            {'question_id': 3, 'type': 'mcq_multi', 'points': 2, 'answer': {'options': ['a']}, 'body': {'prompt': 'primes', 'options': [{'id': 'a', 'text': '2'}, {'id': 'b', 'text': '3'}]}},
            for (var i = 4; i <= 12; i++) {'question_id': i, 'type': 'short_answer', 'points': 1, 'answer': i.isEven ? {'text': 'x'} : null, 'body': {'prompt': 'q$i'}},
          ],
        },
      ],
    });

class _Taking extends StatelessWidget {
  const _Taking();

  @override
  Widget build(BuildContext context) {
    final p = _paper();
    final all = p.all;
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppHeader(
        title: _tr('اختبار الكيمياء — الفصل الثالث', 'Chemistry quiz — unit 3'),
        compact: true,
        actions: [
          AppIconButton(onPressed: () {}, icon: Icons.file_download_rounded, tooltip: 'x'),
          const ExamTimerChip(remainingSeconds: 1234, timed: true),
        ],
      ),
      body: Column(children: [
        ExamProgressBar(index: 0, total: all.length, answered: p.answeredCount, locked: false, pendingSaves: 0,
            answeredFlags: [for (final q in all) q.answered]),
        Expanded(child: ExamQuestionCard(question: all[0], number: 1, section: p.sections[0], enabled: true, onAnswer: (_) {})),
        ExamNavBar(index: 0, total: all.length, canBack: false, submitting: false, onBack: () {}, onNext: () {}, onJump: (_) {},
            answered: {for (final q in all) q.questionId: q.answered}, questionIds: [for (final q in all) q.questionId], onSubmit: () {}),
      ]),
    );
  }
}

class _TakingTf extends StatelessWidget {
  const _TakingTf();

  @override
  Widget build(BuildContext context) {
    final p = _paper();
    final all = p.all;
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppHeader(title: _tr('اختبار الكيمياء', 'Chemistry quiz'), compact: true, actions: const [ExamTimerChip(remainingSeconds: 48, timed: true)]),
      body: Column(children: [
        ExamProgressBar(index: 1, total: all.length, answered: p.answeredCount, locked: true, lockReason: 'other_app', pendingSaves: 2,
            answeredFlags: [for (final q in all) q.answered]),
        Expanded(child: ExamQuestionCard(question: all[1], number: 2, section: p.sections[0], enabled: true, onAnswer: (_) {})),
        Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: ExamQuestionGrid(answered: {for (final q in all) q.questionId: q.answered}, questionIds: [for (final q in all) q.questionId], current: 1, onJump: (_) {}),
        ),
        ExamNavBar(index: all.length - 1, total: all.length, canBack: true, submitting: false, onBack: () {}, onNext: () {}, onJump: (_) {},
            answered: const {}, questionIds: const [], onSubmit: () {}),
      ]),
    );
  }
}

Map<String, dynamic> _result({double pct = 75}) => {
      'visible': true, 'state': 'graded', 'score': pct / 10, 'max_score': 10, 'percentage': pct, 'passed': pct >= 50, 'attempt_id': pct.toInt(),
      'answers': [
        {'question_id': 1, 'position': 1, 'type': 'mcq_single', 'prompt': _tr('أي من المركبات التالية يُعدّ ألكيناً؟', 'Which of the following compounds is an alkene?'),
          'your_answer': _tr('الإيثين', 'Ethene'), 'score': 2, 'max': 2, 'correct_answer': _tr('الإيثين', 'Ethene')},
        {'question_id': 2, 'position': 2, 'type': 'mcq_single', 'prompt': _tr('ما الغاز الناتج عن التمثيل الضوئي؟', 'Which gas does photosynthesis release?'),
          'your_answer': _tr('ثاني أكسيد الكربون', 'Carbon dioxide'), 'score': 0, 'max': 1, 'correct_answer': _tr('الأكسجين', 'Oxygen')},
        {'question_id': 3, 'position': 3, 'type': 'essay', 'prompt': _tr('اشرح قانون نيوتن الثاني بمثال.', 'Explain Newton\'s second law with an example.'),
          'your_answer': _tr('القوة تساوي الكتلة في التسارع ...', 'Force equals mass times acceleration ...'), 'score': 1.5, 'max': 3, 'correct_answer': '—'},
        {'question_id': 4, 'position': 4, 'type': 'mcq_single', 'prompt': _tr('سؤال أُلغي', 'A cancelled question'), 'your_answer': 'b', 'score': 0, 'max': 1, 'voided': true,
          'correct_answer': 'a'},
      ],
    };

class _Result extends StatelessWidget {
  const _Result({this.pct = 75});
  final double pct;


  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: context.colors.background,
        appBar: AppHeader(title: _tr('نتيجة الاختبار', 'Exam result')),
        body: ExamResultBody(result: _result(pct: pct), examTitle: _tr('اختبار الكيمياء — الفصل الثالث', 'Chemistry quiz — unit 3'), onAppeal: (_) {}),
      );
}

class _Consent extends StatelessWidget {
  const _Consent();

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: context.colors.background,
        appBar: AppHeader(title: _tr('قبل الاختبار', 'Before the exam')),
        body: ConsentBody(
          title: _tr('إقرار قبل الاختبار', 'Before you start'),
          body: _tr('سيُسجَّل الخروج من نافذة الاختبار وتبديل التطبيقات. لا تُحفظ صور أو صوت. ' * 4,
              'Leaving the exam window and switching apps are recorded. No pictures or sound are kept. ' * 4),
          version: 2,
          requires: const {'camera': false},
          capabilities: [_tr('تسجيل تبديل النوافذ', 'Records window switches'), _tr('منع لقطات الشاشة على الهاتف', 'Blocks screenshots on phones')],
          accepted: false,
          busy: false,
          onAccept: () {},
        ),
      );
}

class _Cards extends StatelessWidget {
  const _Cards();

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: context.colors.background,
        body: ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
          EngineExamCard(onOpen: () {}, exam: {'id': 1, 'title': _tr('اختبار الكيمياء — الفصل الثالث', 'Chemistry quiz — unit 3'), 'can_start': true,
            'duration_minutes': 30, 'attempts_used': 0, 'attempts_allowed': 2}),
          AppSpace.gapSm,
          EngineExamCard(onOpen: () {}, offlineSaved: true, exam: {'id': 2, 'title': _tr('اختبار منتصف الفصل', 'Midterm'), 'open_attempt_id': 4,
            'duration_minutes': 60, 'attempts_used': 1, 'attempts_allowed': 1}),
          AppSpace.gapSm,
          EngineExamCard(onOpen: () {}, exam: {'id': 3, 'title': _tr('اختبار قصير ١', 'Quiz 1'), 'can_start': false, 'status': 'closed',
            'attempts_used': 1, 'attempts_allowed': 1, 'results': [{'visible': true, 'percentage': 92, 'passed': true}]}),
        ]),
      );
}

class _Offline extends StatelessWidget {
  const _Offline();

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: context.colors.background,
        body: ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
          OfflineExamCard(title: _tr('اختبار الكيمياء — الفصل الثالث', 'Chemistry quiz — unit 3'), stage: OfflineStage.downloaded, hasKey: true, questions: 12, durationMinutes: 30, onTap: () {}),
          AppSpace.gapSm,
          OfflineExamCard(title: _tr('اختبار منتصف الفصل', 'Midterm'), stage: OfflineStage.waitingToSync, hasKey: true, questions: 20, onTap: () {}),
          AppSpace.gapSm,
          const AppCard(padding: EdgeInsets.all(AppSpace.lg), child: OfflineStepsView(stage: OfflineStage.waitingToSync)),
          AppSpace.gapSm,
          const AppCard(padding: EdgeInsets.all(AppSpace.lg), child: OfflineStepsView(stage: OfflineStage.rejected, code: 'bad_signature')),
        ]),
      );
}

class _Quick extends StatelessWidget {
  const _Quick();

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: context.colors.background,
        body: ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
          QuickStartChooser(onPick: (_) {}, canGenerate: true, onClassic: () {}),
          AppSpace.gapLg,
          QuickQuestionCard(index: 0, question: QuickQuestion.ofType('mcq_single')..prompt = _tr('ما عاصمة مصر؟', 'What is the capital of Egypt?'),
              errors: const [], onChanged: () {}, onRemove: () {}),
          AppSpace.gapSm,
          QuickQuestionCard(index: 1, question: QuickQuestion.ofType('true_false')..prompt = _tr('الماء مركب قطبي.', 'Water is polar.'),
              errors: const ['pick_correct'], onChanged: () {}, onRemove: () {}),
        ]),
      );
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
          final theme = ThemeConfigProvider(api: ApiClient());
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(ThemeConfigScope(
            provider: theme,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: theme.materialTheme(dark: false),
              darkTheme: theme.materialTheme(dark: true),
              themeMode: dark ? ThemeMode.dark : ThemeMode.light,
              builder: (context, w) => Directionality(
                  textDirection: lang == 'ar' ? TextDirection.rtl : TextDirection.ltr,
                  child: DefaultTextStyle.merge(style: TextStyle(fontFamilyFallback: AppFonts.fallback), child: w!)),
              home: RepaintBoundary(key: _shot, child: build()),
            ),
          ));
          for (var i = 0; i < 20; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(tester.takeException(), isNull);
          await expectLater(find.byKey(_shot),
              matchesGoldenFile('goldens/exam_take_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'));
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

void main() {
  setUpAll(() async {
    await _loadFonts();
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    final extra = File('assets/translation_extra/et-s-exam-take.json');
    if (extra.existsSync()) translation.addAll(jsonDecode(extra.readAsStringSync()) as Map<String, dynamic>);
  });

  testWidgets('taking', (t) => _render(t, 'taking', () => const _Taking()));
  testWidgets('taking2', (t) => _render(t, 'taking2', () => const _TakingTf()));
  testWidgets('result', (t) => _render(t, 'result', () => const _Result()));
  testWidgets('result top', (t) => _render(t, 'resulttop', () => const _Result(pct: 95)));
  testWidgets('consent', (t) => _render(t, 'consent', () => const _Consent()));
  testWidgets('cards', (t) => _render(t, 'cards', () => const _Cards()));
  testWidgets('offline', (t) => _render(t, 'offline', () => const _Offline()));
  testWidgets('quick', (t) => _render(t, 'quick', () => const _Quick()));
}
