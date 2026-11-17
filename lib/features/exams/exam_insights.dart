// Exam Engine Phase 8 client: appeals (students ask, managers decide) and exam analytics (item analysis, distribution,
// risk signals). Server contract: ../back/exam_engine/routers/insights.py (FLUTTER_API_CHANGES · phase 8).
//
// Pure parts (unit-tested: test/org/exam_insights_test.dart): [Appeal], [ExamAnalytics], [ItemStat], [appealStateText],
// [itemFlagText], [appealCodeText].
import 'package:flutter_education_app/core/api_client.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show asInt, asMap, asMapList, t;
import 'package:flutter_education_app/features/exams/exam_engine_api.dart';

double? _d(dynamic v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));

/// "Question 3" from a question's place in the exam (D-1135); "Question" when the server sent no place. Never the
/// database id: a person cannot find "Question #4821" on the paper.
String questionText(int? position) => position == null ? t('السؤال', 'Question') : t('السؤال $position', 'Question $position');

class Appeal {
  Appeal({required this.id, required this.attemptId, required this.questionId, required this.state, required this.reason,
      this.studentId, this.studentCode, this.reviewerId, this.note, this.scoreBefore, this.scoreAfter, this.createdAt, this.position, this.max});
  final int id;
  final int attemptId;
  final int questionId;
  final String state;
  final String reason;
  final int? studentId;
  final String? studentCode;
  final int? reviewerId;
  final String? note;
  final double? scoreBefore;
  final double? scoreAfter;
  final String? createdAt;

  /// The question's place on the student's paper and its points (D-1135); null from an older server.
  final int? position;
  final double? max;

  /// "Question 3", never a database id; an older server without the place reads just "Question".
  String get questionLabel => questionText(position);

  bool get open => state == 'open' || state == 'in_review';
  String get studentLabel => studentCode ?? (studentId == null ? '—' : '#$studentId');

  factory Appeal.fromJson(Map<String, dynamic> j) => Appeal(
        id: asInt(j['id']), attemptId: asInt(j['attempt_id']), questionId: asInt(j['question_id']), state: '${j['state'] ?? 'open'}',
        reason: '${j['reason'] ?? ''}', studentId: j['student_id'] == null ? null : asInt(j['student_id']),
        studentCode: j['student_code']?.toString(), reviewerId: j['reviewer_id'] == null ? null : asInt(j['reviewer_id']),
        note: j['decision_note']?.toString(), scoreBefore: _d(j['score_before']), scoreAfter: _d(j['score_after']),
        createdAt: j['created_at']?.toString(), position: j['position'] == null ? null : asInt(j['position']), max: _d(j['max']),
      );
}

String appealStateText(String s) => switch (s) {
      'open' => t('مفتوح', 'Open'),
      'in_review' => t('قيد المراجعة', 'In review'),
      'accepted' => t('مقبول', 'Accepted'),
      'rejected' => t('مرفوض', 'Rejected'),
      'withdrawn' => t('مسحوب', 'Withdrawn'),
      _ => s,
    };

String appealCodeText(String? code, String fallback) => switch (code) {
      'appeals_disabled' => t('التظلمات غير متاحة لهذا الاختبار', 'Appeals are not available for this exam'),
      'results_not_available' => t('لا يمكن التظلم قبل ظهور النتيجة', 'You can appeal once the result is visible'),
      'appeal_window_closed' => t('انتهت مهلة التظلم', 'The appeal period has ended'),
      'reason_required' => t('اكتب سبب التظلم (10 أحرف على الأقل)', 'Write the reason (at least 10 characters)'),
      'appeal_open' => t('يوجد تظلم مفتوح على هذه الإجابة', 'There is already an open appeal on this answer'),
      'appeal_limit' => t('بلغت الحد الأقصى للتظلمات في هذه المحاولة', 'You reached the appeal limit for this attempt'),
      'appeal_claimed' => t('يراجع هذا التظلم مراجع آخر', 'Another reviewer is handling this appeal'),
      'reviewer_must_differ' => t('يقرر التظلم مراجع غير من صحح الإجابة', 'A reviewer other than the original marker must decide'),
      'note_required' => t('اكتب سبب القرار — يراه الطالب', 'Write the reason for the decision — the student sees it'),
      'score_out_of_range' => t('الدرجة خارج المدى', 'The score is out of range'),
      _ => fallback,
    };

/// One option of a choice question in the item analysis: how many chose it, the share, and the top vs bottom group.
class OptionStat {
  OptionStat({required this.key, this.label = '', this.count = 0, this.share = 0, this.isCorrect = false, this.upperShare, this.lowerShare});
  final String key;
  final String label;
  final int count;
  final double share;
  final bool isCorrect;
  final double? upperShare;
  final double? lowerShare;

  factory OptionStat.fromJson(Map<String, dynamic> j) => OptionStat(
        key: '${j['key'] ?? ''}', label: '${j['label'] ?? ''}', count: asInt(j['count']), share: _d(j['share']) ?? 0,
        isCorrect: j['is_correct'] == true, upperShare: _d(j['upper_share']), lowerShare: _d(j['lower_share']),
      );
}

class ItemStat {
  ItemStat({required this.questionId, required this.type, required this.points, required this.answered, this.difficulty,
      this.discrimination, this.upperLower, this.options = const {}, this.flags = const [], this.optionStats = const [],
      this.unusedDistractors = const [], this.voided = false, this.position});
  final int questionId;

  /// The question's place in the exam (D-1135); null from an older server.
  final int? position;

  String get questionLabel => questionText(position);
  final String type;
  final double points;
  final int answered;
  final double? difficulty;
  final double? discrimination;
  final double? upperLower;

  /// option key → count (the older payload's shape; derived from [optionStats] when the server sends the list).
  final Map<String, int> options;
  final List<String> flags;

  /// The newer per-option rows (share, upper / lower group, the key) and the distractors nobody chose.
  final List<OptionStat> optionStats;
  final List<String> unusedDistractors;

  /// The question was cancelled (D-245).
  final bool voided;

  factory ItemStat.fromJson(Map<String, dynamic> j) {
    final raw = j['options'];
    final rawStats = j['option_stats'] is List ? j['option_stats'] : (raw is List ? raw : const []);
    final stats = [for (final o in rawStats as List) if (o is Map) OptionStat.fromJson(asMap(o))];
    return ItemStat(
      questionId: asInt(j['question_id']), position: j['position'] == null ? null : asInt(j['position']), type: '${j['type'] ?? ''}',
      points: _d(j['points']) ?? 0, answered: asInt(j['answered']),
      difficulty: _d(j['difficulty']), discrimination: _d(j['discrimination']), upperLower: _d(j['upper_lower']),
      options: raw is Map ? {for (final e in asMap(raw).entries) e.key: asInt(e.value)} : {for (final o in stats) o.key: o.count},
      flags: [for (final f in (j['flags'] as List? ?? const [])) '$f'],
      optionStats: stats,
      unusedDistractors: [for (final k in (j['unused_distractors'] as List? ?? const [])) '$k'],
      voided: j['voided'] == true || j['voided'] is Map,
    );
  }
}

String itemFlagText(String f) => switch (f) {
      'too_hard' => t('صعب جداً', 'Too hard'),
      'too_easy' => t('سهل جداً', 'Too easy'),
      'weak_discrimination' => t('تمييز ضعيف', 'Weak discrimination'),
      'negative' => t('تمييز سلبي — راجع المفتاح', 'Negative discrimination — check the key'),
      'unused_distractor' => t('خيار لم يختره أحد', 'A choice nobody picked'),
      'key_suspect' => t('المفتاح مشكوك فيه', 'The key looks wrong'),
      _ => f,
    };

/// A flag in plain words for the teacher: what it means and what to do about it (null = the short label is enough).
String? itemFlagExplain(String f) => switch (f) {
      'unused_distractor' => t('هذا الخيار الخاطئ لم يختره أي طالب، فهو لا يختبر شيئاً. استبدله بخيار أكثر إقناعاً.',
          'No student chose this wrong option, so it tests nothing. Replace it with a more convincing one.'),
      'key_suspect' => t('خيار خاطئ اختاره من حصلوا على أعلى الدرجات أكثر ممن اختاروا الإجابة الصحيحة. قد يكون مفتاح الإجابة خاطئاً أو السؤال ملتبساً.',
          'A wrong option was chosen by more of the top scorers than the marked answer. The key may be wrong or the question unclear.'),
      _ => null,
    };

class ExamAnalytics {
  ExamAnalytics({required this.state, this.attempts = 0, this.distribution = const {}, this.items = const [], this.risk = const {},
      this.reliability, this.computedAt});
  final String state;
  final int attempts;
  final Map<String, dynamic> distribution;
  final List<ItemStat> items;
  final Map<String, dynamic> risk;
  final double? reliability;
  final String? computedAt;

  List<int> get histogram => [for (final v in (distribution['histogram'] as List? ?? const [])) asInt(v)];
  List<Map<String, dynamic>> riskList(String key) => asMapList(risk[key]);
  int get riskCount => ['proctoring', 'similar_answers', 'shared_wrong_answers', 'fast_high_scores'].fold(0, (n, k) => n + riskList(k).length);

  factory ExamAnalytics.fromJson(Map<String, dynamic> j) {
    final d = asMap(j['data']);
    return ExamAnalytics(
      state: '${j['state'] ?? 'none'}', attempts: asInt(d['attempts']), distribution: asMap(d['distribution']),
      items: asMapList(d['items']).map(ItemStat.fromJson).toList(), risk: asMap(d['risk']), reliability: _d(d['reliability_kr20']),
      computedAt: j['computed_at']?.toString(),
    );
  }
}

class ExamInsightsApi {
  ExamInsightsApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;
  static const base = ExamEngineApi.base;

  Future<EngineResult> myAppeals(int attemptId) => engineCall(() => _api.get('$base/attempts/$attemptId/appeals'));
  Future<EngineResult> appeal(int attemptId, int questionId, String reason) =>
      engineCall(() => _api.post('$base/attempts/$attemptId/appeals', body: {'question_id': questionId, 'reason': reason.trim()}));
  Future<EngineResult> withdraw(int appealId) => engineCall(() => _api.post('$base/appeals/$appealId/withdraw'));
  Future<EngineResult> examAppeals(int examId, {String state = 'open'}) =>
      engineCall(() => _api.get('$base/exams/$examId/appeals', queryParams: {'state': state}));
  Future<EngineResult> claim(int appealId) => engineCall(() => _api.post('$base/appeals/$appealId/claim'));
  Future<EngineResult> decide(int appealId, {required bool accept, double? score, required String note}) =>
      engineCall(() => _api.post('$base/appeals/$appealId/decide', body: {'accept': accept, 'score': ?score, 'note': note.trim()}));
  Future<EngineResult> analytics(int examId) => engineCall(() => _api.get('$base/exams/$examId/analytics'));
  Future<EngineResult> refreshAnalytics(int examId) => engineCall(() => _api.post('$base/exams/$examId/analytics/refresh'));
}
