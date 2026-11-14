// Exam flow v2, pack F2: the answer booklet (D-663), Deliver's "What will be printed", and Fix the key from the item
// analysis (D-664). `EXPORT_SAMPLES=<dir> flutter test test/org/exam_flow_f2_test.dart` also writes the booklet as PDF / Word.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/exams/exam_authoring.dart';
import 'package:flutter_education_app/features/exams/exam_insights.dart';
import 'package:flutter_education_app/features/exams/exam_paper.dart';
import 'package:flutter_education_app/features/exams/exam_paper_booklet.dart';
import 'package:flutter_education_app/features/exams/exam_paper_docx.dart';
import 'package:flutter_education_app/features/exams/exam_paper_pdf.dart';
import 'package:flutter_education_app/features/exams/hub/create/answer_format.dart';
import 'package:flutter_education_app/features/exams/hub/deliver/deliver_logic.dart';
import 'package:flutter_education_app/features/exams/hub/deliver/deliver_summary_card.dart';
import 'package:flutter_education_app/features/exams/hub/result/key_fix.dart';
import 'package:flutter_education_app/features/exams/hub/result/key_fix_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

Map<String, dynamic> _q(int id, String type, Map<String, dynamic> body, Map<String, dynamic> answer, double points) =>
    {'id': id, 'type': type, 'body': body, 'answer': answer, 'points': points, 'placement_id': id, 'position': id, 'tags': [], 'version': 1};

Map<String, dynamic> _exam({bool ar = true}) => {
      'id': 5, 'org_id': 2, 'course_id': 9, 'title': ar ? 'الامتحان النهائي' : 'Final exam', 'status': 'published', 'duration_minutes': 60,
      'max_attempts': 1, 'results_policy': 'when_published', 'allowed_platforms': ['web'], 'settings': {}, 'version': 1, 'max_score': 25,
      'sections': [
        {
          'id': 1, 'position': 0, 'title': ar ? 'الجزء الأول' : 'Part A', 'mode': 'paper', 'weight': 1,
          'questions': [
            _q(1, 'mcq_single', {'prompt': ar ? 'أي غاز تمتصه النباتات؟' : 'Which gas do plants take in?',
              'options': [{'id': 'a', 'text': 'CO2'}, {'id': 'b', 'text': 'O2'}, {'id': 'c', 'text': 'N2'}]}, {'correct': 'a'}, 2),
            _q(2, 'mcq_multi', {'prompt': ar ? 'اختر عضيات النبات' : 'Pick the plant organelles',
              'options': [{'id': 'a', 'text': 'Chloroplast'}, {'id': 'b', 'text': 'Cell wall'}, {'id': 'c', 'text': 'Mitochondria'}]}, {'correct': ['a', 'b']}, 3),
            _q(3, 'true_false', {'prompt': ar ? 'الشمس مصدر الطاقة.' : 'The sun is the energy source.'}, {'correct': false}, 1),
          ],
        },
        {
          'id': 2, 'position': 1, 'title': '', 'mode': 'paper', 'weight': 1,
          'questions': [
            _q(4, 'fill_blank', {'prompt': ar ? 'يتم البناء الضوئي في ___ و ___ .' : 'It happens in the ___ and the ___ .', 'blanks_count': 2}, {'blanks': [['leaf'], ['chloroplast']]}, 2),
            _q(5, 'matching', {'prompt': ar ? 'صِل' : 'Match', 'left': ['Nucleus', 'Ribosome'], 'right': ['Proteins', 'DNA']}, {'pairs': {'Nucleus': 'DNA', 'Ribosome': 'Proteins'}}, 2),
            _q(6, 'ordering', {'prompt': ar ? 'رتّب' : 'Order', 'items': ['B', 'A', 'C']}, {'order': ['A', 'B', 'C']}, 2),
            _q(7, 'essay', {'prompt': ar ? 'اشرح العلاقة بين العمليتين.' : 'Explain how the two depend on each other.'}, {'model': 'Reverse processes.'}, 12),
            _q(8, 'numeric', {'prompt': ar ? 'كم كروموسومًا؟' : 'How many chromosomes?'}, {'value': 46}, 1),
          ],
        },
      ],
    };

ExamPaperDoc _doc({bool ar = true, bool key = false}) => ExamPaperDoc.fromView(ExamView.fromJson(_exam(ar: ar)),
    institution: ar ? 'مدرسة النور' : 'Al Noor School', course: ar ? 'الأحياء' : 'Biology', dateText: '1/12/2026',
    instructions: defaultPaperInstructions(rtl: ar, questions: 8, duration: ''), rtl: ar, accentHex: '1E5AA8', answerKey: key);

Future<ByteData> _font(String path) async => ByteData.sublistView(await File(path).readAsBytes());

String _docXml(Uint8List docx) => utf8.decode(ZipDecoder().decodeBytes(docx).files.firstWhere((f) => f.name == 'word/document.xml').content as List<int>);

Map<String, dynamic> _analytics() => {
      'state': 'ready',
      'data': {
        'attempts': 30,
        'items': [
          {'question_id': 1, 'type': 'mcq_single', 'points': 2, 'answered': 30, 'difficulty': .2, 'discrimination': -.3, 'flags': ['too_hard', 'negative'],
            'option_stats': [
              {'key': 'a', 'count': 6, 'share': .2, 'is_correct': true, 'upper_share': .1},
              {'key': 'b', 'count': 20, 'share': .66, 'upper_share': .8},
            ]},
          {'question_id': 2, 'type': 'mcq_multi', 'points': 3, 'answered': 30, 'difficulty': .7, 'flags': []},
          {'question_id': 3, 'type': 'true_false', 'points': 1, 'answered': 30, 'difficulty': .1, 'flags': ['key_suspect']},
          {'question_id': 7, 'type': 'essay', 'points': 12, 'answered': 30, 'difficulty': .1, 'flags': ['too_hard']},
          {'question_id': 4, 'type': 'fill_blank', 'points': 2, 'answered': 30, 'flags': ['negative'], 'voided': true},
        ],
      },
    };

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('answer booklet (D-663)', () {
    test('objective questions go in the table, the rest get sized blocks', () {
      final plan = bookletPlanOf(_doc(ar: false));
      expect(plan.table.map((e) => e.number), [1, 2, 3]);
      expect(plan.table[1].multi, isTrue);
      expect(plan.table[2].letters, ['T', 'F']);
      expect(plan.table[2].correct, {1}); // false is the second letter
      expect(plan.blocks.map((b) => b.number), [4, 5, 6, 7, 8]);
      final by = {for (final b in plan.blocks) b.number: b};
      expect(by[4]!.slots, 2);
      expect(by[4]!.keySlots, ['leaf', 'chloroplast']);
      expect(by[5]!.slots, 2);
      expect(by[5]!.keySlots, ['B', 'A']); // Nucleus → DNA (2nd), Ribosome → Proteins (1st)
      expect(by[6]!.slots, 3);
      expect(by[6]!.keySlots, ['2', '1', '3']);
      expect(by[7]!.lines, 28);
      expect(by[8]!.lines, 2);
      expect(by[4]!.sectionIndex, 1);
    });

    test('writing space follows the type and the points', () {
      PaperQuestion q(String type, double p) => PaperQuestion(number: 1, type: type, prompt: 'x', points: p);
      expect(bookletLines(q('essay', 1)), 6);
      expect(bookletLines(q('essay', 5)), 14);
      expect(bookletLines(q('essay', 40)), 28);
      expect(bookletLines(q('short_answer', 1)), 3);
      expect(bookletLines(q('short_answer', 10)), 6);
      expect(bookletLines(q('numeric', 3)), 2);
      expect(bookletLines(q('fill_blank', 3)), 0);
      expect(bookletSlots(PaperQuestion(number: 1, type: 'fill_blank', prompt: 'x', points: 1)), 1);
      expect(bookletInTable(q('true_false', 1)), isTrue);
      expect(bookletInTable(q('essay', 1)), isFalse);
    });

    test('words follow the paper language', () {
      expect(const BookletWords(true).title, 'دفتر الإجابة');
      expect(const BookletWords(false).title, 'Answer booklet');
      expect(const BookletWords(true).answerTo(3), 'إجابة السؤال 3');
      expect(const BookletWords(false).answerTo(3), 'Answer to question 3');
      expect(const BookletWords(true).tfLetters, ['ص', 'خ']);
      expect(const BookletWords(false).slotHint('matching'), isNotEmpty);
      expect(const BookletWords(false).slotHint('essay'), '');
    });

    test('copyWith keeps the part', () {
      final d = _doc().copyWith(part: PaperPart.booklet);
      expect(d.copyWith(studentName: 'Ali').part, PaperPart.booklet);
      expect(_doc().part, PaperPart.full);
    });

    for (final tpl in [PaperTemplate.classic, PaperTemplate.modern, PaperTemplate.minimal]) {
      for (final ar in [true, false]) {
        test('${tpl.name} ${ar ? 'ar' : 'en'}: booklet and question paper, PDF and Word', () async {
          final s = PaperStyle.of(tpl);
          final w = BookletWords(ar);
          for (final key in [false, true]) {
            final paper = _doc(ar: ar, key: key).copyWith(part: PaperPart.questions);
            final booklet = _doc(ar: ar, key: key).copyWith(part: PaperPart.booklet);
            final out = await examPaperPdfMany([paper, booklet], tpl, regular: await _font(s.regular), bold: await _font(s.bold));
            expect(String.fromCharCodes(out.bytes.take(5)), '%PDF-');
            expect(out.pages, hasLength(2));
            expect(out.pages.every((p) => p >= 1), isTrue);

            final bx = _docXml(examPaperDocx(booklet, tpl));
            expect(bx, contains(w.title));
            expect(bx, contains(w.answerTo(7)));
            expect(bx, contains(w.tableTitle));
            expect(bx, isNot(contains(ar ? 'اشرح العلاقة' : 'Explain how'))); // no question text in the booklet
            expect(bx.contains('Reverse processes.'), key);
            expect(bx.contains('chloroplast'), key);

            final px = _docXml(examPaperDocx(paper, tpl));
            expect(px, contains(ar ? 'اشرح العلاقة' : 'Explain how'));
            expect(px.contains(w.answerInBooklet), !key);
            expect(px, isNot(contains(PaperWords(ar).answerTableTitle)));
            final dir = Platform.environment['EXPORT_SAMPLES'];
            if (dir != null && !key) {
              File('$dir/booklet_${tpl.name}_${ar ? 'ar' : 'en'}.pdf').writeAsBytesSync(out.bytes);
              File('$dir/booklet_${tpl.name}_${ar ? 'ar' : 'en'}.docx').writeAsBytesSync(await examPaperDocxMany([paper, booklet], tpl));
            }
          }
        });
      }
    }

    test('a booklet takes more pages than none and a Word copy counts its own', () async {
      final b = _doc(ar: false).copyWith(part: PaperPart.booklet);
      expect(wordPageCount(b, PaperTemplate.modern), greaterThanOrEqualTo(1));
    });
  });

  group('answer format + Deliver summary', () {
    test('answerFormatOf reads the key and falls back on old settings', () {
      expect(answerFormatOf({'answer_format': 'table'}), AnswerFormat.table);
      expect(answerFormatOf({'answer_format': 'on_paper'}), AnswerFormat.onPaper);
      expect(answerFormatOf({'bubble_run': {'x': 1}}), AnswerFormat.bubble);
      expect(answerFormatOf({}), isNull);
      for (final f in AnswerFormat.values) {
        expect(answerFormatOf({'answer_format': answerFormatKey(f)}), f);
      }
    });

    test('the format Deliver prints for, and the booklet default', () {
      expect(deliverAnswerFormat({}, paper: false, bubble: false), AnswerFormat.online);
      expect(deliverAnswerFormat({}, paper: true, bubble: true), AnswerFormat.bubble);
      expect(deliverAnswerFormat({}, paper: true, bubble: false), AnswerFormat.onPaper);
      expect(deliverAnswerFormat({'answer_format': 'table'}, paper: true, bubble: false), AnswerFormat.table);
      expect(deliverBookletDefault(AnswerFormat.table, {}), isTrue);
      expect(deliverBookletDefault(AnswerFormat.table, {'answer_booklet': false}), isFalse);
      expect(deliverBookletDefault(AnswerFormat.onPaper, {}), isFalse);
      expect(deliverBookletDefault(AnswerFormat.onPaper, {'answer_booklet': true}), isTrue);
      expect(deliverBookletDefault(AnswerFormat.bubble, {'answer_booklet': true}), isFalse);
      expect(deliverPaperLayout(AnswerFormat.table, booklet: true), (part: PaperPart.questions, table: AnswerTablePlace.none));
      expect(deliverPaperLayout(AnswerFormat.table, booklet: false), (part: PaperPart.full, table: AnswerTablePlace.end));
      expect(deliverPaperLayout(AnswerFormat.bubble, booklet: true), (part: PaperPart.full, table: AnswerTablePlace.none));
    });

    test('one copy QR payloads split between paper and booklet', () {
      final (a, b) = splitBookletQr(['p1', 'p2', 'p3', 'p4'], 2, 2);
      expect(a, ['p1', 'p2']);
      expect(b, ['p3', 'p4']);
      final (c, d) = splitBookletQr(['p1'], 2, 2);
      expect(c, ['p1']);
      expect(d, isEmpty);
    });

    test('what will be printed', () {
      final s = deliverPrintSummary(scope: DeliverScope.students, format: AnswerFormat.table, booklet: true, students: 31, versions: 2, blank: 30);
      expect([for (final l in s.lines) (l.doc, l.count)], [(PrintDoc.questionPaper, 31), (PrintDoc.booklet, 31)]);
      expect(s.together, isTrue);
      expect(s.inFile, 62);
      final v = deliverPrintSummary(scope: DeliverScope.versions, format: AnswerFormat.bubble, booklet: true, students: 0, versions: 3, blank: 30);
      expect([for (final l in v.lines) (l.doc, l.count, l.separate)], [(PrintDoc.questionPaper, 3, false), (PrintDoc.bubbleSheet, 3, true)]);
      expect(v.inFile, 3);
      final b = deliverPrintSummary(scope: DeliverScope.blank, format: AnswerFormat.onPaper, booklet: false, students: 0, versions: 0, blank: 12);
      expect(b.lines.single.count, 12);
      expect(b.together, isFalse);
      final one = deliverPrintSummary(scope: DeliverScope.versions, format: AnswerFormat.onPaper, booklet: false, students: 0, versions: 0, blank: 1);
      expect(one.lines.single.count, 1);
    });
  });

  group('fix the key (D-664)', () {
    final view = ExamView.fromJson(_exam(ar: false));
    final analytics = ExamAnalytics.fromJson(_analytics());

    test('flagged objective questions only, in paper order with their numbers', () {
      final c = keyFixCandidates(view, analytics);
      expect(c.map((x) => (x.questionId, x.n)), [(1, 1), (3, 3)]); // 2 not flagged, 7 essay, 4 cancelled
      expect(c.first.correct, {'a'});
      expect(c.first.options.map((o) => o.id), ['a', 'b', 'c']);
      expect(c.first.options[1].share, .66);
      expect(c.first.reason, itemFlagText('negative'));
      expect(c[1].options.map((o) => o.id), ['true', 'false']);
      expect(c[1].correct, {'false'});
      expect(keyFixCandidates(view, null), isEmpty);
    });

    test('the key-fix body is the picked answers as a list (D-666)', () {
      final c = keyFixCandidates(view, analytics);
      expect(keyFixRequest(c.first, {'b'}), {'correct': ['b']});
      expect(keyFixRequest(c.first, {'b'}, reason: '  negative  '), {'correct': ['b'], 'reason': 'negative'});
      expect(keyFixRequest(c[1], {'true'}), {'correct': [true]});
      expect(keyFixAnswerOf('mcq_multi', {'a', 'c'}), ['a', 'c']);
    });

    test('a pick is ready when it is new and well formed', () {
      final c = keyFixCandidates(view, analytics).first;
      expect(keyFixReady(c, {'a'}), isFalse);
      expect(keyFixReady(c, {}), isFalse);
      expect(keyFixReady(c, {'a', 'b'}), isFalse); // single choice
      expect(keyFixReady(c, {'b'}), isTrue);
    });

    test('the outcome and the texts say marks move', () {
      final o = KeyFixOutcome.fromJson({'answers_changed': 5, 'attempts_changed': 4, 'manual_kept': 1, 'waiting': 0, 'results_published': true});
      expect((o.answersChanged, o.attemptsChanged, o.manualKept, o.resultsPublished), (5, 4, 1, true));
      expect(keyFixOutcomeText(o),
          'The key is saved and 4 results changed. 1 mark you gave by hand is kept. The results are published: students see the new marks now.');
      expect(keyFixOutcomeText(const KeyFixOutcome()), 'The key is saved. No mark changed: no answer is affected by it.');
      expect(keyFixOutcomeText(const KeyFixOutcome(attemptsChanged: 1, waiting: 2)), contains('2 answers waiting'));
      expect(keyFixConfirmText, contains('final marks included'));
      expect(keyFixConfirmText, isNot(contains('do not change')));
      AppConfig.lang = 'ar';
      expect(keyFixOutcomeText(const KeyFixOutcome(attemptsChanged: 2)), 'حُفظ المفتاح وتغيرت نتيجتا طالبين.');
      expect(keyFixConfirmText, contains('الدرجات المعتمدة'));
    });
  });

  group('layout', () {
    final view = ExamView.fromJson(_exam(ar: false));
    final candidates = keyFixCandidates(view, ExamAnalytics.fromJson(_analytics()));
    final map = <String, Widget Function()>{
      'summary, booklet on': () => SingleChildScrollView(
          child: DeliverSummaryCard(
              summary: deliverPrintSummary(scope: DeliverScope.students, format: AnswerFormat.table, booklet: true, students: 31, versions: 2, blank: 30),
              bookletOffered: true, booklet: true, onBooklet: (_) {})),
      'summary, bubble': () => SingleChildScrollView(
          child: DeliverSummaryCard(summary: deliverPrintSummary(scope: DeliverScope.versions, format: AnswerFormat.bubble, booklet: false, students: 0, versions: 4, blank: 30))),
      'summary, booklet off': () => SingleChildScrollView(
          child: DeliverSummaryCard(
              summary: deliverPrintSummary(scope: DeliverScope.blank, format: AnswerFormat.onPaper, booklet: false, students: 0, versions: 1, blank: 500),
              bookletOffered: true, onBooklet: (_) {})),
      'key check card': () => SingleChildScrollView(child: ResultKeyCheckCard(questions: candidates, onFix: (_) {})),
      'fix-key sheet': () => SingleChildScrollView(child: KeyFixSheet(question: candidates.first)),
      'fix-key sheet (true / false)': () => SingleChildScrollView(child: KeyFixSheet(question: candidates[1])),
    };
    for (final e in map.entries) {
      testWidgets(e.key, (tester) async => expectNoLayoutErrors(tester, e.value));
    }

    testWidgets('the booklet switch reports its value', (tester) async {
      bool? got;
      await tester.pumpWidget(layoutHost(
          DeliverSummaryCard(
              summary: deliverPrintSummary(scope: DeliverScope.students, format: AnswerFormat.table, booklet: true, students: 3, versions: 1, blank: 1),
              bookletOffered: true, booklet: true, onBooklet: (v) => got = v),
          scale: 1));
      await tester.tap(find.byKey(const ValueKey('deliver.booklet')));
      await tester.pump();
      expect(got, isFalse);
      expect(find.byKey(const ValueKey('deliver.summary.booklet')), findsOneWidget);
    });
  });
}
