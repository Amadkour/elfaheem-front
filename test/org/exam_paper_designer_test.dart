// The paper designer's host (D-196, FD2): the design API's bodies and the 409 mapping over FakeApi, the "Do you have a
// template?" block's three paths, the kill switch, the picture-bytes resolution and the new widgets under the layout
// harness.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/engine/design_engine.dart';
import 'package:flutter_education_app/design/export_layout/layout_api.dart';
import 'package:flutter_education_app/design/export_layout/layout_element_view.dart' show LayoutAssets;
import 'package:flutter_education_app/design/export_layout/layout_model.dart';
import 'package:flutter_education_app/features/exams/exam_authoring.dart';
import 'package:flutter_education_app/features/exams/exam_cover_picker.dart';
import 'package:flutter_education_app/features/exams/exam_paper_design_api.dart';
import 'package:flutter_education_app/features/exams/exam_paper_designer.dart';
import 'package:flutter_education_app/features/exams/exam_paper_sheet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../ui/layout_harness.dart';

ExamView _view() => ExamView.fromJson({
      'id': 5, 'org_id': 2, 'course_id': 9, 'title': 'Final exam', 'status': 'published', 'starts_at': '2026-12-01T08:00:00', 'duration_minutes': 120,
      'max_attempts': 1, 'results_policy': 'when_published', 'high_stakes': false, 'allowed_platforms': ['web'], 'settings': {}, 'version': 1, 'max_score': 2,
      'sections': [
        {
          'id': 1, 'position': 0, 'title': 'A', 'mode': 'paper', 'weight': 1,
          'questions': [
            {'id': 1, 'type': 'true_false', 'body': {'prompt': 'The sun is a star.'}, 'answer': {'correct': true}, 'points': 2, 'placement_id': 1, 'position': 1, 'tags': [], 'version': 1},
          ],
        },
      ],
    });

LayoutDocument _starterDoc(String purpose) => blankPaperDoc(purpose: purpose, lang: 'en')..designs['ar'] = LayoutDesign(mode: 'page', page: LayoutPage(rtl: true));

Map<String, Object?> _starterJson(String key, String purpose) => {
      'key': key,
      'purpose': purpose,
      'name_ar': 'كلاسيكي',
      'name_en': 'Classic',
      'description_en': 'Header, footer and a free strip',
      'mode': 'page',
      'document': _starterDoc(purpose).toJson(),
    };

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

  Future<FakeApi> backend(Map<String, FakeHandler> routes) async {
    final api = FakeApi(routes, latency: const Duration(milliseconds: 1))..install();
    addTearDown(api.uninstall);
    await ApiClient().primeSession();
    return api;
  }

  group('ExamPaperDesignApi', () {
    test('load reads the document, the cover and the version', () async {
      final doc = _starterDoc(DesignPurpose.examPaper).toJson();
      await backend({
        'GET /api/v1/exam/exams/5/paper-design': (_) => {
              'document': doc,
              'cover': {'design': null, 'university': 'Cairo University', 'marks_table': false},
              'version': 3,
            },
      });
      final s = await ExamPaperDesignApi().load(5);
      expect(s!.version, 3);
      expect(s.document!.purpose, DesignPurpose.examPaper);
      expect(s.cover!.university, 'Cairo University');
      expect(s.cover!.marksTable, isFalse);
      expect(s.cover!.design, isNull);
    });

    test('an exam with no design is empty at version 0; an older server loads as null', () async {
      await backend({'GET /api/v1/exam/exams/5/paper-design': (_) => {'document': null, 'cover': null, 'version': 0}});
      final s = await ExamPaperDesignApi().load(5);
      expect(s!.isEmpty, isTrue);
      expect(s.version, 0);
      expect(await ExamPaperDesignApi().load(6), isNull); // bare 404
    });

    test('save sends document, cover and version, and returns the new version', () async {
      Object? sent;
      await backend({
        'PUT /api/v1/exam/exams/5/paper-design': (o) {
          sent = o.data;
          return {'document': (o.data as Map)['document'], 'cover': (o.data as Map)['cover'], 'version': 4};
        },
      });
      final doc = _starterDoc(DesignPurpose.examPaper);
      final r = await ExamPaperDesignApi().save(5, document: doc, cover: const PaperCoverSpec(university: 'U', marksTable: true), version: 3);
      expect(r.ok, isTrue);
      expect(r.state!.version, 4);
      final body = sent as Map;
      expect(body['version'], 3);
      expect((body['document'] as Map)['purpose'], DesignPurpose.examPaper);
      expect((body['document'] as Map).containsKey('source'), isFalse);
      expect(body['cover'], {'mode': 'designed', 'design': null, 'university': 'U', 'marks_table': true, 'stamp': {'on': false, 'place': 'top'}});
    });

    test('save without a design or a cover sends nulls', () {
      expect(paperDesignBody(document: null, cover: null, version: 0), {'document': null, 'cover': null, 'version': 0});
    });

    test('a stale version (409 design_conflict) is a conflict, not an error', () async {
      await backend({
        'PUT /api/v1/exam/exams/5/paper-design': (_) => const FakeResponse(409, {'detail': {'code': 'design_conflict', 'message': 'stale'}}),
      });
      final r = await ExamPaperDesignApi().save(5, document: _starterDoc(DesignPurpose.examPaper), version: 1);
      expect(r.conflict, isTrue);
      expect(r.ok, isFalse);
      expect(r.error, isNull);
    });

    test('other failures come back as text', () async {
      await backend({
        'PUT /api/v1/exam/exams/5/paper-design': (_) => const FakeResponse(413, {'detail': {'code': 'design_too_big', 'message': 'big'}}),
      });
      final r = await ExamPaperDesignApi().save(5, document: _starterDoc(DesignPurpose.examPaper), version: 1);
      expect(r.conflict, isFalse);
      expect(r.error, contains('512'));
    });
  });

  group('pieces', () {
    test('the paper placeholders are the starters\' keys; the cover adds university', () {
      final keys = paperFields().map((f) => f.key).toList();
      expect(keys, containsAll(['institution', 'course', 'title', 'date', 'duration', 'total', 'version', 'student_name', 'seat', 'instructions', 'page', 'pages']));
      expect(keys, isNot(contains('university')));
      expect(paperFields(cover: true).map((f) => f.key), contains('university'));
    });

    test('paperDocFrom copies a starter into one language of the wanted purpose', () {
      final src = _starterDoc(DesignPurpose.examCover)..languages.addAll(['ar', 'en']);
      final d = paperDocFrom(src, purpose: DesignPurpose.examPaper, lang: 'ar');
      expect(d.purpose, DesignPurpose.examPaper);
      expect(d.languages, ['ar']);
      expect(src.purpose, DesignPurpose.examCover); // the source is untouched
    });

    test('the picture ids of a design: background, band and row images, not URLs', () {
      final d = blankPaperDoc(purpose: DesignPurpose.examPaper, assetId: 'bg1', lang: 'en');
      final g = d.designs['en']!;
      g.header.elements.add(LayoutElement(id: 'a', kind: 'image', value: 'logo1'));
      g.footer.elements.add(LayoutElement(id: 'b', kind: 'signature', value: 'sig1'));
      g.footer.elements.add(LayoutElement(id: 'c', kind: 'image', value: 'https://x/y.png'));
      g.footer.elements.add(LayoutElement(id: 'd', kind: 'text', value: 'not a picture'));
      expect(paperAssetIds(d), {'bg1', 'logo1', 'sig1'});
      expect(paperAssetIds(null), isEmpty);
    });

    test('resolvePaperAssets: the designer\'s memory, then the device copy; missing ids are left out', () async {
      final mem = Uint8List.fromList([1, 2, 3]), disk = Uint8List.fromList([4, 5]);
      LayoutAssets.put('mem', mem);
      SharedPreferences.setMockInitialValues({'exam_paper.asset.disk': base64Encode(disk)});
      await backend({});
      final d = blankPaperDoc(purpose: DesignPurpose.examPaper, assetId: 'mem', lang: 'en');
      d.designs['en']!.header.elements
        ..add(LayoutElement(id: 'a', kind: 'image', value: 'disk'))
        ..add(LayoutElement(id: 'b', kind: 'image', value: 'nowhere'));
      final out = await resolvePaperAssets([d]);
      expect(out['mem'], mem);
      expect(out['disk'], disk);
      expect(out.containsKey('nowhere'), isFalse);
      // a picture the designer holds is kept on the device for the next session
      expect((await SharedPreferences.getInstance()).getString('exam_paper.asset.mem'), base64Encode(mem));
    });

    test('a PDF letterhead goes to the assets route and keeps its id', () async {
      await backend({
        'POST /api/v1/exports/layout/assets': (_) => const FakeResponse(201, {'asset_id': 'a1', 'from_pdf': true, 'pages': 2}),
      });
      final id = await uploadPaperBackground(LayoutApi.instance, Uint8List.fromList([1, 2, 3]), 'letterhead.PDF');
      expect(id, 'a1');
      final r = await LayoutApi.instance.uploadAssetInfo(Uint8List(3), 'x.pdf');
      expect(r.data!.fromPdf, isTrue);
      expect(r.data!.pages, 2);
      expect((await LayoutApi.instance.uploadAsset(Uint8List(3), 'x.png')).data, 'a1');
    });

    test('the gallery puts the classic starter first and the saved templates last', () {
      final starters = [
        LayoutStarter(key: 'exam_paper_modern', purpose: 'exam_paper', nameAr: 'عصري', nameEn: 'Modern', mode: 'page', document: _starterDoc('exam_paper')),
        LayoutStarter(key: 'exam_paper_classic', purpose: 'exam_paper', nameAr: 'كلاسيكي', nameEn: 'Classic', mode: 'page', document: _starterDoc('exam_paper')),
        LayoutStarter(key: 'exam_cover_classic', purpose: 'exam_cover', nameAr: 'غلاف', nameEn: 'Cover', mode: 'page', document: _starterDoc('exam_cover')),
      ];
      final mine = [LayoutTemplate(id: 9, name: 'Mine', document: _starterDoc('exam_paper'))];
      final c = paperStartChoices(starters, mine);
      expect(c.map((x) => x.id), ['exam_paper_classic', 'exam_paper_modern', 'mine:9']);
      expect(c.first.recommended, isTrue);
      expect(paperStartChoices(starters, const [], purpose: 'exam_cover').map((x) => x.id), ['exam_cover_classic']);
    });
  });

  group('the choice block', () {
    Widget block({List<String>? log, bool hasDesign = false, bool word = false, bool coverOn = false, String? busy}) => SingleChildScrollView(
          child: ExamPaperDesignBlock(
            hasDesign: hasDesign,
            wordSelected: word,
            wordName: word ? 'school-template.docx' : null,
            busy: busy,
            onProfessional: () => log?.add('professional'),
            onWord: () => log?.add('word'),
            onLetterhead: () => log?.add('letterhead'),
            onDesign: () => log?.add('design'),
            onSaveTemplate: () => log?.add('save'),
            onUseBuiltIn: () => log?.add('builtin'),
            cover: coverOn
                ? ExamCoverPickerBody(
                    spec: const PaperCoverSpec(), university: TextEditingController(), onMode: (a, m) => log?.add('cover:${m.name}'), onDesign: () => log?.add('coverDesign'))
                : null,
          ),
        );

    testWidgets('the three paths call their own handlers', (t) async {
      final log = <String>[];
      await t.pumpWidget(layoutHost(block(log: log)));
      expect(find.text('Do you have a template?'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('paper.source.professional')));
      await t.tap(find.byKey(const ValueKey('paper.source.word')));
      await t.tap(find.byKey(const ValueKey('paper.source.letterhead')));
      expect(log, ['professional', 'word', 'letterhead']);
      expect(find.byKey(const ValueKey('paper.design')), findsNothing); // no design yet: no design actions
    });

    testWidgets('a chosen design shows its actions; the cover slot holds the cover picker (D-730)', (t) async {
      final log = <String>[];
      await t.pumpWidget(layoutHost(block(log: log, hasDesign: true, coverOn: true)));
      for (final k in ['paper.design', 'paper.save_template', 'paper.use_builtin', 'cover.paper.design', 'cover.paper.university', 'cover.paper.mode.uploaded']) {
        expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
      }
      await t.tap(find.byKey(const ValueKey('paper.design')));
      await t.tap(find.byKey(const ValueKey('paper.save_template')));
      await t.ensureVisible(find.byKey(const ValueKey('cover.paper.mode.uploaded')));
      await t.tap(find.byKey(const ValueKey('cover.paper.mode.uploaded')));
      expect(log, ['design', 'save', 'cover:uploaded']);
    });

    testWidgets('while something runs the actions are disabled', (t) async {
      final log = <String>[];
      await t.pumpWidget(layoutHost(block(log: log, hasDesign: true, busy: 'design')));
      await t.tap(find.byKey(const ValueKey('paper.source.professional')), warnIfMissed: false);
      await t.tap(find.byKey(const ValueKey('paper.design')), warnIfMissed: false);
      expect(log, isEmpty);
    });

    testWidgets('layout: no overflow in any state', (t) async {
      for (final (design, word, cover) in [(false, false, false), (true, false, true), (false, true, false)]) {
        await expectNoLayoutErrors(t, () => block(hasDesign: design, word: word, coverOn: cover));
      }
    });

    testWidgets('layout: the starter gallery and the conflict dialog', (t) async {
      final choices = [
        PaperStartChoice(id: 'exam_paper_classic', name: 'Classic', description: 'Header, footer and a free strip at the bottom for the QR', document: _starterDoc('exam_paper'), recommended: true),
        PaperStartChoice(id: 'mine:1', name: 'A very long template name that keeps going on and on', document: _starterDoc('exam_paper'), mine: true),
      ];
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: PaperStartGallery(title: 'Pick a design', choices: choices, onPick: (_) {})));
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: PaperStartGallery(title: 'Pick a design', choices: const [], onPick: (_) {})));
      await expectNoLayoutErrors(t, () => Builder(builder: (c) => TextButton(onPressed: () => showPaperConflictDialog(c), child: const Text('go'))), act: (t) async {
        await t.tap(find.text('go'));
        await t.pump(const Duration(milliseconds: 300));
        expect(find.byKey(const ValueKey('paper.conflict')), findsOneWidget);
      });
    });
  });

  group('the sheet', () {
    Map<String, FakeHandler> routes({required List<String> puts, int version = 0, Map<String, Object?>? stored}) => {
          'GET /api/v1/exam/exams/5/paper-design': (_) => stored ?? {'document': null, 'cover': null, 'version': version},
          'PUT /api/v1/exam/exams/5/paper-design': (o) {
            puts.add(jsonEncode(o.data));
            final b = o.data as Map;
            return {'document': b['document'], 'cover': b['cover'], 'version': (b['version'] as int) + 1};
          },
          'GET /api/v1/exports/layout/starters': (_) => {
                'items': [_starterJson('exam_paper_classic', 'exam_paper'), _starterJson('exam_cover_classic', 'exam_cover')],
              },
          'GET /api/v1/exports/templates': (_) => {'items': [], 'last_used_id': null},
        };

    Future<void> openSheet(WidgetTester t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(900, 1600);
      addTearDown(t.view.reset);
      await t.pumpWidget(layoutHost(SingleChildScrollView(child: ExamPaperSheet(view: _view(), course: 'Biology', orgName: 'Al Noor')), scale: 1));
      await t.pump(const Duration(milliseconds: 300));
    }

    Future<void> settle(WidgetTester t) async {
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 300));
      }
    }

    Future<void> close(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    }

    testWidgets('Professional default: the gallery, then the pick is stored with the version', (t) async {
      final puts = <String>[];
      final api = await backend(routes(puts: puts, version: 2));
      await openSheet(t);
      expect(find.byKey(const ValueKey('paper.source.professional')), findsOneWidget);
      expect(find.text('Excel'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('paper.source.professional')));
      await settle(t);
      expect(api.calls.map((c) => c.key), contains('GET /api/v1/exports/layout/starters?purpose=exam_paper'));
      expect(find.byKey(const ValueKey('paper.start.exam_paper_classic')), findsOneWidget);
      expect(find.byKey(const ValueKey('paper.start.exam_cover_classic')), findsNothing); // the cover starter is not offered for the paper
      await t.tap(find.byKey(const ValueKey('paper.start.exam_paper_classic')));
      await settle(t);
      expect(puts, hasLength(1));
      final body = jsonDecode(puts.single) as Map;
      expect(body['version'], 2);
      expect((body['document'] as Map)['purpose'], 'exam_paper');
      // a chosen design: its actions show and the built-in picker is replaced
      expect(find.byKey(const ValueKey('paper.design')), findsOneWidget);
      expect(find.text('Pick a design'), findsNothing);
      await close(t);
    });

    testWidgets('a stored design is loaded when the sheet opens', (t) async {
      await backend(routes(puts: [], stored: {'document': _starterDoc('exam_paper').toJson(), 'cover': null, 'version': 4}));
      await openSheet(t);
      await settle(t);
      expect(find.byKey(const ValueKey('paper.design')), findsOneWidget);
      expect(find.text('Pick a design'), findsNothing);
      await close(t);
    });

    testWidgets('My Word template keeps today\'s picker', (t) async {
      await backend(routes(puts: []));
      await openSheet(t);
      expect(find.text('Pick a design'), findsOneWidget);
      expect(find.byKey(const ValueKey('paper.source.word')), findsOneWidget);
      await close(t);
    });

    testWidgets('the kill switch exam.paper_designer hides the block and the sheet stays as it was', (t) async {
      AppConfig.disableList = ['exam.paper_designer'];
      final api = await backend(routes(puts: [], stored: {'document': _starterDoc('exam_paper').toJson(), 'cover': null, 'version': 4}));
      await openSheet(t);
      await settle(t);
      expect(find.text('Do you have a template?'), findsNothing);
      expect(find.byKey(const ValueKey('paper.source.professional')), findsNothing);
      expect(find.text('Pick a design'), findsOneWidget); // today's picker, even with a stored design
      expect(find.text('Excel'), findsOneWidget);
      expect(api.calls.where((c) => c.path.endsWith('/paper-design')), isEmpty);
      await close(t);
    });
  });
}
