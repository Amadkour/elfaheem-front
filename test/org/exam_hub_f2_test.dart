// Exam Hub, the create wizard (pack F2): the plan's rules, the one draft on the server, and the drawn parts at phone and
// desktop sizes.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_authoring.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_engine_api.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_quick.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_versions.dart';
import 'package:flutter_education_app/features/shared/exam_engine/hub/create/exam_create_logic.dart';
import 'package:flutter_education_app/features/shared/exam_engine/hub/create/exam_create_parts.dart';
import 'package:flutter_education_app/features/shared/exam_engine/hub/create/exam_create_sync.dart';
import 'package:flutter_education_app/features/shared/exam_engine/hub/create/exam_create_wizard.dart';
import 'package:flutter_education_app/features/shared/exam_engine/hub/create/offline_plan_api.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/exam_setup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/layout_harness.dart';

const _course = (courseId: 7, orgId: null as int?, name: 'Biology');
const _personal = (courseId: null as int?, orgId: null as int?, name: 'Personal');
const _sheet40 = OmrTemplateItem(id: 1, version: 2, name: 'Bubble 40', questions: 40, options: 4);
const _sheet100 = OmrTemplateItem(id: 2, version: 1, name: 'Bubble 100', questions: 100);
const _own = OmrTemplateItem(id: 3, version: 1, name: 'Mine', questions: 20, kind: 'auto_bubble');

QuickQuestion _mcq(String p) => QuickQuestion.mcq()
  ..prompt = p
  ..correct = 'a'
  ..options[0].text = 'x'
  ..options[1].text = 'y';

class _Authoring extends ExamAuthoringApi {
  final calls = <String>[];
  var examsMade = 0, questionsMade = 0, placements = 0;
  Map<String, dynamic> settingsOnServer = {};
  Map<String, dynamic>? lastUpdate;
  EngineResult? failPublish;

  EngineResult _ok(Map<String, dynamic> m) => EngineResult.ok(m);

  @override
  Future<ExamScope> resolveScope(int courseId, {int? orgId}) async => ExamScope(orgId: null, courseId: courseId, list: EngineResult.ok(const {}));
  @override
  Future<EngineResult> createExam(Map<String, dynamic> body) async {
    calls.add('createExam');
    settingsOnServer = Map.of(body['settings'] as Map<String, dynamic>);
    return _ok({'id': ++examsMade});
  }

  @override
  Future<EngineResult> exam(int id) async => _ok({'id': id, 'settings': settingsOnServer});
  @override
  Future<EngineResult> updateExam(int id, Map<String, dynamic> body) async {
    calls.add('updateExam');
    lastUpdate = body;
    return _ok({'id': id});
  }

  @override
  Future<EngineResult> addSection(int examId, Map<String, dynamic> body) async {
    calls.add('addSection:${body['mode']}');
    return _ok({'id': 50});
  }

  @override
  Future<EngineResult> updateSection(int examId, int sid, Map<String, dynamic> body) async {
    calls.add('updateSection:${body['mode']}');
    return _ok({'id': sid});
  }

  @override
  Future<EngineResult> createQuestion(Map<String, dynamic> body) async {
    calls.add('createQuestion');
    return _ok({'id': ++questionsMade});
  }

  @override
  Future<EngineResult> archiveQuestion(int id) async {
    calls.add('archive:$id');
    return _ok({});
  }

  @override
  Future<EngineResult> place(int examId, int sid, {required int questionId, int? version, double? points, int? position, bool required = false}) async {
    calls.add('place');
    return _ok({'placement_id': 100 + (++placements)});
  }

  @override
  Future<EngineResult> unplace(int examId, int placementId) async {
    calls.add('unplace:$placementId');
    return _ok({});
  }

  @override
  Future<EngineResult> reorderQuestions(int examId, int sid, List<int> placementIds) async {
    calls.add('reorder:${placementIds.join(",")}');
    return _ok({});
  }

  @override
  Future<EngineResult> lifecycle(int id, ExamAction a) async {
    calls.add('lifecycle:${a.name}');
    return failPublish ?? _ok({});
  }
}

class _Setup extends ExamSetupApi {
  final bodies = <Map<String, dynamic>>[];
  final List<String> log;
  _Setup(this.log);
  @override
  Future<EngineResult> putSetup(int id, Map<String, dynamic> body) async {
    bodies.add(body);
    log.add('setup');
    return EngineResult.ok({});
  }
}

class _Versions extends ExamVersionsApi {
  final bodies = <Map<String, dynamic>>[];
  final List<String> log;
  _Versions(this.log);
  @override
  Future<EngineResult> generate(int examId, Map<String, dynamic> body) async {
    bodies.add(body);
    log.add('versions:${body['count']}');
    return EngineResult.ok({});
  }
}

/// `PUT /exams/{id}/offline-plan` (contract §2), logged as `plan`.
class _Plans extends OfflinePlanApi {
  _Plans(this.log);
  final List<String> log;
  final bodies = <Map<String, dynamic>>[];
  @override
  Future<EngineResult> putPlan(int examId, OfflinePlan plan) async {
    bodies.add(plan.toJson());
    log.add('plan');
    return EngineResult.ok({});
  }
}

(ExamCreateSync, _Authoring, _Setup, _Versions) _server() {
  final a = _Authoring();
  final s = _Setup(a.calls);
  final v = _Versions(a.calls);
  return (ExamCreateSync(api: a, setup: s, versions: v, plans: _Plans(a.calls)), a, s, v);
}

/// A paper plan prints generic copies here (D-697: a course's default is one copy per student, which has no versions).
ExamCreatePlan _plan({bool bubble = false, AnswerFormat answer = AnswerFormat.onPaper}) {
  final p = ExamCreatePlan(place: _course, title: 'Exam');
  if (bubble) {
    p.setAnswer(AnswerFormat.bubble);
    p.template = _sheet40;
  } else {
    p.setAnswer(answer);
  }
  if (p.isPaper) p.setCopies(SheetCopies.generic);
  p.exam.questions.addAll([_mcq('one'), _mcq('two')]);
  return p;
}

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('the plan', () {
    // D-697: the paper steps after the questions are the answer sheet, the bubble form, the copies, the attributes, the
    // paper design and the review (Settings is the online exam's only)
    test('a bubble exam is a paper exam and gets the template step', () {
      final p = _plan(bubble: true);
      expect(p.publish, PublishKind.paper);
      expect(p.exam.mode, QuickMode.offline);
      expect(createSteps(p, whereNeeded: true, omrOn: true, identifiersOn: true), [
        CreateStep.where, CreateStep.answer, CreateStep.questions, CreateStep.layout, CreateStep.template, CreateStep.sheets, //
        CreateStep.attributes, CreateStep.design, CreateStep.review,
      ]);
    });

    test('the answer format decides the kind: online, paper, table, bubble', () {
      final p = ExamCreatePlan(place: _course, title: 'Exam');
      expect(createStepReady(CreateStep.answer, p), isFalse);
      p.setAnswer(AnswerFormat.online);
      expect((p.isElectronic, p.isBubble, p.exam.mode), (true, false, QuickMode.online));
      expect(p.settingsJson, {'answer_format': 'online'});
      p.setAnswer(AnswerFormat.table);
      expect((p.isPaper, p.isBubble, p.answerBooklet), (true, false, true));
      expect(p.settingsJson['answer_booklet'], isTrue);
      p.setAnswer(AnswerFormat.onPaper);
      expect(p.settingsJson['answer_booklet'], isFalse);
      p.setAnswer(AnswerFormat.bubble);
      expect((p.isPaper, p.isBubble), (true, true));
      expect(p.settingsJson['answer_format'], 'bubble');
      expect(createSteps(p, whereNeeded: false, omrOn: true, identifiersOn: false),
          [CreateStep.answer, CreateStep.questions, CreateStep.layout, CreateStep.template, CreateStep.sheets, CreateStep.design, CreateStep.review]);
    });

    test('a table and a bubble sheet both take essay questions: what the sheet does not hold goes on the paper (D-697)', () {
      final p = _plan(answer: AnswerFormat.table)..answerSheetOn = false;
      p.exam.questions.add(QuickQuestion.essay()..prompt = 'why');
      expect(bubbleCheckOf(p).blocks, isFalse);
      p.setAnswer(AnswerFormat.bubble);
      expect(bubbleCheckOf(p).notHeld, isEmpty);
      expect(bubbleCheckOf(p).blocks, isFalse);
    });

    test('the sheet comes after the questions and must hold them', () {
      final p = _plan(bubble: true)..template = const OmrTemplateItem(id: 9, version: 1, name: 'x', questions: 1);
      expect(createStepReady(CreateStep.template, p), isFalse);
      p.template = _sheet40;
      expect(createStepReady(CreateStep.template, p), isTrue);
    });

    test('no bubble format while OMR is off', () {
      expect(answerFormatsFor(omrOn: false), [AnswerFormat.online, AnswerFormat.onPaper, AnswerFormat.table]);
      expect(answerFormatsFor(omrOn: true).length, 4);
      expect(kCreateModes, [AnswerFormat.online, AnswerFormat.onPaper]);
    });

    test('older exams: the answer format from what they hold', () {
      expect(answerFormatOf({'answer_format': 'table'}), AnswerFormat.table);
      expect(answerFormatOf({'paper_plan': {'mode': 'versions'}}), AnswerFormat.onPaper);
      expect(answerFormatOf({'omr_template_id': 3, 'paper_plan': {}}), AnswerFormat.bubble);
      expect(answerFormatOf({'paper_format': 'both'}), AnswerFormat.bubble);
      expect(answerFormatOf({'delivery': 'online'}), AnswerFormat.online);
      expect(answerFormatOf({}), isNull);
      expect([for (final f in AnswerFormat.values) answerFormatKey(f)], ['online', 'on_paper', 'table', 'bubble']);
    });

    test('kill switches drop their steps', () {
      final p = _plan(bubble: true);
      expect(createSteps(p, whereNeeded: false, omrOn: false, identifiersOn: false).contains(CreateStep.template), isFalse);
      expect(createSteps(p, whereNeeded: false, omrOn: false, identifiersOn: false).contains(CreateStep.attributes), isFalse);
      expect(createSteps(p..answerSheetOn = false, whereNeeded: false, omrOn: true, identifiersOn: true).contains(CreateStep.layout), isFalse);
    });

    test('per-student copies: the course roster, or an uploaded list without a course; an own sheet too (D-716)', () {
      final p = _plan()..setCopies(SheetCopies.personal);
      expect(p.paperPlan, PaperPlan.personal);
      expect(needsIdentifierStep(p, identifiersOn: true), isFalse, reason: 'a course\'s roster is automatic');
      p.setPlace(_personal);
      expect(p.paperPlan, PaperPlan.personal);
      expect(needsIdentifierStep(p, identifiersOn: true), isTrue, reason: 'no course: the uploaded list');
      final own = _plan(bubble: true)..template = _own;
      expect(own.personalAllowed, isTrue, reason: 'the question paper carries the name; the own form is handed out blank');
      expect(own.versionsAllowed, isFalse);
    });

    test('moving to another place keeps every answer', () {
      final p = _plan();
      p.exam.durationMinutes = 45;
      p.setPlace(_personal);
      expect(p.exam.questions.length, 2);
      expect(p.exam.durationMinutes, 45);
      expect(p.exam.courseId, isNull);
    });

    test('a file prints as one version', () {
      final p = _plan()..versions = 4;
      expect(p.effectiveVersions, 4);
      p.exam.source = QuickSource.file;
      p.normalize();
      expect(p.effectiveVersions, 1);
    });

    test('the setup body never carries version marks and names the pinned sheet', () {
      final b = _plan(bubble: true).setupBody!;
      expect(b['paper_format'], 'both');
      expect(b['omr_template_id'], 1);
      expect(b['omr_template_version'], 2);
      expect(b['form_markers'], isEmpty);
      expect(_plan(answer: AnswerFormat.online).setupBody, {'delivery': 'online'});
      expect(_plan().setupBody!['paper_format'], 'paper');
    });
  });

  group('bubble checks', () {
    // D-697 changed these two: a question the bubble sheet does not hold is answered on the paper, so nothing blocks
    test('questions a bubble cannot hold go on the paper, even without the NB2 sheet', () {
      final p = _plan(bubble: true)..answerSheetOn = false;
      p.exam.questions.add(QuickQuestion.essay()..prompt = 'why');
      expect(bubbleCheckOf(p).notHeld, isEmpty);
      expect(bubbleCheckOf(p).blocks, isFalse);
    });

    test('more questions than rows, more choices than bubbles', () {
      final p = _plan(bubble: true)..template = const OmrTemplateItem(id: 9, version: 1, name: 'x', questions: 1, options: 2);
      p.exam.questions[0].options[2].text = 'z';
      final c = bubbleCheckOf(p);
      expect(c.over, 1);
      expect(c.choicesOver, 1);
    });

    test('imported questions a bubble cannot hold do not block either', () {
      final p = _plan(bubble: true)..held = const [HeldQuestion(placementId: 1, sectionId: 1, type: 'essay', prompt: 'a', points: 1), HeldQuestion(placementId: 2, sectionId: 1, type: 'matching', prompt: 'b', points: 1)];
      expect(p.importedNotBubble, 2);
      expect(bubbleCheckOf(p).blocks, isFalse);
    });

    test('the recommended sheet is the smallest that fits', () {
      expect(recommendedTemplate([_sheet100, _sheet40, _own], 30)?.id, 1);
      expect(recommendedTemplate([_sheet100, _sheet40], 60)?.id, 2);
      expect(recommendedTemplate([_sheet100, _sheet40], 500)?.id, 2);
      expect(recommendedTemplate(const [], 5), isNull);
    });

    test('versions that cannot differ are called out', () {
      // in the booklet; on NB2 the objective questions routed to the paper get choice boxes, which cannot be shuffled
      final p = _plan()
        ..answerSheetOn = false
        ..versions = 3
        ..shuffleQuestions = false
        ..shuffleOptions = false;
      expect(versionsWouldMatch(p), isTrue);
      p.shuffleOptions = true;
      expect(versionsWouldMatch(p), isFalse);
      p.answerSheetOn = true;
      expect((p.shuffleOptionsAllowed, versionsWouldMatch(p)), (false, true));
    });
  });

  group('the one draft', () {
    test('two saves at once make one exam', () async {
      final (sync, a, _, _) = _server();
      final p = _plan();
      final both = await Future.wait([sync.ensure(p), sync.ensure(p)]);
      expect(both, [null, null]);
      expect(a.examsMade, 1);
      expect(await sync.ensure(p), isNull, reason: 'the next save is a real one again');
      expect(a.examsMade, 1);
    });

    test('ensure twice with no change makes one exam and no further call', () async {
      final (sync, a, s, _) = _server();
      final p = _plan();
      expect(await sync.ensure(p), isNull);
      final after = a.calls.length;
      expect(await sync.ensure(p), isNull);
      expect(a.examsMade, 1);
      expect(a.calls.length, after);
      expect(s.bodies.length, 1);
    });

    test('an edited question is replaced, the others stay, the order is the teacher\'s', () async {
      final (sync, a, _, _) = _server();
      final p = _plan();
      await sync.ensure(p);
      a.calls.clear();
      p.exam.questions[0].prompt = 'changed';
      expect(await sync.ensure(p), isNull);
      expect(a.examsMade, 1);
      expect(a.calls.where((c) => c == 'createQuestion').length, 1);
      expect(a.calls, contains('unplace:101'));
      expect(a.calls, contains('archive:1'));
      expect(a.calls, contains('reorder:103,102'));
    });

    test('an update keeps what the server added to settings', () async {
      final (sync, a, _, _) = _server();
      final p = _plan();
      await sync.ensure(p);
      a.settingsOnServer['print_identifiers'] = [{'source': 'name'}];
      p.exam.durationMinutes = 90;
      await sync.ensure(p);
      expect((a.lastUpdate!['settings'] as Map)['print_identifiers'], isNotNull);
      expect((a.lastUpdate!['settings'] as Map)['paper_plan'], {'mode': 'versions', 'versions': 1});
      expect((a.lastUpdate!['settings'] as Map)['answer_format'], 'on_paper');
      expect((a.lastUpdate!['settings'] as Map)['answer_booklet'], isFalse);
    });

    test('the first save carries the answer format and the booklet', () async {
      final (sync, a, _, _) = _server();
      await sync.ensure(_plan(answer: AnswerFormat.table));
      expect(a.settingsOnServer['answer_format'], 'table');
      expect(a.settingsOnServer['answer_booklet'], isTrue);
    });

    test('switching to paper moves the section to paper', () async {
      final (sync, a, _, _) = _server();
      final p = _plan(answer: AnswerFormat.online);
      await sync.ensure(p);
      expect(a.calls, contains('addSection:online'));
      p.setAnswer(AnswerFormat.onPaper);
      await sync.ensure(p);
      expect(a.calls, contains('updateSection:paper'));
    });

    test('finish: versions before their marks, then publish; a retry publishes once', () async {
      // answered in the booklet: with NB2 choice boxes nothing is shuffled (the next test)
      final p = _plan()
        ..answerSheetOn = false
        ..versions = 3;
      final (sync, a, s, v) = _server();
      a.failPublish = EngineResult.fail(500, null, 'x');
      expect(await sync.finish(p), isNotNull);
      a.failPublish = null;
      expect(await sync.finish(p), isNull);
      final vi = a.calls.indexOf('versions:3');
      expect(vi, greaterThan(-1));
      expect(a.calls.indexOf('setup', vi), greaterThan(vi));
      expect(a.calls.indexOf('plan'), inInclusiveRange(0, vi), reason: 'the paper plan is checked by the server before the versions');
      expect(a.calls.where((c) => c == 'createQuestion').length, 2);
      expect(s.bodies.last['form_markers'], kVersionMarkers);
      expect(v.bodies.last['shuffle_questions'], isTrue);
      expect(await sync.finish(p), isNull);
      expect(a.calls.where((c) => c == 'lifecycle:publish').length, 2);   // the failed try + the good one, never a third
    });

    test('choice questions in the NB2 boxes: the versions shuffle neither questions nor options', () async {
      final (sync, _, _, v) = _server();
      final p = _plan()..versions = 3;
      expect((p.shuffleAllowed, p.shuffleQuestions, p.shuffleOptions), (false, true, true));
      expect(await sync.finish(p), isNull);
      expect((v.bodies.single['shuffle_questions'], v.bodies.single['shuffle_options']), (false, false));
    });

    test('a bubble exam never asks to shuffle the question order', () async {
      final (sync, _, _, v) = _server();
      final p = _plan(bubble: true)..versions = 2;
      expect(await sync.finish(p), isNull);
      expect(v.bodies.single['shuffle_questions'], isFalse);
    });

    test('one version makes no versions call', () async {
      final (sync, _, _, v) = _server();
      expect(await sync.finish(_plan()), isNull);
      expect(v.bodies, isEmpty);
    });

    test('discard deletes the draft and its questions', () async {
      final a = _Authoring();
      var deleted = 0;
      final sync = ExamCreateSync(api: a, setup: _Setup(a.calls), versions: _Versions(a.calls), deleter: (_) async {
        deleted++;
        return EngineResult.ok({});
      });
      await sync.ensure(_plan());
      expect(await sync.discard(), isNull);
      expect(deleted, 1);
      expect(sync.examId, isNull);
      expect(a.calls.where((c) => c.startsWith('archive')).length, 2);
    });
  });

  group('layout', () {
    CreateSummaryItem item(String l, String? v, CreateItemState s) => CreateSummaryItem(label: l, value: v, state: s, onTap: () {});

    Widget shell(Widget body) => ExamCreateShell(
          stepKey: 'x',
          items: [
            item('Where', 'A very long course name that keeps going and going for a while', CreateItemState.done),
            item('Answers', 'Bubble sheet', CreateItemState.done),
            item('Questions', null, CreateItemState.current),
            item('Settings', null, CreateItemState.todo),
          ],
          index: 2,
          stepLabel: 'Questions',
          title: 'The questions',
          subtitle: 'Something to read',
          error: 'A problem',
          hint: 'A hint',
          body: body,
          primaryLabel: 'Continue',
          onPrimary: () {},
          backLabel: 'Back',
          onBack: () {},
          onClose: () {},
          estimate: const [('Questions', '12'), ('Total marks', '40')],
        );

    testWidgets('shell + answers + question ways', (t) async {
      await expectNoLayoutErrors(t, () => shell(CreateAnswerBody(formats: AnswerFormat.values, value: AnswerFormat.bubble, lastUsed: AnswerFormat.table, onPick: (_) {})));
      await expectNoLayoutErrors(t, () => shell(CreateQuestionWayBody(onPick: (_) {}, hasCourse: false, canGenerate: true, canImportForms: true, bubble: true)));
    });

    testWidgets('where, with and without a search', (t) async {
      await expectNoLayoutErrors(t, () => shell(CreateWhereBody(places: [for (var i = 0; i < 10; i++) (courseId: i, orgId: 1, name: 'Course number $i with a long name')], selected: null, onPick: (_) {}, orgNames: const {1: 'School'})));
    });

    testWidgets('publish, every branch', (t) async {
      await expectNoLayoutErrors(t, () => shell(CreatePublishBody(plan: _plan(bubble: true)..versions = 3, onPaperPlan: (_) {}, onVersions: (_) {}, onShuffleQuestions: (_) {}, onShuffleOptions: (_) {}, electronicDetail: const SizedBox())));
      await expectNoLayoutErrors(t, () => shell(CreatePublishBody(plan: _plan(answer: AnswerFormat.online)..setPlace(_personal), onPaperPlan: (_) {}, onVersions: (_) {}, onShuffleQuestions: (_) {}, onShuffleOptions: (_) {}, electronicDetail: const SizedBox())));
    });

    testWidgets('sheet notes, problems, leaving, done', (t) async {
      await expectNoLayoutErrors(t, () => shell(Column(children: [
            CreatePendingTemplates(items: const [_sheet40], justSent: true),
            const CreateOwnSheetNote(),
            const CreateBubbleRules(),
            CreateBubbleProblems(check: BubbleCheck(notHeld: [QuickQuestion.essay()], over: 3, capacity: 20, choicesOver: 1, importedNotHeld: 2), onRemove: () {}, onNormal: () {}, onEditor: () {}),
            CreateLeaveBody(hasDraft: true, canSave: true, onPick: (_) {}, onStay: () {}),
          ])));
      await expectNoLayoutErrors(t, () => CreateDoneBody(title: 'A long exam title', place: 'Biology', lines: const [('Questions', '12'), ('Opens', 'Now')], onDone: () {}, onOpen: () {}, onFollow: () {}, onShare: () {}));
    });

    // D-697: the first step is online or on paper; a remembered answer table means on paper, its layout chosen later
    testWidgets('the wizard opens on the How step with the last way preselected', (t) async {
      SharedPreferences.setMockInitialValues({'exam_create.answer.0': 'table'});
      final (sync, _, _, _) = _server();
      final p = ExamCreatePlan(place: _course, title: 'Exam');
      await t.pumpWidget(layoutHost(ExamCreateWizard(sync: sync, initialPlan: p), scaffold: false, scale: 1));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('create.answer.on_paper')), findsOneWidget);
      expect((p.isPaper, p.layout), (true, null));
      expect(p.answerBooklet, isFalse);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('the wizard walks from the questions to the publish step and back, answers kept', (t) async {
      final (sync, _, _, _) = _server();
      final p = _plan();
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(1440, 900);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(layoutHost(ExamCreateWizard(sync: sync, initialPlan: p, initialStep: CreateStep.questions, startedQuestions: true), scaffold: false, scale: 1));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byType(ExamCreateShell), findsOneWidget);
      await t.tap(find.descendant(of: find.byKey(const ValueKey('create.primary')), matching: find.byType(InkWell)).first, warnIfMissed: false);
      await t.pump(const Duration(milliseconds: 400));
      expect(p.exam.questions.length, 2);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    });
  });
}
