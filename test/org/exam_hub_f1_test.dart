// The Exam Hub (D-350, made plain by D-700 – D-703): the `grading` flags, the stages, the one sentence and next step
// of each exam, the detail steps, Needs you now, the degrees import's parsing, and every piece under the layout harness.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppButton;
import 'package:flutter_education_app/features/exams/exam_all.dart';
import 'package:flutter_education_app/features/exams/exam_engine_api.dart' show EngineResult;
import 'package:flutter_education_app/features/exams/hub/exam_hub_screen.dart';
import 'package:flutter_education_app/features/exams/hub/grade/grade_papers_sheet.dart';
import 'package:flutter_education_app/features/exams/hub/hub_degrees_import.dart';
import 'package:flutter_education_app/features/exams/hub/hub_degrees_import_sheet.dart';
import 'package:flutter_education_app/features/exams/hub/hub_entry.dart';
import 'package:flutter_education_app/features/exams/hub/hub_logic.dart';
import 'package:flutter_education_app/features/exams/hub/hub_widgets.dart';
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

AllExam _e(int id, {String status = 'closed', Map<String, dynamic>? g, int? course = 10, String title = 'Exam', Map<String, dynamic>? settings, String? policy, String? starts, String? ends, int q = 12}) => AllExam({
      'id': id,
      'title': '$title $id',
      'status': status,
      'course_id': course,
      'org_id': null,
      'settings': settings,
      'starts_at': starts,
      'ends_at': ends,
      'question_count': q,
      'attempts': {'total': 30},
      'results_policy': policy,
      'grading': ?g,
    });

const _paper = {'mode': 'offline'};
final _now = DateTime.utc(2026, 11, 13, 8);

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

  group('stages (D-700)', () {
    List<int> ids(HubStage s, {AllExamsFilter f = const AllExamsFilter(), HubAttentionKind? focus}) => [for (final e in hubStageList(_data(), s, f: f, focus: focus, now: _now)) e.id];
    test('drafts, running (published, not ended), finished (closed, ended, archived)', () {
      expect(ids(HubStage.drafts), [1]);
      expect(ids(HubStage.running), [5]);
      expect(ids(HubStage.finished)..sort(), [2, 3, 4, 6, 7, 8]);
      expect(hubStageOf(_e(9, status: 'published', g: _g(ended: true))), HubStage.finished, reason: 'its window is over');
    });
    test('without grading the end time decides', () {
      expect(hubStageOf(_e(9, status: 'published', ends: '2026-11-01T10:00:00'), now: _now), HubStage.finished);
      expect(hubStageOf(_e(9, status: 'published', ends: '2026-12-01T10:00:00'), now: _now), HubStage.running);
      expect(hubStageOf(_e(9, status: 'published'), now: _now), HubStage.running);
    });
    test('finished: what waits first, the archive last', () {
      final f = ids(HubStage.finished);
      expect(f.first, 2);
      expect(f[1], 3);
      expect(f.last, 8);
    });
    test('search reaches the course name; course and type narrow', () {
      expect(ids(HubStage.finished, f: const AllExamsFilter(query: 'mathematics second')).length, 5);
      expect(ids(HubStage.finished, f: const AllExamsFilter(query: 'zzz')), isEmpty);
      expect(ids(HubStage.finished, f: const AllExamsFilter(courseId: AllExamsFilter.noCourse)), [7]);
      expect(ids(HubStage.finished, f: const AllExamsFilter(type: AllExamType.paper))..sort(), [2, 3]);
    });
    test('an attention card lists its exams whatever their stage', () {
      expect(ids(HubStage.drafts, focus: HubAttentionKind.unpublished), [3, 4]);
      expect(ids(HubStage.running, focus: HubAttentionKind.drafts), [1]);
    });
    test('the hub opens where students sit exams, else the first stage with any', () {
      expect(hubInitialStage(_data(), now: _now), HubStage.running);
      expect(hubInitialStage(AllExamsData(exams: [_e(1, status: 'draft'), _e(2)]), now: _now), HubStage.drafts);
      expect(hubInitialStage(AllExamsData(exams: [_e(2)]), now: _now), HubStage.finished);
      expect(hubStageCounts(_data(), now: _now), {HubStage.drafts: 1, HubStage.running: 1, HubStage.finished: 6});
    });
    test('an organization scope keeps only its exams', () {
      final d = AllExamsData(exams: [AllExam({'id': 1, 'org_id': 5}), AllExam({'id': 2, 'org_id': 6})]);
      expect([for (final e in hubScoped(d, 5).exams) e.id], [1]);
      expect(identical(hubScoped(d, null), d), isTrue);
    });
  });

  group('needs you now', () {
    test('counts, most urgent first', () {
      final a = hubAttention(_data());
      expect([for (final x in a) x.kind], [HubAttentionKind.toCorrect, HubAttentionKind.inCorrection, HubAttentionKind.unpublished, HubAttentionKind.drafts]);
      expect(a.first.count, 1);
      expect(hubAttentionText(const HubAttention(HubAttentionKind.toCorrect, 3)), '3 exams have answers waiting for your grading');
      expect(hubAttentionText(const HubAttention(HubAttentionKind.drafts, 7)), '7 drafts are not finished');
      AppConfig.lang = 'ar';
      expect(hubAttentionText(const HubAttention(HubAttentionKind.unpublished, 2)), 'اختباران صُحّحا ولم يرَ الطلاب نتيجتهما بعد');
    });
    test('a server without grading still shows the drafts', () {
      expect([for (final x in hubAttention(AllExamsData(exams: [_e(1), _e(2, status: 'draft')]))) x.kind], [HubAttentionKind.drafts]);
      expect(hubAttention(AllExamsData(exams: [_e(1)])), isEmpty);
      expect(hubHasFlags(AllExamsData(exams: [_e(1)])), isFalse);
    });
  });

  group('one sentence, one next step, the rest in the menu (D-701)', () {
    test('drafts: no date, the questions, what is next', () {
      final d = _e(1, status: 'draft', starts: '2020-01-01T00:00:00');
      expect(hubStatusText(d, now: _now), 'Draft: 12 questions, not sent to students yet');
      expect(hubStatusText(_e(1, status: 'draft', settings: _paper), now: _now), 'Draft: 12 questions, not ready to print yet');
      expect(hubStatusText(_e(1, status: 'draft', q: 0), now: _now), 'Draft: no questions yet');
      expect(hubNextStep(d), HubAction.publish);
      expect(hubNextLabel(d), 'Send to students');
      expect(hubNextStep(_e(1, status: 'draft', q: 0)), HubAction.edit);
      expect(hubNextLabel(_e(1, status: 'draft', q: 0)), 'Continue editing');
    });
    test('running: open until, scheduled, how many answered', () {
      final open = _e(9, status: 'published', ends: '2026-11-20T10:00:00', g: _g(ended: false, submitted: 12));
      expect(hubStatusText(open, now: _now), startsWith('Open until 20 Nov'));
      expect(hubStatusText(open, now: _now), endsWith('12 students answered'));
      expect(hubNextStep(open, now: _now), HubAction.results);
      expect(hubNextStep(_e(9, status: 'published', settings: _paper, g: _g(ended: false)), now: _now), HubAction.deliver);
      final later = _e(9, status: 'published', starts: '2026-11-18T09:00:00', g: _g(ended: false));
      expect(hubStatusText(later, now: _now), startsWith('Scheduled: opens 18 Nov'));
      expect(hubNextStep(later, now: _now), HubAction.edit);
      expect(hubCurrentStep(later, now: _now), HubStep.send);
      expect(hubCurrentStep(open, now: _now), HubStep.grade);
    });
    test('finished: what waits, the button that deals with it', () {
      final d = _data();
      AllExam x(int id) => d.exams.firstWhere((e) => e.id == id);
      expect(hubStatusText(x(2), now: _now), 'Finished: 3 papers wait for grading');
      expect(hubNextLabel(x(2), now: _now), 'Grade');
      expect(hubStatusText(x(3), now: _now), 'Grading under way: 5 answers wait for grading');
      expect(hubNextLabel(x(3), now: _now), 'Continue grading');
      expect(hubStatusText(x(4), now: _now), 'Graded: results not published to students yet');
      expect(hubNextLabel(x(4), now: _now), 'Publish results');
      expect(hubNextStep(x(7), now: _now), HubAction.getResult);
      expect(hubNextLabel(x(7), now: _now), 'See results');
      expect(hubStatusText(x(6), now: _now), 'Finished: nobody answered');
      expect(hubNextStep(x(6), now: _now), HubAction.results);
      expect(hubNextStep(_e(9)), HubAction.results, reason: 'no flags: the results screen');
      expect(hubStatusText(x(8), now: _now), startsWith('Archived'));
    });
    test('the menu never repeats the next step, and keeps what the older tabs offered', () {
      for (final e in _data().exams) {
        expect(hubMenuActions(e, now: _now), isNot(contains(hubNextStep(e, now: _now))), reason: 'exam ${e.id}');
      }
      expect(hubMenuActions(_e(1, status: 'draft')), containsAll([HubAction.edit, HubAction.paper, HubAction.duplicate]));
      expect(hubMenuActions(_e(1, g: _g(degrees: true))), containsAll([HubAction.edit, HubAction.results, HubAction.correct, HubAction.importDegrees, HubAction.revision]));
      expect(hubMenuActions(_e(1, status: 'closed', settings: {'paper_file': {'name': 'a.pdf'}})), isNot(contains(HubAction.paper)));
      expect(hubMenuActions(_e(1, status: 'published', settings: _paper, g: _g(ended: false, papers: 2, state: 'in_progress'))), contains(HubAction.deliver));
    });
    test('revision needs a course, and its switch on; Excel too', () {
      expect(hubMenuActions(_e(1, g: _g(degrees: true))), contains(HubAction.revision));
      expect(hubMenuActions(_e(1, g: _g(degrees: true), course: null)), isNot(contains(HubAction.revision)));
      expect(hubCanImport(_e(1, course: null)), isFalse);
      AppConfig.disableList = ['exam.grade_review', 'exam.results.import'];
      expect(hubMenuActions(_e(1, g: _g(degrees: true))), isNot(contains(HubAction.revision)));
      expect(hubCanImport(_e(1)), isFalse);
    });
    test('Excel is the suggestion only while there is nothing to correct', () {
      expect(hubImportRecommended(_e(1, g: _g())), isTrue);
      expect(hubImportRecommended(_e(1, g: _g(papers: 4))), isFalse);
      expect(hubImportRecommended(_e(1, g: _g(), course: null)), isFalse);
    });
    test('Arabic', () {
      AppConfig.lang = 'ar';
      expect(hubStatusText(_e(1, status: 'draft'), now: _now), 'مسودة: 12 سؤالاً، لم تُرسل للطلاب بعد');
      expect(hubNextLabel(_e(1, status: 'draft')), 'أرسل للطلاب');
    });
  });

  group('the detail steps (D-702)', () {
    test('done up to where the exam is, then the current one, then what is ahead', () {
      final d = _data();
      AllExam x(int id) => d.exams.firstWhere((e) => e.id == id);
      List<HubStepState> states(AllExam e) => [for (final s in HubStep.values) hubStepState(e, s, now: _now)];
      expect(states(x(1)), [HubStepState.done, HubStepState.current, HubStepState.upcoming, HubStepState.upcoming]);
      expect(states(_e(1, status: 'draft', q: 0)), [HubStepState.current, HubStepState.upcoming, HubStepState.upcoming, HubStepState.upcoming]);
      expect(states(x(3)), [HubStepState.done, HubStepState.done, HubStepState.current, HubStepState.upcoming]);
      expect(states(x(4)), [HubStepState.done, HubStepState.done, HubStepState.done, HubStepState.current]);
      expect(states(x(7)), [for (final _ in HubStep.values) HubStepState.done]);
      expect(hubStepNote(x(3), HubStep.grade, now: _now), '5 answers wait for grading');
      expect(hubStepNote(x(5), HubStep.grade, now: _now), 'After the exam ends');
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

  group('Grade paper sheets', () {
    test('kill switches hide each kind, and the action with none left', () {
      expect(hubGradeKinds(), [GradeKind.bubble, GradeKind.essay]);
      AppConfig.disableList = ['exam.auto_correct'];
      expect(hubGradeKinds(), [GradeKind.essay]);
      AppConfig.disableList = ['exam.bubble', 'exam.essay_run'];
      expect(hubGradeKinds(), isEmpty);
    });
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
    ExamHubBody body({HubStage stage = HubStage.running, HubAttentionKind? focus, AllExamsData? d, AllExamsFilter f = const AllExamsFilter()}) => ExamHubBody(
          data: d,
          stage: stage,
          focus: focus,
          filter: f,
          now: _now,
          onStage: (_) {},
          onFilter: (_) {},
          onAttention: (_) {},
          onClearFocus: () {},
          onAction: (_, _) {},
          onRetry: () {},
          onNew: () {},
          onRefresh: () async {},
          onSelect: (_) {},
          onOpen: (_) {},
        );
    testWidgets('each stage', (t) async {
      for (final s in HubStage.values) {
        await expectNoLayoutErrors(t, () => body(stage: s, d: _data()));
      }
    });
    testWidgets('a card list, a narrowed one, a type filter', (t) async {
      await expectNoLayoutErrors(t, () => body(focus: HubAttentionKind.unpublished, d: _data()));
      await expectNoLayoutErrors(t, () => body(d: _data(), f: const AllExamsFilter(query: 'zzz', type: AllExamType.file)));
    });
    testWidgets('loading, empty, no flags', (t) async {
      await expectNoLayoutErrors(t, () => body());
      await expectNoLayoutErrors(t, () => body(d: const AllExamsData(exams: [])));
      await expectNoLayoutErrors(t, () => body(stage: HubStage.finished, d: AllExamsData(exams: [_e(1), _e(2, status: 'published')])));
      await expectNoLayoutErrors(t, () => body(stage: HubStage.drafts, d: AllExamsData(exams: [_e(1)])));
    });
    testWidgets('the pieces', (t) async {
      final d = _data();
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: HubAttentionCards(items: hubAttention(d), active: HubAttentionKind.drafts, onTap: (_) {})));
      for (final e in d.exams) {
        await expectNoLayoutErrors(t, () => SingleChildScrollView(child: HubExamTile(exam: e, course: d.courseName(e), now: _now, onAction: (_) {})));
        await expectNoLayoutErrors(t, () => SingleChildScrollView(child: HubExamDetail(exam: e, course: d.courseName(e), now: _now, onAction: (_) {})));
      }
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: HubExamTile(exam: d.exams.first, busy: true, selected: true, now: _now, onAction: (_) {})));
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: HubFilterBody(type: AllExamType.paper, onType: (_) {}, onDone: () {})));
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
    testWidgets('Grade papers', (t) async {
      const courses = [
        (courseId: 1, orgId: 4 as int?, name: 'Biology for the second year of the secondary school, group A'),
        (courseId: 2, orgId: null as int?, name: 'Chemistry'),
      ];
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: GradePapersBody(courses: courses, kinds: GradeKind.values, orgNames: const {4: 'A school with a long name'}, onPick: (_, _) {})));
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: GradePapersBody(courses: courses, kinds: GradeKind.values, initial: courses.first, orgNames: const {4: 'A school with a long name'}, onPick: (_, _) {})));
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: GradePapersBody(courses: const [], kinds: GradeKind.values, onPick: (_, _) {})));
    });
    testWidgets('the whole screen', (t) => expectNoLayoutErrors(t, () => ExamHubScreen(now: _now, loader: () async => _data()), scaffold: false));
    testWidgets('the exam page of a phone', (t) async {
      final d = _data();
      for (final e in [d.exams[1], d.exams[2], d.exams[4]]) {
        await expectNoLayoutErrors(t, () => HubExamPage(examId: e.id, changes: ValueNotifier(0), exam: () => e, course: () => d.courseName(e), org: () => null, busy: () => false, now: _now, onAction: (_, _, _) {}), scaffold: false);
      }
    });
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
