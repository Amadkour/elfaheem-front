// `EXPORT_SAMPLES=<dir> flutter test test/org/exam_paper_test.dart` also writes every design as PDF and Word into <dir>.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_authoring.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_paper.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_paper_docx.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_paper_pdf.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_paper_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

Map<String, dynamic> _q(int id, String type, Map<String, dynamic> body, Map<String, dynamic> answer, double points) =>
    {'id': id, 'type': type, 'body': body, 'answer': answer, 'points': points, 'placement_id': id, 'position': id, 'tags': [], 'version': 1};

ExamView _view({bool ar = true}) => ExamView.fromJson({
      'id': 5, 'org_id': 2, 'course_id': 9, 'title': ar ? 'الامتحان النهائي — الأحياء' : 'Final exam — Biology', 'status': 'published',
      'starts_at': '2026-12-01T08:00:00', 'duration_minutes': 120, 'max_attempts': 1, 'results_policy': 'when_published', 'high_stakes': true,
      'allowed_platforms': ['web'], 'settings': {}, 'version': 1, 'max_score': 30,
      'sections': [
        {
          'id': 1, 'position': 0, 'title': ar ? 'الجزء الأول: اختيار من متعدد' : 'Part A: multiple choice', 'mode': 'paper', 'weight': 1,
          'questions': [
            _q(1, 'mcq_single', {'prompt': ar ? 'أي غاز تمتصه النباتات أثناء البناء الضوئي؟' : 'Which gas do plants take in during photosynthesis?',
              'options': [{'id': 'a', 'text': 'CO2'}, {'id': 'b', 'text': 'O2'}, {'id': 'c', 'text': 'N2'}, {'id': 'd', 'text': 'H2'}]}, {'correct': 'a'}, 2),
            _q(2, 'mcq_multi', {'prompt': ar ? 'اختر العضيات الموجودة في الخلية النباتية فقط' : 'Pick the organelles found only in plant cells',
              'options': [{'id': 'a', 'text': ar ? 'البلاستيدات الخضراء التي تحتوي على الكلوروفيل وتقوم بعملية البناء الضوئي' : 'Chloroplasts, which hold chlorophyll and carry out photosynthesis'},
                {'id': 'b', 'text': ar ? 'الجدار الخلوي' : 'Cell wall'}, {'id': 'c', 'text': ar ? 'الميتوكوندريا' : 'Mitochondria'}]}, {'correct': ['a', 'b']}, 3),
            _q(3, 'true_false', {'prompt': ar ? 'الشمس مصدر الطاقة في السلسلة الغذائية.' : 'The sun is the energy source of a food chain.'}, {'correct': true}, 1),
          ],
        },
        {
          'id': 2, 'position': 1, 'title': '', 'instructions': ar ? 'أجب في المساحة المخصصة.' : 'Answer in the space given.', 'mode': 'paper', 'weight': 1,
          'questions': [
            _q(4, 'fill_blank', {'prompt': ar ? 'تتم عملية البناء الضوئي في ___ .' : 'Photosynthesis happens in the ___ .', 'blanks_count': 1}, {'blanks': [['chloroplast']]}, 2),
            _q(5, 'matching', {'prompt': ar ? 'صِل كل عضية بوظيفتها' : 'Match each organelle with its job', 'left': ['Nucleus', 'Ribosome'],
              'right': ['Proteins', 'DNA', 'Energy']}, {'pairs': {'Nucleus': 'DNA', 'Ribosome': 'Proteins'}}, 2),
            _q(6, 'ordering', {'prompt': ar ? 'رتّب مراحل الانقسام' : 'Order the phases', 'items': ['Metaphase', 'Prophase', 'Anaphase']},
                {'order': ['Prophase', 'Metaphase', 'Anaphase']}, 2),
            _q(7, 'essay', {'prompt': ar ? 'اشرح العلاقة بين البناء الضوئي والتنفس الخلوي.' : 'Explain how photosynthesis and respiration depend on each other.'},
                {'model': 'They are reverse processes.', 'rubric': [{'id': 'c1', 'criterion': 'reverse reactions', 'points': 6}]}, 12),
            _q(8, 'numeric', {'prompt': ar ? 'كم كروموسوماً في خلية الإنسان؟' : 'How many chromosomes in a human cell?'}, {'value': 46}, 1),
          ],
        },
      ],
    });

ExamPaperDoc _doc({bool ar = true, bool key = false}) => ExamPaperDoc.fromView(_view(ar: ar),
    institution: ar ? 'مدرسة النور الثانوية' : 'Al Noor High School', course: ar ? 'الأحياء' : 'Biology', dateText: '1/12/2026',
    instructions: defaultPaperInstructions(rtl: ar, questions: 8, duration: ar ? '120 دقيقة' : '120 minutes'), rtl: ar, accentHex: '1E5AA8', answerKey: key);

Future<ByteData> _font(String path) async => ByteData.sublistView(await File(path).readAsBytes());

String _docXml(Uint8List docx) => utf8.decode(ZipDecoder().decodeBytes(docx).files.firstWhere((f) => f.name == 'word/document.xml').content as List<int>);

void main() {
  setUp(() => AppConfig.lang = 'en');

  test('fromView numbers questions across sections and keeps the key', () {
    final d = _doc();
    expect(d.questionCount, 8);
    expect(d.sections.map((s) => s.questions.first.number), [1, 4]);
    final mcq = d.sections.first.questions.first;
    expect(mcq.options, ['CO2', 'O2', 'N2', 'H2']);
    expect(mcq.correct, {0});
    expect(d.sections.first.questions[1].correct, {0, 1});
    expect(d.sections.first.questions[2].tfCorrect, isTrue);
    final essay = d.sections[1].questions[3];
    expect(essay.lines, 16);
    expect(essay.answerText, contains('reverse processes'));
    expect(d.sections[1].questions[4].answerText, '46');
    expect(d.total, 30);
  });

  test('auto design: classic for high-stakes, modern otherwise', () {
    expect(resolvePaperTemplate(PaperTemplate.auto, highStakes: true), PaperTemplate.classic);
    expect(resolvePaperTemplate(PaperTemplate.auto, highStakes: false), PaperTemplate.modern);
    expect(resolvePaperTemplate(PaperTemplate.minimal, highStakes: true), PaperTemplate.minimal);
  });

  test('helpers', () {
    expect(choiceLetter(1, rtl: true), 'ب');
    expect(choiceLetter(2, rtl: false), 'C');
    expect(answerLines('mcq_single', 5), 0);
    expect(answerLines('essay', 1), 5);
    expect(answerLines('essay', 50), 16);
    expect(blankPrompt('The ___ is green', 1), contains('……'));
    expect(blankPrompt('Name two parts', 2).split('\n').length, 3);
    expect(defaultPaperInstructions(rtl: true, questions: 4, duration: '').length, 4);
    expect(paperPlaceholders(_doc())['total'], '30');
  });

  for (final tpl in [PaperTemplate.classic, PaperTemplate.modern, PaperTemplate.minimal]) {
    for (final ar in [true, false]) {
      test('${tpl.name} ${ar ? 'ar' : 'en'}: PDF and Word, paper and key', () async {
        final s = PaperStyle.of(tpl);
        for (final key in [false, true]) {
          final d = _doc(ar: ar, key: key);
          final pdf = await examPaperPdf(d, tpl, regular: await _font(s.regular), bold: await _font(s.bold));
          expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
          final docx = examPaperDocx(d, tpl);
          final xml = _docXml(docx);
          expect(xml, contains(ar ? 'مدرسة النور' : 'Al Noor'));
          expect(xml, contains(ar ? 'اشرح العلاقة' : 'Explain how'));
          expect(xml.contains('reverse processes'), key);         // the key copy only
          expect(xml, contains('<w:titlePg/>'));
          if (tpl == PaperTemplate.classic) expect(xml, contains('w:pgBorders'));
          final out = Platform.environment['EXPORT_SAMPLES'];
          if (out != null) {
            final name = 'paper_${tpl.name}_${ar ? 'ar' : 'en'}${key ? '_key' : ''}';
            File('$out/$name.pdf').writeAsBytesSync(pdf);
            File('$out/$name.docx').writeAsBytesSync(docx);
          }
        }
      });
    }
  }

  test('a custom Word template: placeholders filled, {{questions}} replaced, the rest kept', () {
    String p(String text) => '<w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:b/></w:rPr><w:t>$text</w:t></w:r></w:p>';
    final a = Archive()
      ..add(ArchiveFile.bytes('word/document.xml', utf8.encode('<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>'
          '${p('{{institution}} — {{title}}')}<w:p w14:paraId="A1"/><w:p><w:r><w:t>{{ques</w:t></w:r><w:r><w:t>tions}}</w:t></w:r></w:p>${p('Keep me')}</w:body></w:document>')))
      ..add(ArchiveFile.bytes('word/header1.xml', utf8.encode('<w:hdr xmlns:w="x">${p('{{course}} · {{date}}')}</w:hdr>')))
      ..add(ArchiveFile.bytes('word/media/logo.png', [1, 2, 3]));
    final tpl = ZipEncoder().encodeBytes(a);
    expect(templateHasQuestions(tpl), isTrue);
    final out = fillExamTemplate(tpl, _doc(ar: false));
    final files = {for (final f in ZipDecoder().decodeBytes(out).files) f.name: f.content as List<int>};
    final doc = utf8.decode(files['word/document.xml']!);
    expect(doc, contains('Al Noor High School — Final exam — Biology'));
    expect(doc, contains('<w:b/>'));                                  // the paragraph's own style is kept
    expect(doc, contains('Which gas do plants take in'));
    expect(doc, isNot(contains('{{')));
    expect(doc, contains('Keep me'));
    expect(doc, contains('<w:p w14:paraId="A1"/>'));                  // an empty paragraph with attributes is left alone
    expect(utf8.decode(files['word/header1.xml']!), contains('Biology · 1/12/2026'));
    expect(files['word/media/logo.png'], [1, 2, 3]);
    final plain = ZipEncoder().encodeBytes(Archive()..add(ArchiveFile.bytes('word/document.xml', utf8.encode('<w:document><w:body>${p('no marker')}</w:body></w:document>'))));
    expect(templateHasQuestions(plain), isFalse);
  });

  test('printableImage keeps PNG / JPEG and drops what it cannot read', () {
    final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0, 0]);
    expect(printableImage(png), same(png));
    expect(printableImage(Uint8List.fromList([1, 2, 3, 4, 5])), isNull);
    expect(printableImage(null), isNull);
  });

  group('layout', () {
    testWidgets('template cards', (t) async {
      await expectNoLayoutErrors(
          t,
          () => Wrap(spacing: 10, runSpacing: 10, children: [
                for (final p in PaperTemplate.values)
                  PaperTemplateCard(template: p, selected: p == PaperTemplate.classic, onTap: () {}, subtitle: p == PaperTemplate.custom ? 'school-exam-template-2026.docx' : null),
              ]));
    });

    testWidgets('the sheet', (t) async {
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: ExamPaperSheet(view: _view(), course: 'Biology', orgName: 'Al Noor High School')),
          act: (t) async {
        await t.ensureVisible(find.byType(ExpansionTile));
        await t.tap(find.byType(ExpansionTile));
        await t.pumpAndSettle();
      });
    });
  });
}
