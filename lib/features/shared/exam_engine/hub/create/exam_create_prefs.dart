// What the "New exam" wizard remembers per teacher on this device (D-661): the last answer format and the last bubble
// sheet, preselected in the next exam; and (D-687) the answer sheets' choices: print or have the bubble sheets,
// personal or generic, academic ID or system number. SharedPreferences, `exam_create.<key>.<userId>`; a failure only means nothing
// is preselected.
library;

import 'package:shared_preferences/shared_preferences.dart';

import 'answer_format.dart';
import 'answer_sheet_plan.dart';

typedef CreateRemembered = ({AnswerFormat? answer, int? templateId, BubbleSource? bubble, SheetCopies? copies, IdSource? idSource});

class ExamCreatePrefs {
  const ExamCreatePrefs(this.userId);

  /// 0 = not signed in / unknown (still remembered, on the device).
  final int userId;

  String get _answerKey => 'exam_create.answer.$userId';
  String get _templateKey => 'exam_create.template.$userId';
  String get _bubbleKey => 'exam_create.bubble_source.$userId';
  String get _copiesKey => 'exam_create.copies.$userId';
  String get _idKey => 'exam_create.id_source.$userId';

  Future<CreateRemembered> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_answerKey);
      final answer = raw == null ? null : answerFormatOf({'answer_format': raw});
      return (
        answer: answer,
        templateId: p.getInt(_templateKey),
        bubble: bubbleSourceOf(p.getString(_bubbleKey)),
        copies: sheetCopiesOf(p.getString(_copiesKey)),
        idSource: idSourceOf(p.getString(_idKey)),
      );
    } catch (_) {
      return (answer: null, templateId: null, bubble: null, copies: null, idSource: null);
    }
  }

  Future<void> save({AnswerFormat? answer, int? templateId, BubbleSource? bubble, SheetCopies? copies, IdSource? idSource}) async {
    try {
      final p = await SharedPreferences.getInstance();
      if (answer != null) await p.setString(_answerKey, answerFormatKey(answer));
      if (templateId != null) await p.setInt(_templateKey, templateId);
      if (bubble != null) await p.setString(_bubbleKey, bubbleSourceKey(bubble));
      if (copies != null) await p.setString(_copiesKey, sheetCopiesKey(copies));
      if (idSource != null) await p.setString(_idKey, idSourceKey(idSource));
    } catch (_) {
      // nothing remembered: the next exam starts unselected
    }
  }
}
