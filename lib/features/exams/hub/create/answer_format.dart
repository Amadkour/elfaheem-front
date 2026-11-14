// How students answer an exam (D-661): the wizard's first choice after Where, saved as `settings.answer_format`.
//
//   online     in the app
//   on_paper   on the printed exam itself
//   table      an answer table / booklet beside the question paper (`settings.answer_booklet` true)
//   bubble     a bubble sheet, marked by scanning
//
// Exams made before D-661 have no `answer_format`: it is derived from what they hold (a bubble template, a paper plan,
// the delivery). Shared with the answer-booklet pack: keep this API as it is.
library;

enum AnswerFormat { online, onPaper, table, bubble }

/// The value stored in `settings.answer_format`.
String answerFormatKey(AnswerFormat f) => switch (f) {
      AnswerFormat.online => 'online',
      AnswerFormat.onPaper => 'on_paper',
      AnswerFormat.table => 'table',
      AnswerFormat.bubble => 'bubble',
    };

/// The exam's answer format from its `settings` (or the exam itself, which carries the setup fields); null when nothing
/// says.
AnswerFormat? answerFormatOf(Map settings) {
  final raw = '${settings['answer_format'] ?? ''}';
  for (final f in AnswerFormat.values) {
    if (answerFormatKey(f) == raw) return f;
  }
  // older exams: what they hold (a bubble run is a bubble exam)
  if (settings['bubble_run'] != null) return AnswerFormat.bubble;
  final format = '${settings['paper_format'] ?? ''}';
  if (settings['omr_template_id'] != null || format == 'bubble' || format == 'both') return AnswerFormat.bubble;
  if (settings['answer_booklet'] == true) return AnswerFormat.table;
  if (settings['paper_plan'] != null || format == 'paper' || settings['delivery'] == 'paper') return AnswerFormat.onPaper;
  if (settings['delivery'] == 'online') return AnswerFormat.online;
  return null;
}
