// VISUAL review renders (not a CI suite): the Exam Hub (D-356) in the Warm Editorial theme — the hub page, its flows,
// plus the "before you go on" sheets — at 390x844 and 1440x900, ar / en, light / dark, into
// test/visual/goldens/exam_hub_*.png. Compared by eye.
//
//   flutter test test/visual/exam_hub_editorial_golden_test.dart --update-goldens [--plain-name creation]
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
import 'package:flutter_education_app/features/exams/exam_all.dart';
import 'package:flutter_education_app/features/exams/hub/exam_hub_screen.dart';
import 'package:flutter_education_app/features/exams/hub/hub_widgets.dart';
import 'package:flutter_education_app/features/exams/hub/create/exam_create_parts.dart';
import 'package:flutter_education_app/features/exams/hub/correct/exam_correct_flow.dart';
import 'package:flutter_education_app/features/exams/paper/scan/omr_scan.dart' show OmrBatchProgress;
import 'package:flutter_education_app/features/exams/marks/mark_sessions_api.dart';
import 'package:flutter_education_app/features/exams/marks/review/grade_review_rows.dart';
import 'package:flutter_education_app/features/exams/hub/result/exam_get_result_screen.dart';
import 'package:flutter_education_app/features/exams/hub/result/exam_result_data.dart';
import 'package:flutter_education_app/features/exams/hub/deliver/exam_deliver_screen.dart' show DeliverPreviewPane;
import 'package:flutter_education_app/features/exams/hub/revision/revision_models.dart';
import 'package:flutter_education_app/features/exams/hub/revision/revision_result_panel.dart';
import 'package:flutter_education_app/features/exams/marks/mark_templates_api.dart';
import 'package:flutter_education_app/features/exams/marks/templates/mark_template_library.dart';
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

AllExam _e(int id, String title, {String status = 'closed', Map<String, dynamic>? g, int? course = 10, Map<String, dynamic>? settings, String? ends, String type = 'online', int q = 12, int attempts = 30}) => AllExam({
      'id': id,
      'title': title,
      'status': status,
      'course_id': course,
      'org_id': null,
      'type': type,
      'settings': settings,
      'ends_at': ends,
      'starts_at': '2026-11-03T09:00:00',
      'duration_minutes': 45,
      'question_count': q,
      'attempts': {'total': attempts},
      'grading': ?g,
    });

const _paper = {'mode': 'offline'};

AllExamsData _data() {
  final ar = AppConfig.lang == 'ar';
  String x(String a, String e) => ar ? a : e;
  return AllExamsData(exams: [
    _e(1, x('اختبار الوحدة الرابعة: الدوال', 'Unit 4 check: functions'), status: 'draft', q: 8, g: _g(state: 'not_applicable', ended: false)),
    _e(2, x('امتحان منتصف الفصل الورقي', 'Midterm paper exam'), g: _g(submitted: 3, papers: 3), settings: _paper, type: 'paper'),
    _e(3, x('اختبار الأسبوع السادس', 'Week 6 quiz'), g: _g(state: 'in_progress', papers: 40, review: 3, answers: 2, submitted: 38, degrees: true, source: 'exam'), settings: _paper, type: 'paper'),
    _e(4, x('مراجعة الفصل الثالث', 'Chapter 3 review'), g: _g(state: 'corrected', submitted: 30, degrees: true, source: 'exam')),
    _e(5, x('اختبار نهاية الفصل الدراسي الأول في الرياضيات للصف الثاني الثانوي', 'End of term exam in mathematics for the second year of secondary school'),
        status: 'published', g: _g(ended: false, state: 'waiting'), ends: '2026-12-01T10:00:00'),
    _e(6, x('تمرين سريع على المتتابعات', 'Quick drill on sequences'), g: _g(state: 'waiting')),
    _e(7, x('اختبار قصير في الهندسة', 'Short geometry quiz'), g: _g(state: 'corrected', degrees: true, source: 'import', published: true), course: null),
    _e(8, x('اختبار تجريبي قديم', 'Old trial exam'), status: 'archived', g: _g(state: 'not_applicable')),
  ], courseNames: {10: x('الرياضيات للصف الثاني الثانوي', 'Mathematics, second secondary')}, orgNames: const {});
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

Future<void> _render(WidgetTester tester, String name, Widget Function() build, {Future<void> Function(WidgetTester)? act, List<Size> sizes = const [Size(390, 844), Size(1440, 900)]}) async {
  final prevLang = AppConfig.lang;
  debugDisableShadows = false;
  final fake = FakeApi(const {}, latency: const Duration(milliseconds: 5))..install();
  try {
    for (final size in sizes) {
      for (final lang in const ['ar', 'en']) {
        for (final dark in const [false, true]) {
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
          await expectLater(find.byKey(_shot), matchesGoldenFile('goldens/exam_hub_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'));
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


class _Sheet extends StatelessWidget {
  const _Sheet({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Material(
              color: context.colors.cardBg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
              child: AppSheetContent(title: title, children: [child]),
            ),
          ),
        ),
      );
}

void main() {
  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    // the sidecar strings this branch adds (folded into translation.json at merge)
    for (final f in Directory('assets/translation_extra').listSync().whereType<File>()) {
      translation.addAll(jsonDecode(f.readAsStringSync()) as Map<String, dynamic>);
    }
    await _loadFonts();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    AppConfig.disableList = [];
  });

  // the hub page itself (D-700 – D-703) renders in exam_hub_simple_golden_test.dart, every stage and the exam page
  testWidgets('hub', (t0) => _render(t0, 'hub', () => ExamHubScreen(loader: () async => _data())));
  resultScenes();
  marksScenes();
  correctScenes();
  createScenes();
  leftoverScenes();
  testWidgets('sheets', (t0) => _render(t0, 'sheets', sizes: const [Size(390, 844)], () => Builder(
      builder: (context) => _Sheet(
            title: AppConfig.lang == 'ar' ? 'لا درجات لهذا الاختبار بعد' : 'This exam has no degrees yet',
            child: HubNoDegreesBody(canImport: true, importRecommended: true, noCourse: false, onImport: () {}, onCorrect: () {}),
          ))));
}

ResultsBoard _board({bool partial = true}) {
  Map<String, dynamic> a(int id, int student, String state, {double? score, bool? passed}) => {
        'id': id, 'student_id': student, 'state': state, 'score': score, 'max_score': 20,
        'percentage': score == null ? null : score * 5, 'passed': passed, 'needs_review': false,
      };
  final ar = AppConfig.lang == 'ar';
  const arNames = ['سارة أحمد', 'عمر خالد', 'ليلى محمود', 'يوسف إبراهيم', 'مريم حسن', 'عبد الرحمن الشافعي', 'نور علي', 'كريم سامي', 'هدى فؤاد', 'أحمد ناصر', 'سلمى رشدي', 'ياسين عادل'];
  const enNames = ['Sara Ahmed', 'Omar Khaled', 'Laila Mahmoud', 'Youssef Ibrahim', 'Mariam Hassan', 'Abdelrahman El-Shafei', 'Nour Ali', 'Karim Samy', 'Hoda Fouad', 'Ahmed Nasser', 'Salma Roshdy', 'Yassin Adel'];
  const scores = [18.0, 8.0, 15.5, 12.0, 19.0, 9.5, 16.0, 13.0, 17.0, 6.0, 14.0, 11.0];
  return ResultsBoard.fromSources(
    exam: {
      'id': 9, 'title': 'Physics midterm', 'course_id': 7, 'status': 'closed', 'results_policy': 'when_published',
      'results_published_at': null, 'anonymous_grading': false, 'settings': const {}, 'max_score': 20,
      'sections': [
        {
          'title': 'A', 'mode': 'online',
          'questions': [
            {'id': 100, 'type': 'mcq', 'points': 10, 'body': {'prompt': ar ? 'ما تعريف القوة؟' : 'What is force?'}},
            {'id': 101, 'type': 'mcq', 'points': 10, 'body': {'prompt': ar ? 'ما الفرق بين الكتلة والوزن؟' : 'What is the difference between mass and weight?'}},
          ],
        },
      ],
    },
    attempts: {
      'items': [
        for (var i = 0; i < 12; i++)
          partial && i == 3 ? a(i + 1, 100 + i, 'submitted') : a(i + 1, 100 + i, 'graded', score: scores[i], passed: scores[i] >= 10),
      ],
    },
    names: {for (var i = 0; i < 12; i++) 100 + i: (ar ? arNames : enNames)[i]},
    analytics: {
      'state': 'ready',
      'data': {
        'items': [
          {'question_id': 101, 'answered': 12, 'difficulty': 0.35, 'points': 10},
          {'question_id': 100, 'answered': 12, 'difficulty': 0.62, 'points': 10},
        ],
      },
    },
    hubServer: true,
  );
}

class _ResultHost extends StatelessWidget {
  const _ResultHost({this.partial = true});
  final bool partial;

  @override
  Widget build(BuildContext context) {
    final board = _board(partial: partial);
    return Scaffold(
      appBar: AppHeader(title: AppConfig.lang == 'ar' ? 'امتحان الفيزياء النصفي' : 'Physics midterm'),
      body: LayoutBuilder(builder: (context, box) {
        final pad = AppSpace.gutter(box.maxWidth);
        return ListView(padding: EdgeInsets.fromLTRB(pad, AppSpace.md, pad, AppSpace.xl), children: [
          ResultBoardView(board: board, wide: box.maxWidth >= 1024, columnLabel: null, callbacks: ResultBoardCallbacks(onExport: () {}, onStudio: () {}, onImport: () {}, onScans: () {}, onAnswers: () {}, onPublish: () {}, onDataLab: () {})),
        ]);
      }),
    );
  }
}

Future<void> _scrollDown(WidgetTester t) async {
  final s = find.byType(Scrollable);
  if (s.evaluate().isEmpty) return;
  final state = t.state<ScrollableState>(s.first);
  state.position.jumpTo(state.position.maxScrollExtent * 0.55);
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void resultScenes() {
  testWidgets('result', (t0) => _render(t0, 'result', () => const _ResultHost()));
  testWidgets('result_done', (t0) => _render(t0, 'result_done', () => const _ResultHost(partial: false), act: _scrollDown));
}

const _session = MarkSession(id: 7, courseId: 3, mode: MarkMode.import, columnKey: 'midterm', columnMax: 20, paperMax: 50, roundingStep: 0.5, counts: MarkCounts(match: 3, mismatch: 4, unreadable: 2, pending: 5));

MarkRow _markRow({int id = 1, bool student = true, List<String> issues = const ['scaled'], String status = 'open', double? recorded = 14, double diff = 2}) => MarkRow(
      id: id,
      studentId: student ? 11 : null,
      studentName: student ? (AppConfig.lang == 'ar' ? 'سارة علي الشريف' : 'Sara Ali Al-Sherif') : null,
      identifierMasked: '2024***17',
      identifierMethod: 'qr',
      marks: const [
        MarkPart(fieldId: 'q1', questionNo: '1', value: 20, conf: .97, max: 25),
        MarkPart(fieldId: 'q2', questionNo: '2', value: 20, conf: .9, max: 25),
        MarkPart(fieldId: 'q3', questionNo: '3', status: 'unreadable', max: 10),
      ],
      written: 40,
      computed: 40,
      used: 40,
      scaled: 16,
      recorded: recorded,
      diff: diff,
      issues: issues,
      status: status,
    );

class _MarksHost extends StatelessWidget {
  const _MarksHost();

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final list = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      GradeRowTile(row: _markRow(diff: 0, recorded: 16), list: MarkList.match),
      AppSpace.gapXs,
      GradeRowTile(row: _markRow(id: 2), list: MarkList.mismatch, selected: true),
      AppSpace.gapXs,
      GradeRowTile(row: _markRow(id: 3, student: false, issues: const ['unknown_student']), list: MarkList.unreadable),
      AppSpace.gapXs,
      GradeRowTile(row: _markRow(id: 4, status: 'applied'), list: MarkList.mismatch),
    ]);
    final detail = GradeRowDetail(row: _markRow(id: 2), session: _session, onApply: () {}, onKeep: () {}, onDismiss: () {}, onFix: (_) {});
    final apply = Material(
      color: context.colors.cardBg,
      borderRadius: AppRadius.cardAll,
      child: Padding(padding: const EdgeInsets.all(AppSpace.lg), child: GradeApplySheet(row: _markRow(id: 2), columnLabel: 'Midterm', onConfirm: (_) {})),
    );
    return Scaffold(
      appBar: AppHeader(title: AppConfig.lang == 'ar' ? 'مراجعة الدرجات' : 'Review grades'),
      body: ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
        if (wide)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: list),
            AppSpace.gapLg,
            Expanded(child: detail),
            AppSpace.gapLg,
            Expanded(child: apply),
          ])
        else ...[list, AppSpace.gapLg, detail, AppSpace.gapLg, apply],
      ]),
    );
  }
}

void marksScenes() {
  testWidgets('marks', (t0) => _render(t0, 'marks', () => const _MarksHost()));
}

void correctScenes() {
  testWidgets('correct', (t0) => _render(t0, 'correct', () {
        final ar = AppConfig.lang == 'ar';
        final b = OmrBatchProgress.fromJson({'batch_id': 1, 'kind': 'camera', 'total': 40, 'done': 30, 'graded': 28, 'review': 2, 'rejected': 1, 'pending': 10, 'status': 'processing', 'en': '30 of 40 papers processed', 'ar': 'تمت معالجة 30 من 40 ورقة'});
        final p = OmrBatchProgress.fromJson({'batch_id': 2, 'kind': 'pdf', 'total': 12, 'done': 12, 'graded': 12, 'review': 0, 'rejected': 0, 'pending': 0, 'status': 'done', 'en': '12 of 12 papers processed', 'ar': 'تمت معالجة 12 من 12 ورقة'});
        return Scaffold(
          appBar: AppHeader(title: ar ? 'تصحيح الاختبار' : 'Correct the exam'),
          body: CorrectionStartView(title: ar ? 'امتحان منتصف الفصل الورقي' : 'Midterm paper exam', batches: [b, p], onImport: () {}, onScan: () {}, onResume: () {}, onBatch: (_) {}, onReview: () {}, onResults: () {}),
        );
      }));
}

Widget _createShell() {
  final ar = AppConfig.lang == 'ar';
  String x(String a, String e) => ar ? a : e;
  CreateSummaryItem item(String l, String? v, CreateItemState s) => CreateSummaryItem(label: l, value: v, state: s, onTap: () {});
  return Scaffold(
    body: ExamCreateShell(
      stepKey: 'x',
      items: [
        item(x('المكان', 'Where'), x('الرياضيات للصف الثاني الثانوي', 'Mathematics, second secondary'), CreateItemState.done),
        item(x('النوع', 'Type'), x('اختبار عادي', 'Normal exam'), CreateItemState.done),
        item(x('الأسئلة', 'Questions'), null, CreateItemState.current),
        item(x('النشر', 'Publish'), null, CreateItemState.todo),
        item(x('الطلاب', 'Students'), null, CreateItemState.todo),
      ],
      index: 2,
      stepLabel: x('الأسئلة', 'Questions'),
      title: x('من أين تأتي الأسئلة؟', 'Where do the questions come from?'),
      subtitle: x('اختر طريقة، ويمكنك التعديل قبل النشر.', 'Choose a way; you can edit them before publishing.'),
      body: CreateQuestionWayBody(onPick: (_) {}, hasCourse: true, canGenerate: true, canImportForms: true, bubble: false),
      primaryLabel: x('متابعة', 'Continue'),
      onPrimary: () {},
      backLabel: x('رجوع', 'Back'),
      onBack: () {},
      onClose: () {},
      estimate: [(x('الأسئلة', 'Questions'), '12'), (x('مجموع الدرجات', 'Total marks'), '40')],
    ),
  );
}

void createScenes() {
  testWidgets('create', (t0) => _render(t0, 'create', _createShell));
  testWidgets('create_done', (t0) => _render(t0, 'create_done', () {
        final ar = AppConfig.lang == 'ar';
        return Scaffold(
          body: CreateDoneBody(
            title: ar ? 'اختبار الوحدة الرابعة' : 'Unit 4 check',
            place: ar ? 'الرياضيات للصف الثاني الثانوي' : 'Mathematics, second secondary',
            lines: [(ar ? 'يفتح' : 'Opens', '3 Nov 2026 · 9:00 AM'), (ar ? 'المدة' : 'Duration', ar ? '45 دقيقة' : '45 min'), (ar ? 'الأسئلة' : 'Questions', '12')],
            onDone: () {},
            onOpen: () {},
            onFollow: () {},
            onShare: () {},
          ),
        );
      }));
}

void leftoverScenes() {
  final session = MarkSession.fromJson({
    'session': {'id': 7, 'course_id': 3, 'template_id': 2, 'mode': 'review', 'column_key': 'midterm', 'column_max': 20, 'paper_max': 20, 'status': 'open'},
    'counts': {'match': 0, 'mismatch': 0, 'unreadable': 0, 'pending': 0, 'applied': 0, 'kept': 0},
  });
  final row = RevisionRow.fromJson({
    'id': 1,
    'page_id': 101,
    'student': {'id': 11, 'name': 'Sara Ali'},
    'identifier': {'value_masked': '2024***17', 'method': 'digits', 'conf': 0.99},
    'marks': [
      {'field_id': 'q1', 'question_no': 1, 'value': 8, 'conf': 0.97, 'max': 10, 'status': 'ok', 'crop_url': null},
      {'field_id': 'q2', 'question_no': 2, 'value': 8, 'conf': 0.91, 'max': 10, 'status': 'ok', 'crop_url': null},
    ],
    'paper_total_written': 16,
    'paper_total_computed': 16,
    'paper_total_used': 16,
    'scaled': 16,
    'recorded': 14,
    'diff': 2,
    'issues': const <String>[],
    'list': 'mismatch',
    'status': 'open',
  });
  testWidgets('revision_panel', (t0) => _render(t0, 'revision_panel', () => RevisionResultPanel(row: row, session: session, behind: 2, onUpdate: () {}, onIgnore: () {}, onRetake: () {}, onLater: () {})));
  testWidgets('deliver_preview', (t0) => _render(t0, 'deliver_preview', () => const Scaffold(body: SingleChildScrollView(padding: EdgeInsets.all(AppSpace.md), child: DeliverPreviewPane(pages: null, busy: false, studentName: 'Sara Ali', studentCount: 31, versions: ['A', 'B'], version: 'A')))));
  testWidgets('mark_template_card', (t0) => _render(t0, 'mark_template_card', sizes: const [Size(390, 844)], () => Scaffold(
        body: ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
          for (final k in const ['answer_table', 'mark_sheet', 'cover'])
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: MarkTemplateCard(item: MarkTemplate.fromJson({'id': 7, 'family_id': 'f', 'version': 2, 'name': 'Midterm $k', 'kind': k, 'fields_count': 12, 'total_max': 20, 'owner_name': 'Sara', 'updated_at': '2026-11-01T10:00:00', 'has_image': true}), onTap: () {}, onDelete: () {}),
            ),
        ]),
      )));
}
