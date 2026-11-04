// Review fixes on printed papers: per-paper footer page counts, question images, the key summary, the bytes cache cap.
// `EXPORT_SAMPLES=<dir> flutter test test/org/exam_paper_images_test.dart` writes <dir>/sample_exam.pdf (2 named copies, Arabic,
// an image, an answer table).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_authoring.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_media.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_paper.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_paper_docx.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_paper_pdf.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_versions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

final _mid = '${'cd' * 32}.png';

Map<String, dynamic> _q(int id, String type, Map<String, dynamic> body, Map<String, dynamic> answer, double points) =>
    {'id': id, 'type': type, 'body': body, 'answer': answer, 'points': points, 'placement_id': id, 'position': id, 'tags': [], 'version': 1};

ExamView _view({bool ar = true, int essays = 0}) => ExamView.fromJson({
      'id': 5, 'title': ar ? 'امتحان الأحياء' : 'Biology exam', 'status': 'published', 'duration_minutes': 60, 'max_attempts': 1,
      'results_policy': 'when_published', 'allowed_platforms': ['web'], 'settings': {}, 'version': 1, 'max_score': 12,
      'sections': [
        {
          'id': 1, 'position': 0, 'title': '', 'mode': 'paper', 'weight': 1,
          'questions': [
            _q(1, 'mcq_single', {
              'prompt': ar ? 'ما اسم الجزء المشار إليه في الصورة؟' : 'Name the part shown in the picture.',
              'options': [{'id': 'a', 'text': 'A'}, {'id': 'b', 'text': 'B'}, {'id': 'c', 'text': 'C'}, {'id': 'd', 'text': 'D'}],
              'media': [{'id': _mid, 'alt': ar ? 'خلية نباتية' : 'a plant cell'}],
            }, {'correct': 'b'}, 2),
            _q(2, 'mcq_multi', {'prompt': ar ? 'اختر' : 'Pick', 'options': [{'id': 'a', 'text': 'x'}, {'id': 'b', 'text': 'y'}, {'id': 'c', 'text': 'z'}]}, {'correct': ['a', 'c']}, 2),
            _q(3, 'true_false', {'prompt': ar ? 'صح أم خطأ؟' : 'True or false?'}, {'correct': true}, 1),
            for (var i = 0; i < essays; i++) _q(10 + i, 'essay', {'prompt': 'Essay $i'}, {'model': 'm'}, 12),
          ],
        },
      ],
    });

ExamPaperDoc _doc({bool ar = true, int essays = 0, AnswerTablePlace table = AnswerTablePlace.none}) => ExamPaperDoc.fromView(_view(ar: ar, essays: essays),
    institution: ar ? 'مدرسة النور' : 'Al Noor', course: ar ? 'الأحياء' : 'Biology', dateText: '1/12/2026',
    instructions: defaultPaperInstructions(rtl: ar, questions: 3, duration: '60'), rtl: ar, accentHex: '1E5AA8', answerTable: table);

Future<ByteData> _font(String p) async => ByteData.sublistView(await File(p).readAsBytes());

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

void main() {
  setUp(() => AppConfig.lang = 'en');

  test('the footer: "turn over" on every page of a paper but its own last one', () {
    expect([for (var p = 1; p <= 2; p++) paperTurnOver(p, 2)], [true, false]);
    expect(paperTurnOver(1, 1), isFalse);
  });

  test('a merged PDF counts each paper on its own (2 copies x 2 pages)', () async {
    final regular = await _font('assets/fonts/plex/IBMPlexSansArabic-Regular.ttf'), bold = await _font('assets/fonts/plex/IBMPlexSansArabic-Bold.ttf');
    final one = (await examPaperPdfMany([_doc(essays: 4)], PaperTemplate.minimal, regular: regular, bold: bold)).pages.single;
    expect(one, greaterThanOrEqualTo(2));
    final two = await examPaperPdfMany([_doc(essays: 4), _doc(essays: 4)], PaperTemplate.minimal, regular: regular, bold: bold);
    expect(two.pages, [one, one], reason: 'the second copy numbers its pages from 1 and ends where the first ends');
  });

  test('question images: media is carried, fetched once before laying out, a failed fetch becomes a placeholder', () async {
    final d = _doc(ar: false);
    final q = d.sections.single.questions.first;
    expect(q.mediaId, _mid);
    expect(q.mediaAlt, 'a plant cell');
    expect(d.hasImages, isTrue);

    final calls = <String>[];
    final ok = await attachPaperImages(d, (qid, mid) async {
      calls.add('$qid/$mid');
      return _picture();
    });
    expect(calls, ['1/$_mid']);
    expect(ok.sections.single.questions.first.image, isNotNull);
    expect(ok.sections.single.questions[1].image, isNull);

    final bad = await attachPaperImages(d, (_, _) async => throw StateError('offline'));
    final bq = bad.sections.single.questions.first;
    expect(bq.image, isNull);
    expect(bq.imageFailed, isTrue);
    expect(bq.imagePlaceholder, '[image: a plant cell]');

    final regular = await _font('assets/fonts/plex/IBMPlexSansArabic-Regular.ttf'), bold = await _font('assets/fonts/plex/IBMPlexSansArabic-Bold.ttf');
    final withImg = await examPaperPdf(ok, PaperTemplate.minimal, regular: regular, bold: bold);
    final without = await examPaperPdf(bad, PaperTemplate.minimal, regular: regular, bold: bold);
    expect(withImg.length, greaterThan(without.length), reason: 'the picture is in the file');
    // a version keeps the image and the placeholder
    final v = applyVersion(ok, ExamVersion.fromJson({'code': 'B', 'question_order': [3, 2, 1]}));
    expect(v.sections.single.questions.last.image, isNotNull);
    // Word: the placeholder line, no picture
    final word = examPaperDocx(bad, PaperTemplate.minimal);
    expect(String.fromCharCodes(word).isNotEmpty, isTrue);
  });

  test('the key summary uses the paper letters and numbering, matched on question id', () {
    final d = _doc(ar: false);
    final v = applyVersion(d, ExamVersion.fromJson({'code': 'B', 'question_order': [2, 1, 3], 'option_orders': {'1': [1, 0, 2, 3]}}));
    // the server numbers paper sections only and displays by the exam's language: both are ignored
    final items = [
      const AnswerKeyItem(1, 2, 'mcq_multi', 2, 'A, C'),
      const AnswerKeyItem(2, 1, 'mcq_single', 2, 'B'),
      const AnswerKeyItem(3, 3, 'true_false', 1, 'True'),
    ];
    final lines = keyLinesForPaper(v, items);
    expect([for (final l in lines) l.n], [1, 2, 3]);
    expect(lines[0].display, 'A, C');
    expect(lines[1].display, 'A', reason: 'question 1 shows option b first in version B, so the correct one is letter A');
    expect(lines[2].display, 'True');
    AppConfig.lang = 'ar';
    final ar = keyLinesForPaper(_doc(), items);
    expect(ar[0].display, 'ب');
  });

  test('version warnings are words; the shuffled icon is for versions that differ from A', () {
    expect(versionWarningText('nothing_shuffled'), isNot('nothing_shuffled'));
    expect(versionWarningText('some_new_code'), isNot('some_new_code'));
    final a = ExamVersion.fromJson({'code': 'A', 'question_order': [1, 2, 3]});
    final same = ExamVersion.fromJson({'code': 'B', 'question_order': [1, 2, 3]});
    final diff = ExamVersion.fromJson({'code': 'C', 'question_order': [3, 2, 1]});
    expect(versionShuffled(a, a), isFalse);
    expect(versionShuffled(same, a), isFalse);
    expect(versionShuffled(diff, a), isTrue);
  });

  test('QuestionDraft.withType keeps the image', () {
    final d = QuestionDraft(type: 'mcq_single')..media = QuestionMedia(_mid, 'cell');
    expect(d.withType('true_false').media, QuestionMedia(_mid, 'cell'));
  });

  test('MediaBytesCache is capped by total bytes too', () {
    final c = MediaBytesCache(maxBytes: 100);
    c.put('a', Uint8List(60));
    c.put('b', Uint8List(60));
    expect(c.length, 1);
    expect(c.peek('a'), isNull);
    expect(c.totalBytes, 60);
    c.put('c', Uint8List(500));
    expect(c.length, 1, reason: 'one image alone may exceed the cap');
    c.clear();
    expect(c.totalBytes, 0);
  });

  test('sample: two named Arabic copies with an image and an answer table', () async {
    final dir = Platform.environment['EXPORT_SAMPLES'];
    if (dir == null || dir.isEmpty) return;
    AppConfig.lang = 'ar';
    final regular = await _font('assets/fonts/plex/IBMPlexSansArabic-Regular.ttf'), bold = await _font('assets/fonts/Bahij_TheSansArabic-Bold.ttf');
    final base = await attachPaperImages(_doc(essays: 3, table: AnswerTablePlace.start), (_, _) async => _picture());
    final names = ['أحمد محمد', 'سارة علي'];
    final docs = [
      for (var i = 0; i < 2; i++) base.copyWith(studentName: names[i], qrSlots: 1),
    ];
    final counted = await examPaperPdfMany(docs, PaperTemplate.modern, regular: regular, bold: bold);
    final real = [
      for (var i = 0; i < 2; i++)
        docs[i].copyWith(qrSlots: 0, qrPages: [for (var p = 1; p <= counted.pages[i]; p++) 'NB1-$i-$p']),
    ];
    final out = await examPaperPdfMany(real, PaperTemplate.modern, regular: regular, bold: bold);
    expect(out.pages, counted.pages);
    await File('$dir/sample_exam.pdf').writeAsBytes(out.bytes);
  });
}
