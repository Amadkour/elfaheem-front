// What the "New exam" wizard remembers per teacher on this device (D-661): the last answer format and the last bubble
// sheet, preselected in the next exam. SharedPreferences, `exam_create.<key>.<userId>`; a failure only means nothing
// is preselected.
library;

import 'package:shared_preferences/shared_preferences.dart';

import 'answer_format.dart';

typedef CreateRemembered = ({AnswerFormat? answer, int? templateId});

class ExamCreatePrefs {
  const ExamCreatePrefs(this.userId);

  /// 0 = not signed in / unknown (still remembered, on the device).
  final int userId;

  String get _answerKey => 'exam_create.answer.$userId';
  String get _templateKey => 'exam_create.template.$userId';

  Future<CreateRemembered> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_answerKey);
      final answer = raw == null ? null : answerFormatOf({'answer_format': raw});
      return (answer: answer, templateId: p.getInt(_templateKey));
    } catch (_) {
      return (answer: null, templateId: null);
    }
  }

  Future<void> save({AnswerFormat? answer, int? templateId}) async {
    try {
      final p = await SharedPreferences.getInstance();
      if (answer != null) await p.setString(_answerKey, answerFormatKey(answer));
      if (templateId != null) await p.setInt(_templateKey, templateId);
    } catch (_) {
      // nothing remembered: the next exam starts unselected
    }
  }
}
