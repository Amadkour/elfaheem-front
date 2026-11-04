// Paper versions, the answer table and per-student copies (exam creation, pack F3):
//   • pure: a version's question_order / option_orders applied to a paper, request bodies, print-plan parsing, the
//     answer-table rows;
//   • the calls over the fake backend (versions, answer key, print plan);
//   • per-student copies: pages counted by laying a version out once, the plan asked for that many pages, one paper
//     per plan item with a QR payload on EVERY page, all merged into one PDF;
//   • the new widgets under the layout harness.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_paper.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_paper_docx.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_paper_pdf.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_paper_sheet.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_versions.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_versions_sheet.dart';
import 'package:flutter_education_app/design/app_switch.dart' show AppSwitchTile;
import 'package:flutter_education_app/features/shared/exam_engine/paper/exam_setup.dart' show versionsBubbleText;
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../ui/layout_harness.dart';

PaperQuestion _mcq(int id, int n, List<String> opts, Set<int> correct) =>
    PaperQuestion(id: id, number: n, type: 'mcq_single', prompt: 'Q$id', points: 1, options: opts, correct: correct);

ExamPaperDoc _paper({bool rtl = false, int essays = 0}) => ExamPaperDoc(
      institution: 'School', course: 'Biology', title: 'Final', dateText: '1/12/2026', durationText: '60 min', total: 10, rtl: rtl, instructions: const [],
      sections: [
        PaperSection(title: 'A', instructions: '', questions: [_mcq(1, 1, ['a', 'b', 'c', 'd'], {1}), _mcq(2, 2, ['w', 'x', 'y'], {0})]),
        PaperSection(title: 'B', instructions: '', questions: [
          _mcq(3, 3, ['p', 'q'], {1}),
          for (var i = 0; i < essays; i++) PaperQuestion(id: 10 + i, number: 4 + i, type: 'essay', prompt: 'Explain $i', points: 12),
        ]),
      ],
    );

const _ver = {
  'code': 'B', 'label': null, 'copies': 25, 'seed': 7,
  'question_order': [2, 1, 3],
  'option_orders': {'1': [3, 1, 0, 2], '3': [1, 0]},
  'key': {'1': 'b'},
};

Future<ByteData> _font(String path) async => ByteData.sublistView(await File(path).readAsBytes());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => AppConfig.lang = 'en');

  group('applyVersion', () {
    test('questions follow question_order inside their section and are numbered again', () {
      final d = applyVersion(_paper(), ExamVersion.fromJson(_ver));
      expect(d.version, 'B');
      expect([for (final s in d.sections) [for (final q in s.questions) q.id]], [[2, 1], [3]], reason: 'sections stay in order');
      expect([for (final s in d.sections) for (final q in s.questions) q.number], [1, 2, 3]);
    });

    test('options follow option_orders and the key moves with them', () {
      final d = applyVersion(_paper(), ExamVersion.fromJson(_ver));
      final q1 = d.sections[0].questions.firstWhere((q) => q.id == 1);
      expect(q1.options, ['d', 'b', 'a', 'c']);
      expect(q1.correct, {1}, reason: 'b was index 1 and is printed second');
      final q3 = d.sections[1].questions.single;
      expect(q3.options, ['q', 'p']);
      expect(q3.correct, {0});
      final q2 = d.sections[0].questions.firstWhere((q) => q.id == 2);
      expect(q2.options, ['w', 'x', 'y'], reason: 'no order for it: unchanged');
    });

    test('a version without orders keeps the exam order; a bad option order is ignored', () {
      final plain = applyVersion(_paper(), ExamVersion.fromJson({'code': 'A', 'question_order': null, 'option_orders': {}}));
      expect(plain.version, 'A');
      expect(plain.sections[0].questions.map((q) => q.id), [1, 2]);
      final bad = applyVersion(_paper(), ExamVersion.fromJson({'code': 'C', 'option_orders': {'1': [0, 9]}}));
      expect(bad.sections[0].questions.first.options, ['a', 'b', 'c', 'd']);
    });
  });

  group('requests and replies', () {
    test('versionBody clamps the count and spreads the copies', () {
      expect(versionBody(count: 3, shuffleQuestions: true, shuffleOptions: false, copies: 30), {
        'count': 3, 'shuffle_questions': true, 'shuffle_options': false, 'copies': {'A': 30, 'B': 30, 'C': 30},
      });
      expect(versionBody(count: 99, shuffleQuestions: false, shuffleOptions: false)['count'], kMaxVersions);
      expect(versionBody(count: 0, shuffleQuestions: false, shuffleOptions: false).containsKey('copies'), isFalse);
    });

    test('printPlanBody: named sends the students, blank the copies; pages are 1-40', () {
      expect(printPlanBody(named: true, studentIds: [4, 5], pages: 2, form: 'A'), {'mode': 'named', 'student_ids': [4, 5], 'pages': 2, 'form': 'A'});
      expect(printPlanBody(named: false, copies: 20, pages: 99), {'mode': 'blank', 'copies': 20, 'pages': 40});
    });

    test('PrintPlan.fromJson reads copies, students and one QR payload per page', () {
      final plan = PrintPlan.fromJson({
        'items': [
          {'copy_no': 1, 'form': 'A', 'student': {'id': 4, 'name': 'Sara', 'identifier_masked': '••12'}, 'pages': ['NBP1|x=1|p=1', 'NBP1|x=1|p=2']},
          {'copy_no': 2, 'form': 'B', 'student': null, 'pages': ['NBP1|x=1|p=1']},
        ],
      });
      expect(plan.items.length, 2);
      expect(plan.items[0].studentName, 'Sara');
      expect(plan.items[0].studentId, 4);
      expect(plan.items[1].studentId, isNull);
      expect(plan.qrCount, 3);
    });

    test('copiesFor: version applied, name set, QR per page (fewer pages keep their own)', () {
      final versions = ExamVersions.fromJson({'items': [_ver, {'code': 'A'}]});
      final plan = PrintPlan.fromJson({
        'items': [
          {'copy_no': 1, 'form': 'B', 'student': {'id': 4, 'name': 'Sara'}, 'pages': ['q1', 'q2', 'q3']},
          {'copy_no': 2, 'form': 'A', 'student': {'id': 5, 'name': 'Omar'}, 'pages': ['r1', 'r2', 'r3']},
        ],
      });
      final docs = copiesFor(_paper(), plan, versions, pagesOf: {'B': 3, 'A': 2});
      expect(docs[0].version, 'B');
      expect(docs[0].studentName, 'Sara');
      expect(docs[0].qrPages, ['q1', 'q2', 'q3']);
      expect(docs[1].qrPages, ['r1', 'r2'], reason: 'version A has two pages');
    });

    test('answerKeyItems and keyLinesOf', () {
      final items = answerKeyItems({'items': [{'n': 1, 'question_id': 3, 'type': 'mcq_single', 'points': 2, 'answer': 'x', 'display': 'ب'}]});
      expect(items.single.display, 'ب');
      expect(keyLinesOf(items).single.n, 1);
    });
  });

  group('answer table', () {
    test('rows for the choice questions only, letters by language, three groups per row', () {
      final d = _paper(essays: 2);
      final e = answerTableEntries(d);
      expect([for (final x in e) x.number], [1, 2, 3]);
      expect(e[1].letters, ['A', 'B', 'C']);
      expect(answerTableEntries(_paper(rtl: true)).first.letters.first, 'أ');
      final rows = answerTableRows([...e, ...e]);
      expect(rows.map((r) => r.length), [3, 3]);
      expect(answerTableRows(e, groups: 2).map((r) => r.length), [2, 1]);
    });
  });

  group('calls over the fake backend', () {
    late FakeApi fake;
    final seen = <String>[];
    setUp(() {
      seen.clear();
      fake = FakeApi({
        'GET /api/v1/exam/exams/5/versions': (_) => {'items': [_ver], 'shuffle_questions': true, 'shuffle_options': true},
        'POST /api/v1/exam/exams/5/versions': (o) {
          seen.add(jsonEncode(o.data));
          return {'items': [_ver], 'warnings': []};
        },
        'PUT /api/v1/exam/exams/5/versions/copies': (o) {
          seen.add(jsonEncode(o.data));
          return {'items': [_ver]};
        },
        'GET /api/v1/exam/exams/5/answer-key': (o) => {
              'form': o.queryParameters['form'],
              'items': [{'n': 1, 'question_id': 2, 'type': 'mcq_single', 'points': 1, 'answer': 'a', 'display': 'A'}],
            },
        'POST /api/v1/exam/exams/5/print-plan': (o) {
          final b = Map<String, dynamic>.from(o.data as Map);
          seen.add(jsonEncode(b));
          final ids = ((b['student_ids'] as List?) ?? [for (var i = 0; i < (b['copies'] as int); i++) 0]).cast<int>();
          return {
            'items': [
              for (var i = 0; i < ids.length; i++)
                {
                  'copy_no': i + 1,
                  'form': i.isEven ? 'A' : 'B',
                  'student': b['mode'] == 'named' ? {'id': ids[i], 'name': 'Student ${ids[i]}', 'identifier_masked': '••${ids[i]}'} : null,
                  'pages': [for (var p = 1; p <= (b['pages'] as int); p++) 'NBP1|x=5|f=${i.isEven ? 'A' : 'B'}|u=${ids[i]}|c=${i + 1}|p=$p|h=00'],
                },
            ],
          };
        },
      }, latency: const Duration(milliseconds: 5))
        ..install();
    });
    tearDown(() => fake.uninstall());

    test('versions, generate, copies, answer key', () async {
      final api = ExamVersionsApi();
      final v = ExamVersions.fromJson((await api.versions(5)).map);
      expect(v.items.single.code, 'B');
      expect(v.shuffleOptions, isTrue);
      expect((await api.generate(5, versionBody(count: 2, shuffleQuestions: true, shuffleOptions: true, copies: 25))).ok, isTrue);
      expect(seen.single, contains('"count":2'));
      expect((await api.setCopies(5, {'A': 25, 'B': 20})).ok, isTrue);
      final k = await api.answerKey(5, form: 'B');
      expect(answerKeyItems(k.map).single.display, 'A');
      expect(k.map['form'], 'B');
    });

    test('2 students x several pages: one QR per page of every copy, one merged PDF', () async {
      final regular = await _font('assets/fonts/plex/IBMPlexSansArabic-Regular.ttf'), bold = await _font('assets/fonts/plex/IBMPlexSansArabic-Bold.ttf');
      final versions = ExamVersions.fromJson({'items': [{'code': 'A'}, _ver]});
      final res = await buildPaperCopies(
          base: _paper(essays: 12), versions: versions, api: ExamVersionsApi(), examId: 5, tpl: PaperTemplate.minimal, regular: regular, bold: bold,
          named: true, studentIds: [7, 8]);
      expect(res.error, isNull);
      expect(res.copies, 2);
      final planned = jsonDecode(seen.last) as Map;
      final pages = planned['pages'] as int;
      expect(pages, greaterThanOrEqualTo(2), reason: 'the paper is long enough for several pages');
      expect(res.pages, inInclusiveRange(4, 2 * pages), reason: 'each copy has its own version pages (never more than the planned count), a QR on each');
      expect(res.bytes!.sublist(0, 4), [0x25, 0x50, 0x44, 0x46]);
    });

    test('a blank print asks for the copies', () async {
      final regular = await _font('assets/fonts/plex/IBMPlexSansArabic-Regular.ttf'), bold = await _font('assets/fonts/plex/IBMPlexSansArabic-Bold.ttf');
      final res = await buildPaperCopies(
          base: _paper(), versions: const ExamVersions(), api: ExamVersionsApi(), examId: 5, tpl: PaperTemplate.minimal, regular: regular, bold: bold,
          named: false, blank: 3);
      expect(res.copies, 3);
      expect(jsonDecode(seen.last), containsPair('mode', 'blank'));
    });

    test('Word copies: a zip with one document per student, the name in every header', () async {
      final regular = await _font('assets/fonts/plex/IBMPlexSansArabic-Regular.ttf'), bold = await _font('assets/fonts/plex/IBMPlexSansArabic-Bold.ttf');
      final res = await buildPaperCopies(
          base: _paper(), versions: const ExamVersions(), api: ExamVersionsApi(), examId: 5, tpl: PaperTemplate.minimal, regular: regular, bold: bold,
          named: true, studentIds: [7, 8], word: true);
      final files = ZipDecoder().decodeBytes(res.bytes!).files.where((f) => f.name.endsWith('.docx')).toList();
      expect(files.length, 2);
      final inner = ZipDecoder().decodeBytes(files.first.content as List<int>);
      final header = utf8.decode(inner.files.firstWhere((f) => f.name == 'word/header2.xml').content as List<int>);
      expect(header, contains('Student 7'));
    });
  });

  group('writers', () {
    test('PDF with an answer table, version and key summary; Word with the table', () async {
      final regular = await _font('assets/fonts/plex/IBMPlexSansArabic-Regular.ttf'), bold = await _font('assets/fonts/plex/IBMPlexSansArabic-Bold.ttf');
      for (final rtl in [false, true]) {
        final d = applyVersion(_paper(rtl: rtl), ExamVersion.fromJson(_ver))
            .copyWith(answerTable: AnswerTablePlace.start, answerKey: true, keySummary: const [PaperKeyLine(1, 'B'), PaperKeyLine(2, 'A')]);
        final pdf = await examPaperPdf(d, PaperTemplate.modern, regular: regular, bold: bold);
        expect(pdf.length, greaterThan(1000));
        final docx = examPaperDocx(d, PaperTemplate.minimal);
        final xml = utf8.decode(ZipDecoder().decodeBytes(docx).files.firstWhere((f) => f.name == 'word/document.xml').content as List<int>);
        expect(xml, contains(PaperWords(rtl).answerTableTitle));
        expect(xml, contains(PaperWords(rtl).version('B')));
        expect(xml, contains('●'));
      }
    });
  });

  group('layout', () {
    final versions = ExamVersions.fromJson({'items': [{'code': 'A'}, _ver]});
    testWidgets('VersionsForm', (t) async {
      await expectNoLayoutErrors(
          t,
          () => SingleChildScrollView(
                child: VersionsForm(
                  count: 4, shuffleQuestions: true, shuffleOptions: false, copies: 30, onCount: (_) {}, onShuffleQuestions: (_) {}, onShuffleOptions: (_) {},
                  onCopies: (_) {}, versions: versions.items, warnings: const ['Question 3 has one option, so it cannot be shuffled'], onGenerate: () {},
                ),
              ));
    });

    testWidgets('VersionsForm on a bubble exam: shuffling questions is off with its reason', (t) async {
      await expectNoLayoutErrors(
          t,
          () => SingleChildScrollView(
                child: VersionsForm(
                  count: 2, shuffleQuestions: true, shuffleOptions: true, copies: 1, onCount: (_) {}, onShuffleQuestions: (_) {}, onShuffleOptions: (_) {},
                  onCopies: (_) {}, bubble: true, onGenerate: () {},
                ),
              ),
          act: (t) async {
            final tile = t.widget<AppSwitchTile>(find.byKey(const ValueKey('versions.shuffleQuestions')));
            expect(tile.onChanged, isNull, reason: 'off on a bubble exam');
            expect(tile.subtitle, versionsBubbleText);
          });
    });

    testWidgets('a stale version shows the banner and cannot be picked', (t) async {
      final stale = ExamVersions.fromJson({'items': [{'code': 'A', 'stale': true}], 'stale': true});
      expect(stale.stale, isTrue);
      expect(stale.items.single.stale, isTrue);
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: PaperVersionsSection(versions: stale, selected: null, onSelect: (_) {}, onEdit: () {})),
          act: (t) async {
        expect(find.byKey(const ValueKey('paper.versions.stale')), findsOneWidget);
      });
    });

    testWidgets('paper sheet sections', (t) async {
      await expectNoLayoutErrors(
          t,
          () => SingleChildScrollView(
                child: Column(children: [
                  PaperVersionsSection(versions: versions, selected: 'B', onSelect: (_) {}, onEdit: () {}),
                  PaperAnswerAreaSection(format: 'both', syncable: true, onFormat: (_) {}, table: AnswerTablePlace.end, onTable: (_) {}),
                  PaperCopiesSection(named: true, onNamed: (_) {}, picked: 12, onPick: () {}, blank: 30, onBlank: (_) {}, busy: false, wordNote: true, onPrint: () {}),
                  PaperCopiesSection(named: false, onNamed: (_) {}, picked: 0, onPick: () {}, blank: 30, onBlank: (_) {}, busy: true, wordNote: false, onPrint: null),
                ]),
              ));
    });
  });
}
