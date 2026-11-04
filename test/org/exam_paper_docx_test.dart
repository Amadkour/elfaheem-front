// Word copies of a printed exam: a QR on every page of a per-student copy (one section per planned page, each footer holds that
// page's QR), question images as inline pictures, a failed image keeps its "[image: alt]" line.
// `EXPORT_SAMPLES=<dir> flutter test test/org/exam_paper_docx_test.dart` writes <dir>/sample_exam.docx (2 students, Arabic, an image).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_paper.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_paper_docx.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_qr_png.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List _picture() {
  final im = img.Image(width: 360, height: 180);
  for (final p in im) {
    p
      ..r = (p.x * 255 ~/ 360)
      ..g = 120
      ..b = (p.y * 255 ~/ 180)
      ..a = 255;
  }
  return Uint8List.fromList(img.encodePng(im));
}

PaperQuestion _mcq(int n, {String? mediaId, Uint8List? image, bool failed = false, String alt = 'خلية نباتية'}) => PaperQuestion(
    id: n, number: n, type: 'mcq_single', prompt: 'السؤال $n', points: 2, options: ['أ', 'ب', 'ج', 'د'], correct: {1},
    mediaId: mediaId, mediaAlt: mediaId == null ? '' : alt, image: image, imageFailed: failed);

ExamPaperDoc _doc({List<PaperQuestion>? qs, List<String> qr = const [], String student = '', bool rtl = true}) {
  final questions = qs ?? [for (var i = 1; i <= 12; i++) _mcq(i)];
  final qs0 = questions;
  return ExamPaperDoc(
      institution: 'مدرسة النور', course: 'الأحياء', title: 'امتحان الأحياء', dateText: '1/12/2026', durationText: '60', total: qs0.fold(0.0, (a, q) => a + q.points),
      sections: [PaperSection(title: '', instructions: '', questions: questions)], instructions: const ['اقرأ بعناية'], rtl: rtl,
      studentName: student, qrPages: qr);
}

Map<String, Uint8List> _files(Uint8List docx) =>
    {for (final f in ZipDecoder().decodeBytes(docx).files.where((f) => f.isFile)) f.name: Uint8List.fromList(f.content as List<int>)};

String _text(Map<String, Uint8List> z, String name) => utf8.decode(z[name]!);

/// The matrix a QR PNG draws, read back from its pixels (quiet zone cut off); [n] = modules per side of that payload.
List<List<bool>> _readMatrix(Uint8List png, int n) {
  final im = img.decodePng(png)!;
  final px = im.width ~/ (n + 2 * kQrQuietModules);
  expect(px * (n + 2 * kQrQuietModules), im.width);
  expect(px, greaterThanOrEqualTo(4));
  return [
    for (var y = 0; y < n; y++)
      [for (var x = 0; x < n; x++) im.getPixel((x + kQrQuietModules) * px + px ~/ 2, (y + kQrQuietModules) * px + px ~/ 2).r < 128],
  ];
}

void main() {
  setUp(() => AppConfig.lang = 'ar');

  test('a QR png is the payload\'s matrix with a quiet zone and modules of at least 4 px', () {
    for (final p in ['NB1.exam5.copy1.p1', 'https://nextbrain.site/x?a=1&b=2']) {
      final png = qrPng(p);
      final m = qrMatrix(p);
      expect(_readMatrix(png, m.length), m);
      final im = img.decodePng(png)!;
      expect(im.width, im.height);
      expect(im.getPixel(0, 0).r, 255); // quiet zone is white
      expect(im.width % (m.length + 2 * kQrQuietModules), 0);
      expect(im.width ~/ (m.length + 2 * kQrQuietModules), greaterThanOrEqualTo(4));
    }
    expect(qrMatrix('a'), isNot(qrMatrix('b')));
  });

  test('N copies x M pages: one QR picture per page, each with its own payload', () {
    final qs = [for (var i = 1; i <= 40; i++) _mcq(i)];
    final pages = wordPageCount(_doc(qs: qs), PaperTemplate.minimal);
    expect(pages, greaterThanOrEqualTo(3));
    for (final student in ['علي', 'منى']) {
      final payloads = [for (var p = 1; p <= pages; p++) 'NB.$student.p$p'];
      final z = _files(examPaperDocx(_doc(qs: qs, qr: payloads, student: student), PaperTemplate.minimal));
      final doc = _text(z, 'word/document.xml');
      // a section per page: pages-1 section-break paragraphs plus the body's own
      expect(RegExp('<w:sectPr>').allMatches(doc).length, pages);
      final footers = z.keys.where((k) => RegExp(r'^word/footer\d+\.xml$').hasMatch(k)).toList()..sort();
      expect(footers.length, pages);
      for (var p = 0; p < pages; p++) {
        final ftr = _text(z, 'word/footer${p + 1}.xml');
        expect(RegExp('<w:drawing>').allMatches(ftr).length, 1, reason: 'footer ${p + 1} has one QR');
        final rels = _text(z, 'word/_rels/footer${p + 1}.xml.rels');
        final target = RegExp(r'Target="(media/[^"]+)"').firstMatch(rels)!.group(1)!;
        expect(target, 'media/qr${p + 1}.png');
        final png = z['word/$target']!;
        expect(_readMatrix(png, qrMatrix(payloads[p]).length), qrMatrix(payloads[p]), reason: 'page ${p + 1} draws its own payload');
        // and section p points at footer p
        expect(doc, contains('<w:footerReference w:type="default" r:id="rFtr${p + 1}"/>'));
      }
      expect(RegExp('qr\\d+\\.png').allMatches(z.keys.join(' ')).length, pages);
      // the questions are all there, in order, none repeated
      final nums = RegExp('السؤال (\\d+)').allMatches(doc).map((m) => int.parse(m.group(1)!)).toList();
      expect(nums, [for (var i = 1; i <= 40; i++) i]);
    }
  });

  test('the sections hold the questions in page order (page 1 first)', () {
    final qs = [for (var i = 1; i <= 40; i++) _mcq(i)];
    final n = wordPageCount(_doc(qs: qs), PaperTemplate.classic);
    final z = _files(examPaperDocx(_doc(qs: qs, qr: [for (var i = 1; i <= n; i++) 'p$i']), PaperTemplate.classic));
    final doc = _text(z, 'word/document.xml');
    final parts = doc.split(RegExp(r'<w:sectPr>'));
    expect(parts.length, n + 1); // n sections + the tail after the last sectPr
    expect(parts[0], contains('امتحان الأحياء'));
    expect(parts[0], contains('السؤال 1<'));
    expect(parts[1], isNot(contains('السؤال 1<')));
    expect(parts[2], contains('<w:footerReference'));
    // the headers belong to the first section only (later ones inherit)
    expect(RegExp('headerReference').allMatches(doc).length, 2);
  });

  test('no QR plan: a single section, one footer, no QR picture', () {
    final z = _files(examPaperDocx(_doc(), PaperTemplate.modern));
    final doc = _text(z, 'word/document.xml');
    expect(RegExp('<w:sectPr>').allMatches(doc).length, 1);
    expect(z.keys.where((k) => k.startsWith('word/footer')).length, 1);
    expect(_text(z, 'word/footer1.xml'), isNot(contains('<w:drawing>')));
    expect(z.keys.where((k) => k.startsWith('word/media/')), isEmpty);
  });

  test('a one-page plan keeps one section with its QR', () {
    final z = _files(examPaperDocx(_doc(qs: [_mcq(1), _mcq(2)], qr: ['only']), PaperTemplate.minimal));
    expect(_readMatrix(z['word/media/qr1.png']!, qrMatrix('only').length), qrMatrix('only'));
    expect(RegExp('<w:sectPr>').allMatches(_text(z, 'word/document.xml')).length, 1);
  });

  test('a question image is a drawing under its prompt, with media, rel and content type', () {
    final pic = _picture();
    final qs = [_mcq(1, mediaId: 'm1', image: pic), _mcq(2)];
    final z = _files(examPaperDocx(_doc(qs: qs), PaperTemplate.minimal));
    final doc = _text(z, 'word/document.xml');
    final at = doc.indexOf('السؤال 1<');
    final next = doc.indexOf('السؤال 2<');
    final draw = doc.indexOf('<w:drawing>');
    expect(draw, greaterThan(at));
    expect(draw, lessThan(next));
    expect(doc, isNot(contains('[image')));
    expect(z['word/media/q1.png'], pic);
    expect(_text(z, 'word/_rels/document.xml.rels'), contains('Id="rQ1"'));
    expect(_text(z, 'word/_rels/document.xml.rels'), contains('Target="media/q1.png"'));
    expect(doc, contains('r:embed="rQ1"'));
    expect(_text(z, '[Content_Types].xml'), contains('Extension="png" ContentType="image/png"'));
    // aspect ratio 2:1 kept, within the text width
    final ext = RegExp(r'<wp:extent cx="(\d+)" cy="(\d+)"').firstMatch(doc)!;
    final cx = int.parse(ext.group(1)!), cy = int.parse(ext.group(2)!);
    expect(cx / cy, closeTo(2, .01));
    expect(cx, lessThanOrEqualTo((11906 - 2000 - 560) * 635));
  });

  test('a big picture is scaled down to fit; a small one is not enlarged', () {
    final big = img.Image(width: 4000, height: 3000);
    final small = img.Image(width: 40, height: 40);
    final z = _files(examPaperDocx(
        _doc(qs: [_mcq(1, mediaId: 'a', image: Uint8List.fromList(img.encodePng(big))), _mcq(2, mediaId: 'b', image: Uint8List.fromList(img.encodePng(small)))]),
        PaperTemplate.minimal));
    final doc = _text(z, 'word/document.xml');
    final exts = RegExp(r'<wp:extent cx="(\d+)" cy="(\d+)"').allMatches(doc).map((m) => (int.parse(m.group(1)!), int.parse(m.group(2)!))).toList();
    expect(exts.length, 2);
    expect(exts[0].$1 / exts[0].$2, closeTo(4 / 3, .01));
    expect(exts[0].$1, lessThanOrEqualTo((11906 - 2000 - 560) * 635));
    expect(exts[0].$2, lessThanOrEqualTo(4800 * 635));
    expect(exts[1], (40 * 15 * 635, 40 * 15 * 635));
  });

  test('a missing, failed or undecodable image keeps the [image: alt] line', () {
    final qs = [
      _mcq(1, mediaId: 'm1', failed: true, alt: 'خلية'),
      _mcq(2, mediaId: 'm2', alt: 'بلا بايتات'),
      _mcq(3, mediaId: 'm3', image: Uint8List.fromList([1, 2, 3, 4, 5, 6]), alt: 'تالفة'),
    ];
    final z = _files(examPaperDocx(_doc(qs: qs), PaperTemplate.minimal));
    final doc = _text(z, 'word/document.xml');
    expect(doc, contains('[image: خلية]'));
    expect(doc, contains('[image: بلا بايتات]'));
    expect(doc, contains('[image: تالفة]'));
    expect(doc, isNot(contains('<w:drawing>')));
    expect(z.keys.where((k) => k.startsWith('word/media/')), isEmpty);
  });

  test('images and QRs together: every media file has a rel and the png default is declared once', () {
    final z = _files(examPaperDocx(_doc(qs: [for (var i = 1; i <= 8; i++) _mcq(i, mediaId: i.isOdd ? 'm$i' : null, image: i.isOdd ? _picture() : null)], qr: ['a']), PaperTemplate.modern));
    final rels = _text(z, 'word/_rels/document.xml.rels') + z.entries.where((e) => e.key.contains('footer') && e.key.endsWith('.rels')).map((e) => utf8.decode(e.value)).join();
    for (final m in z.keys.where((k) => k.startsWith('word/media/'))) {
      expect(rels, contains('Target="media/${m.split('/').last}"'));
    }
    expect(RegExp('Extension="png"').allMatches(_text(z, '[Content_Types].xml')).length, 1);
    final ids = RegExp(r'<wp:docPr id="(\d+)"').allMatches(_text(z, 'word/document.xml')).map((m) => m.group(1)).toList();
    expect(ids.toSet().length, ids.length, reason: 'drawing ids are unique');
  });

  test('English left-to-right copy', () {
    final qs = [for (var i = 1; i <= 40; i++) _mcq(i)];
    final n = wordPageCount(_doc(qs: qs, rtl: false), PaperTemplate.classic);
    final z = _files(examPaperDocx(_doc(qs: qs, qr: [for (var i = 1; i <= n; i++) 'x$i'], rtl: false), PaperTemplate.classic));
    expect(RegExp('<w:sectPr>').allMatches(_text(z, 'word/document.xml')).length, n);
    expect(_text(z, 'word/footer1.xml'), contains('Page '));
  });

  test('sample per-student Word file', () {
    final dir = Platform.environment['EXPORT_SAMPLES'];
    if (dir == null) return;
    final qs = [for (var i = 1; i <= 14; i++) _mcq(i, mediaId: i == 2 ? 'm' : null, image: i == 2 ? _picture() : null)];
    final big = [for (var i = 1; i <= 30; i++) _mcq(i, mediaId: i % 10 == 3 ? 'm$i' : null, image: i % 10 == 3 ? _picture() : null)];
    final pages14 = wordPageCount(_doc(qs: qs), PaperTemplate.modern), pages30 = wordPageCount(_doc(qs: big), PaperTemplate.modern);
    File('$dir/sample_30.docx').writeAsBytesSync(examPaperDocx(_doc(qs: big, student: 'علي أحمد', qr: [for (var p = 1; p <= pages30; p++) 'NB.big.p$p']), PaperTemplate.modern));
    File('$dir/pages.txt').writeAsStringSync('14q=$pages14 30q=$pages30');
    final names = ['علي أحمد', 'منى محمود'];
    for (var s = 0; s < names.length; s++) {
      final bytes = examPaperDocx(_doc(qs: qs, student: names[s], qr: [for (var p = 1; p <= pages14; p++) 'NB.copy${s + 1}.p$p']), PaperTemplate.modern);
      File('$dir/sample_exam${s == 0 ? '' : '_2'}.docx')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes);
    }
  });
}
