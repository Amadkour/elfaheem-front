// The answer booklet (D-663): a separate printable document that goes with the question paper. The student keeps the
// questions and writes every answer in the booklet: one answer table for the objective questions (choice and true /
// false: circle the letter), then one numbered block per written question with ruled lines sized by its type and points,
// or numbered slots for blanks, matching and ordering. The writers draw it from the same ExamPaperDoc (part = booklet),
// so the header, the student box, the printed identifiers, the per-page QR and the versions all stay one code path.
//
// Pure (unit-tested): bookletInTable · bookletLines · bookletSlots · bookletPlanOf · BookletWords.
library;

import 'package:flutter_education_app/features/exams/exam_paper.dart';

/// Whether [q] is answered in the booklet's table (choice letters, or True / False).
bool bookletInTable(PaperQuestion q) => (q.isChoice && q.options.isNotEmpty) || q.type == 'true_false';

/// Ruled lines a written answer gets in the booklet: more room than the in-paper lines, since the booklet holds the whole
/// answer. Numeric 2, short answers 3 to 6 by points, essays and file answers by points (6 to 28). Slot types get none.
int bookletLines(PaperQuestion q) => switch (q.type) {
      'numeric' => 2,
      'short_answer' => (q.points + 2).round().clamp(3, 6),
      'essay' || 'file_upload' => (q.points * 2 + 4).round().clamp(6, 28),
      'fill_blank' || 'matching' || 'ordering' => 0,
      _ => bookletInTable(q) ? 0 : 3,
    };

/// Numbered places to write in: one per blank, per matching row, per item to order; 0 for the others.
int bookletSlots(PaperQuestion q) => switch (q.type) {
      'fill_blank' => q.blanks < 1 ? 1 : q.blanks,
      'matching' => q.left.length,
      'ordering' => q.items.length,
      _ => 0,
    };

/// One written question's block in the booklet.
class BookletBlock {
  const BookletBlock({required this.number, required this.type, required this.points, required this.lines, required this.slots,
      required this.sectionIndex, this.sectionTitle = '', this.answerText = '', this.keySlots = const []});
  final int number;
  final String type;
  final double points;
  final int lines, slots;

  /// The part it belongs to (a heading is printed when the part changes on a paper with several parts).
  final int sectionIndex;
  final String sectionTitle;

  /// The answer-key copy: the model answer, and what each slot holds (blank text, the matching letter, the position).
  final String answerText;
  final List<String> keySlots;
}

/// Everything a writer prints in the booklet, in order.
class BookletPlan {
  const BookletPlan({this.table = const [], this.blocks = const []});
  final List<AnswerTableEntry> table;
  final List<BookletBlock> blocks;
  bool get isEmpty => table.isEmpty && blocks.isEmpty;
}

/// The booklet of [d]: the table rows (choice letters, True / False as two letters) and the written blocks, numbered as
/// the question paper numbers them (so a version's order is kept).
BookletPlan bookletPlanOf(ExamPaperDoc d) {
  final w = BookletWords(d.rtl);
  final table = <AnswerTableEntry>[];
  final blocks = <BookletBlock>[];
  for (var si = 0; si < d.sections.length; si++) {
    final s = d.sections[si];
    for (final q in s.questions) {
      if (q.isChoice && q.options.isNotEmpty) {
        table.add(AnswerTableEntry(q.number, [for (var i = 0; i < q.options.length; i++) choiceLetter(i, rtl: d.rtl)], q.correct, multi: q.type == 'mcq_multi'));
      } else if (q.type == 'true_false') {
        table.add(AnswerTableEntry(q.number, w.tfLetters, q.tfCorrect == null ? const {} : {q.tfCorrect! ? 0 : 1}));
      } else {
        blocks.add(BookletBlock(
          number: q.number, type: q.type, points: q.points, lines: bookletLines(q), slots: bookletSlots(q), sectionIndex: si,
          sectionTitle: s.title, answerText: q.answerText, keySlots: _keySlots(q, d.rtl),
        ));
      }
    }
  }
  return BookletPlan(table: table, blocks: blocks);
}

List<String> _keySlots(PaperQuestion q, bool rtl) => switch (q.type) {
      'fill_blank' => q.answerText.isEmpty ? const [] : q.answerText.split(' · '),
      'matching' => [
          for (final l in q.left)
            () {
              final k = q.right.indexOf(q.pairs[l] ?? '');
              return k < 0 ? '' : choiceLetter(k, rtl: rtl);
            }(),
        ],
      'ordering' => [for (final it in q.items) q.order.contains(it) ? '${q.order.indexOf(it) + 1}' : ''],
      _ => const [],
    };

/// The booklet's labels (the paper's own language, not the app's).
class BookletWords {
  const BookletWords(this.rtl);
  final bool rtl;
  String get title => rtl ? 'دفتر الإجابة' : 'Answer booklet';
  String get note => rtl
      ? 'اكتب كل إجاباتك في هذا الدفتر. ورقة الأسئلة لا تُصحَّح.'
      : 'Write all your answers in this booklet. The question paper is not marked.';
  String get tableTitle => rtl ? 'أسئلة الاختيار وصح أو خطأ — ضع دائرة حول الحرف الصحيح' : 'Choice and true / false questions — circle the right letter';
  String get written => rtl ? 'الإجابات المكتوبة' : 'Written answers';
  String answerTo(int n) => rtl ? 'إجابة السؤال $n' : 'Answer to question $n';
  String get end => rtl ? 'نهاية دفتر الإجابة' : 'End of the answer booklet';
  String get answerInBooklet => rtl ? 'أجب في دفتر الإجابة المرفق، لا على هذه الورقة.' : 'Answer in the answer booklet, not on this paper.';
  String get blanksHint => rtl ? 'اكتب ما في كل فراغ برقمه' : 'Write what goes in each blank by its number';
  String get matchHint => rtl ? 'اكتب حرف الإجابة أمام رقم كل عنصر' : 'Write the matching letter next to each number';
  String get orderHint => rtl ? 'اكتب ترتيب كل عنصر أمام رقمه' : 'Write the position of each item next to its number';
  List<String> get tfLetters => rtl ? const ['ص', 'خ'] : const ['T', 'F'];

  /// The hint above a block's slots; empty for ruled lines.
  String slotHint(String type) => switch (type) {
        'fill_blank' => blanksHint,
        'matching' => matchHint,
        'ordering' => orderHint,
        _ => '',
      };
}
