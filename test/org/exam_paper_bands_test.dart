// The exam paper drawn from an engine design (exam_paper_bands.dart): header / footer / signature / logo bands in the PDF and
// the Word file, the cover page per student, the QR on every page, the Excel workbook.
// `EXPORT_SAMPLES=<dir> flutter test test/org/exam_paper_bands_test.dart` also writes the files into <dir> to look at.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/export_layout/layout_model.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_paper.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_paper_bands.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_paper_docx.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_paper_pdf.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_paper_xlsx.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_qr_png.dart';
import 'package:flutter_test/flutter_test.dart';

PaperQuestion _q(int n, String type, String prompt, {List<String> options = const [], Set<int> correct = const {}, double points = 2, String difficulty = ''}) =>
    PaperQuestion(number: n, type: type, prompt: prompt, points: points, options: options, correct: correct, difficulty: difficulty);

ExamPaperDoc _doc({
  bool ar = false,
  LayoutDocument? design,
  ExamCover? cover,
  Map<String, Uint8List> assets = const {},
  String student = '',
  List<String> qr = const [],
  bool key = false,
  String? version,
}) =>
    ExamPaperDoc(
      institution: ar ? 'مدرسة النور الثانوية' : 'Al Noor High School',
      course: ar ? 'الأحياء' : 'Biology',
      title: ar ? 'الامتحان النهائي' : 'Final exam',
      dateText: '1/12/2026',
      durationText: ar ? '120 دقيقة' : '120 minutes',
      total: 8,
      sections: [
        PaperSection(title: '', instructions: '', questions: [
          _q(1, 'mcq_single', ar ? 'أي غاز تمتصه النباتات؟' : 'Which gas do plants take in?',
              options: ['CO2', 'O2', 'N2'], correct: {0}, difficulty: 'easy'),
          _q(2, 'true_false', ar ? 'الشمس مصدر الطاقة.' : 'The sun is the energy source.', points: 1),
          _q(3, 'short_answer', ar ? 'عرّف البناء الضوئي.' : 'Define photosynthesis.', points: 5, difficulty: 'hard'),
        ]),
      ],
      instructions: ar ? ['اكتب اسمك.', 'أجب عن كل الأسئلة.'] : ['Write your name.', 'Answer every question.'],
      rtl: ar,
      accentHex: '1E5AA8',
      answerKey: key,
      studentName: student,
      qrPages: qr,
      qrSlots: qr.isEmpty ? 0 : 1,
      design: design,
      cover: cover,
      assets: assets,
      version: version,
      seat: '17',
    );

LayoutDesign _design(bool rtl, {bool every = false, String logoId = 'logo', double headerH = 30}) {
  final d = LayoutDesign(page: LayoutPage(rtl: rtl, margins: LayoutMargins(top: 15, right: 12, bottom: 15, left: 12)), mode: 'page');
  final w = d.page.contentWidth;
  d.header = LayoutBand(height: headerH, placement: every ? 'every_page' : 'first_page', elements: [
    LayoutElement(id: 'h1', kind: 'text', x: rtl ? w - 110 : 0, y: 2, w: 110, h: 8, value: '{{institution}}', style: LayoutStyle(size: 14, weight: 700)),
    LayoutElement(id: 'h2', kind: 'field', x: rtl ? w - 110 : 0, y: 11, w: 110, h: 6, value: 'Header-{{title}}-{{version}}', style: LayoutStyle(size: 10)),
    LayoutElement(id: 'h3', kind: 'image', x: rtl ? 0 : w - 25, y: 2, w: 25, h: 22, value: logoId),
    LayoutElement(id: 'h4', kind: 'signature', x: rtl ? 30 : w - 80, y: 2, w: 40, h: 24, value: 'sig', sigName: '{{student_name}}', sigTitle: 'Dean'),
    LayoutElement(id: 'h5', kind: 'line', x: 0, y: headerH - 2, w: w, h: 1, style: LayoutStyle(border: LayoutBorder(width: .4, color: '#B9C1CA'))),
    LayoutElement(id: 'h6', kind: 'rect', x: 0, y: 19, w: 20, h: 4, style: LayoutStyle(bg: '#EEF0F3', border: LayoutBorder(width: .2, color: '#9AA3AE'))),
    LayoutElement(id: 'h7', kind: 'ellipse', x: 24, y: 19, w: 8, h: 4, style: LayoutStyle(bg: '#DDEEFF')),
  ]);
  d.footer = LayoutBand(height: 12, placement: 'every_page', elements: [
    LayoutElement(id: 'f1', kind: 'text', x: 0, y: 2, w: 80, h: 6, value: 'Footer-{{course}}', style: LayoutStyle(size: 9)),
    LayoutElement(id: 'f2', kind: 'page_number', x: w - 40, y: 2, w: 40, h: 6, value: 'P {{page}} / {{pages}}', style: LayoutStyle(size: 9, align: 'end')),
  ]);
  return d;
}

LayoutDocument _designDoc({bool every = false, String logoId = 'logo'}) => LayoutDocument(
    purpose: 'exam_paper', languages: ['ar', 'en'], designs: {'ar': _design(true, every: every, logoId: logoId), 'en': _design(false, every: every, logoId: logoId)});

Map<String, Uint8List> _assets() => {'logo': qrPng('logo', modulepx: 3), 'sig': qrPng('sig', modulepx: 3)};

Future<ByteData> _font(String path) async => ByteData.sublistView(await File(path).readAsBytes());

Future<PaperPdfResult> _pdf(List<ExamPaperDoc> docs) async {
  final s = PaperStyle.of(PaperTemplate.minimal);
  return examPaperPdfMany(docs, PaperTemplate.minimal, regular: await _font(s.regular), bold: await _font(s.bold));
}

int _pdfPages(Uint8List b) => RegExp(r'/Type\s*/Page(?![s\w])').allMatches(latin1.decode(b, allowInvalid: true)).length;

Map<String, String> _parts(Uint8List zip) =>
    {for (final f in ZipDecoder().decodeBytes(zip).files) if (f.isFile && !f.name.contains('/media/')) f.name: utf8.decode(f.content as List<int>)};

void _sample(String name, Uint8List bytes) {
  final out = Platform.environment['EXPORT_SAMPLES'];
  if (out != null) File('$out/$name').writeAsBytesSync(bytes);
}

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('pure parts', () {
    test('colours, page tokens, design lookup', () {
      expect(parseLayoutColor('#1a2b3c'), ('1A2B3C', 1.0));
      expect(parseLayoutColor('#80FF0000')!.$1, 'FF0000');
      expect(parseLayoutColor('#80FF0000')!.$2, closeTo(.5, .01));
      expect(parseLayoutColor('red'), isNull);
      expect(paperFillPages('P {{page}} / {{ pages }} {{x}}', 2, 5), 'P 2 / 5 {{x}}');
      final doc = _designDoc();
      expect(paperDesignFor(doc, rtl: true)!.page.rtl, isTrue);
      expect(paperDesignFor(doc, rtl: false)!.page.rtl, isFalse);
      expect(paperDesignFor(null, rtl: true), isNull);
    });

    test('values fill the placeholders; start / end follow the page direction; a missing asset is skipped', () {
      final d = _doc(ar: true, design: _designDoc(), student: 'سلمى', assets: {'sig': qrPng('s')});
      final design = paperDesignFor(d.design, rtl: true)!;
      final ctx = PaperBandCtx(doc: d, design: design, values: d.paperValues(), lang: 'ar', widthMm: design.page.contentWidth);
      final items = resolvePaperElements(design.header.elements, ctx);
      final texts = [for (final i in items) if (i.kind == 'text') i.text];
      expect(texts, contains('مدرسة النور الثانوية'));
      expect(texts, contains('Header-الامتحان النهائي-'));
      expect(texts, contains('سلمى')); // the signature's name
      expect(items.where((i) => i.kind == 'image').length, 1); // the signature's picture; the logo id is not in assets
      // start in an Arabic page is the RIGHT edge, end the left; x stays physical
      final start = LayoutElement(id: 'a', kind: 'text', value: 'x', style: LayoutStyle(align: 'start'));
      final end = LayoutElement(id: 'b', kind: 'text', value: 'y', style: LayoutStyle(align: 'end'));
      expect(resolvePaperElements([start, end], ctx).map((i) => i.align), ['right', 'left']);
      final en = _doc(design: _designDoc());
      final enDesign = paperDesignFor(en.design, rtl: false)!;
      final enCtx = PaperBandCtx(doc: en, design: enDesign, values: en.paperValues(), lang: 'en', widthMm: enDesign.page.contentWidth);
      expect(resolvePaperElements([start, end], enCtx).map((i) => i.align), ['left', 'right']);
      expect(items.firstWhere((i) => i.text == 'مدرسة النور الثانوية').rtl, isTrue);
    });

    test('paperValues carries the copy: student, seat, version, university', () {
      final d = _doc(student: 'Salma', version: 'B', cover: const ExamCover(university: 'Cairo Uni'));
      final v = d.paperValues();
      expect(v['student_name'], 'Salma');
      expect(v['seat'], '17');
      expect(v['version'], 'B');
      expect(v['university'], 'Cairo Uni');
      expect(v['institution'], 'Al Noor High School');
      expect(v['total'], '8');
      expect(d.paperValues(copy: d.copyWith(studentName: 'Omar'))['student_name'], 'Omar');
    });

    test('the marks grid fits the box: more questions, more blocks', () {
      expect(planMarksGrid(10, 120).groups, 1);
      expect(planMarksGrid(40, 120).groups, greaterThan(1));
      expect(planMarksGrid(200, 100).groups, 4);
      expect(planMarksGrid(200, 100).rowH, greaterThanOrEqualTo(3.5));
    });
  });

  for (final ar in [false, true]) {
    final lang = ar ? 'ar' : 'en';

    test('$lang: PDF with a design renders; the page count matches the paper without it', () async {
      final plain = await _pdf([_doc(ar: ar, qr: ['p1'])]);
      final withDesign = await _pdf([_doc(ar: ar, design: _designDoc(), assets: _assets(), qr: ['p1'], student: ar ? 'سلمى' : 'Salma')]);
      expect(String.fromCharCodes(withDesign.bytes.take(5)), '%PDF-');
      expect(withDesign.pages, plain.pages);
      expect(_pdfPages(withDesign.bytes), _pdfPages(plain.bytes));
      // a long paper keeps the same number of pages when the band takes the room of the built-in header
      final longQs = [for (var i = 1; i <= 30; i++) _q(i, 'short_answer', 'Question number $i about the topic', points: 3)];
      ExamPaperDoc long({LayoutDocument? design}) {
        final d = _doc(ar: ar, design: design, assets: _assets());
        return ExamPaperDoc(
            institution: d.institution, course: d.course, title: d.title, dateText: d.dateText, durationText: d.durationText, total: 90,
            sections: [PaperSection(title: '', instructions: '', questions: longQs)], instructions: d.instructions, rtl: ar, design: design, assets: d.assets);
      }
      final a = await _pdf([long()]), b = await _pdf([long(design: _designDoc(every: true))]);
      expect(a.pages.first, greaterThan(1));
      expect(b.pages.first, closeTo(a.pages.first, 1));
      _sample('bands_$lang.pdf', withDesign.bytes);
    });

    test('$lang: Word with a design: bands in the header / footer parts, RTL, pictures, fields', () {
      final docx = examPaperDocx(_doc(ar: ar, design: _designDoc(), assets: _assets(), student: ar ? 'سلمى' : 'Salma', qr: ['a']), PaperTemplate.minimal);
      final parts = _parts(docx);
      final first = parts['word/header2.xml']!; // the first page's header holds the first_page band
      expect(first, contains(ar ? 'مدرسة النور الثانوية' : 'Al Noor High School'));
      expect(first, contains('Header-${ar ? 'الامتحان النهائي' : 'Final exam'}-'));
      expect(first, contains('wps:wsp'));
      expect(first, contains('a:prstGeom prst="ellipse"'));
      expect(first, contains('a:prstGeom prst="line"'));
      expect(first, contains('r:embed='));
      expect(first.contains('<w:bidi/>'), ar); // the text paragraphs carry the Arabic base direction
      expect(first, contains(ar ? 'سلمى' : 'Salma')); // the signature's name line
      expect(first, contains('Dean'));
      final footer = parts['word/footer1.xml']!;
      expect(footer, contains('Footer-${ar ? 'الأحياء' : 'Biology'}'));
      expect(footer, contains('NUMPAGES'));
      expect(footer, contains('rQr')); // the QR is still there
      expect(parts['word/_rels/header2.xml.rels'], contains('media/bd'));
      expect(ZipDecoder().decodeBytes(docx).files.where((f) => f.name.startsWith('word/media/bd')).length, 2);
      // the built-in header block is gone from the body; the instructions and questions stay
      final body = parts['word/document.xml']!;
      expect(body, contains(ar ? 'أي غاز' : 'Which gas'));
      expect(body, contains(ar ? 'أجب عن كل الأسئلة' : 'Answer every question'));
      _sample('bands_$lang.docx', docx);
    });

    test('$lang: Word keeps its page count and a QR on every page', () {
      final qr = ['p1', 'p2', 'p3'];
      final plainPages = wordPageCount(_doc(ar: ar), PaperTemplate.minimal);
      final designPages = wordPageCount(_doc(ar: ar, design: _designDoc(), assets: _assets()), PaperTemplate.minimal);
      expect(designPages, plainPages);
      final long = ExamPaperDoc(
          institution: 'S', course: 'C', title: 'T', dateText: '', durationText: '', total: 90, rtl: ar, qrPages: qr, qrSlots: 1,
          sections: [PaperSection(title: '', instructions: '', questions: [for (var i = 1; i <= 24; i++) _q(i, 'essay', 'Explain topic $i', points: 4)])],
          instructions: const [], design: _designDoc(), assets: _assets());
      final parts = _parts(examPaperDocx(long, PaperTemplate.minimal));
      final footers = parts.keys.where((k) => RegExp(r'^word/footer\d+\.xml$').hasMatch(k)).toList();
      expect(footers.length, greaterThan(1));
      for (final f in footers) {
        expect(parts[f], contains('rQr'), reason: f);
      }
    });

    test('$lang: a cover per student is prepended with that student\'s name and the marks grid', () async {
      const cover = ExamCover(university: 'Cairo University');
      final names = ar ? ['سلمى', 'عمر'] : ['Salma', 'Omar'];
      final docs = [for (final n in names) _doc(ar: ar, cover: cover, student: n, qr: ['x'])];
      final base = await _pdf([for (final n in names) _doc(ar: ar, student: n, qr: ['x'])]);
      final withCover = await _pdf(docs);
      expect(withCover.pages, base.pages); // the cover is outside the paper's own pages and QR payloads
      expect(_pdfPages(withCover.bytes), _pdfPages(base.bytes) + 2);
      for (final n in names) {
        final docx = examPaperDocx(_doc(ar: ar, cover: cover, student: n, qr: ['x']), PaperTemplate.minimal);
        final body = _parts(docx)['word/document.xml']!;
        final coverPart = body.substring(0, body.indexOf(ar ? 'أي غاز' : 'Which gas'));
        expect(coverPart, contains(n));
        expect(coverPart, contains('Cairo University'));
        expect(coverPart, contains(ar ? 'مدرسة النور الثانوية' : 'Al Noor High School'));
        // n · max marks · blank mark · total: question numbers 1..3, their points, the total row
        for (final t in ['>1<', '>2<', '>3<', '>5<', '>8<']) {
          expect(coverPart, contains(t));
        }
        expect(coverPart, contains(ar ? 'المجموع' : 'Total'));
        expect(wordPageCount(_doc(ar: ar, cover: cover, student: n, qr: ['x']), PaperTemplate.minimal), wordPageCount(_doc(ar: ar), PaperTemplate.minimal));
        expect(body, contains('<w:pgNumType w:start="1"/>')); // the paper numbers its own pages from 1
        _sample('cover_${lang}_$n.docx', docx);
      }
      _sample('cover_$lang.pdf', withCover.bytes);
    });

    test('$lang: Excel workbook: sheets, versions, a known cell, the marks grid', () {
      final a = _doc(ar: ar, version: 'A', key: true), b = _doc(ar: ar, version: 'B', key: true);
      final bytes = examPaperXlsx(_doc(ar: ar, key: true), versions: [a, b], roster: [ar ? 'سلمى' : 'Salma', ar ? 'عمر' : 'Omar']);
      final z = ZipDecoder().decodeBytes(bytes);
      expect(z.files.map((f) => f.name), containsAll(['[Content_Types].xml', 'xl/workbook.xml', 'xl/styles.xml', 'xl/worksheets/sheet1.xml', 'xl/worksheets/sheet4.xml']));
      final parts = _parts(bytes);
      final wb = parts['xl/workbook.xml']!;
      final names = RegExp(r'<sheet name="([^"]+)"').allMatches(wb).map((m) => m.group(1)).toList();
      expect(names, ar ? ['الأسئلة', 'مفتاح الإجابة A', 'مفتاح الإجابة B', 'جدول الدرجات'] : ['Questions', 'Answer key A', 'Answer key B', 'Marks grid']);
      final q = parts['xl/worksheets/sheet1.xml']!;
      expect(q, contains('<c r="A2" s="3"><v>1</v></c>'));
      expect(q, contains(ar ? 'أي غاز تمتصه النباتات؟' : 'Which gas do plants take in?'));
      expect(q, contains('CO2'));
      expect(q, contains('easy'));
      expect(q.contains('rightToLeft="1"'), ar);
      expect(parts['xl/worksheets/sheet2.xml'], contains(ar ? 'أ  CO2' : 'A  CO2'));
      final grid = parts['xl/worksheets/sheet4.xml']!;
      expect(grid, contains(ar ? 'سلمى' : 'Salma'));
      expect(grid, contains('<f>SUM(C3:E3)</f>'));
      _sample('paper_$lang.xlsx', bytes);
    });
  }

  test('without a key the Questions sheet has no answer column; with no versions one key sheet is written', () {
    final parts = _parts(examPaperXlsx(_doc()));
    expect(RegExp(r'<sheet name="([^"]+)"').allMatches(parts['xl/workbook.xml']!).map((m) => m.group(1)), ['Questions', 'Answer key', 'Marks grid']);
    expect(parts['xl/worksheets/sheet1.xml'], isNot(contains('>Answer<')));
  });

  test('a design that names a missing asset still renders in PDF and Word', () async {
    final d = _doc(design: _designDoc(logoId: 'gone'), assets: const {});
    expect((await _pdf([d])).pages.single, greaterThan(0));
    final parts = _parts(examPaperDocx(d, PaperTemplate.minimal));
    expect(parts['word/header2.xml'], isNot(contains('r:embed=')));
  });
}
