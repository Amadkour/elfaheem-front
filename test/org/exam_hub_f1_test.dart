// The Exam Hub's list side (D-350): the `grading` flags, what a tap does, the smart header, the degrees import's
// parsing, and every presentational piece under the layout harness.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppButton;
import 'package:flutter_education_app/features/shared/exam_engine/exam_all.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_engine_api.dart' show EngineResult;
import 'package:flutter_education_app/features/shared/exam_engine/hub/exam_hub_screen.dart';
import 'package:flutter_education_app/features/shared/exam_engine/hub/hub_degrees_import.dart';
import 'package:flutter_education_app/features/shared/exam_engine/hub/hub_degrees_import_sheet.dart';
import 'package:flutter_education_app/features/shared/exam_engine/hub/hub_entry.dart';
import 'package:flutter_education_app/features/shared/exam_engine/hub/hub_logic.dart';
import 'package:flutter_education_app/features/shared/exam_engine/hub/hub_widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../ui/layout_harness.dart';

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

AllExam _e(int id, {String status = 'closed', Map<String, dynamic>? g, int? course = 10, String title = 'Exam', Map<String, dynamic>? settings, String? policy, String? ends}) => AllExam({
      'id': id,
      'title': '$title $id',
      'status': status,
      'course_id': course,
      'org_id': null,
      'settings': settings,
      'ends_at': ends,
      'question_count': 12,
      'attempts': {'total': 30},
      'results_policy': policy,
      'grading': ?g,
    });

const _paper = {'mode': 'offline'};

AllExamsData _data() => AllExamsData(exams: [
      _e(1, status: 'draft', g: _g(state: 'not_applicable', ended: false)),
      _e(2, g: _g(submitted: 3, papers: 3), settings: _paper),
      _e(3, g: _g(state: 'in_progress', papers: 40, review: 3, answers: 2, submitted: 38, degrees: true, source: 'exam'), settings: _paper),
      _e(4, g: _g(state: 'corrected', submitted: 30, degrees: true, source: 'exam')),
      _e(5, status: 'published', g: _g(ended: false, state: 'waiting'), ends: '2026-12-01T10:00:00', title: 'A very long title of an exam that keeps going well past the width of a phone screen'),
      _e(6, g: _g(state: 'waiting')),
      _e(7, g: _g(state: 'corrected', degrees: true, source: 'import', published: true), course: null),
      _e(8, status: 'archived', g: _g(state: 'not_applicable')),
    ], courseNames: const {10: 'Mathematics for the second year of secondary school'}, orgNames: const {});

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
  });
  setUp(() {
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
  });

  group('grading parsing', () {
    test('reads the block and survives a server without it', () {
      final g = _e(3, g: _g(state: 'in_progress', papers: 40, degrees: true, source: 'exam')).grading!;
      expect((g.state, g.papers, g.hasDegrees, g.degreesSource), ('in_progress', 40, true, 'exam'));
      expect(_e(9).grading, isNull);
    });
  });

  group('flags', () {
    test('correction flag of each state', () {
      expect(hubCorrectionOf(_e(1, status: 'draft', g: _g(state: 'not_applicable'))), isNull);
      expect(hubCorrectionOf(_e(2, g: _g())), HubCorrection.notCorrected);
      expect(hubCorrectionOf(_e(3, g: _g(state: 'in_progress'))), HubCorrection.inProgress);
      expect(hubCorrectionOf(_e(4, g: _g(state: 'corrected'))), HubCorrection.corrected);
      expect(hubCorrectionOf(_e(5, status: 'published', g: _g(ended: false))), HubCorrection.notEnded);
      expect(hubCorrectionOf(_e(9)), isNull, reason: 'no grading: no flag');
    });
    test('scanned early follows the work; online answers during the sitting do not', () {
      expect(hubCorrectionOf(_e(1, status: 'published', g: _g(ended: false, state: 'in_progress', papers: 5))), HubCorrection.inProgress);
      expect(hubCorrectionOf(_e(1, status: 'published', g: _g(ended: false, state: 'in_progress', answers: 5))), HubCorrection.notEnded);
    });
    test('an online exam nobody sat needs nothing; a paper exam with no scans does', () {
      expect(hubNeedsCorrection(_e(1, g: _g())), isFalse);
      expect(hubNeedsCorrection(_e(1, g: _g(), settings: _paper)), isTrue);
      expect(hubNeedsCorrection(_e(1, g: _g(submitted: 2))), isTrue);
    });
    test('an after-submit exam has nothing to publish', () {
      expect(hubUnpublished(_e(1, g: _g(state: 'corrected', degrees: true))), isTrue);
      expect(hubUnpublished(_e(1, g: _g(state: 'corrected', degrees: true), policy: 'after_submit')), isFalse);
      expect(hubUnpublished(_e(1, g: _g(state: 'corrected', degrees: true, published: true))), isFalse);
    });
  });

  group('lists', () {
    test('correction leaves drafts and the archive out, waiting first', () {
      final ids = [for (final e in hubCorrectionList(_data())) e.id];
      expect(ids, isNot(contains(1)));
      expect(ids, isNot(contains(8)));
      expect(ids.first, 2);
      expect(ids.last, anyOf(4, 7));
      expect([for (final e in hubCorrectionList(_data(), only: HubCorrection.inProgress)) e.id], [3]);
    });
    test('results chips', () {
      List<int> ids(HubResultsFilter? f) => [for (final e in hubResultsList(_data(), only: f)) e.id]..sort();
      expect(ids(HubResultsFilter.hasDegrees), [3, 4, 7]);
      expect(ids(HubResultsFilter.noDegrees), [2, 5, 6]);
      expect(ids(HubResultsFilter.unpublished), [3, 4]);
    });
    test('search reaches the course name', () {
      expect(hubCorrectionList(_data(), query: 'mathematics second').length, 5);
      expect(hubCorrectionList(_data(), query: 'zzz'), isEmpty);
    });
    test('an organization scope keeps only its exams', () {
      final d = AllExamsData(exams: [AllExam({'id': 1, 'org_id': 5}), AllExam({'id': 2, 'org_id': 6})]);
      expect([for (final e in hubScoped(d, 5).exams) e.id], [1]);
      expect(identical(hubScoped(d, null), d), isTrue);
    });
  });

  group('smart header', () {
    test('counts, most urgent first', () {
      final a = hubAttention(_data());
      expect([for (final x in a) x.kind], [HubAttentionKind.toCorrect, HubAttentionKind.inCorrection, HubAttentionKind.unpublished, HubAttentionKind.drafts]);
      expect(a.first.count, 1);
      expect(hubAttentionText(const HubAttention(HubAttentionKind.toCorrect, 3)), '3 exams waiting to be corrected');
      AppConfig.lang = 'ar';
      expect(hubAttentionText(const HubAttention(HubAttentionKind.unpublished, 2)), 'نتيجتان لم تُنشرا');
    });
    test('a server without grading shows none', () {
      expect(hubAttention(AllExamsData(exams: [_e(1), _e(2, status: 'draft')])), isEmpty);
      expect(hubHasFlags(AllExamsData(exams: [_e(1)])), isFalse);
    });
  });

  group('what a tap does', () {
    test('creation', () {
      expect(hubMainAction(_e(1, status: 'draft'), HubSurface.creation), HubAction.edit);
      expect(hubMainAction(_e(1, status: 'published'), HubSurface.creation), HubAction.deliver);
      expect(hubMainAction(_e(1, status: 'closed'), HubSurface.creation), HubAction.results);
      expect(hubMoreActions(_e(1, status: 'draft'), HubSurface.creation), containsAll([HubAction.publish, HubAction.paper]));
      expect(hubMoreActions(_e(1, status: 'published'), HubSurface.creation), containsAll([HubAction.edit, HubAction.results, HubAction.paper]));
      expect(hubMoreActions(_e(1, status: 'closed', settings: {'paper_file': {'name': 'a.pdf'}}), HubSurface.creation), isNot(contains(HubAction.paper)));
    });
    test('correction and results', () {
      expect(hubMainAction(_e(1, g: _g(state: 'corrected', degrees: true)), HubSurface.correction), HubAction.getResult);
      expect(hubMainAction(_e(1, g: _g()), HubSurface.correction), HubAction.correct);
      expect(hubMainAction(_e(1, status: 'published', g: _g(ended: false)), HubSurface.correction), HubAction.correct);
      expect(hubMainAction(_e(1), HubSurface.correction), HubAction.correct, reason: 'no flags: straight to the flow');
      expect(hubMainAction(_e(1, g: _g(degrees: true)), HubSurface.results), HubAction.getResult);
      expect(hubMainAction(_e(1, g: _g()), HubSurface.results), HubAction.addDegrees);
      expect(hubMainAction(_e(1), HubSurface.results), HubAction.getResult);
    });
    test('revision needs a course, and its switch on; Excel too', () {
      expect(hubMoreActions(_e(1, g: _g(degrees: true)), HubSurface.results), contains(HubAction.revision));
      expect(hubMoreActions(_e(1, g: _g(degrees: true), course: null), HubSurface.results), isNot(contains(HubAction.revision)));
      expect(hubCanImport(_e(1, course: null)), isFalse);
      AppConfig.disableList = ['exam.grade_review', 'exam.results.import'];
      expect(hubMoreActions(_e(1, g: _g(degrees: true)), HubSurface.results), isNot(contains(HubAction.revision)));
      expect(hubCanImport(_e(1)), isFalse);
    });
    test('Excel is the suggestion only while there is nothing to correct', () {
      expect(hubImportRecommended(_e(1, g: _g())), isTrue);
      expect(hubImportRecommended(_e(1, g: _g(papers: 4))), isFalse);
      expect(hubImportRecommended(_e(1, g: _g(), course: null)), isFalse);
    });
  });

  test('who teaches in an organization', () {
    expect(examHubTeachesInAnyOrg([{'roles': ['student']}]), isFalse);
    expect(examHubTeachesInAnyOrg([{'roles': ['student']}, {'roles': ['teacher']}]), isTrue);
    expect(examHubTeachesInAnyOrg([{'roles': ['teacher_assistant']}]), isTrue);
    expect(examHubTeachesInAnyOrg(const []), isFalse);
    expect(examHubTeachingRole('admin_assistant'), isFalse);
  });

  testWidgets('a flow that replaced itself refreshes on the real return', (tester) async {
    final nav = GlobalKey<NavigatorState>();
    late BuildContext home;
    await tester.pumpWidget(MaterialApp(navigatorKey: nav, home: Builder(builder: (c) {
      home = c;
      return const Text('home');
    })));
    var reloads = 0;
    final pushed = nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Text('wizard')));
    await tester.pumpAndSettle();
    nav.currentState!.pushReplacement(MaterialPageRoute<void>(builder: (_) => const Text('run')));
    await tester.pumpAndSettle();
    await pushed; // finished, with the teacher still away
    whenBackOn(home, () => reloads++);
    expect(reloads, 0);
    nav.currentState!.pop();
    await tester.pumpAndSettle();
    expect(reloads, 1);
  });

  testWidgets('the full mark re-checks the rows, and only the newest answer counts', (tester) async {
    AppConfig.lang = 'en';
    final api = _HeldDegrees();
    final theme = ThemeConfigProvider(api: ApiClient());
    await tester.pumpWidget(ThemeConfigScope(provider: theme, child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: HubDegreesImportSheet(examId: 1, title: 'T', api: api, initialFileName: 'a.xlsx', initialBytes: Uint8List(1)))))));
    await tester.pump();
    expect(api.asked, [null]);
    api.answer(0, matched: 5, max: 20);
    await tester.pump();
    expect(find.text('Save 5 degrees'), findsOneWidget);
    AppButton save() => tester.widget<AppButton>(find.byKey(const ValueKey('exam.hub.degrees.save')));
    expect(save().onPressed, isNotNull);

    await tester.enterText(find.byType(TextField), '30');
    await tester.pump();
    expect(save().onPressed, isNull, reason: 'the rows on screen were checked against 20');
    await tester.pump(const Duration(milliseconds: 500));
    expect(api.asked, [null, 30.0]);

    await tester.enterText(find.byType(TextField), '40');
    await tester.pump(const Duration(milliseconds: 500));
    expect(api.asked, [null, 30.0, 40.0]);
    api.answer(1, matched: 9, max: 30); // late, about a mark no longer in the field
    await tester.pump();
    await tester.pump();
    expect(find.text('Save 9 degrees'), findsNothing);
    api.answer(2, matched: 7, max: 40);
    await tester.pump();
    await tester.pump();
    expect(find.text('Save 7 degrees'), findsOneWidget);
    expect(save().onPressed, isNotNull);
  });

  group('degrees import', () {
    test('preview parsing', () {
      final p = DegreesPreview.fromJson({
        'columns': ['Name', 'Degree'],
        'match_column': 'Name',
        'degree_column': 'Degree',
        'max_score': 20,
        'rows': 3,
        'matched': 2,
        'unmatched': [{'row': 4, 'value': 'Zed'}],
        'invalid': [{'row': 3, 'value': 'x', 'reason': 'not_a_number'}],
        'import_key': 'k',
      });
      expect((p.matched, p.maxScore, p.needsColumns, p.canSave), (2, 20.0, false, true));
      expect(p.unmatched.single.value, 'Zed');
      expect(degreeReasonText(p.invalid.single.reason), 'The degree is not a number');
      expect(degreesHeadline(p), '2 of 3 rows are ready to save');
      expect(DegreesPreview.fromJson({'columns': ['A'], 'rows': 2}).needsColumns, isTrue);
      expect(DegreesPreview.fromJson({'rows': 2, 'matched': 0, 'import_key': 'k'}).canSave, isFalse);
    });
    test('full mark', () {
      expect(parseFullMark('٢٠'), 20);
      expect(parseFullMark(' 12.5 '), 12.5);
      expect(parseFullMark('12,5'), 12.5);
      expect(parseFullMark('0'), isNull);
      expect(parseFullMark('abc'), isNull);
      expect(fullMarkText(20), '20');
      expect(fullMarkText(12.5), '12.5');
    });
  });

  group('layout', () {
    ExamHubBody body({required int tab, HubSurface segment = HubSurface.correction, AllExamsData? d}) => ExamHubBody(
          data: d,
          tab: tab,
          segment: segment,
          filter: const AllExamsFilter(),
          onFilter: (_) {},
          onSegment: (_) {},
          onCorrectionFilter: (_) {},
          onResultsFilter: (_) {},
          onAttention: (_) {},
          onAction: (_, _) {},
          onRetry: () {},
          onNew: () {},
          onStartRevision: () {},
          onRefresh: () async {},
        );
    testWidgets('creation', (t) => expectNoLayoutErrors(t, () => body(tab: 0, d: _data())));
    testWidgets('correction', (t) => expectNoLayoutErrors(t, () => body(tab: 1, d: _data())));
    testWidgets('results', (t) => expectNoLayoutErrors(t, () => body(tab: 1, segment: HubSurface.results, d: _data())));
    testWidgets('loading, empty, no flags', (t) async {
      await expectNoLayoutErrors(t, () => body(tab: 0));
      await expectNoLayoutErrors(t, () => body(tab: 1, d: const AllExamsData(exams: [])));
      await expectNoLayoutErrors(t, () => body(tab: 1, d: AllExamsData(exams: [_e(1), _e(2, status: 'published')])));
      await expectNoLayoutErrors(t, () => body(tab: 1, segment: HubSurface.results, d: AllExamsData(exams: [_e(1)])));
    });
    testWidgets('sheets', (t) async {
      // the bodies sit in AppSheetContent, which scrolls them
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: HubNotEndedBody(text: hubNotEndedText(_e(5, status: 'published', ends: '2026-12-01T10:00:00')), onWait: () {}, onCorrectAnyway: () {})));
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: HubNoDegreesBody(canImport: true, importRecommended: true, onImport: () {}, onCorrect: () {})));
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: HubNoDegreesBody(canImport: false, importRecommended: false, noCourse: true, onImport: () {}, onCorrect: () {})));
    });
    testWidgets('import sheet', (t) async {
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: HubDegreesPickBody(onTemplate: () {}, onPick: () {})));
      final p = DegreesPreview.fromJson({
        'columns': ['Student name', 'A really long column title that does not fit anywhere', 'Degree'],
        'match_column': 'Student name',
        'degree_column': 'Degree',
        'max_score': 20,
        'rows': 40,
        'matched': 36,
        'unmatched': [for (var i = 0; i < 5; i++) {'row': i + 2, 'value': 'A person with quite a long name indeed $i'}],
        'invalid': [{'row': 9, 'value': '', 'reason': 'empty'}],
        'import_key': 'k',
      });
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: HubDegreesPreviewBody(
            fileName: 'a_very_long_file_name_for_the_degrees_of_the_midterm_exam_2026.xlsx',
            preview: p,
            maxController: TextEditingController(text: '20'),
            onChangeFile: () {},
            onMaxChanged: () {},
            onMatchColumn: (_) {},
            onDegreeColumn: (_) {},
            onSave: () {},
          )));
    });
    testWidgets('the whole screen', (t) => expectNoLayoutErrors(t, () => ExamHubScreen(loader: () async => _data()), scaffold: false));
  });
}

/// Every preview waits until the test answers it.
class _HeldDegrees extends DegreesApi {
  final asked = <double?>[];
  final _held = <Completer<(DegreesPreview?, EngineResult)>>[];

  @override
  Future<(DegreesPreview?, EngineResult)> preview(int examId, {required String fileName, required Uint8List bytes, String? matchColumn, String? degreeColumn, double? maxScore}) {
    asked.add(maxScore);
    final c = Completer<(DegreesPreview?, EngineResult)>();
    _held.add(c);
    return c.future;
  }

  void answer(int i, {required int matched, required double max}) => _held[i].complete((
        DegreesPreview(columns: const ['Name', 'Degree'], matchColumn: 'Name', degreeColumn: 'Degree', maxScore: max, rows: 9, matched: matched, importKey: 'k'),
        EngineResult.ok(const {}),
      ));
}
