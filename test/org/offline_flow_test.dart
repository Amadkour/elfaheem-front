// The paper exam flow (D-697): which layouts fit which questions and which is the best fit, which steps every layout ×
// course / no course × copies combination walks through, the sheet_plan v2 the wizard saves (back contract
// OFFLINE_FLOW_CONTRACT.md §1) and how older exams read into it, the attribute payloads (§3), what the device remembers,
// and every new step widget under the layout harness.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/exams/exam_engine_api.dart';
import 'package:flutter_education_app/features/exams/exam_quick.dart';
import 'package:flutter_education_app/features/exams/exam_versions.dart' show versionsErrorText;
import 'package:flutter_education_app/features/exams/hub/create/attributes_step.dart';
import 'package:flutter_education_app/features/exams/hub/create/exam_create_logic.dart';
import 'package:flutter_education_app/features/exams/hub/create/exam_create_parts.dart';
import 'package:flutter_education_app/features/exams/hub/create/exam_create_prefs.dart';
import 'package:flutter_education_app/features/exams/hub/create/offline_plan_api.dart';
import 'package:flutter_education_app/features/exams/hub/create/offline_steps.dart';
import 'package:flutter_education_app/features/exams/hub/create/paper_preview.dart';
import 'package:flutter_education_app/features/exams/paper/exam_setup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/layout_harness.dart';

const _course = (courseId: 7, orgId: null as int?, name: 'Biology');
const _none = (courseId: null as int?, orgId: null as int?, name: 'Personal');
const _sheet = OmrTemplateItem(id: 12, version: 1, name: 'Bubble 40', questions: 40, options: 4);

QuickQuestion _q(String type) {
  final q = QuickQuestion.ofType(type)..prompt = 'p';
  if (type == 'mcq_single') {
    q
      ..correct = 'a'
      ..options[0].text = 'x'
      ..options[1].text = 'y';
  }
  return q;
}

QuestionMix _mix({int mcq = 0, int tf = 0, int written = 0, bool file = false}) =>
    QuestionMix.of([for (var i = 0; i < mcq; i++) 'mcq_single', for (var i = 0; i < tf; i++) 'true_false', for (var i = 0; i < written; i++) 'essay'], isFile: file);

ExamCreatePlan _paper(PaperLayout l, {bool course = true, SheetCopies copies = SheetCopies.generic}) {
  final p = ExamCreatePlan(place: course ? _course : _none, title: 'Exam')..setOffline(true);
  p.exam.questions.addAll([_q('mcq_single'), _q('mcq_single'), _q('true_false'), _q('essay')]);
  p
    ..setLayout(l)
    ..template = l.usesBubble ? _sheet : null
    ..setCopies(copies);
  return p;
}

/// Steps as letters: A how · Q questions · L answer sheet · T bubble form · S copies · I students · X attributes ·
/// D paper design · R review.
List<CreateStep> _s(String code) => [
      for (final ch in code.split(''))
        switch (ch) {
          'A' => CreateStep.answer,
          'Q' => CreateStep.questions,
          'L' => CreateStep.layout,
          'T' => CreateStep.template,
          'S' => CreateStep.sheets,
          'I' => CreateStep.identify,
          'X' => CreateStep.attributes,
          'D' => CreateStep.design,
          _ => CreateStep.review,
        },
    ];

class _FakePlans extends OfflinePlanApi {
  _FakePlans(this.payload);
  final Map<String, dynamic> payload;
  @override
  Future<EngineResult> attributes(int examId) async => EngineResult.ok(payload);
  @override
  Future<EngineResult> attributeValues(int examId, String key) async => EngineResult.ok({
        'items': [
          {'student_id': 101, 'name': 'Student one', 'value': 'Student one'},
        ],
      });
}

const _attributesPayload = <String, dynamic>{
  'students': {'source': 'course', 'total': 30},
  'attributes': [
    {'key': 'name', 'source': 'builtin', 'label_ar': 'الاسم', 'label_en': 'Name', 'filled': 30, 'masked': false, 'editable': false},
    {'key': 'system_number', 'source': 'builtin', 'label_ar': 'رقم النظام', 'label_en': 'System number', 'filled': 30},
    {'key': 'academic_id', 'source': 'core', 'label_ar': 'الرقم الأكاديمي', 'label_en': 'Academic ID', 'filled': 27},
    {'key': 'national_id', 'source': 'core', 'label_ar': 'الرقم القومي', 'label_en': 'National ID', 'filled': 12, 'masked': true},
    {'key': 'section', 'source': 'core', 'label_ar': 'الشعبة', 'label_en': 'Section', 'filled': 30},
    {'key': 'datalab:seat_no', 'source': 'datalab', 'label_ar': 'رقم الجلوس', 'label_en': 'Seat No.', 'filled': 30, 'editable': true, 'exam': true},
    {'key': 'file:hall', 'source': 'file', 'label_ar': 'Hall', 'label_en': 'Hall', 'filled': 28},
  ],
  'selected': ['name', 'academic_id'],
  'sample': {
    'student_id': 101,
    'name': 'Sara Nabil',
    'values': {'name': 'Sara Nabil', 'system_number': '101', 'academic_id': '2024000101', 'national_id': '••••••••••1234', 'section': '2'},
  },
};

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('layouts and the question mix', () {
    test('no objective question: only options 1 and 4 fit, and 1 is the best fit', () {
      final m = _mix(written: 5);
      expect(recommendedPaperLayout(m, omrOn: true), PaperLayout.allInPaper);
      expect([for (final o in paperLayoutOptions(m, omrOn: true)) if (o.available) o.layout], [PaperLayout.allInPaper, PaperLayout.questionsOnly]);
      expect(paperLayoutOptions(m, omrOn: true).where((o) => !o.available).every((o) => (o.why ?? '').isNotEmpty), isTrue, reason: 'a greyed card says why');
    });

    test('multiple choice and true / false: option 3; multiple choice alone: option 2', () {
      expect(recommendedPaperLayout(_mix(mcq: 10, tf: 5, written: 2), omrOn: true), PaperLayout.bubbleObjective);
      expect(recommendedPaperLayout(_mix(mcq: 10, written: 2), omrOn: true), PaperLayout.bubbleMcq);
      expect(paperLayoutAvailable(PaperLayout.bubbleObjective, _mix(mcq: 10), omrOn: true), isFalse, reason: 'no true / false: the same as option 2');
      expect(recommendedPaperLayout(_mix(tf: 8), omrOn: true), PaperLayout.bubbleObjective);
      expect(paperLayoutAvailable(PaperLayout.bubbleMcq, _mix(tf: 8), omrOn: true), isFalse, reason: 'no multiple choice for option 2');
    });

    test('too few to shade, a file, or the scanner off: the paper', () {
      expect(recommendedPaperLayout(_mix(mcq: 2, written: 6), omrOn: true), PaperLayout.allInPaper);
      expect(recommendedPaperLayout(_mix(mcq: 20, file: true), omrOn: true), PaperLayout.allInPaper);
      expect(paperLayoutAvailable(PaperLayout.bubbleMcq, _mix(mcq: 20, file: true), omrOn: true), isFalse);
      expect(recommendedPaperLayout(_mix(mcq: 20), omrOn: false), PaperLayout.allInPaper);
      expect(paperLayoutOptions(_mix(mcq: 20), omrOn: false).map((o) => o.layout), [PaperLayout.allInPaper, PaperLayout.questionsOnly], reason: 'hidden, not greyed');
    });

    test('layouts 2 and 3 differ only in where true / false goes', () {
      expect(PaperLayout.bubbleMcq.bubbleTypes, {'mcq_single', 'mcq_multi'});
      expect(PaperLayout.bubbleObjective.bubbleTypes, {'mcq_single', 'mcq_multi', 'true_false'});
      final two = _paper(PaperLayout.bubbleMcq), three = _paper(PaperLayout.bubbleObjective);
      expect((two.bubbleQuestionCount, three.bubbleQuestionCount), (2, 3));
      expect(two.shuffleOptionsAllowed, isFalse, reason: 'the true / false is a row of choice boxes on NB2');
      expect(three.shuffleOptionsAllowed, isTrue);
    });

    test('shuffled versions only when no choice question is answered in the NB2 boxes', () {
      final one = _paper(PaperLayout.allInPaper)..versions = 3;
      expect((one.shuffleAllowed, one.shuffleQuestionsAllowed, one.shuffleOptionsAllowed), (false, false, false));
      final booklet = _paper(PaperLayout.allInPaper)..answerSheetOn = false;
      expect((booklet.shuffleQuestionsAllowed, booklet.shuffleOptionsAllowed), (true, true));
      final three = _paper(PaperLayout.bubbleObjective);
      expect((three.shuffleQuestionsAllowed, three.shuffleOptionsAllowed), (false, true), reason: 'a bubble sheet keeps the question order');
      final four = _paper(PaperLayout.questionsOnly);
      expect((four.shuffleQuestionsAllowed, four.shuffleOptionsAllowed), (true, true));
      expect(versionsErrorText(EngineResult.fail(409, 'versions_shuffle_options', 'x')), contains('cannot be shuffled'));
    });
  });

  group('which steps, every layout × course / no course × copies', () {
    final expected = <(PaperLayout, bool, SheetCopies), String>{
      (PaperLayout.allInPaper, true, SheetCopies.personal): 'AQLSXDR',
      (PaperLayout.allInPaper, true, SheetCopies.generic): 'AQLSXDR',
      (PaperLayout.allInPaper, false, SheetCopies.personal): 'AQLSIXDR',
      (PaperLayout.allInPaper, false, SheetCopies.generic): 'AQLSDR',
      (PaperLayout.bubbleMcq, true, SheetCopies.personal): 'AQLTSXDR',
      (PaperLayout.bubbleMcq, true, SheetCopies.generic): 'AQLTSXDR',
      (PaperLayout.bubbleMcq, false, SheetCopies.personal): 'AQLTSIXDR',
      (PaperLayout.bubbleMcq, false, SheetCopies.generic): 'AQLTSDR',
      (PaperLayout.bubbleObjective, true, SheetCopies.personal): 'AQLTSXDR',
      (PaperLayout.bubbleObjective, true, SheetCopies.generic): 'AQLTSXDR',
      (PaperLayout.bubbleObjective, false, SheetCopies.personal): 'AQLTSIXDR',
      (PaperLayout.bubbleObjective, false, SheetCopies.generic): 'AQLTSDR',
      (PaperLayout.questionsOnly, true, SheetCopies.personal): 'AQLSXDR',
      (PaperLayout.questionsOnly, true, SheetCopies.generic): 'AQLSXDR',
      (PaperLayout.questionsOnly, false, SheetCopies.personal): 'AQLSIXDR',
      (PaperLayout.questionsOnly, false, SheetCopies.generic): 'AQLSDR',
    };
    for (final e in expected.entries) {
      final (layout, course, copies) = e.key;
      test('${paperLayoutKey(layout)} · ${course ? 'course' : 'no course'} · ${copies.name}', () {
        final p = _paper(layout, course: course, copies: copies);
        expect(createSteps(p, whereNeeded: false, omrOn: true, identifiersOn: true), _s(e.value));
        // the students and the ID boxes
        expect(p.needsPeopleFile, copies == SheetCopies.personal && !course);
        expect(asksIdSource(p), course && copies == SheetCopies.generic && layout != PaperLayout.questionsOnly);
        // the identifiers kill switch drops the attributes, the OMR switch the bubble form
        expect(createSteps(p, whereNeeded: false, omrOn: false, identifiersOn: false), _s(e.value.replaceAll('X', '').replaceAll('T', '')));
      });
    }

    test('online is unchanged: How, Questions, Settings', () {
      final p = ExamCreatePlan(place: _course, title: 'x')..setOffline(false);
      expect(createSteps(p, whereNeeded: true, omrOn: true, identifiersOn: true), [CreateStep.where, ..._s('AQ'), CreateStep.publish]);
    });

    test('an uploaded exam file has no paper design and prints as one version', () {
      final p = _paper(PaperLayout.allInPaper)..exam.source = QuickSource.file;
      p.normalize();
      expect(createSteps(p, whereNeeded: false, omrOn: true, identifiersOn: true), isNot(contains(CreateStep.design)));
      expect(p.personalAllowed, isFalse);
      expect(p.effectiveCopies, SheetCopies.generic);
    });

    test('back and forward keep the choices: How back to online and to paper again keeps the layout and the copies', () {
      final p = _paper(PaperLayout.bubbleMcq, copies: SheetCopies.personal);
      p.setOffline(false);
      expect(p.isElectronic, isTrue);
      p.setOffline(true);
      expect((p.layout, p.isBubble, p.effectiveCopies, p.template?.id), (PaperLayout.bubbleMcq, true, SheetCopies.personal, 12));
    });
  });

  group('sheet_plan v2 and older exams', () {
    test('the plan of each layout (contract §1)', () {
      final one = _paper(PaperLayout.allInPaper).offlinePlan!.toJson();
      expect(one['answer_layout'], 'all_in_paper');
      expect(one['bubble'], isNull);
      expect(one['copies'], 'one');
      expect(one.containsKey('students'), isFalse);
      final three = (_paper(PaperLayout.bubbleObjective, course: false, copies: SheetCopies.personal)
            ..bubbleForm = BubbleFormSource.imported
            ..bubbleSource = BubbleSource.have
            ..attributes = [(key: 'name', label: 'Name'), (key: 'file:hall', label: 'Hall')])
          .offlinePlan!
          .toJson();
      expect(three, {
        'v': 2,
        'answer_layout': 'paper_plus_bubble_objective',
        'written_sheet': 'NB2',
        'bubble': {'source': 'imported', 'ids': [12], 'print': false},
        'copies': 'per_student',
        'students': {'source': 'file'},
        'attributes': ['name', 'file:hall'],
        'id_source': 'academic',
        'paper_design': null,
      });
      expect(_paper(PaperLayout.questionsOnly).offlinePlan!.toJson()['answer_layout'], 'questions_only');
      expect(_paper(PaperLayout.questionsOnly).wantsAnswerSheet, isFalse);
      final back = OfflinePlan.ofSettings({'sheet_plan': three})!;
      expect((back.version, back.layout, back.bubbleSource, back.bubblePrint, back.personal, back.fromFile),
          (2, PaperLayout.bubbleObjective, BubbleFormSource.imported, false, true, true));
      expect(back.attributes, ['name', 'file:hall']);
    });

    test('F1 plans (v1) and older exams open in the new flow', () {
      final v1 = OfflinePlan.ofSettings({
        'sheet_plan': {'bubble': 'print', 'answer_sheet': 'NB2', 'copies': 'personal', 'students': 'course', 'id_source': 'system'},
      }, templateId: 4)!;
      expect((v1.version, v1.layout, v1.writtenSheet, v1.bubblePrint, v1.personal, v1.idSource),
          (1, PaperLayout.bubbleObjective, WrittenSheet.nb2, true, true, IdSource.system));
      expect(v1.bubbleIds, [4]);
      final v1Table = OfflinePlan.ofSettings({
        'sheet_plan': {'copies': 'generic'},
      })!;
      expect((v1Table.layout, v1Table.writtenSheet, v1Table.hasBubble), (PaperLayout.allInPaper, WrittenSheet.booklet, false));
      expect(paperLayoutOf({'answer_format': 'bubble'}), PaperLayout.bubbleObjective);
      expect(paperLayoutOf({'answer_format': 'table', 'answer_booklet': true}), PaperLayout.allInPaper);
      expect(paperLayoutOf({'answer_format': 'on_paper'}), PaperLayout.allInPaper);
      expect(paperLayoutOf({'paper_plan': {'mode': 'personal'}}), PaperLayout.allInPaper);
      expect(paperCopiesOf({'paper_plan': {'mode': 'personal'}}), SheetCopies.personal);
      expect(paperLayoutOf({'answer_format': 'online'}), isNull);
      expect(paperLayoutOf({}), isNull);
    });

    test('a D-661 answer format still sets up the plan (old prefs, older callers)', () {
      final p = ExamCreatePlan(place: _course, title: 'x')..setAnswer(AnswerFormat.bubble);
      expect(p.layout, PaperLayout.bubbleObjective);
      p.setAnswer(AnswerFormat.table);
      expect((p.layout, p.writtenSheet, p.answerBooklet), (PaperLayout.allInPaper, WrittenSheet.booklet, true));
      p.setAnswer(AnswerFormat.online);
      expect(p.offlinePlan, isNull);
    });
  });

  group('attributes (contract §3)', () {
    test('the listing, the sample, and the file columns', () {
      final a = ExamAttributes.fromJson(_attributesPayload);
      expect((a.studentsSource, a.total, a.items.length), ('course', 30, 7));
      expect(a.byKey('national_id')!.masked, isTrue);
      expect(a.byKey('datalab:seat_no')!.custom, isTrue);
      expect(a.sampleName, 'Sara Nabil');
      expect(a.sample['section'], '2');
      expect(a.fileColumns.single.key, 'file:hall');
      expect(attributeCoverageText(28, 30), '28/30 have it');
      expect(attributeCoverageText(3, 0), '');
    });

    test('the keys: the name first, nothing the exam lacks, at most 12; the plan, then this device, then the server', () {
      final a = ExamAttributes.fromJson(_attributesPayload);
      expect(cleanAttributeKeys(['section', 'name', 'gone', 'section', 'academic_id'], a), ['name', 'section', 'academic_id']);
      expect(startingAttributeKeys(a, plan: ['section']), ['name', 'section']);
      expect(startingAttributeKeys(a, remembered: ['gone', 'datalab:seat_no']), ['name', 'datalab:seat_no']);
      expect(startingAttributeKeys(a, remembered: ['gone']), ['name', 'academic_id']);
      expect(reorderedList(['a', 'b', 'c'], 0, 2), ['b', 'c', 'a']);
      expect(reorderedList(['a', 'b', 'c'], 2, 0), ['c', 'a', 'b']);
    });

    test('refusals in words', () {
      expect(offlinePlanErrorText(EngineResult.fail(422, 'plan_bubble_required', 'x')), contains('bubble form'));
      expect(offlinePlanErrorText(EngineResult.fail(409, 'attributes_need_students', 'x')), contains('students'));
      expect(offlinePlanErrorText(EngineResult.fail(409, 'exam_closed', 'x')), contains('no longer'));
    });

    test('the device remembers the layout and the attributes in order', () async {
      SharedPreferences.setMockInitialValues({});
      const prefs = ExamCreatePrefs(3);
      await prefs.save(layout: PaperLayout.bubbleMcq, attributes: ['name', 'section', 'academic_id'], copies: SheetCopies.generic);
      final got = await prefs.load();
      expect((got.layout, got.copies), (PaperLayout.bubbleMcq, SheetCopies.generic));
      expect(got.attributes, ['name', 'section', 'academic_id']);
    });
  });

  group('no overflow', () {
    final mixed = _mix(mcq: 12, tf: 4, written: 3);
    testWidgets('answer sheet layouts', (t) => expectNoLayoutErrors(
        t,
        () => SingleChildScrollView(
            child: CreateLayoutBody(
                options: paperLayoutOptions(_mix(tf: 3, written: 2), omrOn: true),
                value: PaperLayout.allInPaper,
                recommended: PaperLayout.bubbleObjective,
                lastUsed: PaperLayout.questionsOnly,
                mix: mixed,
                onPick: (_) {}))));

    testWidgets('bubble ways and copies with versions', (t) => expectNoLayoutErrors(
        t,
        () => SingleChildScrollView(
              child: Column(children: [
                CreateBubbleWays(onImport: () {}, onDesign: () {}),
                CreateCopiesBody(
                  copies: SheetCopies.generic,
                  hasCourse: false,
                  personalAllowed: false,
                  whyNotPersonal: 'An uploaded file prints as it is, so it cannot carry a name',
                  lastUsed: SheetCopies.generic,
                  onCopies: (_) {},
                  versions: CreateVersionsPanel(plan: _paper(PaperLayout.allInPaper)..versions = 3, onVersions: (_) {}, onShuffleQuestions: (_) {}, onShuffleOptions: (_) {}),
                ),
                CreateVersionsPanel(
                  plan: _paper(PaperLayout.allInPaper)
                    ..answerSheetOn = false
                    ..versions = 3,
                  onVersions: (_) {},
                  onShuffleQuestions: (_) {},
                  onShuffleOptions: (_) {},
                ),
              ]),
            )));

    testWidgets('attributes, the header preview, the custom attribute form', (t) => expectNoLayoutErrors(t, () {
          const long = 'A very long attribute label that goes on and on for a while';
          return SingleChildScrollView(
            child: Column(children: [
              CreateAttributesBody(
                chosen: const [
                  AttributeItem(id: 'name', label: 'Name', filled: 30, total: 30, sample: 'Sara Nabil', fixed: true),
                  AttributeItem(id: 'x', label: long, filled: 28, total: 30, sample: 'B-12 with a long value that should be cut'),
                ],
                available: const [AttributeItem(id: 'a', label: 'Academic ID', filled: 27, total: 30), AttributeItem(id: 'b', label: long)],
                onToggle: (_) {},
                onReorder: (_, _) {},
                onCustom: () {},
                studentName: 'Sara Nabil Abdelrahman Mohamed',
                max: 2,
                saving: true,
                note: 'From the course\'s students (30 students)',
              ),
              CustomAttributeForm(onDone: (_) {}, ways: CustomAttributeWay.values),
            ]),
          );
        }));

    testWidgets('paper design and review', (t) => expectNoLayoutErrors(
        t,
        () => SingleChildScrollView(
              child: Column(children: [
                CreatePaperDesignBody(designed: false, attributes: const ['Name', 'Academic ID', 'Seat number in the main hall'], onDesign: () {}),
                CreatePaperDesignBody(designed: true, attributes: const [], onDesign: null, busy: true),
                CreateReviewBody(
                  lines: [
                    for (final s in [CreateStep.layout, CreateStep.template, CreateStep.sheets])
                      (step: s, label: createStepLabel(s), value: 'Question paper + bubble sheet for multiple choice and true / false'),
                  ],
                  onEdit: (_) {},
                  notes: const ['3 students have no academic ID'],
                ),
              ]),
            )));

    testWidgets('the attributes step, loaded from the server', (t) => expectNoLayoutErrors(
        t,
        () => SingleChildScrollView(
            child: AttributesStep(
                examId: 1,
                courseId: 7,
                initial: const ['name', 'section'],
                idSource: IdSource.academic,
                onIdSource: (_) {},
                onChanged: (_) {},
                api: _FakePlans(_attributesPayload)))));
  });

  testWidgets('the attributes step reports the keys in order, the plan\'s first', (t) async {
    List<ChosenAttribute>? got;
    await t.pumpWidget(layoutHost(
        SingleChildScrollView(child: AttributesStep(examId: 1, courseId: 7, initial: const ['section', 'academic_id'], onChanged: (v) => got = v, api: _FakePlans(_attributesPayload))),
        scale: 1));
    await t.pump();
    await t.pump();
    expect([for (final a in got!) a.key], ['name', 'section', 'academic_id']);
    expect(find.text('Sara Nabil'), findsWidgets);
    expect(find.text('27/30 have it'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('create.attr.off.system_number')));
    await t.pump();
    await t.pump();
    expect(got!.last.key, 'system_number');
  });

  // contract §5, recorded from the back's e2e_offline_flow.py (pngs shrunk, no names)
  group('the server print preview', () {
    Map<String, dynamic> fx(String k) =>
        Map<String, dynamic>.from((jsonDecode(File('test/fixtures/payloads/offline/paper_preview.json').readAsStringSync()) as Map)[k] as Map);

    test('the REAL preview answers: the page, its part, the adjustments in words', () {
      final nb2 = PaperPreview.fromJson(fx('nb2_student'))!;
      expect(nb2.part, 'nb2');
      expect(nb2.png.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
      expect(nb2.adjustments.map((a) => a.reason), contains('qr_not_allowed'));
      expect(nb2.adjustments.map(adjustmentText).every((s) => s.startsWith('Header: ') || s.startsWith('Footer: ')), isTrue);
      expect(PaperPreview.fromJson(fx('nb2_generic_unsaved'))!.adjustments, isEmpty);
      final bubble = PaperPreview.fromJson(fx('bubble_student'))!;
      expect(bubble.part, 'bubble');
      expect(adjustmentText(bubble.adjustments.firstWhere((a) => a.reason == 'no_footer_on_this_sheet')), 'Footer: this sheet has no room for a footer');
      expect(PaperPreview.fromJson({'png': 'bm90IGEgcG5n'}), isNull);
    });

    test('the request body and the X-Design-Adjustments header', () {
      expect(paperPreviewBody(PreviewPart.bubble, studentId: 101, attributes: ['name', 'section'], lang: 'ar'),
          {'part': 'bubble', 'student_id': 101, 'attributes': ['name', 'section'], 'lang': 'ar'});
      expect(paperPreviewBody(PreviewPart.nb2), {'part': 'nb2'});
      final header = base64.encode(utf8.encode(jsonEncode(fx('nb2_student')['adjustments'])));
      expect(adjustmentsOfHeader(header).length, PaperPreview.fromJson(fx('nb2_student'))!.adjustments.length);
      expect(adjustmentsOfHeader(null), isEmpty);
      expect(adjustmentsOfHeader('%%%'), isEmpty);
    });

    testWidgets('no overflow: loading, the page with a picker and notices', (t) => expectNoLayoutErrors(t, () {
          final p = PaperPreview.fromJson(fx('nb2_student'))!;
          return SingleChildScrollView(
            child: Column(children: [
              PaperPreviewView(png: null, students: const [], studentId: null, onStudent: (_) {}),
              PaperPreviewView(
                png: p.png,
                adjustments: p.adjustments,
                students: const [(id: 1, name: 'A student with a very long name that keeps on going'), (id: 2, name: 'B')],
                studentId: 1,
                onStudent: (_) {},
                parts: PreviewPart.values,
                part: PreviewPart.nb2,
                onPart: (_) {},
              ),
            ]),
          );
        }));

    testWidgets('a failing route or the switch off shows the client preview', (t) async {
      final fallback = const Text('client preview', key: ValueKey('fb'));
      await t.pumpWidget(layoutHost(SingleChildScrollView(child: PaperPreviewPane(examId: 1, parts: const [PreviewPart.nb2], attributes: const ['name'], fallback: fallback, api: _FailPreview(), people: _FakePlans(_attributesPayload))), scale: 1));
      await t.pump(const Duration(milliseconds: 20));
      await t.pump(const Duration(milliseconds: 20));
      expect(find.byKey(const ValueKey('fb')), findsOneWidget);
      AppConfig.disableList.add(kExamPaperDesignerKey);
      addTearDown(() => AppConfig.disableList.remove(kExamPaperDesignerKey));
      await t.pumpWidget(layoutHost(SingleChildScrollView(child: PaperPreviewPane(key: const ValueKey(2), examId: 1, parts: const [PreviewPart.nb2], attributes: const ['name'], fallback: fallback, api: _OkPreview(fx('nb2_student')))), scale: 1));
      expect(find.byKey(const ValueKey('fb')), findsOneWidget);
    });

    testWidgets('the real page replaces the skeleton', (t) async {
      await t.pumpWidget(layoutHost(
          SingleChildScrollView(child: PaperPreviewPane(examId: 1, parts: const [PreviewPart.nb2], attributes: const ['name'], fallback: const SizedBox(), api: _OkPreview(fx('nb2_student')), people: _FakePlans(_attributesPayload))),
          scale: 1));
      expect(find.byKey(const ValueKey('create.preview.loading')), findsOneWidget);
      await t.pump(const Duration(milliseconds: 20));
      await t.pump(const Duration(milliseconds: 20));
      expect(find.byKey(const ValueKey('create.preview.page')), findsOneWidget);
      expect(find.textContaining('extra QR code'), findsOneWidget);
    });
  });

  _printAdjustmentTests();
}

class _FailPreview extends PaperPreviewApi {
  @override
  Future<EngineResult> preview(int examId, Map<String, dynamic> body) async => EngineResult.fail(404, null, 'Not Found');
}

class _OkPreview extends PaperPreviewApi {
  _OkPreview(this.payload);
  final Map<String, dynamic> payload;
  @override
  Future<EngineResult> preview(int examId, Map<String, dynamic> body) async => EngineResult.ok(payload);
}

void _printAdjustmentTests() {
  group('adjustments on a real print', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      SeenDesignAdjustments.clear();
    });
    Map<String, dynamic> fx(String k) =>
        Map<String, dynamic>.from((jsonDecode(File('test/fixtures/payloads/offline/paper_preview.json').readAsStringSync()) as Map)[k] as Map);
    List<DesignAdjustment> real() => PaperPreview.fromJson(fx('nb2_student'))!.adjustments;
    Map<String, List<String>> header(List<DesignAdjustment> l) => {
          'x-design-adjustments': [
            base64.encode(utf8.encode(jsonEncode([for (final a in l) {'part': a.part, 'element': a.element, 'action': a.action, 'reason': a.reason}]))),
          ],
        };

    test('said once when unseen, two at most and "N more"; not again, nor after the preview showed them', () async {
      final said = <String>[];
      final list = real();
      expect(await noticePrintAdjustments(5, header(list), notify: said.add), isNotNull);
      expect(said.single, contains('and ${list.length - 2} more'));
      expect(await noticePrintAdjustments(5, header(list), notify: said.add), isNull);
      SeenDesignAdjustments.remember(6, list);   // what the preview showed for exam 6
      expect(await noticePrintAdjustments(6, header(list), notify: said.add), isNull);
      expect(said, hasLength(1));
      // a different set is said again
      expect(await noticePrintAdjustments(6, header(list.take(1).toList()), notify: said.add), adjustmentText(list.first));
    });

    test('the device remembers what was seen across a restart of the app', () async {
      final said = <String>[];
      SeenDesignAdjustments.remember(7, real());
      await Future<void>.delayed(Duration.zero);
      SeenDesignAdjustments.clear();
      expect(await noticePrintAdjustments(7, header(real()), notify: said.add), isNull);
    });

    test('no header, an empty list or an unreadable one: nothing said', () async {
      final said = <String>[];
      expect(await noticePrintAdjustments(1, const {}, notify: said.add), isNull);
      expect(await noticePrintAdjustments(1, const {'x-design-adjustments': ['%%%']}, notify: said.add), isNull);
      expect(await noticePrintAdjustments(1, header(const []), notify: said.add), isNull);
      expect(said, isEmpty);
    });

    test('the print goes through without the header', () async {
      final api = _PdfServer(const {});
      final (bytes, fail) = await AnswerSheetApi(api).sheetsPdf(3, {'layout': 'NB2'});
      expect(fail, isNull);
      expect(bytes!.length, 5);
    });
  });
}

/// A server answering a PDF to `postForBytes`, with [headers].
class _PdfServer implements ApiClient {
  _PdfServer(this.headers);
  final Map<String, List<String>> headers;

  @override
  dynamic noSuchMethod(Invocation i) {
    if (i.memberName == #postForBytes) {
      final on = i.namedArguments[#onHeaders] as void Function(Map<String, List<String>>)?;
      on?.call(headers);
      return Future<Uint8List>.value(Uint8List.fromList('%PDF-'.codeUnits));
    }
    return super.noSuchMethod(i);
  }
}
