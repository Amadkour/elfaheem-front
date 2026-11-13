// Exam covers (D-730 - D-732): the stored choice (old covers read as designed, "same for the answers"), the file checks,
// the cover as a page the writers draw (picture, details box, cover code), the PDF and Word files with the cover in
// front (page numbers and QR payloads untouched), the upload with a PDF page, the picker's saves over FakeApi, and the
// picker under the layout harness.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/export_layout/layout_api.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_cover.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_cover_picker.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_paper.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_paper_design_api.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_paper_designer.dart' show paperWithDesign;
import 'package:flutter_education_app/features/shared/exam_engine/exam_paper_docx.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_paper_pdf.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_qr_png.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../ui/layout_harness.dart';

const _code = 'NBC:5.ABCDEFGHIJ';
const _asset = 'a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1';
final Uint8List _picture = qrPng('my school cover', modulepx: 8);

ExamPaperDoc _doc({bool ar = false, ExamCover? cover, List<String> qr = const [], Map<String, Uint8List> assets = const {}}) => ExamPaperDoc(
      institution: 'Al Noor High School',
      course: 'Biology',
      title: 'Final exam',
      dateText: '1/12/2026',
      durationText: '120 minutes',
      total: 6,
      sections: [
        PaperSection(title: '', instructions: '', questions: [
          PaperQuestion(number: 1, type: 'mcq_single', prompt: 'Which gas do plants take in?', points: 1, options: ['CO2', 'O2'], correct: {0}),
          PaperQuestion(number: 2, type: 'short_answer', prompt: 'Define photosynthesis.', points: 5),
        ]),
      ],
      instructions: ['Write your name.'],
      rtl: ar,
      studentName: qr.isEmpty ? '' : 'Mariam Hassan',
      qrPages: qr,
      cover: cover,
      assets: assets,
    );

Future<ByteData> _font(String path) async => ByteData.sublistView(await File(path).readAsBytes());

Future<PaperPdfResult> _pdf(List<ExamPaperDoc> docs) async {
  final s = PaperStyle.of(PaperTemplate.minimal);
  return examPaperPdfMany(docs, PaperTemplate.minimal, regular: await _font(s.regular), bold: await _font(s.bold));
}

int _pdfPages(Uint8List b) => RegExp(r'/Type\s*/Page(?![s\w])').allMatches(latin1.decode(b, allowInvalid: true)).length;

PaperCoverSpec _uploaded({bool stamp = false, AnswerCoverSpec? answer}) => PaperCoverSpec(
    mode: CoverMode.uploaded,
    upload: const CoverUpload(assetId: _asset, page: 2, pages: 4, width: 1240, height: 1754, name: 'school-cover.pdf'),
    stamp: CoverStamp(on: stamp, place: CoverPlace.bottom),
    answer: answer);

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    mockRequestPlugins();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
  });

  group('the stored choice', () {
    test('a cover saved before D-730 is the designed one; no cover reads as none', () {
      final old = PaperCoverSpec.fromJson({'design': null, 'university': 'Cairo University', 'marks_table': false})!;
      expect(old.mode, CoverMode.designed);
      expect(old.paperSide.on, isTrue);
      expect(old.answerSide.on, isFalse, reason: 'the answer side had no cover before');
      expect(PaperCoverSpec.fromJson(null), isNull);
    });

    test('an uploaded cover round-trips; "same" gives the answers the paper\'s cover', () {
      final s = _uploaded(stamp: true, answer: const AnswerCoverSpec(same: true));
      final back = PaperCoverSpec.fromJson(jsonDecode(jsonEncode(s.toJson())))!;
      expect(back.mode, CoverMode.uploaded);
      expect(back.upload!.assetId, _asset);
      expect((back.upload!.page, back.upload!.pages, back.upload!.name), (2, 4, 'school-cover.pdf'));
      expect(back.stamp.on, isTrue);
      expect(back.stamp.place, CoverPlace.bottom);
      expect(back.answer!.same, isTrue);
      expect(back.answerSide.mode, CoverMode.uploaded);
      expect(back.answerSide.upload!.assetId, _asset);
      // a designed answer mode is never stored: the designed cover reaches the answers through "same" only
      expect(AnswerCoverSpec.fromJson({'mode': 'designed'})!.mode, CoverMode.none);
    });

    test('nothing printing on either side is saved as no cover; a designed cover set to none keeps its design', () {
      expect(coverForSave(const PaperCoverSpec(mode: CoverMode.none)), isNull);
      expect(coverForSave(const PaperCoverSpec(mode: CoverMode.uploaded)), isNull, reason: 'uploaded with no file prints nothing');
      expect(coverForSave(const PaperCoverSpec(mode: CoverMode.none, university: 'U')), isNotNull);
      expect(coverForSave(const PaperCoverSpec(mode: CoverMode.none, answer: AnswerCoverSpec(mode: CoverMode.uploaded, upload: CoverUpload(assetId: _asset)))),
          isNotNull);
    });

    test('summary line, in both languages', () {
      expect(coverSummaryText(_uploaded(answer: const AnswerCoverSpec(same: true))), 'Questions: Uploaded · page 2 of 4 · Answers: Same as the question paper');
      expect(coverSummaryText(null, answerSide: false), 'Questions: No cover');
      AppConfig.lang = 'ar';
      expect(coverSummaryText(const PaperCoverSpec()), 'الأسئلة: الغلاف المصمم · الإجابة: بدون غلاف');
    });
  });

  group('the file', () {
    test('type and size limits, before any upload', () {
      expect(coverFileProblem('cover.png', 1000), isNull);
      expect(coverFileProblem('cover.JPG', 1000), isNull);
      expect(coverFileProblem('cover.pdf', 9 * 1024 * 1024), isNull);
      expect(coverFileProblem('cover.gif', 1000), 'A cover is a PNG or JPG picture, or a PDF');
      expect(coverFileProblem('cover.png', 3 * 1024 * 1024), 'The picture is larger than 2 MB');
      expect(coverFileProblem('cover.pdf', 11 * 1024 * 1024), 'The PDF is larger than 10 MB');
      AppConfig.lang = 'ar';
      expect(coverFileProblem('cover.docx', 10), 'الغلاف صورة PNG أو JPG أو ملف PDF');
    });

    test('a PDF page is asked for with ?page=; the answer becomes the upload; a refusal is in words', () async {
      final api = FakeApi({
        'POST /api/v1/exports/layout/assets': (o) => o.uri.queryParameters['page'] == '9'
            ? const FakeResponse(422, {'detail': {'code': 'pdf_page_out_of_range', 'message': 'x', 'pages': 4}})
            : {'asset_id': _asset, 'width': 1240, 'height': 1754, 'from_pdf': true, 'pages': 4, 'page': 3},
      }, latency: const Duration(milliseconds: 1))
        ..install();
      addTearDown(api.uninstall);
      await ApiClient().primeSession();
      final pdf = Uint8List.fromList(utf8.encode('%PDF-1.4 fake'));
      final r = await uploadCover(LayoutApi.instance, pdf, 'cover.pdf', page: 3);
      expect(api.calls.map((c) => c.key), contains('POST /api/v1/exports/layout/assets?page=3'));
      expect((r.upload!.assetId, r.upload!.page, r.upload!.pages, r.upload!.name), (_asset, 3, 4, 'cover.pdf'));
      final bad = await uploadCover(LayoutApi.instance, pdf, 'cover.pdf', page: 9);
      expect(bad.upload, isNull);
      expect(bad.error, 'The PDF has no such page');
    });
  });

  group('the cover as a page', () {
    test('an uploaded cover: the picture is the page, the details box only when on, the cover code in the corner', () {
      final plain = examCoverOf(_uploaded(), answer: false, rtl: false)!;
      final d = plain.design!.designs.values.single;
      expect(d.page.backgroundImage, _asset);
      expect(d.page.backgroundFit, 'contain');
      expect(d.row.elements, isEmpty);
      expect(plain.marksTable, isFalse);

      final stamped = examCoverOf(_uploaded(stamp: true), answer: false, rtl: true, code: _code)!.design!.designs.values.single;
      final ids = stamped.row.elements.map((e) => e.id).toList();
      expect(ids, ['cover.stamp.box', 'cover.stamp.name', 'cover.stamp.ids', 'cover.code']);
      final code = stamped.row.elements.last;
      expect((code.kind, code.value, code.x), ('qr', _code, 0.0));
      expect(code.y + code.h, closeTo(stamped.page.contentHeight, .01), reason: 'the bottom corner');
      final box = stamped.row.elements.first;
      expect(box.y + box.h, lessThan(code.y), reason: 'the bottom box stays above the code');
      expect(stamped.row.elements[1].value, 'الاسم: {{student_name}}');
    });

    test('a designed cover keeps its design and gains the code; none and an empty upload print nothing', () {
      final designed = examCoverOf(const PaperCoverSpec(university: 'U'), answer: false, rtl: false, code: _code)!;
      expect(designed.design!.designs.values.single.row.elements.last.kind, 'qr');
      expect(designed.marksTable, isTrue);
      expect(examCoverOf(const PaperCoverSpec(), answer: false, rtl: false)!.design, isNull, reason: 'no code: the built-in cover as before');
      expect(examCoverOf(const PaperCoverSpec(mode: CoverMode.none), answer: false, rtl: false), isNull);
      expect(examCoverOf(const PaperCoverSpec(mode: CoverMode.uploaded), answer: false, rtl: false), isNull);
      expect(examCoverOf(const PaperCoverSpec(), answer: true, rtl: false), isNull, reason: 'the answers have no cover unless chosen');
      final answer = examCoverOf(_uploaded(answer: const AnswerCoverSpec(mode: CoverMode.uploaded, upload: CoverUpload(assetId: 'b2'))), answer: true, rtl: false)!;
      expect(answer.design!.designs.values.single.page.backgroundImage, 'b2');
      expect(coverAssetDocs(_uploaded(answer: const AnswerCoverSpec(mode: CoverMode.uploaded, upload: CoverUpload(assetId: 'b2'))))
          .map((x) => x?.designs.values.single.page.backgroundImage), [null, _asset, 'b2']);
    });

    test('PDF: the cover is an extra first page; page numbers and QR payloads belong to the paper alone', () async {
      final plain = await _pdf([_doc(qr: const ['Q1', 'Q2', 'Q3', 'Q4'])]);
      final paperPages = plain.pages.single;
      final covered = paperWithDesign(_doc(qr: const ['Q1', 'Q2', 'Q3', 'Q4']), cover: _uploaded(stamp: true), assets: {_asset: _picture}, coverCode: _code);
      expect(covered.cover, isNotNull);
      final seen = <int, Set<(int, int)>>{};
      paperFooterProbe = (p, no, total) {
        if (p >= 0) (seen[p] ??= {}).add((no, total));
      };
      addTearDown(() => paperFooterProbe = null);
      final out = await _pdf([covered, covered]);
      expect(out.pages, [paperPages, paperPages], reason: 'the cover is not counted');
      expect(_pdfPages(out.bytes), 2 * (paperPages + 1), reason: 'one cover in front of each copy');
      for (final p in [0, 1]) {
        expect(seen[p], {for (var i = 1; i <= paperPages; i++) (i, paperPages)}, reason: 'copy $p numbers its own pages from 1, after its cover');
      }
    });

    test('Word: the cover is its own section holding the picture; the page count is the paper\'s', () {
      final plain = _doc();
      final covered = paperWithDesign(plain, cover: _uploaded(stamp: true), assets: {_asset: _picture}, coverCode: _code);
      expect(wordPageCount(covered, PaperTemplate.minimal), wordPageCount(plain, PaperTemplate.minimal));
      final zip = ZipDecoder().decodeBytes(examPaperDocx(covered, PaperTemplate.minimal));
      final media = zip.files.where((f) => f.name.startsWith('word/media/')).toList();
      expect(media.length, greaterThanOrEqualTo(2), reason: 'the cover picture and the cover code');
      final doc = utf8.decode(zip.files.firstWhere((f) => f.name == 'word/document.xml').content as List<int>);
      expect(doc.contains('behindDoc="1"'), isTrue, reason: 'the picture sits behind the details box');
      expect('<w:sectPr>'.allMatches(doc).length, greaterThan('<w:sectPr>'.allMatches(utf8.decode(ZipDecoder()
          .decodeBytes(examPaperDocx(plain, PaperTemplate.minimal)).files.firstWhere((f) => f.name == 'word/document.xml').content as List<int>)).length));
    });
  });

  group('the picker', () {
    Future<(FakeApi, List<Map>)> backend() async {
      final puts = <Map>[];
      final api = FakeApi({
        'GET /api/v1/exam/exams/5/paper-design': (_) => {'document': null, 'cover': _uploaded().toJson(), 'version': 2, 'cover_code': _code},
        'PUT /api/v1/exam/exams/5/paper-design': (o) {
          final b = o.data as Map;
          puts.add(b);
          return {'document': b['document'], 'cover': b['cover'], 'version': (b['version'] as int) + 1, 'cover_code': _code};
        },
        'GET /api/v1/exports/layout/assets/': (_) => const FakeResponse(404, {'detail': {'code': 'asset_not_found'}}),
        'POST /api/v1/exports/layout/assets/keep': (_) => {'kept': 1},
      }, latency: const Duration(milliseconds: 1))
        ..install();
      addTearDown(api.uninstall);
      await ApiClient().primeSession();
      return (api, puts);
    }

    Future<void> settle(WidgetTester t) async {
      for (var i = 0; i < 5; i++) {
        await t.pump(const Duration(milliseconds: 200));
      }
    }

    testWidgets('loads the choice, "same for both" and the details box save with the version held', (t) async {
      final (_, puts) = await backend();
      final saved = <int>[];
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(900, 1800);
      addTearDown(t.view.reset);
      await t.pumpWidget(layoutHost(SingleChildScrollView(child: ExamCoverEditor(examId: 5, onSaved: (s) => saved.add(s.version))), scale: 1));
      await settle(t);
      expect(find.byKey(const ValueKey('cover.paper.thumb')), findsOneWidget);
      expect(find.text('Page 2 of 4'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('cover.same')));
      await settle(t);
      expect(puts, hasLength(1));
      expect(puts.single['version'], 2);
      expect((puts.single['cover'] as Map)['answer'], containsPair('same', true));
      expect(find.byKey(const ValueKey('cover.answer.same_text')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('cover.paper.stamp')));
      await settle(t);
      await t.tap(find.byKey(const ValueKey('cover.paper.place.middle')));
      await settle(t);
      expect(puts, hasLength(3));
      expect(puts.last['version'], 4, reason: 'each save sends the version the last one returned');
      expect((puts.last['cover'] as Map)['stamp'], {'on': true, 'place': 'middle'});
      await t.tap(find.byKey(const ValueKey('cover.paper.remove')));
      await settle(t);
      expect(puts.last['cover'], isNull, reason: 'removed, with "same" on: nothing prints any more, saved as no cover');
      expect(saved, [3, 4, 5, 6]);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('layout: every state, phone and desktop, both languages', (t) async {
      final pics = {_asset: _picture};
      for (final spec in [
        const PaperCoverSpec(mode: CoverMode.none),
        const PaperCoverSpec(university: 'A university with a rather long official name'),
        const PaperCoverSpec(mode: CoverMode.uploaded),
        _uploaded(stamp: true, answer: const AnswerCoverSpec(mode: CoverMode.uploaded, upload: CoverUpload(assetId: _asset, name: 'answers.png'))),
        _uploaded(answer: const AnswerCoverSpec(same: true)),
        const PaperCoverSpec(answer: AnswerCoverSpec(same: true)),
      ]) {
        await expectNoLayoutErrors(
            t, () => SingleChildScrollView(child: ExamCoverPickerBody(spec: spec, pictures: pics, university: TextEditingController(text: spec.university))));
      }
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: ExamCoverPickerBody(spec: _uploaded(), busy: 'paper', error: 'The PDF is larger than 10 MB')));
    });
  });
}
