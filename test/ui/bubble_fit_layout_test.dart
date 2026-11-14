// The bubble-fit panel (D-720 – D-722) at every size and language, and the print sheet's flow: a 409
// question_options_exceed_sheet opens the panel (never the bare error), a trim is confirmed first, then the sheet prints.
// D-724: the teacher's own sheet ends with Download PDF (no dead end). D-725: the alert after a trim names the change.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppPrimaryButton;
import 'package:flutter_education_app/features/exams/exam_engine_api.dart';
import 'package:flutter_education_app/features/exams/paper/exam_setup.dart';
import 'package:flutter_education_app/features/exams/paper/scan/bubble_fit.dart';
import 'package:flutter_education_app/features/exams/paper/scan/bubble_fit_panel.dart';
import 'package:flutter_education_app/features/exams/paper/scan/omr_scan.dart';
import 'package:flutter_education_app/features/exams/paper/scan/omr_sheets_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

import '../org/bubble_fit_test.dart' show fitJson;
import 'layout_harness.dart';

Map<String, dynamic> openFit() {
  final j = fitJson();
  j['items'] = [for (final x in j['items'] as List) <String, dynamic>{...(x as Map<String, dynamic>), 'choice': null}];
  return j;
}

class _Scan extends OmrScanApi {
  int calls = 0;
  @override
  Future<EngineResult> sheetsInfo(int examId) async {
    calls++;
    if (calls == 1) {
      return EngineResult.fail(409, kBubbleFitCode, 'أسئلة بخيارات أكثر من فقاعات الورقة', {'code': kBubbleFitCode, 'question_ids': [14, 15]});
    }
    return EngineResult.ok({'template_id': 4, 'printable': true, 'questions': 5, 'sheet_questions': 100, 'forms': <String>[], 'id_kind': 'shaded',
      'fit': {'ignore': 1, 'written': 0, 'trimmed': 1}});
  }
}

class _Fit extends BubbleFitApi {
  _Fit({this.changes = const []});
  final List<Map<String, dynamic>> changes;
  final puts = <Map<String, dynamic>>[];
  @override
  Future<EngineResult> get(int examId) async => EngineResult.ok(openFit());
  @override
  Future<EngineResult> put(int examId, Map<String, dynamic> body) async {
    puts.add(body);
    final j = openFit();
    j['items'] = [<String, dynamic>{...((j['items'] as List).last as Map<String, dynamic>), 'choice': 'ignore'}];
    j['changes'] = changes;
    return EngineResult.ok(j);
  }
}

class _Setup extends ExamSetupApi {
  @override
  Future<EngineResult> templates({int? orgId}) async => EngineResult.ok({
        'items': [
          {'id': 3, 'version': 1, 'name': 'mcq50_4', 'status': 'published', 'questions': 50, 'options': 4, 'kind': 'bubble'},
          {'id': 4, 'version': 1, 'name': 'mcq100_5', 'status': 'published', 'questions': 100, 'options': 5, 'kind': 'bubble'},
        ],
      });
}

void main() {
  setUp(() => AppConfig.disableList = []);

  testWidgets('the panel: nothing chosen, a trim preview, choices, trimmed, sheets', (tester) async {
    final f = BubbleFit.fromJson(fitJson());
    const sheets = [OmrTemplateItem(id: 4, version: 1, name: 'Bubble sheet · 100 questions · 5 choices (A–E)', questions: 100, options: 5)];
    for (final chosen in [<int, BubbleFitAction>{}, {14: BubbleFitAction.trim, 15: BubbleFitAction.ignore}]) {
      await expectNoLayoutErrors(
          tester,
          () => SingleChildScrollView(
              child: BubbleFitView(fit: f, chosen: chosen, onChoose: (_, _) {}, onAll: (_) {}, onApply: () {}, sheets: sheets, onUseSheet: (_) {}, onOwnSheet: () {}, onRestore: (_) {}, onDone: () {})));
    }
    await expectNoLayoutErrors(
        tester,
        () => SingleChildScrollView(
            child: BubbleFitView(
                fit: BubbleFit.fromJson({...fitJson(), 'locked': true}), chosen: const {}, onChoose: (_, _) {}, onApply: () {}, sheets: const [], error: 'x')));
  });

  testWidgets('the alert body and the own-sheet print options (D-724, D-725)', (tester) async {
    const changes = [
      BubbleFitChange(questionId: 14, number: 5, restored: false, removed: [BubbleFitRemovedOption(id: 'e', index: 4, text: 'All of the above, and a long choice text that wraps')]),
      BubbleFitChange(questionId: 16, number: 12, restored: false, removed: [BubbleFitRemovedOption(id: 'd', index: 3, text: 'Telnet')]),
    ];
    await expectNoLayoutErrors(tester, () => const SingleChildScrollView(child: BubbleFitChangesBody(changes: changes)));
    final info = OmrSheetsInfo.fromJson({'template_id': 9, 'printable': true, 'own_sheet': true, 'template_name': 'ورقة المدرسة 150 سؤال',
      'questions': 15, 'sheet_questions': 150, 'forms': <String>[], 'id_kind': 'shaded', 'modes': ['prefilled', 'named', 'blank']});
    expect((info.ownSheet, info.printable), (true, true));
    expect(info.forms, isEmpty);
    final copies = TextEditingController(text: '30');
    addTearDown(copies.dispose);
    await expectNoLayoutErrors(
        tester,
        () => SingleChildScrollView(
            child: OmrSheetsOptionsView(
                info: info, mode: OmrPrintMode.blank, onMode: (_) {}, forms: const {}, onForm: (_) {}, copiesController: copies,
                students: const SizedBox.shrink(), onDownload: () {}, onShare: () {})));
    await tester.pumpWidget(layoutHost(
        SingleChildScrollView(
            child: OmrSheetsOptionsView(
                info: info, mode: OmrPrintMode.blank, onMode: (_) {}, forms: const {}, onForm: (_) {}, copiesController: copies,
                students: const SizedBox.shrink(), onDownload: () {}, onShare: () {})),
        scale: 1));
    expect(find.byKey(const ValueKey('omr.sheets.own')), findsOneWidget);
    expect(find.byType(AppPrimaryButton), findsOneWidget, reason: 'the panel always ends with Download PDF');
    final dead = OmrSheetsInfo.fromJson({'printable': false, 'own_sheet': true, 'questions': 15, 'sheet_questions': 150});
    await expectNoLayoutErrors(
        tester,
        () => SingleChildScrollView(
            child: OmrSheetsOptionsView(
                info: dead, mode: OmrPrintMode.blank, onMode: (_) {}, forms: const {}, onForm: (_) {}, copiesController: copies,
                students: const SizedBox.shrink(), onDownload: () {}, onShare: () {})));
  });

  testWidgets('a trim: confirmed, sent, then the alert names the change and asks to reprint', (tester) async {
    AppConfig.lang = 'en';
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 1600);
    addTearDown(tester.view.resetPhysicalSize);
    final fit = _Fit(changes: [
      {'question_id': 14, 'n': 5, 'action': 'trim', 'removed_options': [{'id': 'd', 'index': 3, 'text': 'opt 3'}]},
    ]);
    var resolved = 0;
    await tester.pumpWidget(layoutHost(SingleChildScrollView(child: BubbleFitSection(examId: 7, api: fit, setupApi: _Setup(), onResolved: () => resolved++)), scale: 1));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.byKey(const ValueKey('fit.q.14.trim')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('fit.q.15.ignore')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('fit.apply')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove them'));
    await tester.pumpAndSettle();
    expect(fit.puts.single, {'questions': {'14': 'trim', '15': 'ignore'}});
    expect(find.text('The question paper was updated'), findsOneWidget);
    expect(find.text('Question 5: removed choice D “opt 3”'), findsOneWidget);
    expect(find.byKey(const ValueKey('fit.change.reprint')), findsOneWidget);
    expect(resolved, 0, reason: 'the alert is read first');
    await tester.tap(find.byKey(const ValueKey('fit.change.ok')));
    await tester.pumpAndSettle();
    expect(find.text('The question paper was updated'), findsNothing);
    expect(resolved, 1);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('print sheet: 409 opens the panel, apply sends the choice, then the options come back', (tester) async {
    AppConfig.lang = 'en';
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 1600);
    addTearDown(tester.view.resetPhysicalSize);
    final scan = _Scan();
    final fit = _Fit();
    await tester.pumpWidget(layoutHost(SingleChildScrollView(child: OmrSheetsSheet(examId: 7, api: scan, fitApi: fit, setupApi: _Setup())), scale: 1));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Leave off the sheet'), findsWidgets);
    expect(find.textContaining('more choices than this sheet has bubbles'), findsOneWidget);
    expect(find.byKey(const ValueKey('fit.sheet.4')), findsOneWidget, reason: 'the 5-choice sheet is offered');
    expect(find.byKey(const ValueKey('fit.q.15.trim')), findsNothing, reason: 'a question whose correct answers fill the sheet cannot be trimmed');
    await tester.tap(find.byKey(const ValueKey('fit.q.14.ignore')));
    await tester.pump();
    expect(find.textContaining('enter its mark yourself'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('fit.q.15.ignore')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('fit.apply')));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(fit.puts.single, {'questions': {'14': 'ignore', '15': 'ignore'}});
    expect(scan.calls, 2, reason: 'every question has its way: the sheet reloads');
    expect(find.byKey(const ValueKey('omr.sheets.fit.change')), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });
}
