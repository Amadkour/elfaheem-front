// The paper exam's answer sheets (D-687, folded into D-697): which wizard steps apply, what the plan saves (v2 and the
// old v1), the NB2 / people payloads (contract B1 / B2), the scan quality rejections (B3), and the drawn parts.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/exams/exam_engine_api.dart';
import 'package:flutter_education_app/features/exams/exam_quick.dart';
import 'package:flutter_education_app/features/exams/hub/create/answer_sheet_widgets.dart';
import 'package:flutter_education_app/features/exams/hub/create/exam_create_logic.dart';
import 'package:flutter_education_app/features/exams/paper/exam_setup.dart';
import 'package:flutter_education_app/features/exams/paper/scan/scan_files.dart';
import 'package:flutter_education_app/features/exams/paper/scan/scan_upload_view.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

const _course = (courseId: 7, orgId: null as int?, name: 'Biology');
const _personal = (courseId: null as int?, orgId: null as int?, name: 'Personal');
const _sheet = OmrTemplateItem(id: 1, version: 2, name: 'Bubble 40', questions: 40, options: 4);
const _own = OmrTemplateItem(id: 3, version: 1, name: 'Mine', questions: 20, kind: 'auto_bubble');

QuickQuestion _mcq() => QuickQuestion.mcq()
  ..prompt = 'p'
  ..correct = 'a'
  ..options[0].text = 'x'
  ..options[1].text = 'y';

QuickQuestion _short() => QuickQuestion.ofType('short_answer')
  ..prompt = 'Why?'
  ..keyText = 'Because.';

ExamCreatePlan _plan(AnswerFormat f, {bool course = true, bool written = false, bool mcq = true}) {
  final p = ExamCreatePlan(place: course ? _course : _personal, title: 'Exam')..setAnswer(f);
  if (mcq) p.exam.questions.add(_mcq());
  if (written) p.exam.questions.add(_short());
  if (p.isBubble) p.template = _sheet;
  return p;
}

List<CreateStep> _steps(ExamCreatePlan p) => createSteps(p, whereNeeded: false, omrOn: true, identifiersOn: true);

void main() {
  setUp(() => AppConfig.lang = 'en');

  // D-697 replaced F1's rules here: every paper exam chooses its copies, the written answers go on the NB2 sheet in
  // layouts 1 to 3 (no question blocks a bubble exam any more), and a course's students need no step of their own.
  group('which steps apply', () {
    test('online: no sheets, no students', () {
      final p = _plan(AnswerFormat.online, written: true);
      expect(_steps(p), [CreateStep.answer, CreateStep.questions, CreateStep.publish]);
      expect(p.sheetPlan, isNull);
      expect(p.settingsJson.containsKey('sheet_plan'), isFalse);
    });

    test('an answer table reads as layout 1, its paper part in the booklet', () {
      final p = _plan(AnswerFormat.table, written: true);
      expect(p.layout, PaperLayout.allInPaper);
      expect(p.writtenSheet, WrittenSheet.booklet);
      expect(p.wantsAnswerSheet, isFalse);
      expect(_steps(p), contains(CreateStep.sheets));
    });

    test('on paper with written questions: the NB2 sheet holds them, per student by default with a course', () {
      final p = _plan(AnswerFormat.onPaper, written: true);
      expect(p.writtenQuestionCount, 1);
      expect(p.wantsAnswerSheet, isTrue);
      expect(p.effectiveCopies, SheetCopies.personal);
      expect(_steps(p), [CreateStep.answer, CreateStep.questions, CreateStep.layout, CreateStep.sheets, CreateStep.attributes, CreateStep.design, CreateStep.review]);
    });

    test('the kill switch hides the NB2 sheet and the answer-sheet step', () {
      final p = _plan(AnswerFormat.onPaper, written: true)..answerSheetOn = false;
      expect(p.wantsAnswerSheet, isFalse);
      expect(_steps(p), isNot(contains(CreateStep.layout)));
    });

    test('bubble: the copies are always asked, whoever prints the sheets', () {
      final p = _plan(AnswerFormat.bubble);
      expect(_steps(p), contains(CreateStep.sheets));
      p.bubbleSource = BubbleSource.have;
      expect(p.printsBubbleSheets, isFalse);
      expect(_steps(p), contains(CreateStep.sheets));
      p
        ..bubbleSource = BubbleSource.print
        ..template = _own;
      expect(p.printsBubbleSheets, isFalse);
      expect(p.versionsAllowed, isFalse);
    });

    test('bubble with written questions: they are answered on the paper, nothing blocks', () {
      final p = _plan(AnswerFormat.bubble, written: true);
      expect(bubbleCheckOf(p).blocks, isFalse);
      expect(p.bubbleQuestionCount, 1);
      expect(p.wantsAnswerSheet, isTrue);
      p.answerSheetOn = false;
      expect(bubbleCheckOf(p).blocks, isFalse);
    });

    test('no course: generic by default; per student needs the uploaded list before Continue', () {
      final p = _plan(AnswerFormat.onPaper, course: false, written: true);
      expect(p.effectiveCopies, SheetCopies.generic);
      expect(_steps(p), isNot(contains(CreateStep.identify)));
      p.setCopies(SheetCopies.personal);
      expect(p.needsPeopleFile, isTrue);
      expect(_steps(p), containsAllInOrder([CreateStep.sheets, CreateStep.identify, CreateStep.attributes]));
      expect(createStepReady(CreateStep.identify, p), isFalse);
      p.peopleCount = 30;
      expect(createStepReady(CreateStep.identify, p), isTrue);
    });

    test('generic copies of a course ask what the ID boxes are matched on', () {
      final p = _plan(AnswerFormat.bubble)..setCopies(SheetCopies.generic);
      expect(asksIdSource(p), isTrue);
      p.setCopies(SheetCopies.personal);
      expect(asksIdSource(p), isFalse);
      expect(asksIdSource(_plan(AnswerFormat.bubble, course: false)), isFalse);
    });
  });

  group('the saved plan', () {
    test('settings.sheet_plan is v2 and reads back in the terms Deliver prints with', () {
      final p = _plan(AnswerFormat.bubble, written: true)..idSource = IdSource.system;
      final json = p.settingsJson['sheet_plan'] as Map<String, dynamic>;
      expect(json, {
        'v': 2,
        'answer_layout': 'paper_plus_bubble_objective',
        'written_sheet': 'NB2',
        'bubble': {'source': 'template', 'ids': [1], 'print': true},
        'copies': 'per_student',
        'students': {'source': 'course'},
        'id_source': 'system',
        'paper_design': null,
      });
      final back = SheetPlan.ofSettings({'sheet_plan': json})!;
      expect(back.bubble, BubbleSource.print);
      expect(back.answerSheet, isTrue);
      expect(back.personal, isTrue);
      expect(back.fromFile, isFalse);
      expect(back.idSource, IdSource.system);
      expect(SheetPlan.ofSettings({'paper_plan': {}}), isNull);
    });

    test('an F1 (v1) plan still reads as it did', () {
      final back = SheetPlan.ofSettings({
        'sheet_plan': {'bubble': 'have', 'answer_sheet': 'NB2', 'copies': 'personal', 'students': 'file'},
      })!;
      expect((back.bubble, back.answerSheet, back.personal, back.fromFile), (BubbleSource.have, true, true, true));
    });

    test('the NB2 request (contract B1)', () {
      expect(answerSheetsBody(const SheetPlan(answerSheet: true, copies: SheetCopies.generic), blank: 900),
          {'layout': 'NB2', 'copies': 'generic', 'blank': kMaxGenericSheets});
      expect(answerSheetsBody(const SheetPlan(answerSheet: true, copies: SheetCopies.personal, idSource: IdSource.academic), studentIds: [12, 15]),
          {'layout': 'NB2', 'copies': 'personal', 'students': 'course', 'id_source': 'academic', 'student_ids': [12, 15]});
      expect(answerSheetsBody(const SheetPlan(answerSheet: true, copies: SheetCopies.personal, fromFile: true), lang: 'ar'),
          {'layout': 'NB2', 'copies': 'personal', 'students': 'file', 'lang': 'ar'});
    });

    test('the REAL people list reply (fixtures/payloads/autograde/people_file.json)', () {
      final j = jsonDecode(File('test/fixtures/payloads/autograde/people_file.json').readAsStringSync()) as Map;
      final u = PeopleUpload.fromJson(Map<String, dynamic>.from(j['payload'] as Map));
      expect((u.added, u.updated, u.total), (2, 0, 2));
      expect(u.skipped, isEmpty);
      expect(u.names, hasLength(2));
    });

    test('the people list answer and its refusals (contract B2)', () {
      final u = PeopleUpload.fromJson({
        'added': 28,
        'updated': 2,
        'total': 30,
        'skipped': [
          {'row': 7, 'code': 'empty_row'},
        ],
        'people': [
          {'id': -1, 'name': 'Sara Nabil', 'code': '2041', 'source': 'list'},
        ],
      });
      expect((u.added, u.updated, u.total), (28, 2, 30));
      expect(u.skipped.single.row, 7);
      expect(u.names, ['Sara Nabil']);
      final bad = EngineResult.fail(422, 'bad_people_file', 'x', {
        'problems': [
          {'row': 0, 'code': 'no_columns'},
        ],
      });
      expect(answerSheetErrorText(bad), contains('column'));
      expect(answerSheetErrorText(EngineResult.fail(409, 'run_has_course', 'x')), contains('course'));
    });
  });

  group('scan quality (contract B3)', () {
    test('a refused NB2 photo is a file-level failure to retake', () {
      for (final code in kScanRetakeCodes) {
        expect(scanFileLevelFailure(EngineResult.fail(422, code, code)), isTrue);
        expect(scanStopFailure(EngineResult.fail(422, code, code)), isFalse);
      }
      final marks = scanRetakeText(EngineResult.fail(422, 'sheet_marks_missing', 'x', {'file': 'a.jpg', 'found': 3}))!;
      expect(marks, contains('Retake this page'));
      expect(marks, contains('3 of 4'));
      expect(scanSendErrorText(EngineResult.fail(422, 'page_blurry', 'x')), contains('blurred'));
      expect(scanRetakeText(EngineResult.fail(422, 'bad_image', 'x')), isNull);
    });

    test('only the blurred page fails; the rest of the part goes through', () async {
      final files = [for (final n in ['p1.jpg', 'p2.jpg', 'p3.jpg']) ScanSourceFile.bytes(n, Uint8List.fromList([1, 2, 3]))];
      final up = ScanUploader(
        files: files,
        prepare: (f) async => [(f.name, Uint8List.fromList([1, 2, 3]))],
        send: (part, batch) async {
          if (part.any((x) => x.$1 == 'p2.jpg')) return EngineResult.fail(422, 'page_blurry', 'blurred', {'file': 'p2.jpg'});
          return EngineResult.ok({'batch_id': 5, 'pages': part.length, 'duplicates': 0});
        },
        errorText: scanSendErrorText,
        prepareErrorText: (c) => c,
      );
      await up.run();
      expect(up.failures.length, 1);
      expect(up.failures.single.file.name, 'p2.jpg');
      expect(up.failures.single.retake, isTrue);
      expect(up.sent.length, 2);
    });
  });

  group('layout', () {
    testWidgets('bubble source', (t) async => expectNoLayoutErrors(t, () => SingleChildScrollView(child: CreateBubbleSourceBody(value: BubbleSource.have, onPick: (_) {}))));

    testWidgets('ID source', (t) async => expectNoLayoutErrors(t, () => SingleChildScrollView(child: CreateIdSourceRow(value: IdSource.system, onPick: (_) {}))));

    testWidgets('people list', (t) async => expectNoLayoutErrors(
        t,
        () => SingleChildScrollView(
              child: Column(children: [
                PeopleFileBody(onPick: () {}),
                PeopleFileBody(
                  upload: const PeopleUpload(added: 28, updated: 2, total: 30, skipped: [(row: 7, code: 'empty_row'), (row: 9, code: 'no_name')], names: ['Sara Nabil', 'Omar Khaled Abdelrahman']),
                  error: 'The file is larger than 2 MB',
                  onPick: () {},
                ),
              ]),
            )));

    testWidgets('deliver card', (t) async => expectNoLayoutErrors(
        t,
        () => SingleChildScrollView(
              child: Column(children: [
                AnswerSheetPrintCard(plan: const SheetPlan(answerSheet: true), blank: 30, onBlank: (_) {}, onDownload: () {}),
                AnswerSheetPrintCard(
                    plan: const SheetPlan(answerSheet: true, copies: SheetCopies.personal), blank: 30, onBlank: (_) {}, onDownload: () {}, error: 'Choose the students first'),
              ]),
            )));

    testWidgets('retake list', (t) async => expectNoLayoutErrors(t, () {
          final f = ScanSourceFile.bytes('IMG_20261112_101010_with_a_long_name.jpg', Uint8List(3));
          return SingleChildScrollView(
              child: ScanUploadFailures(failures: [
            ScanFailure(f, scanRetakeText(EngineResult.fail(422, 'sheet_marks_missing', 'x', {'found': 2}))!, code: 'sheet_marks_missing', status: 422),
            ScanFailure(ScanSourceFile.bytes('b.jpg', Uint8List(3)), 'Too large', code: 'image_too_large', status: 413),
          ], onRetry: () {}));
        }));
  });
}
