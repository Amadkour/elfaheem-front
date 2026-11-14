// What the "New exam" wizard remembers per teacher on this device (D-661): the last answer format and the last bubble
// sheet, preselected in the next exam; (D-687) the answer sheets' choices: print or have the bubble sheets, personal or
// generic, academic ID or system number; and (D-697) the last answer-sheet layout and the attributes printed on each
// copy, in their order. SharedPreferences, `exam_create.<key>.<userId>`; a failure only means nothing is preselected.
library;

import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_education_app/features/exams/hub/create/answer_format.dart';
import 'package:flutter_education_app/features/exams/hub/create/answer_sheet_plan.dart';
import 'package:flutter_education_app/features/exams/hub/create/offline_flow.dart';

typedef CreateRemembered = ({
  AnswerFormat? answer,
  int? templateId,
  BubbleSource? bubble,
  SheetCopies? copies,
  IdSource? idSource,
  PaperLayout? layout,
  List<String> attributes,
});

class ExamCreatePrefs {
  const ExamCreatePrefs(this.userId);

  /// 0 = not signed in / unknown (still remembered, on the device).
  final int userId;

  String get _answerKey => 'exam_create.answer.$userId';
  String get _templateKey => 'exam_create.template.$userId';
  String get _bubbleKey => 'exam_create.bubble_source.$userId';
  String get _copiesKey => 'exam_create.copies.$userId';
  String get _idKey => 'exam_create.id_source.$userId';
  String get _layoutKey => 'exam_create.layout.$userId';
  String get _attributesKey => 'exam_create.attributes.$userId';

  static const CreateRemembered nothing = (answer: null, templateId: null, bubble: null, copies: null, idSource: null, layout: null, attributes: <String>[]);

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
        layout: paperLayoutOfKey(p.getString(_layoutKey)),
        attributes: p.getStringList(_attributesKey) ?? const <String>[],
      );
    } catch (_) {
      return nothing;
    }
  }

  /// [attributes]: the printed attributes' ids (`IdentifierChoice.id`), in their order.
  Future<void> save({
    AnswerFormat? answer,
    int? templateId,
    BubbleSource? bubble,
    SheetCopies? copies,
    IdSource? idSource,
    PaperLayout? layout,
    List<String>? attributes,
  }) async {
    try {
      final p = await SharedPreferences.getInstance();
      if (answer != null) await p.setString(_answerKey, answerFormatKey(answer));
      if (templateId != null) await p.setInt(_templateKey, templateId);
      if (bubble != null) await p.setString(_bubbleKey, bubbleSourceKey(bubble));
      if (copies != null) await p.setString(_copiesKey, sheetCopiesKey(copies));
      if (idSource != null) await p.setString(_idKey, idSourceKey(idSource));
      if (layout != null) await p.setString(_layoutKey, paperLayoutKey(layout));
      if (attributes != null && attributes.isNotEmpty) await p.setStringList(_attributesKey, attributes);
    } catch (_) {
      // nothing remembered: the next exam starts unselected
    }
  }
}
