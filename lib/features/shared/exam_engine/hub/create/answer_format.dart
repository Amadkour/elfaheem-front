// How students answer an exam (`settings.answer_format`, exam flow v2): in the app, on the question paper itself, in an
// answer table (an answer booklet by default, D-663) or on a bubble sheet. Written by the create wizard; an exam made
// before it has no key, so [answerFormatOf] reads what older settings say and answers null when they say nothing (the
// caller then decides from the exam's setup, as it did before).
library;

enum AnswerFormat { online, onPaper, table, bubble }

/// The wire value of [f] (`settings.answer_format`).
String answerFormatKey(AnswerFormat f) => switch (f) {
      AnswerFormat.online => 'online',
      AnswerFormat.onPaper => 'on_paper',
      AnswerFormat.table => 'table',
      AnswerFormat.bubble => 'bubble',
    };

/// The answer format saved in [settings]; for an older exam, what its settings imply (a bubble run is a bubble exam);
/// null when nothing says.
AnswerFormat? answerFormatOf(Map settings) {
  final raw = '${settings['answer_format'] ?? ''}';
  for (final f in AnswerFormat.values) {
    if (answerFormatKey(f) == raw) return f;
  }
  if (settings['bubble_run'] != null) return AnswerFormat.bubble;
  return null;
}
