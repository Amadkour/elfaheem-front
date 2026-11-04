// Results publishing, what students see, cancelling a question, the grade log (D-170, D-175, D-176). Server
// contract: ../back/docs/grading/CONTRACT.md §1. Pure parts (unit-tested: test/org/exam_publish_flow_test.dart,
// exam_question_void_test.dart, exam_grade_log_test.dart): [PublishOutcome], [ReviewPending], [ResultAnswer],
// [GradeLogEntry], [GradeLogPage], the texts, and [ExamGradingApi]. The widgets are in exam_grading_widgets.dart.
import 'package:flutter_education_app/core/api_client.dart';

import '../../admin/admin_common.dart' show asInt, asMap, asMapList, t;
import 'exam_engine_api.dart';

/// What students see of a published result: `settings.results_view`.
const resultsViews = ['score', 'answers', 'answers_key'];

String resultsViewLabel(String v) => switch (v) {
      'answers' => t('الدرجة + إجاباتهم', 'Score + their answers'),
      'answers_key' => t('الدرجة + إجاباتهم + الإجابة الصحيحة', 'Score + their answers + the correct answers'),
      _ => t('الدرجة فقط', 'Score only'),
    };

String resultsViewHint(String v) => switch (v) {
      'answers' => t('يرى الطالب درجته وما أجاب به في كل سؤال، دون كشف الإجابة الصحيحة.',
          'Students see their score and what they answered on each question, without the correct answer.'),
      'answers_key' => t('يرى الطالب درجته وإجاباته والإجابة الصحيحة لكل سؤال. مناسب للتعلم بعد الاختبار.',
          'Students see their score, their answers and the correct answer to each question. Good for learning after the exam.'),
      _ => t('يرى الطالب درجته فقط، دون أسئلة أو إجابات.', 'Students see only their score, no questions or answers.'),
    };

/// `409 review_pending {open_answers, open_items}` (the old code `review_items_open` is the same answer).
class ReviewPending {
  ReviewPending({required this.openAnswers, required this.openItems});
  final int openAnswers;
  final int openItems;

  int get total => openAnswers + openItems;

  /// null = the failure is not "review pending".
  static ReviewPending? from(EngineResult r) {
    if (r.ok || (r.code != 'review_pending' && r.code != 'review_items_open')) return null;
    final d = r.detail;
    return ReviewPending(
        openAnswers: asInt(d['open_answers'] ?? d['answers'] ?? d['open']), openItems: asInt(d['open_items'] ?? d['items']));
  }
}

/// The server's answer to publishing: when, and how many attempts show / are held for a review.
class PublishOutcome {
  PublishOutcome({this.publishedAt, this.visible, this.held = 0});
  final String? publishedAt;

  /// null = an older server that does not count.
  final int? visible;
  final int held;

  factory PublishOutcome.fromJson(Map<String, dynamic> j) => PublishOutcome(
        publishedAt: j['results_published_at']?.toString(),
        visible: j['visible_attempts'] == null ? null : asInt(j['visible_attempts']),
        held: asInt(j['held_attempts']),
      );

  /// The notice after publishing.
  String get text {
    if (visible == null) return t('نُشرت النتائج', 'Results published');
    if (held == 0) return t('نُشرت النتائج: ظهرت لـ $visible', 'Results published: $visible attempt(s) can see them');
    return t('نُشرت النتائج: ظهرت لـ $visible وبقيت $held محجوبة حتى تُراجَع', 'Results published: $visible can see them, $held held until reviewed');
  }
}

/// One answer of the student's result (`answers` of `GET /attempts/{id}/result`).
class ResultAnswer {
  ResultAnswer({required this.questionId, required this.position, required this.type, required this.prompt, this.yourAnswer,
      this.score, this.max, this.voided, this.correctAnswer, this.hasCorrect = false});
  final int questionId;
  final int position;
  final String type;
  final String prompt;
  final dynamic yourAnswer;
  final double? score;
  final double? max;

  /// `remove` | `full_marks` | null (not cancelled). The contract says `voided` is a flag; a map / mode string is accepted.
  final String? voided;
  final dynamic correctAnswer;

  /// `correct_answer` was sent (only for the "answers + key" view).
  final bool hasCorrect;

  bool get isVoided => voided != null;

  factory ResultAnswer.fromJson(Map<String, dynamic> j) {
    final v = j['voided'];
    final mode = v is Map ? '${v['mode'] ?? 'remove'}' : (v is String && v.isNotEmpty ? v : (v == true ? '${j['void_mode'] ?? 'remove'}' : null));
    double? d(String k) => j[k] == null ? null : (j[k] is num ? (j[k] as num).toDouble() : double.tryParse('${j[k]}'));
    return ResultAnswer(
      questionId: asInt(j['question_id']), position: asInt(j['position']), type: '${j['type'] ?? ''}', prompt: '${j['prompt'] ?? ''}',
      yourAnswer: j['your_answer'], score: d('score'), max: d('max'), voided: mode, correctAnswer: j['correct_answer'],
      hasCorrect: j.containsKey('correct_answer') && j['correct_answer'] != null,
    );
  }
}

/// An answer value (any type) as one line of text.
String answerValueText(dynamic v) {
  if (v == null) return '—';
  if (v is String) return v.trim().isEmpty ? '—' : v.trim();
  if (v is bool) return v ? t('صحيح', 'True') : t('خطأ', 'False');
  if (v is List) return v.isEmpty ? '—' : v.map(answerValueText).join(' · ');
  if (v is Map) {
    final m = asMap(v);
    for (final k in const ['text', 'option', 'value', 'label']) {
      if (m[k] != null) return answerValueText(m[k]);
    }
    for (final k in const ['options', 'blanks', 'order']) {
      if (m[k] is List) return answerValueText(m[k]);
    }
    if (m['pairs'] is Map) return asMap(m['pairs']).entries.map((e) => '${e.key} ↔ ${e.value}').join(' · ');
    return m.isEmpty ? '—' : m.values.map(answerValueText).join(' · ');
  }
  return '$v';
}

String voidModeLabel(String m) => m == 'full_marks' ? t('الدرجة الكاملة للجميع', 'Full marks to everyone') : t('حذف السؤال من الدرجة', 'Remove it from the score');

String voidModeHint(String m) => m == 'full_marks'
    ? t('يحصل كل طالب على درجة السؤال كاملة، وتبقى الدرجة الكلية كما هي.',
        'Every student gets the question\'s full points, the exam total stays the same.')
    : t('يخرج السؤال من درجة الطالب ومن الدرجة الكلية معاً، فتُحسب النسبة على بقية الأسئلة.',
        'The question leaves both the students\' scores and the exam total, so the percentage is computed on the other questions.');

String voidedChipText(String mode) =>
    mode == 'full_marks' ? t('درجة كاملة للجميع', 'Full marks to everyone') : t('أُلغي السؤال ولم يُحتسب', 'Cancelled, not counted');

String voidErrorText(String? code, String fallback) => switch (code) {
      'reason_required' || 'bad_reason' => t('اكتب سبب الإلغاء (من 3 إلى 500 حرف)', 'Write the reason (3 to 500 characters)'),
      'bad_void_mode' || 'bad_mode' => t('اختر طريقة الإلغاء', 'Pick how to cancel it'),
      'question_not_in_exam' || 'placement_not_found' => t('السؤال ليس في هذا الاختبار', 'The question is not in this exam'),
      'already_voided' => t('السؤال ملغى بالفعل', 'The question is already cancelled'),
      'not_voided' => t('السؤال غير ملغى', 'The question is not cancelled'),
      'forbidden' => t('ليس لديك صلاحية على هذا', 'You do not have permission for this'),
      _ => fallback,
    };

String gradeLogFieldText(String entity, String field) => switch (field) {
      'voided' => t('إلغاء السؤال', 'Question cancelled'),
      'score' => entity == 'answer' ? t('درجة الإجابة', 'Answer mark') : t('الدرجة', 'Score'),
      'final_score' => entity == 'attempt' ? t('الدرجة الكلية', 'Total score') : t('درجة الإجابة', 'Answer mark'),
      _ => field.isEmpty ? entity : field,
    };

/// A logged value, shown plainly ("—" when empty, 2 or 2.5 for a number, yes / no for a flag).
String gradeLogValueText(dynamic v) {
  if (v == null) return '—';
  if (v is bool) return v ? t('نعم', 'Yes') : t('لا', 'No');
  if (v is num) return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
  if (v is Map) return v.isEmpty ? '—' : answerValueText(v);
  final s = '$v'.trim();
  final n = num.tryParse(s);
  if (n != null) return gradeLogValueText(n);
  return s.isEmpty ? '—' : s;
}

/// `regrade` is written by the system itself (actor 0): show it as such.
String gradeLogReasonText(String reason) => reason == 'regrade' ? t('إعادة تصحيح آلية بعد تغيير المفتاح', 'Automatic regrade after the key changed') : reason;

class GradeLogEntry {
  GradeLogEntry({required this.id, this.at, this.actorId, this.actorName, required this.entity, this.entityId, this.attemptId,
      this.studentId, this.questionId, required this.field, this.oldValue, this.newValue, this.reason = ''});
  final int id;
  final String? at;
  final int? actorId;
  final String? actorName;
  final String entity;
  final int? entityId;
  final int? attemptId;
  final int? studentId;
  final int? questionId;
  final String field;
  final dynamic oldValue;
  final dynamic newValue;
  final String reason;

  bool get bySystem => actorId == 0 || actorId == null && (actorName == null || actorName!.isEmpty);

  factory GradeLogEntry.fromJson(Map<String, dynamic> j) {
    int? n(String k) => j[k] == null ? null : asInt(j[k]);
    return GradeLogEntry(
      id: asInt(j['id']), at: j['at']?.toString(), actorId: n('actor_id'), actorName: j['actor_name']?.toString(), entity: '${j['entity'] ?? ''}',
      entityId: n('entity_id'), attemptId: n('attempt_id'), studentId: n('student_id'), questionId: n('question_id'),
      field: '${j['field'] ?? ''}', oldValue: j['old'], newValue: j['new'], reason: '${j['reason'] ?? ''}',
    );
  }
}

class GradeLogPage {
  GradeLogPage({required this.items, this.nextBeforeId});
  final List<GradeLogEntry> items;
  final int? nextBeforeId;

  factory GradeLogPage.fromJson(Map<String, dynamic> j) => GradeLogPage(
        items: [for (final e in asMapList(j['items'])) GradeLogEntry.fromJson(e)],
        nextBeforeId: j['next_before_id'] == null ? null : asInt(j['next_before_id']),
      );
}

class ExamGradingApi {
  ExamGradingApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;
  static const base = ExamEngineApi.base;

  /// [gradedOnly]: publish the reviewed attempts and hold the ones with an open item until a person resolves it.
  Future<EngineResult> publishResults(int examId, {bool gradedOnly = false}) =>
      engineCall(() => _api.post('$base/exams/$examId/results/publish', body: {if (gradedOnly) 'graded_only': true}));
  Future<EngineResult> unpublishResults(int examId) => engineCall(() => _api.post('$base/exams/$examId/results/unpublish'));

  Future<EngineResult> voidQuestion(int examId, int questionId, {required String reason, required String mode}) =>
      engineCall(() => _api.post('$base/exams/$examId/questions/$questionId/void', body: {'reason': reason.trim(), 'mode': mode}));
  Future<EngineResult> restoreQuestion(int examId, int questionId, {required String reason}) =>
      engineCall(() => _api.post('$base/exams/$examId/questions/$questionId/void/restore', body: {'reason': reason.trim()}));

  Future<EngineResult> gradeLog(int examId, {int? attemptId, int? questionId, int? beforeId, int limit = 50}) =>
      engineCall(() => _api.get('$base/exams/$examId/grade-log', queryParams: {
            'attempt_id': ?attemptId,
            'question_id': ?questionId,
            'before_id': ?beforeId,
            'limit': limit,
          }));
}
