// "Use your own sheet" (D-302): the detected layout from the server (test/fixtures/payloads/omr_auto/*.json, real
// `/omr/auto-templates/detect` bodies of a filled bubble sheet photographed by phone and of a written answer table),
// the numbering the review screen shows (the server's order: down each column / across, left / right first, from a
// start number), one ID block at a time, the whole flow pick → detect → check → save over the fake backend, the
// wizard's "Use your own sheet" tile, and no overflow at 320×640 / 1400×900 in Arabic and English.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/exams/paper/exam_setup.dart';
import 'package:flutter_education_app/features/exams/paper/exam_setup_wizard.dart';
import 'package:flutter_education_app/features/exams/paper/templates/own_sheet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../ui/layout_harness.dart';

const _b = '/api/v1/exam/omr/auto-templates';

Map<String, dynamic> _p(String name) => jsonDecode(jsonEncode(payload('omr_auto/$name.json'))) as Map<String, dynamic>;

OwnSheetDraft _draft(String name) => OwnSheetDraft.fromJson(_p(name));

void _tall(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 2400);
  addTearDown(tester.view.reset);
}

Future<void> _frames(WidgetTester tester, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Widget _review(OwnSheetDraft d) => OwnSheetReview(draft: d, name: TextEditingController(text: 'My sheet'), onChanged: () {}, onSave: () {}, onRetake: () {});

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
  });
  setUp(() => AppConfig.lang = 'en');

  test('bubble layout: questions numbered like the server, one ID block, right-to-left and a start number', () {
    final d = _draft('detect_bubble');
    final s = asMapOf(_p('detect_bubble')['summary']);
    expect(d.kind, OwnSheetKind.bubbles);
    expect(d.questions.length, s['questions']);
    expect(d.options, s['options']);
    expect(d.idDigits, s['id_digits']);
    final labels = d.blockLabels.values.toList();
    expect(labels, containsAll(['Q1–20', 'Q21–40', 'Q41–60', 'Student ID']));

    final firstBlock = d.questions.first.block;
    d.rtl = true;
    expect(d.questions.first.block, isNot(firstBlock), reason: 'right to left starts with the rightmost column');
    d.start = 101;
    expect(d.questions.first.n, 101);
    expect(d.blockLabels.values, contains('Q101–120'));

    final id = d.blocks.firstWhere((b) => d.roleOf(b) == 'identifier');
    final other = d.blocks.firstWhere((b) => d.roleOf(b) == 'answers');
    d.setRole(other['id'] as int, 'identifier');
    expect(d.roleOf(id), 'answers', reason: 'one ID block per sheet');
    expect(d.blocks.where((b) => d.roleOf(b) == 'identifier').length, 1);
  });

  test('written table: rows numbered, options and numbers / letters sent with the layout', () {
    final d = _draft('detect_table');
    expect(d.kind, OwnSheetKind.table);
    expect(d.questions.length, 30);
    expect(d.options, 4);
    expect(d.letters, isFalse);
    d.letters = true;
    d.options = 5;
    expect(d.layout['answer'], 'letter');
    expect(d.layout['options'], 5);
  });

  testWidgets('pick → detect → check → save: the confirmed layout is sent and the new sheet comes back', (tester) async {
    _tall(tester);
    Map<String, dynamic>? sent;
    final fake = FakeApi({
      'POST $_b/detect': (_) => _p('detect_bubble'),
      'POST $_b': (o) {
        sent = jsonDecode(jsonEncode(o.data)) as Map<String, dynamic>;
        return FakeResponse(201, {'id': 77, 'version': 1, 'name': sent!['name'], 'status': 'published', 'kind': 'auto_bubble', 'questions': 60, 'options': 4,
          'id_kind': 'shaded', 'id_digits': 8, 'own_sheet': true});
      },
    }, latency: const Duration(milliseconds: 20))
      ..install();
    addTearDown(fake.uninstall);
    OmrTemplateItem? made;
    await tester.pumpWidget(layoutHost(Builder(
        builder: (context) => Center(
            child: TextButton(
                onPressed: () async => made = await openOwnSheet(context, picker: ({required bool camera}) async => ('sheet.jpg', Uint8List.fromList(List.filled(64, 1)))),
                child: const Text('open')))), scale: 1));
    await tester.tap(find.text('open'));
    await _frames(tester);
    await tester.tap(find.byKey(const ValueKey('own.upload')));
    await _frames(tester);
    expect(find.text('We found a bubble sheet'), findsOneWidget);
    expect(find.text('60 questions'), findsOneWidget);
    expect(find.text('8-digit student ID'), findsOneWidget);
    await tester.tap(find.text('Right column first'));
    await _frames(tester, 2);
    await tester.ensureVisible(find.byKey(const ValueKey('own.save')));
    await tester.tap(find.byKey(const ValueKey('own.save')));
    await _frames(tester);
    expect(sent!['kind'], 'auto_bubble');
    expect(sent!['blank_key'], startsWith('omrauto/'));
    expect(asMapOf(asMapOf(sent!['layout'])['numbering'])['direction'], 'rtl');
    expect(made?.id, 77);
    expect(made?.isOwnSheet, isTrue);
  });

  testWidgets('a picture with no sheet: the reason, and the person can try again', (tester) async {
    _tall(tester);
    final fake = FakeApi({
      'POST $_b/detect': (_) => const FakeResponse(422, {'detail': {'code': 'sheet_not_detected', 'message': 'x', 'message_en': 'x'}}),
    }, latency: const Duration(milliseconds: 20))
      ..install();
    addTearDown(fake.uninstall);
    await tester.pumpWidget(layoutHost(OwnSheetPage(picker: ({required bool camera}) async => ('a.jpg', Uint8List(8))), scale: 1, scaffold: false));
    await _frames(tester);
    await tester.tap(find.byKey(const ValueKey('own.upload')));
    await _frames(tester);
    expect(find.textContaining("couldn't find bubbles or an answer table"), findsOneWidget);
    expect(find.byKey(const ValueKey('own.upload')), findsOneWidget);
  });

  testWidgets('the wizard offers "Use your own sheet" above the sheets', (tester) async {
    var opened = 0;
    await tester.pumpWidget(layoutHost(
        SingleChildScrollView(
            child: TemplateStepBody(templates: const [], selectedId: null, onPick: (_) {}, onPaperOnly: () {}, onOwnSheet: () => opened++)),
        scale: 1));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('setup.template.own')));
    expect(opened, 1);
  });

  testWidgets('no overflow: the intro, a bubble sheet and a table under review', (tester) async {
    await expectNoLayoutErrors(tester, () => OwnSheetIntro(onUpload: () {}, onCamera: () {}, error: 'Something went wrong'));
    await expectNoLayoutErrors(tester, () => _review(_draft('detect_bubble')));
    await expectNoLayoutErrors(tester, () => _review(_draft('detect_table')));
  });
}

Map<String, dynamic> asMapOf(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
