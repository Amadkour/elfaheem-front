// Exam Engine Phase 8 client: appeals (students ask, managers decide) and exam analytics (item analysis, distribution,
// risk signals). Server contract: ../back/exam_engine/routers/insights.py (FLUTTER_API_CHANGES · phase 8).
//
// Pure parts (unit-tested: test/org/exam_insights_test.dart): [Appeal], [ExamAnalytics], [ItemStat], [appealStateText],
// [itemFlagText], [appealCodeText].
import 'package:flutter_education_app/core/api_client.dart';

import '../../admin/admin_common.dart' show asInt, asMap, asMapList, t;
import 'exam_engine_api.dart';

double? _d(dynamic v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));

class Appeal {
  Appeal({required this.id, required this.attemptId, required this.questionId, required this.state, required this.reason,
      this.studentId, this.studentCode, this.reviewerId, this.note, this.scoreBefore, this.scoreAfter, this.createdAt});
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

  bool get open => state == 'open' || state == 'in_review';
  String get studentLabel => studentCode ?? (studentId == null ? '—' : '#$studentId');

  factory Appeal.fromJson(Map<String, dynamic> j) => Appeal(
        id: asInt(j['id']), attemptId: asInt(j['attempt_id']), questionId: asInt(j['question_id']), state: '${j['state'] ?? 'open'}',
        reason: '${j['reason'] ?? ''}', studentId: j['student_id'] == null ? null : asInt(j['student_id']),
        studentCode: j['student_code']?.toString(), reviewerId: j['reviewer_id'] == null ? null : asInt(j['reviewer_id']),
        note: j['decision_note']?.toString(), scoreBefore: _d(j['score_before']), scoreAfter: _d(j['score_after']),
        createdAt: j['created_at']?.toString(),
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

class ItemStat {
  ItemStat({required this.questionId, required this.type, required this.points, required this.answered, this.difficulty,
      this.discrimination, this.upperLower, this.options = const {}, this.flags = const []});
  final int questionId;
  final String type;
  final double points;
  final int answered;
  final double? difficulty;
  final double? discrimination;
  final double? upperLower;
  final Map<String, int> options;
  final List<String> flags;

  factory ItemStat.fromJson(Map<String, dynamic> j) => ItemStat(
        questionId: asInt(j['question_id']), type: '${j['type'] ?? ''}', points: _d(j['points']) ?? 0, answered: asInt(j['answered']),
        difficulty: _d(j['difficulty']), discrimination: _d(j['discrimination']), upperLower: _d(j['upper_lower']),
        options: {for (final e in asMap(j['options']).entries) e.key: asInt(e.value)},
        flags: [for (final f in (j['flags'] as List? ?? const [])) '$f'],
      );
}

String itemFlagText(String f) => switch (f) {
      'too_hard' => t('صعب جداً', 'Too hard'),
      'too_easy' => t('سهل جداً', 'Too easy'),
      'weak_discrimination' => t('تمييز ضعيف', 'Weak discrimination'),
      'negative' => t('تمييز سلبي — راجع المفتاح', 'Negative discrimination — check the key'),
      _ => f,
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
