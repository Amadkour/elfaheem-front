// Exam Hub, F3 (delivery, D-354): the printed-identifier logic, one Word file for many copies, the page replay, and the
// layout of the presentational widgets.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:dio/dio.dart' show FormData, MultipartFile;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/exams/exam_paper.dart';
import 'package:flutter_education_app/features/exams/exam_paper_bands.dart';
import 'package:flutter_education_app/features/exams/exam_paper_docx.dart';
import 'package:flutter_education_app/features/exams/exam_paper_pdf.dart';
import 'package:flutter_education_app/features/exams/exam_engine_api.dart' show EngineResult;
import 'package:flutter_education_app/features/exams/exam_versions.dart';
import 'package:flutter_education_app/features/exams/hub/deliver/deliver_logic.dart';
import 'package:flutter_education_app/features/exams/hub/deliver/exam_deliver_screen.dart';
import 'package:flutter_education_app/features/exams/hub/deliver/identifier_plan_step.dart';
import 'package:flutter_education_app/features/exams/hub/deliver/paper_page_replay.dart';
import 'package:flutter_education_app/features/exams/paper/exam_setup.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

ExamPaperDoc doc({bool rtl = true}) => ExamPaperDoc(
      institution: 'مدرسة النور', course: 'رياضيات', title: 'امتحان الفصل', dateText: '2026-11-20', durationText: '60', total: 4, instructions: const ['أجب عن كل الأسئلة'], rtl: rtl,
      sections: [
        PaperSection(title: 'القسم الأول', instructions: '', questions: [
          PaperQuestion(id: 1, number: 1, type: 'mcq_single', prompt: 'كم يساوي 2 + 2؟', points: 2, options: const ['3', '4', '5'], correct: const {1}),
          PaperQuestion(id: 2, number: 2, type: 'essay', prompt: 'اشرح الجمع', points: 2),
        ]),
      ],
    );

const ids = [PaperPrintedId(labelAr: 'رقم الجلوس', labelEn: 'Seat', value: '1024'), PaperPrintedId(labelAr: 'القاعة', labelEn: 'Hall', value: 'B2')];

Future<(ByteData, ByteData)> fonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final s = PaperStyle.of(PaperTemplate.minimal);
  return (await rootBundle.load(s.regular), await rootBundle.load(s.bold));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => AppConfig.lang = 'en');

  group('printed identifiers on the paper', () {
    test('the student box without identifiers is unchanged', () {
      final r = paperStudentBoxRows(doc().copyWith(studentName: 'Ali', seat: '7'));
      expect(r.length, 2);
      expect(r[0].map((c) => c.key), ['name', 'id']);
      expect(r[1].map((c) => c.key), ['group', 'seat']);
      expect(r[0][0].value, 'Ali');
    });

    test('the plan\'s identifiers reach the copy, and survive copyWith', () {
      final plan = PrintPlan.fromJson({
        'items': [
          {'copy_no': 1, 'form': null, 'pages': ['q1'], 'student': {'id': 5, 'name': 'Ali', 'identifier_masked': '••12', 'identifiers': [{'label_ar': 'رقم الجلوس', 'label_en': 'Seat', 'value': '1024'}]}},
        ],
      });
      final d = copiesFor(doc(), plan, const ExamVersions()).single;
      expect(d.printedIds.single.value, '1024');
      expect(d.copyWith(qrSlots: 1).printedIds.single.value, '1024');
      expect(d.paperValues()['identifier_1'], '1024');
      expect(d.paperValues()['identifier_4'], '');
      final cells = paperStudentBoxRows(d).expand((r) => r).toList();
      expect(cells.where((c) => c.key == 'identifier').single.value, '1024');
    });

    test('four identifiers make three rows, and a repeated name is dropped', () {
      final d = ExamPaperCopy.of(doc().copyWith(studentName: 'Ali'), const [
        PaperPrintedId(labelAr: 'a', labelEn: 'a', value: '1'),
        PaperPrintedId(labelAr: 'b', labelEn: 'b', value: '2'),
        PaperPrintedId(labelAr: 'c', labelEn: 'c', value: '3'),
        PaperPrintedId(labelAr: 'd', labelEn: 'd', value: '4'),
      ]);
      expect(paperStudentBoxRows(d).length, 3);
      final same = ExamPaperCopy.of(doc().copyWith(studentName: 'Ali'), const [PaperPrintedId(labelAr: 'Name', labelEn: 'Name', value: 'Ali')]);
      expect(paperStudentBoxRows(same).expand((r) => r).where((c) => c.key == 'identifier'), isEmpty);
    });

    test('a blank copy shows the labels to write in', () {
      final plan = PrintPlan.fromJson({
        'items': [{'copy_no': 1, 'form': null, 'pages': const <String>[], 'student': null}],
      });
      final d = copiesFor(doc(), plan, const ExamVersions(), blankIds: const [PaperPrintedId(labelAr: 'جلوس', labelEn: 'Seat')]).single;
      expect(d.printedIds.single.value, '');
    });

    test('the PDF and Word writers print the identifier', () async {
      final (regular, bold) = await fonts();
      final d = ExamPaperCopy.of(doc(rtl: false).copyWith(studentName: 'Ali', qrPages: const ['x']), ids);
      final pdf = await examPaperPdfMany([d], PaperTemplate.minimal, regular: regular, bold: bold);
      expect(pdf.bytes.length, greaterThan(1000));
      final parts = ZipDecoder().decodeBytes(examPaperDocx(d, PaperTemplate.minimal));
      final xml = utf8.decode(parts.files.firstWhere((f) => f.name == 'word/document.xml').content as List<int>);
      expect(xml, contains('1024'));
      expect(xml, contains('B2'));
    });
  });

  group('one Word file for many copies', () {
    test('every copy, its own headers and QR footers, and page numbering restarted', () async {
      final copies = [
        for (var i = 0; i < 3; i++) ExamPaperCopy.of(doc().copyWith(studentName: 'Student $i', version: 'A', qrPages: ['qr$i-1', 'qr$i-2']), ids),
      ];
      final bytes = await examPaperDocxMany(copies, PaperTemplate.minimal);
      final z = ZipDecoder().decodeBytes(bytes);
      String part(String n) => utf8.decode(z.files.firstWhere((f) => f.name == n).content as List<int>);
      final document = part('word/document.xml');
      for (var i = 0; i < 3; i++) {
        expect(document, contains('Student $i'));
      }
      // one body: a section per page of each copy, numbering restarts on each copy's first section
      expect('<w:body>'.allMatches(document).length, 1);
      expect('<w:pgNumType w:start="1"/>'.allMatches(document).length, 3);
      // the headers exist under unique names and every rel target resolves
      final rels = part('word/_rels/document.xml.rels');
      final names = {for (final f in z.files) f.name};
      for (final m in RegExp(r'Target="([^"]+)"').allMatches(rels)) {
        expect(names, contains('word/${m[1]}'));
      }
      for (final m in RegExp(r'r:(?:id|embed)="([^"]+)"').allMatches(document)) {
        expect(rels, contains('Id="${m[1]}"'), reason: m[1]);
      }
      final types = part('[Content_Types].xml');
      for (final f in names.where((n) => RegExp(r'^word/d\d+_(header|footer)\d+\.xml$').hasMatch(n))) {
        expect(types, contains('/$f'));
      }
      // a copy's "of N" counts that copy, not the whole file
      final footer = part('word/d0_footer1.xml');
      expect(footer.contains('NUMPAGES'), isFalse);
    });

    test('one copy stays the plain single-document file', () async {
      final z = ZipDecoder().decodeBytes(await examPaperDocxMany([doc()], PaperTemplate.minimal));
      expect(z.files.any((f) => f.name == 'word/header1.xml'), isTrue);
    });

    test('the same logo is stored once across copies', () async {
      final logo = Uint8List.fromList(base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='));
      final copies = [
        for (var i = 0; i < 4; i++)
          ExamPaperDoc(institution: 'x', course: '', title: 't', dateText: '', durationText: '', total: 1, instructions: const [], rtl: false, logo: logo, sections: doc().sections, studentName: 's$i'),
      ];
      final z = ZipDecoder().decodeBytes(await examPaperDocxMany(copies, PaperTemplate.minimal));
      expect(z.files.where((f) => f.name.contains('logo')).length, 1);
    });
  });

  group('a PDF build', () {
    test('reports progress and can be cancelled between papers', () async {
      final (regular, bold) = await fonts();
      final copies = [for (var i = 0; i < 3; i++) doc().copyWith(studentName: 'Student $i')];
      final seen = <int>[];
      var cancel = false;
      await expectLater(
          examPaperPdfMany(copies, PaperTemplate.minimal, regular: regular, bold: bold, control: PaperBuildControl(onStep: (a, _) {
            seen.add(a);
            if (a >= 3) cancel = true;
          }, cancelled: () => cancel)),
          throwsA(isA<PaperBuildCancelled>()));
      expect(seen, isNotEmpty);
    });
  });

  group('the page replay', () {
    testWidgets('draws every page of the written file', (tester) async {
      final (regular, bold) = await fonts();
      await tester.runAsync(() async {
        final d = ExamPaperCopy.of(doc(rtl: true).copyWith(studentName: 'علي محمد', qrPages: const ['qr-a', 'qr-b']), ids);
        final out = await examPaperPdfMany([d], PaperTemplate.minimal, regular: regular, bold: bold);
        final pages = await replayPdfPages(out.document!);
        expect(pages.length, out.pages.first);
        final img = await pages.first.picture.toImage(200, 283);
        final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
        // something dark was drawn (text and rules), not an empty sheet
        var ink = 0;
        for (var i = 0; i + 3 < data!.lengthInBytes; i += 4) {
          if (data.getUint8(i + 3) > 0 && data.getUint8(i) < 120) ink++;
        }
        expect(ink, greaterThan(40));
        final dir = Platform.environment['F3_RENDER_DIR'];
        if (dir != null) {
          final big = await pages.first.picture.toImage(595, 842);
          final png = await big.toByteData(format: ui.ImageByteFormat.png);
          File('$dir/replay_page1.png').writeAsBytesSync(png!.buffer.asUint8List());
        }
        for (final p in pages) {
          p.dispose();
        }
      });
    });
  });

  group('logic', () {
    test('multiple files in one form field are sent under the same name', () {
      final f = FormData.fromMap({'files': [MultipartFile.fromBytes([1], filename: '1.pdf'), MultipartFile.fromBytes([2], filename: '2.pdf')]});
      expect([for (final e in f.files) e.key].toSet().length, 1);
      expect(f.files.first.key, 'files');
    });

    test('the recommended matching identifier', () {
      final opts = identifierOptions(const [IdentityFieldDef(key: 'academic_id', labelAr: 'أ', labelEn: 'A', kind: 'digits'), IdentityFieldDef(key: 'national_id', labelAr: 'ق', labelEn: 'N', kind: 'digits')]);
      // the exam's own choice wins
      expect(recommendedMatching(opts, const {}, current: const IdentifierChoice('email'))?.choice.source, 'email');
      // full coverage on a good identifier beats a partial one
      expect(recommendedMatching(opts, const {'academic_id': IdCoverage(filled: 5, total: 31), 'national_id': IdCoverage(filled: 31, total: 31)})?.choice.source, 'national_id');
      // with nothing known, a real identifier beats a name
      expect(recommendedMatching(opts, const {})?.choice.source, isNot('name'));
    });

    test('the matching identifier is printed, first, at most four', () {
      PrintedIdSpec p(String s) => PrintedIdSpec(source: s, labelAr: s, labelEn: s);
      final out = printedWithMatching([p('a'), p('b'), p('c'), p('d')], p('m'));
      expect(out.first.source, 'm');
      expect(out.length, 4);
    });

    test('coverage and a masked preview', () {
      final c = IdCoverage.fromJson({'items': [{'student_id': 1, 'name': 'A', 'value': ''}, {'student_id': 2, 'name': 'B', 'value': 'x'}], 'filled': 1, 'total': 2});
      expect(c.missingNames, ['A']);
      expect(coverageText(1, 2), '1 of 2 have a value');
      expect(printedValuePreview('national_id', '29001011234567'), '••••4567');
      expect(printedValuePreview('datalab', '29001011234567'), '29001011234567');
      expect(namesText(['a', 'b', 'c', 'd', 'e', 'f']), 'a, b, c, d and 2 more');
    });

    test('an email is warned about only before the start', () {
      final now = DateTime.utc(2026, 11, 9, 10);
      expect(earlyEmailWarning(now.add(const Duration(hours: 1)), now), isNotNull);
      expect(earlyEmailWarning(now.subtract(const Duration(hours: 1)), now), isNull);
      expect(earlyEmailWarning(null, now), isNull);
    });

    test('upload rounds', () {
      expect(uploadBatches([10, 10, 10], maxBytes: 25), [2, 3]);
      expect(uploadBatches([40, 1], maxBytes: 25), [1, 2]);
      expect(uploadBatches([1, 1, 1], maxBytes: 100, maxFiles: 2), [2, 3]);
      expect(uploadBatches(const []), isEmpty);
    });

    test('the plan the wizard saved decides what Deliver opens on, once read from settings', () {
      expect(DeliverPlan.ofSettings({'other': 1}), isNull);
      expect(DeliverPlan.ofSettings(null), isNull);
      final personal = DeliverPlan.ofSettings({'paper_plan': {'mode': 'personal', 'versions': 1}})!;
      final three = DeliverPlan.ofSettings({'paper_plan': {'mode': 'versions', 'versions': 3}})!;
      expect(personal.personal, isTrue);
      expect(three.versions, 3);
      expect(deliverOpeningScope(personal, paper: true, hasRoster: true), DeliverScope.students);
      expect(deliverOpeningScope(three, paper: true, hasRoster: true), DeliverScope.versions);
      expect(deliverOpeningScope(null, paper: true, hasRoster: true), DeliverScope.students);
      expect(deliverOpeningScope(personal, paper: true, hasRoster: false), DeliverScope.versions);
      expect(deliverOpeningScope(personal, paper: false, hasRoster: true), DeliverScope.versions);
    });

    test('planned versions nobody made are offered; a number the teacher made is left alone', () {
      const three = DeliverPlan(personal: false, versions: 3);
      expect(deliverVersionsOwed(three, 0), 3);
      expect(deliverVersionsOwed(three, 1), 3);
      expect(deliverVersionsOwed(three, 2), isNull);
      expect(deliverVersionsOwed(const DeliverPlan(personal: true), 0), isNull);
      expect(deliverVersionsOwed(const DeliverPlan(personal: false), 0), isNull);
      expect(deliverVersionsOwed(null, 0), isNull);
    });

    test('a masked source gives counts and who is missing, never a value to show', () {
      final m = IdCoverage.fromJson({'filled': 1, 'total': 2, 'masked': true, 'items': [{'student_id': 1, 'name': 'Ali', 'value': '••••1234'}, {'student_id': 2, 'name': 'Sara', 'value': ''}]});
      expect(m.masked, isTrue);
      expect(m.missingNames, ['Sara']);
      const spec = PrintedIdSpec(source: 'national_id', labelAr: 'قومي', labelEn: 'National ID');
      expect(plannedPaperLines([spec], {spec.id: m}).single.$2, '••••1234', reason: 'the shape that prints, not the mask the server sent');
      const academic = PrintedIdSpec(source: 'academic_id', labelAr: 'أكاديمي', labelEn: 'Academic ID');
      final line = plannedPaperLines([academic], {academic.id: m}).single.$2;
      expect(line, isNot(contains('•')), reason: 'an academic number prints whole');
      expect(plannedPaperLines([academic], {academic.id: const IdCoverage(total: 3, masked: true)}).single.$2, '');
      final real = IdCoverage.fromJson({'filled': 1, 'total': 1, 'items': [{'student_id': 1, 'name': 'Ali', 'value': '77'}]});
      const seat = PrintedIdSpec(source: 'datalab', key: 'seat', labelAr: 'جلوس', labelEn: 'Seat');
      expect(plannedPaperLines([seat], {seat.id: real}).single.$2, '77');
    });

    test('masking that blanks everything cannot claim who is missing', () {
      final m = IdCoverage.fromJson({'filled': 2, 'total': 3, 'masked': true, 'items': [{'student_id': 1, 'name': 'A', 'value': ''}, {'student_id': 2, 'name': 'B', 'value': ''}, {'student_id': 3, 'name': 'C', 'value': ''}]});
      expect(m.namesKnown, isFalse);
      expect(m.missingNames, isEmpty);
      expect(m.missingCount, 1);
    });

    test('a round fits under the nginx cap, and a 413 is said in words', () {
      expect(kDeliverRoundBytes, lessThan(10 * 1024 * 1024));
      final mb = 1024 * 1024;
      expect(uploadBatches([5 * mb, 5 * mb, mb]), [1, 3]);
      final nginx = EngineResult.fail(413, null, '<html>413 Request Entity Too Large</html>');
      expect(deliverTooLarge(nginx), isTrue);
      expect(deliverErrorText(nginx), deliverTooLargeText);
      expect(deliverErrorText(nginx), isNot(contains('<html>')));
    });

    test('new delivery codes, and who could not be reached', () {
      AppConfig.lang = 'en';
      expect(deliverCodeText('delivery_total_too_large'), isNotEmpty);
      expect(deliverCodeText('delivery_daily_limit', {'scope': 'org'}), contains('organization'));
      expect(deliverCodeText('delivery_daily_limit', {'scope': 'global'}), contains('platform'));
      final coded = EngineResult.fail(413, 'delivery_total_too_large', 'x');
      expect(deliverTooLarge(coded), isTrue);
      expect(deliverErrorText(coded), contains('26 MB'));
      ExamDelivery row(List<Map<String, dynamic>> f) => ExamDelivery.fromJson({'id': 'x', 'mode': 'students', 'failed_names': f});
      expect(row(const []).failedText, isNull);
      expect(row(const [{'student_id': 1, 'name': 'Ali'}, {'student_id': 2, 'name': null}]).failedText, 'Could not reach: Ali, and 1 other');
      expect(row(const [{'student_id': 2, 'name': null}, {'student_id': 3, 'name': null}]).failedText, 'Could not reach 2 students');
    });

    test('created_at without a zone is UTC', () {
      final d = ExamDelivery.fromJson({'id': 'x', 'mode': 'whole', 'created_at': '2026-11-09T10:00:00'});
      expect(d.createdAt, DateTime.utc(2026, 11, 9, 10));
    });

    testWidgets('Back does not close the progress dialog', (tester) async {
      await tester.pumpWidget(ThemeConfigScope(provider: ThemeConfigProvider(api: ApiClient()), child: MaterialApp(home: Builder(builder: (context) => TextButton(onPressed: () => showDialog<void>(context: context, barrierDismissible: false, builder: (_) => BuildProgressDialog(progress: const BuildProgress(title: 'x'), onCancel: () {})), child: const Text('open'))))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(BuildProgressDialog), findsOneWidget);
    });

    test('delivery rows', () {
      final d = ExamDelivery.fromJson({'id': 'x', 'mode': 'students', 'recipients': 3, 'sent': 2, 'failed': 0, 'no_email': [{'student_id': 9, 'name': 'Z'}], 'status': 'partial', 'created_by_name': 'T'});
      expect(d.running, isFalse);
      expect(d.summary, contains('2 of 3'));
      expect(anyDeliveryRunning([ExamDelivery.fromJson({'id': 'y', 'mode': 'whole', 'status': 'queued'})]), isTrue);
      expect(deliverCodeText('delivery_file_too_large'), isNotEmpty);
      expect(deliverFileStem('A/B', 'x'), 'A_B - x');
    });
  });

  group('no overflow', () {
    final opts = identifierOptions(const []);
    const cov = IdCoverage(filled: 28, total: 31, items: [IdValueRow(1, 'Ali Hassan', ''), IdValueRow(2, 'Sara Ahmed', '1234')]);
    IdentifierPlanBody plan() => IdentifierPlanBody(
          options: opts,
          printed: [PrintedIdSpec.of(opts[3]), PrintedIdSpec.of(opts[2])],
          matching: opts[3].choice,
          coverage: {opts[3].choice.id: cov, opts[2].choice.id: const IdCoverage(filled: 31, total: 31)},
          recommended: opts[3].choice,
          onToggle: (_) {}, onMatch: (_) {}, onHand: (_) {}, onExcel: (_) {}, onAsk: (_) {}, onNew: () {},
        );

    testWidgets('the identifier plan', (t) => expectNoLayoutErrors(t, () => SingleChildScrollView(child: plan())));
    testWidgets('the roster grid', (t) => expectNoLayoutErrors(t, () {
          final c = [TextEditingController(text: '12')];
          return RosterGrid(rows: const [IdValueRow(1, 'A very long student name that does not fit a phone', '12')], controllers: c, height: 200);
        }));
    testWidgets('the import preview', (t) => expectNoLayoutErrors(t, () => const SingleChildScrollView(
        child: ImportPreviewCard(preview: IdImportPreview(rows: 3, matched: 1, unmatched: [IdImportIssue(2, 'x')], duplicates: [IdImportIssue(3, 'y')], invalid: [IdImportIssue(4, 'z', 'too_long')])))));
    testWidgets('new identifier', (t) => expectNoLayoutErrors(t, () => SingleChildScrollView(child: NewIdentifierForm(onDone: (_, __) {}))));
    testWidgets('printing', (t) => expectNoLayoutErrors(t, () => SingleChildScrollView(
        child: DeliverPrintCard(scope: DeliverScope.students, onScope: (_) {}, word: true, onWord: (_) {}, studentCount: 31, versionCount: 3, showStudents: true, blank: 30, onBlank: (_) {}, onPrint: () {}, onMore: () {}))));
    testWidgets('email', (t) => expectNoLayoutErrors(t, () => SingleChildScrollView(
        child: DeliverEmailCard(canStudents: true, studentCount: 31, noEmailNames: const ['Ali Hassan', 'Sara Ahmed'], coverageKnown: true, earlyWarning: 'The exam has not started yet.',
            deliveries: const [ExamDelivery(id: 'a', mode: 'students', recipients: 31, sent: 28, noEmail: [DeliveryNoEmail(1, 'Ali')], status: 'partial', createdBy: 'Teacher')], onStudents: () {}, onWhole: () {}))));
    testWidgets('a build in progress', (t) => expectNoLayoutErrors(t, () => BuildProgressDialog(progress: const BuildProgress(title: 'Building the student copies ...', done: 7, total: 31), onCancel: () {})));
    testWidgets('the preview pane, loading and empty', (t) async {
      await expectNoLayoutErrors(t, () => const SingleChildScrollView(child: DeliverPreviewPane(pages: null, busy: true)));
      await expectNoLayoutErrors(t, () => const SingleChildScrollView(child: DeliverPreviewPane(pages: [], busy: false, studentName: 'Ali', studentCount: 31)));
    });
  });
}
