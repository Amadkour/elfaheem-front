// The bubble-fit panel (D-720 – D-722) at every size and language, and the print sheet's flow: a 409
// question_options_exceed_sheet opens the panel (never the bare error), a trim is confirmed first, then the sheet prints.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_engine_api.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/exam_setup.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/bubble_fit.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/bubble_fit_panel.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_scan.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_sheets_sheet.dart';
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
  final puts = <Map<String, dynamic>>[];
  @override
  Future<EngineResult> get(int examId) async => EngineResult.ok(openFit());
  @override
  Future<EngineResult> put(int examId, Map<String, dynamic> body) async {
    puts.add(body);
    final j = openFit();
    j['items'] = [<String, dynamic>{...((j['items'] as List).last as Map<String, dynamic>), 'choice': 'ignore'}];
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
