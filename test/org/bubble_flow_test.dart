// The bubble-sheet flow's pure part against REAL engine replies (recorded by back tests/exam_engine/e2e_bubble_flow.py
// with BUBBLE_DUMP into test/fixtures/payloads/bubble/): the import draft and its detection, the run with its key, the
// key sheet proposal, the Data Lab preview.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/exams/exam_engine_api.dart';
import 'package:flutter_education_app/features/exams/paper/bubble/bubble_flow.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _fx(String name) => Map<String, dynamic>.from(jsonDecode(File('test/fixtures/payloads/bubble/$name.json').readAsStringSync()) as Map);

void main() {
  setUp(() => AppConfig.lang = 'en');

  test('a detection draft: pictures done, questions, choices, ID, regions', () {
    final d = BubbleImport.fromJson(_fx('import_detected'));
    expect(d.detected, isTrue);
    expect(d.questions, 24);
    expect(d.options, 4);
    expect(d.idDigits, 6);
    expect(d.shape, 'rect');
    expect(d.nextStep, isNull);
    expect(d.steps['question']?.ok, isTrue);
    expect(d.steps['identifier']?.kind, 'shaded');
    final blocks = d.blocks;
    expect(blocks.where((b) => b.role == 'identifier'), hasLength(1));
    expect(blocks.expand((b) => b.cells.expand((r) => r)).every((p) => p[0] <= 1.2 && p[1] <= 1.2), isTrue);
  });

  test('a tap goes as a fraction of the sheet with its action', () {
    expect(const BubbleTap(BubbleTapMode.setIdentifier, 0.125, 0.5).toJson(), {'action': 'set_role', 'x': 0.125, 'y': 0.5, 'role': 'identifier'});
    expect(const BubbleTap(BubbleTapMode.extraBubble, 0.2, 0.3).toJson()['action'], 'extra_bubble');
    expect(const BubbleTap(BubbleTapMode.missingQuestion, 0.2, 0.3).toJson()['action'], 'missing_question');
  });

  test('a run: sheet, key per question number, points, modes', () {
    final r = BubbleRun.fromJson(_fx('run'));
    expect(r.hasKey, isTrue);
    expect(r.ownSheet, isTrue);
    expect(r.questions, hasLength(6));
    expect(r.questions[1].points, 3);
    expect(r.forms.single.code, 'A');
    expect(r.forms.single.key[2], ['C']);
    expect(BubbleKeyForm.fromJson({'code': 'B', 'key': {'1': ['A', 'D']}}).toJson()['key'], {'1': ['A', 'D']});
  });

  test('a marked key sheet proposes letters and flags what is not clear', () {
    final p = BubbleKeyProposal.fromJson(_fx('key_sheet'));
    expect(p.ok, isTrue);
    expect(p.clear, 6);
    expect(p.items.first.letters, ['A']);
    expect(p.items.every((i) => i.clear), isTrue);
  });

  test('the Data Lab preview: before and after, overwrites, what the write expects', () {
    final p = LabPreview.fromJson(_fx('lab_preview'));
    expect(p.columnKey, 'midterm');
    expect(p.columnMax, 16.0);
    expect(p.overwrites, 1);
    final row = p.rows.firstWhere((r) => r.studentId == 11);
    expect((row.oldValue, row.newValue, row.overwrites), (4.0, 16.0, true));
    expect(row.pageId, isNotNull, reason: 'every mark links to its scanned sheet');
    expect(p.expect['11'], 4.0);
    expect(bubbleNumText(16.0), '16');
    expect(bubbleNumText(7.5), '7.5');
    expect(bubbleNumText(null), '—');
  });

  test('server codes become text in both languages', () {
    expect(bubbleErrorText(EngineResult.fail(409, 'overwrite_confirmation_required', 'x')).toLowerCase(), contains('overwrit'));
    AppConfig.lang = 'ar';
    expect(bubbleErrorText(EngineResult.fail(403, 'feature_disabled', 'x')), contains('متوقفة'));
  });

  test('step titles and tap labels are translated', () {
    expect(BubbleStep.question.title, 'One question');
    expect(BubbleTapMode.wrongRegion.label, 'Wrong region');
    AppConfig.lang = 'ar';
    expect(BubbleStep.filled.shortTitle, 'مظلّلة');
  });
}
