// No overflow at 320x640 and 1400x900, ar + en, textScaler 1.3: the template library (cards), the editor (canvas over
// a small in-memory picture, the side panel on desktop / the bottom bar on phones), a box's form, the panel's lists
// and the test-result view.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/shared/exam_engine/marks/mark_templates_api.dart';
import 'package:flutter_education_app/features/shared/exam_engine/marks/templates/mark_canvas.dart';
import 'package:flutter_education_app/features/shared/exam_engine/marks/templates/mark_editor_model.dart';
import 'package:flutter_education_app/features/shared/exam_engine/marks/templates/mark_editor_panel.dart';
import 'package:flutter_education_app/features/shared/exam_engine/marks/templates/mark_field_form.dart';
import 'package:flutter_education_app/features/shared/exam_engine/marks/templates/mark_template_editor.dart';
import 'package:flutter_education_app/features/shared/exam_engine/marks/templates/mark_template_library.dart';
import 'package:flutter_education_app/features/shared/exam_engine/marks/templates/mark_template_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../support/fake_api.dart';
import 'layout_harness.dart';

Uint8List png() => Uint8List.fromList(img.encodePng(img.Image(width: 40, height: 56)));

MarkSheetSpec spec() => MarkSheetSpec.fromDetect({
      'page': {'aspect': 1.414, 'ref_w': 1654, 'ref_h': 2339},
      'proposals': [
        {'id': 'p1', 'guess': 'identifier', 'conf': 0.9, 'box': [0.6, 0.03, 0.3, 0.06], 'source': 'national_id'},
        {'id': 'p2', 'guess': 'question_mark', 'conf': 0.9, 'box': [0.1, 0.2, 0.1, 0.04], 'max': 5},
        {'id': 'p3', 'guess': 'question_mark', 'conf': 0.7, 'box': [0.1, 0.3, 0.1, 0.04], 'max': 6},
        {'id': 'p4', 'guess': 'total', 'conf': 0.8, 'box': [0.1, 0.5, 0.1, 0.05], 'max': 10},
        {'id': 'p5', 'guess': 'answer_row', 'conf': 0.8, 'box': [0.4, 0.5, 0.4, 0.05]},
        {'id': 'p6', 'guess': 'blob', 'conf': 0.3, 'box': [0.5, 0.7, 0.1, 0.05]},
      ],
    }, MarkKind.markSheet);

final _row = {'id': 5, 'family_id': 5, 'version': 2, 'name': 'A very long template name for the final examination of the second semester', 'kind': 'mark_sheet', 'fields_count': 12, 'total_max': 50, 'owner_name': 'Dr Salma Abdelrahman', 'updated_at': '2026-11-01T10:00:00'};

void main() {
  setUp(() => mockRequestPlugins());

  testWidgets('library', (tester) async {
    final fake = FakeApi({
      'GET /api/v1/exam/mark-templates': (_) => {'items': [_row, {..._row, 'id': 6, 'kind': 'answer_table', 'name': 'Quiz'}, {..._row, 'id': 7, 'kind': 'cover', 'total_max': null}]},
    }, latency: const Duration(milliseconds: 5))
      ..install();
    addTearDown(fake.uninstall);
    await expectNoLayoutErrors(tester, () => const MarkTemplatesPage(orgId: 3), scaffold: false, frames: 8);
  });

  testWidgets('library: empty', (tester) async {
    final fake = FakeApi({'GET /api/v1/exam/mark-templates': (_) => {'items': <Object>[]}}, latency: const Duration(milliseconds: 5))..install();
    addTearDown(fake.uninstall);
    await expectNoLayoutErrors(tester, () => const MarkTemplatesPage(), scaffold: false, frames: 8);
  });

  testWidgets('editor over a small picture', (tester) async {
    await expectNoLayoutErrors(tester, () => MarkTemplateEditorPage(spec: spec(), image: png(), blankKey: 'k', kind: MarkKind.markSheet, name: 'Mid'), scaffold: false, frames: 6);
  });

  testWidgets('editor: the phone sheets (box form, list)', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => MarkTemplateEditorPage(spec: spec(), image: png(), blankKey: 'k', kind: MarkKind.markSheet, name: 'Mid'),
      scaffold: false,
      frames: 6,
      act: (tester) async {
        final size = tester.view.physicalSize;
        if (size.width < 900) {
          await tester.tap(find.byIcon(Icons.list_alt_rounded));
          await tester.pump(const Duration(milliseconds: 400));
        }
      },
    );
  });

  testWidgets('box form (every type) and the panel', (tester) async {
    final model = MarkEditorModel(spec());
    for (final id in ['p1', 'p2', 'p4', 'p5', 'p6']) {
      model.select(id);
      final f = model.selected!;
      await expectNoLayoutErrors(
        tester,
        () => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: MarkFieldForm(field: f, issues: model.issuesOf(id), onType: (_) {}, onChanged: (_, {coalesce}) {}, onDelete: () {}),
        ),
        frames: 2,
      );
    }
    final c = TextEditingController(text: 'Name');
    addTearDown(c.dispose);
    model.select('p2');
    await expectNoLayoutErrors(tester, () => MarkEditorPanel(model: model, nameController: c), frames: 2);
    await expectNoLayoutErrors(tester, () => MarkEditorPanel(model: model, nameController: c, showForm: false), frames: 2);
  });

  testWidgets('canvas alone', (tester) async {
    final model = MarkEditorModel(spec())..select('p2');
    await expectNoLayoutErrors(tester, () => MarkCanvas(model: model, aspect: 0.707, image: png()), frames: 3);
  });

  testWidgets('test result', (tester) async {
    final reading = MarkTestReading.fromJson({
      'ok': true,
      'method': 'table',
      'reading': {
        'fields': [
          {'id': 'p2', 'type': 'question_mark', 'value': '4.5', 'conf': 0.97, 'status': 'ok', 'box': [0.1, 0.2, 0.1, 0.04]},
          {'id': 'p3', 'type': 'question_mark', 'value': '7.5', 'conf': 0.55, 'status': 'low', 'candidates': [['7.5', 0.55], ['1.5', 0.3], ['7', 0.2]], 'box': [0.1, 0.3, 0.1, 0.04]},
          {'id': 'p4', 'type': 'total', 'value': null, 'conf': 0.0, 'status': 'unreadable', 'box': [0.1, 0.5, 0.1, 0.05]},
        ],
        'sum': {'parts_read': 2, 'computed': 12.0, 'written': 10.0, 'consistent': false},
        'identifier': {'value': '12345678901234', 'method': 'national_id', 'conf': 0.97},
      },
    });
    await expectNoLayoutErrors(tester, () => MarkTestResultView(reading: reading, spec: spec(), image: png(), onAgain: () {}, onBack: () {}), frames: 2);
    await expectNoLayoutErrors(tester, () => MarkTestResultView(reading: const MarkTestReading(ok: false, qualityCode: 'blurry'), spec: spec()), frames: 2);
  });
}
