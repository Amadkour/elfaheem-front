// Questions with more choices than the bubble sheet (D-720 – D-722): the GET …/omr/fit reply as the back e2e
// (tests/exam_engine/e2e_bubble_fit.py) returns it, the PUT body, the sheet filter and the wizard's warning; the PUT's
// `changes` and the alert's words after a trim / an Undo (D-725).
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/exam_engine/hub/create/exam_create_logic.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/exam_setup.dart' show OmrTemplateItem;
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/bubble_fit.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> fitJson() => {
      'template_id': 3,
      'sheet_options': 4,
      'written_sheet': 'NB2',
      'locked': false,
      'org_id': 1,
      'open': 2,
      'items': [
        {
          'question_id': 14, 'n': 5, 'type': 'mcq_single', 'prompt': 'five, to the paper', 'count': 5, 'choice': 'written', 'can_trim': true,
          'trim_removes': ['d'],
          'options': [
            for (final (i, id) in ['a', 'b', 'c', 'd', 'e'].indexed) {'id': id, 'text': 'opt $i', 'correct': id == 'e'},
          ],
        },
        {
          'question_id': 15, 'n': 6, 'type': 'mcq_multi', 'prompt': 'all five right', 'count': 5, 'choice': null, 'can_trim': false,
          'trim_removes': <String>[],
          'options': [for (final id in ['a', 'b', 'c', 'd', 'e']) {'id': id, 'text': id, 'correct': true}],
        },
      ],
      'trimmed': [
        {'question_id': 13, 'n': 4, 'removed': ['e'], 'from_version': 1, 'to_version': 2},
      ],
    };

void main() {
  setUp(() => AppConfig.lang = 'en');

  test('reads the reply', () {
    final f = BubbleFit.fromJson(fitJson());
    expect((f.sheetOptions, f.templateId, f.orgId, f.onNb2, f.locked, f.maxOptions), (4, 3, 1, true, false, 5));
    expect(f.items.map((x) => x.number), [5, 6]);
    expect(f.items.first.choice, BubbleFitAction.written);
    expect(f.items.first.trimRemoves, ['d']);
    expect(f.items.first.options.where((o) => o.correct).map((o) => o.id), ['e']);
    expect(f.items.last.canTrim, isFalse);
    expect(f.items.last.choice, isNull);
    expect(f.trimmed.single.questionId, 13);
    expect(f.trimmed.single.removed, ['e']);
  });

  test('the PUT body sends only what changed', () {
    final f = BubbleFit.fromJson(fitJson());
    expect(bubbleFitBody(f, {14: BubbleFitAction.written, 15: BubbleFitAction.ignore}), {
      'questions': {'15': 'ignore'},
    });
    expect(bubbleFitBody(f, {14: BubbleFitAction.trim}), {
      'questions': {'14': 'trim'},
    });
  });

  test('another sheet: enough choices and rows, printed sheets first, never the current one', () {
    const all = [
      OmrTemplateItem(id: 3, version: 1, name: 'current', questions: 50, options: 4),
      OmrTemplateItem(id: 4, version: 1, name: 'big5', questions: 100, options: 5),
      OmrTemplateItem(id: 5, version: 1, name: 'own5', questions: 40, options: 5, kind: 'auto_bubble'),
      OmrTemplateItem(id: 6, version: 1, name: 'small5', questions: 10, options: 5),
      OmrTemplateItem(id: 7, version: 1, name: 'table', questions: 60, options: 6, kind: 'answer_table'),
    ];
    expect(bubbleFitSheets(all, options: 5, questions: 20, current: 3).map((x) => x.id), [4, 5]);
    expect(bubbleFitSheets(all, options: 6, questions: 20, current: 3), isEmpty);
  });

  test('the words: how each choice is marked, Arabic letters', () {
    expect(bubbleFitActionLine(BubbleFitAction.ignore, onNb2: true, sheetOptions: 4), contains('enter its mark yourself'));
    expect(bubbleFitActionLine(BubbleFitAction.written, onNb2: true, sheetOptions: 4), contains('written answer sheet'));
    expect(bubbleFitActionLine(BubbleFitAction.written, onNb2: false, sheetOptions: 4), contains('booklet'));
    expect(bubbleFitHeadline(BubbleFit.fromJson(fitJson())), startsWith('2 questions have more choices'));
    expect([for (var i = 0; i < 5; i++) bubbleFitLetter(i, ar: true)], ['أ', 'ب', 'ج', 'د', 'هـ']);
    AppConfig.lang = 'ar';
    expect(bubbleFitHeadline(BubbleFit.fromJson(fitJson())), startsWith('سؤالان'));
  });

  test('a trim / an Undo: the PUT names the changes, the alert says what and asks to reprint (D-725)', () {
    // the shape tests/exam_engine/e2e_bubble_fit.py asserts
    final j = {
      ...fitJson(),
      'changes': [
        {'question_id': 13, 'n': 4, 'action': 'trim', 'removed_options': [{'id': 'e', 'index': 4, 'text': 'All of the above'}]},
      ],
    };
    final ch = bubbleFitChangesOf(j);
    expect((ch.single.number, ch.single.restored, ch.single.removed.single.index), (4, false, 4));
    expect(bubbleFitChangesOf(fitJson()), isEmpty, reason: 'an older server sends no changes: no alert');
    expect(bubbleFitChangeLine(ch.single, ar: false), 'Question 4: removed choice E “All of the above”');
    expect(bubbleFitChangesTitle(ch), 'The question paper was updated');
    expect(bubbleFitReprintLine(ch), contains('print it again'));
    expect(bubbleFitChangesFollow(ch), contains('online exam'));
    const back = BubbleFitChange(questionId: 13, number: 4, restored: true, removed: [BubbleFitRemovedOption(id: 'e', index: 4, text: 'x'), BubbleFitRemovedOption(id: 'd', index: 3)]);
    expect(bubbleFitChangeLine(back, ar: false), 'Question 4: choices E “x”, D are back');
    expect(bubbleFitChangesTitle([back]), contains('back on the question paper'));
    final tr = BubbleFit.fromJson({
      ...fitJson(),
      'trimmed': [
        {'question_id': 13, 'n': 4, 'removed': ['e'], 'removed_options': [{'id': 'e', 'index': 4, 'text': 'E'}]},
      ],
    });
    expect(tr.trimmed.single.removedOptions.single.text, 'E');
    AppConfig.lang = 'ar';
    expect(bubbleFitChangeLine(ch.single, ar: true), 'السؤال 4: حُذف الخيار هـ «All of the above»');
    expect(bubbleFitReprintLine(ch), contains('اطبعها من جديد'));
  });

  test('the wizard warns with the numbers and no longer blocks (D-722)', () {
    const c = BubbleCheck(choicesOver: 2, choicesOverNumbers: [4, 6]);
    expect(c.blocks, isFalse);
    expect(c.speaks, isTrue);
  });
}
