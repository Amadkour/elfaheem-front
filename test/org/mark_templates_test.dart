// Templates for the teacher's own paper sheets (contract docs/grading/CONTRACT.md §3 + §4), over the fake backend:
//   • the pure part: detect proposals → a spec, the plain-words validation, the JSON sent, the editor model (draw /
//     move / delete / undo, one drag = one step);
//   • the screens: the library lists the templates, "New template" → kind → blank picture → detect → the editor with the
//     proposals → an error stops Save → delete the stray box → Save (POST) → test on a filled sheet → what was read.
import 'dart:convert' show base64Encode;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/shared/exam_engine/marks/mark_templates_api.dart';
import 'package:flutter_education_app/features/shared/exam_engine/marks/templates/mark_editor_model.dart';
import 'package:flutter_education_app/features/shared/exam_engine/marks/templates/mark_template_editor.dart';
import 'package:flutter_education_app/features/shared/exam_engine/marks/templates/mark_template_library.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';

Uint8List png() => Uint8List.fromList(img.encodePng(img.Image(width: 20, height: 28)));

Map<String, dynamic> proposal(String id, String guess, List<double> box, {double conf = 0.9, Map<String, dynamic> more = const {}}) =>
    {'id': id, 'guess': guess, 'conf': conf, 'box': box, ...more};

Map<String, dynamic> detectReply() => {
      'blank_key': 'blank/abc.png',
      'image': {'w': 1654, 'h': 2339},
      'page': {'aspect': 1.414, 'ref_w': 1654, 'ref_h': 2339, 'anchors': {'corner_marks': false, 'table_box': null, 'qr_box': null}},
      'proposals': [
        proposal('p1', 'identifier', [0.60, 0.03, 0.30, 0.06], more: {'source': 'national_id', 'digits': 14}),
        proposal('p2', 'question_mark', [0.10, 0.20, 0.10, 0.04], more: {'max': 5}),
        proposal('p3', 'question_mark', [0.10, 0.30, 0.10, 0.04], conf: 0.7, more: {'max': 5}),
        proposal('p4', 'total', [0.10, 0.50, 0.10, 0.05], more: {'max': 10}),
        proposal('p5', 'blob', [0.50, 0.70, 0.10, 0.05], conf: 0.3),
      ],
    };

MarkSheetSpec spec0() => MarkSheetSpec.fromDetect(detectReply(), MarkKind.markSheet);

List<String> codes(MarkSheetSpec s) => [for (final i in validateSpec(s)) i.code];

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
  });

  group('spec and validation', () {
    test('detect proposals become typed fields; the stray box has no type; missing question numbers are numbered', () {
      final s = spec0();
      expect([for (final f in s.fields) f.type], [FieldType.identifier, FieldType.questionMark, FieldType.questionMark, FieldType.total, FieldType.unset]);
      expect([for (final f in s.questionMarks) f.questionNo], [1, 2]);
      expect(s.fields.first.source, 'national_id');
      expect(s.fields.first.digits, 14);
      expect(s.sumTotal, 'p4');
      expect(s.aspect, closeTo(1654 / 2339, 1e-9));
      expect(codes(s), ['unset_type']);
      expect(validateSpec(s).single.error, isTrue);
    });

    test('the rules: identifier, duplicate numbers, max, overlap, outside, sum', () {
      var s = spec0();
      s = s.copyWith(fields: [
        for (final f in s.fields)
          if (f.type != FieldType.unset && f.type != FieldType.identifier) f,
      ]);
      expect(codes(s), ['missing_identifier']);
      final q = s.questionMarks.toList();
      s = s.copyWith(fields: [
        for (final f in s.fields)
          if (f.id == q[1].id) f.copyWith(questionNo: 1, max: 0) else f,
      ]);
      expect(codes(s), containsAll(['missing_identifier', 'duplicate_question', 'max_not_positive']));
      s = s.copyWith(fields: [
        for (final f in s.fields)
          if (f.id == q[0].id) f.copyWith(box: f.box.shift(const Offset(0.0, 0.0))) else if (f.id == q[1].id) f.copyWith(box: q[0].box.deflate(0.001)) else f,
      ]);
      expect(codes(s), contains('overlap'));
      s = s.copyWith(fields: [for (final f in s.fields) if (f.id == q[0].id) f.copyWith(box: const Rect.fromLTWH(0.95, 0.9, 0.2, 0.2)) else f]);
      expect(codes(s), contains('outside_page'));
    });

    test('sum rule: parts max 10 vs total 12 is a WARNING in plain words; the default parts are all question marks', () {
      var s = spec0().copyWith(fields: [for (final f in spec0().fields) if (f.type != FieldType.unset) f]);
      expect(validateSpec(s), isEmpty);
      expect(partsMaxSum(s), 10);
      s = s.copyWith(fields: [for (final f in s.fields) if (f.id == 'p4') f.copyWith(max: 12) else f]);
      final w = validateSpec(s).single;
      expect((w.code, w.error), ('sum_mismatch', false));
      expect(w.text, 'The parts add up to 10 but the total is 12.');
      AppConfig.lang = 'ar';
      expect(w.text, contains('10'));
      expect(w.text, contains('12'));
      AppConfig.lang = 'en';
      // choosing one part only
      s = s.copyWith(sumParts: ['p2']);
      expect(partsMaxSum(s), 5);
      expect(s.toJson()['sum_rule'], {'total': 'p4', 'parts': ['p2'], 'mode': 'sum'});
    });

    test('the JSON sent follows the contract', () {
      final s = spec0().copyWith(fields: [for (final f in spec0().fields) if (f.type != FieldType.unset) f]);
      final j = s.toJson();
      expect(j['kind'], 'mark_sheet');
      expect((j['page'] as Map)['ref_w'], 1654);
      final fields = (j['fields'] as List).cast<Map<String, dynamic>>();
      expect(fields[0], {'id': 'p1', 'type': 'identifier', 'box': [0.6, 0.03, 0.3, 0.06], 'source': 'national_id', 'digits': 14});
      expect(fields[1], {'id': 'p2', 'type': 'question_mark', 'box': [0.1, 0.2, 0.1, 0.04], 'question_no': 1, 'max': 5.0, 'step': 0.5});
      expect(fields[3], {'id': 'p4', 'type': 'total', 'box': [0.1, 0.5, 0.1, 0.05], 'max': 10.0});
      expect(j['sum_rule'], {'total': 'p4', 'parts': ['p2', 'p3'], 'mode': 'sum'});
      // a saved spec reads back to the same thing
      expect(MarkSheetSpec.fromJson(j).toJson(), j);
    });

    test('an answer row splits its box into option cells and keeps them', () {
      const row = MarkField(id: 'a1', type: FieldType.answerRow, box: Rect.fromLTWH(0.2, 0.1, 0.4, 0.05), questionNo: 1);
      final r = row.asType(FieldType.answerRow);
      expect([for (final o in r.options) o.label], ['A', 'B', 'C', 'D']);
      expect(r.options[1].box.left, closeTo(0.3, 1e-9));
      final j = r.toJson();
      expect((j['options'] as List).length, 4);
      expect(j['mode'], 'mark');
      expect(MarkField.fromJson(j, fallbackId: 'x').options.length, 4);
    });

    test('a list row and the test reading parse', () {
      final m = MarkTemplate.fromJson({'id': 7, 'family_id': '0c1f6a9e-3b7d-4c2e-9a51-7d2f4e8b6c13', 'version': 2, 'name': 'Quiz', 'kind': 'answer_table', 'fields_count': 12, 'total_max': 20, 'owner_name': 'Sara', 'updated_at': '2026-11-01T10:00:00', 'has_image': true});
      expect((m.id, m.familyId, m.version, m.kind, m.totalMax, m.fieldsCount), (7, '0c1f6a9e-3b7d-4c2e-9a51-7d2f4e8b6c13', 2, MarkKind.answerTable, 20.0, 12));
      expect(m.updatedAt, isNotNull);
      final r = MarkTestReading.fromJson({
        'ok': true,
        'method': 'table',
        'reading': {
          'fields': [
            {'id': 'p2', 'type': 'question_mark', 'value': '7.5', 'conf': 0.62, 'status': 'low', 'candidates': [['7.5', 0.62], ['1.5', 0.2]], 'box': [0.1, 0.2, 0.1, 0.04]},
          ],
          'sum': {'parts_read': 2, 'computed': 9.5, 'written': 10, 'consistent': false},
          'identifier': {'value': '12345678901234', 'method': 'national_id', 'conf': 0.97},
        },
        'preview_url': '/api/v1/exam/mark-templates/7/preview',
      });
      expect(r.previewUrl, isNotNull);
      expect(r.fields.single.candidates.first, ('7.5', 0.62));
      expect((r.computed, r.written, r.consistent, r.identifierValue), (9.5, 10.0, false, '12345678901234'));
    });
  });

  group('editor model', () {
    test('draw, move (one drag = one undo step), type, delete, undo / redo', () {
      final m = MarkEditorModel(spec0());
      final n0 = m.fields.length;
      final id = m.addBox(const Rect.fromLTWH(0.3, 0.8, 0.1, 0.05));
      expect(m.fields.length, n0 + 1);
      expect(m.selectedId, id);
      m.setType(id, FieldType.questionMark);
      expect(m.spec.field(id)!.questionNo, 3);
      m.beginDrag();
      for (var i = 1; i <= 5; i++) {
        m.dragBox(id, Rect.fromLTWH(0.3 + i * 0.01, 0.8, 0.1, 0.05));
      }
      m.endDrag(changed: true);
      expect(m.spec.field(id)!.box.left, closeTo(0.35, 1e-9));
      m.undo();
      expect(m.spec.field(id)!.box.left, closeTo(0.3, 1e-9));
      m.redo();
      expect(m.spec.field(id)!.box.left, closeTo(0.35, 1e-9));
      // a drag past the page edge stays on the page
      m.beginDrag();
      m.dragBox(id, const Rect.fromLTWH(0.98, 0.8, 0.1, 0.05));
      m.endDrag(changed: true);
      expect(m.spec.field(id)!.box.right, lessThanOrEqualTo(1.0));
      // a tap that moved nothing leaves no step
      final undoBefore = m.canUndo;
      m.beginDrag();
      m.endDrag(changed: false);
      expect(m.canUndo, undoBefore);
      m.delete(id);
      expect(m.spec.field(id), isNull);
      expect(m.selectedId, isNull);
      m.undo();
      expect(m.spec.field(id), isNotNull);
      expect(m.hit(m.spec.field(id)!.box.center), id);
    });

    test('typing coalesces into one step; deleting the total drops the sum rule', () {
      final m = MarkEditorModel(spec0());
      final f = m.spec.field('p2')!;
      m.update(f.copyWith(max: 6), coalesce: 'max:p2');
      m.update(f.copyWith(max: 65), coalesce: 'max:p2');
      m.update(f.copyWith(max: 6.5), coalesce: 'max:p2');
      expect(m.spec.field('p2')!.max, 6.5);
      m.undo();
      expect(m.spec.field('p2')!.max, 5);
      m.delete('p4');
      expect(m.spec.sumTotal, isNull);
      expect(m.spec.toJson().containsKey('sum_rule'), isFalse);
    });
  });

  group('screens over the fake backend', () {
    Future<void> frames(WidgetTester tester, [int n = 12]) async {
      for (var i = 0; i < n; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
    }

    Widget app(Widget home) => ThemeConfigScope(provider: ThemeConfigProvider(api: ApiClient()), child: MaterialApp(home: home));

    testWidgets('library → new → detect → editor → save → test', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Map<String, dynamic>? posted;
      Map<String, dynamic>? listQuery;
      var detectCalls = 0;
      var testCalls = 0;
      final fake = FakeApi({
        'GET /api/v1/exam/mark-templates': (o) {
          listQuery = o.uri.queryParameters;
          return {
            'items': [
              {'id': 1, 'family_id': 1, 'version': 1, 'name': 'Midterm cover', 'kind': 'cover', 'org_id': 5, 'status': 'published', 'fields_count': 2, 'total_max': 50, 'owner_id': 9, 'owner_name': 'Dr Salma', 'updated_at': '2026-11-01T10:00:00', 'has_image': true},
              {'id': 2, 'family_id': 2, 'version': 3, 'name': 'Quiz table', 'kind': 'answer_table', 'org_id': 5, 'status': 'published', 'fields_count': 21, 'total_max': null, 'owner_id': 9, 'owner_name': 'Dr Salma', 'updated_at': '2026-11-02T10:00:00', 'has_image': true},
            ],
          };
        },
        'POST /api/v1/exam/mark-templates/detect': (_) {
          detectCalls++;
          return detectReply();
        },
        'POST /api/v1/exam/mark-templates': (o) {
          posted = Map<String, dynamic>.from(o.data as Map);
          return {'id': 7, 'family_id': 7, 'version': 1, 'name': posted!['name'], 'kind': posted!['kind'], 'org_id': 5, 'status': 'published', 'fields_count': 4, 'total_max': 10, 'owner_name': 'Me', 'updated_at': '2026-11-04T10:00:00'};
        },
        'GET /api/v1/exam/mark-templates/7/image': (_) => 'png',
        'POST /api/v1/exam/mark-templates/7/test': (_) {
          testCalls++;
          return {
            'ok': true,
            'method': 'table',
            'quality': {'ok': true},
            'reading': {
              'fields': [
                {'id': 'p2', 'type': 'question_mark', 'value': '4.5', 'conf': 0.97, 'status': 'ok', 'candidates': [], 'box': [0.1, 0.2, 0.1, 0.04]},
                {'id': 'p3', 'type': 'question_mark', 'value': '7.5', 'conf': 0.55, 'status': 'low', 'candidates': [['7.5', 0.55], ['1.5', 0.3]], 'box': [0.1, 0.3, 0.1, 0.04]},
              ],
              'sum': {'parts_read': 2, 'computed': 12.0, 'written': 10.0, 'consistent': false},
              'identifier': {'value': '12345678901234', 'method': 'national_id', 'conf': 0.97},
            },
            'preview_url': null,
            'preview_b64': base64Encode(png()),
          };
        },
      }, latency: const Duration(milliseconds: 10))
        ..install();
      addTearDown(fake.uninstall);

      Future<(String, Uint8List)?> picker({required bool camera}) async => ('blank.png', png());
      await tester.pumpWidget(app(MarkTemplatesPage(orgId: 5, picker: picker)));
      await frames(tester);
      expect(listQuery, {'org_id': '5'});
      expect(find.text('Midterm cover'), findsOneWidget);
      expect(find.text('Quiz table'), findsOneWidget);
      expect(find.textContaining('Dr Salma'), findsNWidgets(2));
      expect(find.text('21 fields'), findsOneWidget);
      expect(find.text('Total 50'), findsOneWidget);

      // new → kind → blank picture → detect
      await tester.tap(find.text('New template'));
      await frames(tester);
      await tester.tap(find.text('Mark sheet'));
      await frames(tester);
      await tester.tap(find.text('Upload a picture instead'));
      await frames(tester, 20);
      expect(detectCalls, 1);
      // the editor: five boxes, the stray one is an error and stops Save
      expect(find.text('Boxes (5)'), findsOneWidget);
      expect(find.textContaining('A box has no type'), findsWidgets);
      expect(find.textContaining('1 errors'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Template name'), 'Final mark sheet');
      await tester.tap(find.text('Save template'));
      await frames(tester);
      expect(posted, isNull);

      // select the stray box from the list and delete it from its form
      await tester.ensureVisible(find.textContaining('Type not set ·'));
      await tester.pump();
      await tester.tap(find.textContaining('Type not set ·'));
      await frames(tester);
      await tester.ensureVisible(find.byTooltip('Delete box'));
      await tester.pump();
      await tester.tap(find.byTooltip('Delete box'));
      await frames(tester);
      expect(find.text('Boxes (4)'), findsOneWidget);
      expect(find.textContaining('4 boxes · no problems'), findsOneWidget);
      // the sum rule card says it plainly
      expect(find.text('Parts max sum = 10, total max = 10'), findsOneWidget);

      await tester.tap(find.text('Save template'));
      await frames(tester, 20);
      expect(posted, isNotNull);
      expect(posted!['name'], 'Final mark sheet');
      expect(posted!['kind'], 'mark_sheet');
      expect(posted!['blank_key'], 'blank/abc.png');
      expect(posted!['org_id'], 5);
      final spec = posted!['spec'] as Map;
      expect((spec['fields'] as List).length, 4);
      expect(spec['sum_rule'], {'total': 'p4', 'parts': ['p2', 'p3'], 'mode': 'sum'});

      // test on one filled sheet
      await tester.tap(find.byTooltip('Test on a filled sheet'));
      await frames(tester);
      await tester.tap(find.text('Upload a picture'));
      await frames(tester, 20);
      expect(testCalls, 1);
      expect(find.text('4.5'), findsOneWidget);
      expect(find.text('7.5'), findsOneWidget);
      expect(find.text('Low confidence'), findsOneWidget);
      expect(find.text('97%'), findsWidgets);
      expect(find.text('Written total: 10'), findsOneWidget);
      expect(find.textContaining('Computed from the parts: 12'), findsOneWidget);
      expect(find.textContaining('does not match the parts'), findsOneWidget);
      expect(find.text('1 fields need a look. Move their boxes in the editor, then test again.'), findsOneWidget);
    });

    testWidgets('pick mode returns the tapped template', (tester) async {
      final fake = FakeApi({
        'GET /api/v1/exam/mark-templates': (_) => {
              'items': [
                {'id': 2, 'family_id': 2, 'version': 3, 'name': 'Quiz table', 'kind': 'answer_table', 'status': 'published', 'fields_count': 21},
                {'id': 3, 'family_id': 3, 'version': 1, 'name': 'Old one', 'kind': 'cover', 'status': 'retired'},
              ],
            },
      }, latency: const Duration(milliseconds: 10))
        ..install();
      addTearDown(fake.uninstall);
      MarkTemplate? got;
      await tester.pumpWidget(app(Builder(
        builder: (context) => TextButton(
          onPressed: () async => got = await openMarkTemplates(context, pick: true),
          child: const Text('open'),
        ),
      )));
      await tester.tap(find.text('open'));
      await frames(tester);
      expect(find.text('Old one'), findsNothing); // retired ones are not offered
      await tester.tap(find.text('Quiz table'));
      await frames(tester);
      expect(got?.id, 2);
      expect(got?.kind, MarkKind.answerTable);
    });

    testWidgets('Delete removes the selected box from the editor', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final fake = FakeApi({}, latency: const Duration(milliseconds: 10))..install();
      addTearDown(fake.uninstall);
      await tester.pumpWidget(app(MarkTemplateEditorPage(spec: spec0(), image: png(), blankKey: 'k', kind: MarkKind.markSheet)));
      await frames(tester);
      expect(find.text('Boxes (5)'), findsOneWidget);
      await tester.ensureVisible(find.textContaining('Type not set ·'));
      await tester.pump();
      await tester.tap(find.textContaining('Type not set ·'));
      await frames(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await frames(tester);
      expect(find.text('Boxes (4)'), findsOneWidget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await frames(tester);
      expect(find.text('Boxes (5)'), findsOneWidget);
    });
  });
}
