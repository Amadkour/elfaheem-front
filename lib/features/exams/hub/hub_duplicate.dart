// Duplicate an exam from the Exam Hub's Creation list (D-665): `POST /exams/{id}/duplicate` (back D-652) makes a new
// DRAFT with the same sections and the same pinned bank questions (no question copies), the same set-up minus what
// belonged to the old sitting (window, passcode, paper versions, cancelled questions, attempts). The title gets
// " (copy)" / " (نسخة)" by the exam's language. The hub then opens the copy in the editor, as it does for any draft.
// Grading runs (essay / bubble) are not exams to reuse: the hub never offers them the action, the server refuses them.
//
// Pure (unit-tested): hubCanDuplicate · duplicatedExamId · duplicateErrorText.
library;

import 'package:flutter_education_app/core/api_client.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show asInt, t;
import 'package:flutter_education_app/features/exams/exam_all.dart' show AllExam;
import 'package:flutter_education_app/features/exams/exam_authoring.dart' show authoringError;
import 'package:flutter_education_app/features/exams/exam_engine_api.dart' show EngineResult, engineCall;

/// Every exam but a grading run (D-662 essay runs, D-340 bubble runs) and an archived one.
bool hubCanDuplicate(AllExam e) => e.grading?.run == null && e.status != 'archived';

/// The new exam's id from the reply (null when the reply has none).
int? duplicatedExamId(EngineResult r) {
  if (!r.ok) return null;
  final id = asInt(r.map['id']);
  return id > 0 ? id : null;
}

String duplicateErrorText(EngineResult r) => r.code == 'run_not_duplicable'
    ? t('جولات التصحيح لا تُنسخ. ابدأ جولة جديدة.', 'A grading run cannot be duplicated. Start a new run.')
    : authoringError(r);

class ExamDuplicateApi {
  ExamDuplicateApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;

  /// [title] null: the server names it "<title> (copy)" in the exam's language.
  Future<EngineResult> duplicate(int examId, {String? title}) =>
      engineCall(() => _api.post('/api/v1/exam/exams/$examId/duplicate', body: {if (title != null && title.trim().isNotEmpty) 'title': title.trim()}));
}
