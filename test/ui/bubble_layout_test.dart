// No overflow from 320 px to desktop, Arabic and English, textScaler 1.3: the plain-value widgets of the bubble-sheet
// flow (D-340 – D-343). The screens hold only state around these.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/bubble/bubble_flow.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/bubble/bubble_one_photo.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/bubble/bubble_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

Map<String, dynamic> _fx(String name) => Map<String, dynamic>.from(jsonDecode(File('test/fixtures/payloads/bubble/$name.json').readAsStringSync()) as Map);

Widget _scroll(Widget child) => Padding(padding: const EdgeInsets.all(12), child: SingleChildScrollView(child: child));

final _issues = [
  const BubbleIssue(code: 'too_blurry', ar: 'الصورة مهزوزة — ثبّت الهاتف وأعد التصوير', en: 'The picture is blurry. Hold the phone steady and take it again.'),
  const BubbleIssue(code: 'not_one_question', ar: 'هذه الصورة فيها أكثر من سؤال — اقتصّ سؤالًا واحدًا فقط', en: 'This picture holds more than one question. Crop it to a single question.'),
];

void main() {
  testWidgets('the wizard progress and every step card', (tester) async {
    for (final s in BubbleStep.values) {
      await expectNoLayoutErrors(tester, () => _scroll(Column(children: [
            BubbleWizardProgress(current: s, done: {BubbleStep.question}),
            BubbleStepCard(step: s, result: BubbleStepResult(ok: false, issues: _issues), preview: null, onCamera: () {}, onFiles: () {}, onContinue: () {}, error: 'A long server message that must wrap on the phone'),
            BubbleStepCard(step: s, result: BubbleStepResult(ok: true, options: 4, shape: 'circle', kind: 'shaded', digits: 10), preview: null, onCamera: () {}, onFiles: () {}, onContinue: () {}),
          ])));
    }
  });

  testWidgets('the review panel, phone and wide', (tester) async {
    final d = BubbleImport.fromJson(_fx('import_detected'));
    final note = TextEditingController();
    final name = TextEditingController();
    addTearDown(note.dispose);
    addTearDown(name.dispose);
    await expectNoLayoutErrors(tester, () => LayoutBuilder(builder: (_, box) => _scroll(BubbleReviewPanel(
            data: d,
            image: null,
            wide: box.maxWidth >= 900,
            tapMode: BubbleTapMode.wrongRegion,
            onMode: (_) {},
            taps: const [BubbleTap(BubbleTapMode.wrongRegion, .3, .4)],
            onTapSheet: (_) {},
            onRemoveTaps: () {},
            note: note,
            onDetect: () {},
            onConfirm: () {},
            onUndo: () {},
            name: name,
            error: 'A long server message',
          ))));
  });

  testWidgets('the key grid and the Data Lab preview', (tester) async {
    final r = BubbleRun.fromJson(_fx('run'));
    final qs = [...r.questions, ...r.questions, ...r.questions];
    final form = r.forms.first;
    final lab = LabPreview.fromJson(_fx('lab_preview'));
    await expectNoLayoutErrors(tester, () => LayoutBuilder(builder: (_, box) => _scroll(Column(children: [
          BubbleKeyGrid(questions: qs, form: form, flagged: {2}, columns: box.maxWidth >= 1100 ? 3 : (box.maxWidth >= 720 ? 2 : 1), onToggle: (_, _) {}, onDetails: (_) {}),
          BubbleLabPreviewView(preview: lab, onSheet: (_) {}),
        ]))));
  });
  testWidgets('one photo (D-500): the capture card and the result with its fixes', (tester) async {
    final j = _fx('import_detected');
    j['one_photo'] = true;
    j['numbering'] = {'direction': 'rtl'};
    j['issues'] = [
      {'code': 'cut_off', 'ar': 'جزء من الورقة خارج الصورة — صوّر الورقة كاملة', 'en': 'Part of the sheet is outside the picture. Photograph the whole sheet.'}
    ];
    j['questions'] = [
      for (var n = 1; n <= 30; n++)
        {
          'n': n,
          'block': 1,
          'cells': [for (var c = 0; c < 4; c++) [0.2 + c * 0.05, 0.3 + n * 0.02]],
          'labels': ['A', 'B', 'C', 'D'],
        }
    ];
    final d = BubbleImport.fromJson(j);
    expect(d.onePhoto, isTrue);
    expect(d.isRtl, isTrue);
    expect(d.marks.length, 30);
    final name = TextEditingController();
    addTearDown(name.dispose);
    await expectNoLayoutErrors(tester, () => _scroll(Column(children: [
          BubbleCaptureCard(onFiles: () {}, onCamera: () {}, onWrittenTable: () {}, issues: _issues, error: 'A long server message'),
          BubbleCaptureCard(onFiles: () {}, busy: true),
        ])));
    for (final mode in [null, BubbleTapMode.fixOptions, BubbleTapMode.dragId]) {
      await expectNoLayoutErrors(tester, () => LayoutBuilder(builder: (_, box) => _scroll(BubbleResultPanel(
            data: d,
            image: null,
            wide: box.maxWidth >= 900,
            mode: mode,
            selectedBlock: d.blocks.first,
            onMode: (_) {},
            onTapSheet: (_) {},
            onIdBox: (_) {},
            onRotate: () {},
            onDirection: () {},
            onBlockOptions: (_, _) {},
            onUndo: () {},
            onRetake: () {},
            onConfirm: () {},
            name: name,
            error: 'A long server message',
          ))));
    }
  });
}
