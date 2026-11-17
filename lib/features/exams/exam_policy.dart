// lib/features/exams/exam_policy.dart
//
// The Super Admin's exam policy (D-1130, back features/exams/exam_policy.py): what a NEW exam starts with (defaults) and
// what the engine refuses (limits). Pure, unit-tested: [ExamPolicy] parses `GET /api/v1/exam-policy`, clamps a value to
// the limits, says a limit in words and words the engine's 422 `policy_*` codes. [ExamPolicy.current] is the last one
// read (the creation flows call [ExamPolicy.load] when they open, so a new exam is born from the platform's defaults);
// before any read it is [ExamPolicy.fallback], which is exactly what the app did before this decision.
library;

import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;

const kExamPolicyPath = '/api/v1/exam-policy';
const kAdminExamPolicyPath = '/api/v1/admin/exam-policy';

/// When students see their result.
const kResultsPolicies = ['after_submit', 'when_published', 'hidden'];

/// What students see of it.
const kResultsViews = ['score', 'answers', 'answers_key'];

class ExamPolicy {
  const ExamPolicy({
    this.durationMinutes = 30,
    this.maxAttempts = 1,
    this.shuffle = true,
    this.resultsPolicy = 'after_submit',
    this.resultsView = 'score',
    this.passingPercent = 50,
    this.highStakes = false,
    this.maxDurationMinutes = 0,
    this.attemptsCap = 100,
    this.allowUnlimitedAttempts = true,
    this.maxQuestions = 0,
    this.allowAnswerKey = true,
  });

  // defaults
  final int durationMinutes;
  final int maxAttempts;
  final bool shuffle;
  final String resultsPolicy;
  final String resultsView;
  final double passingPercent;
  final bool highStakes;

  // limits (0 = none)
  final int maxDurationMinutes;
  final int attemptsCap;
  final bool allowUnlimitedAttempts;
  final int maxQuestions;
  final bool allowAnswerKey;

  static const fallback = ExamPolicy();

  /// The last policy read; [fallback] until then.
  static ExamPolicy current = fallback;
  static DateTime? _readAt;

  static int _int(Object? v, int d) => v is num ? v.toInt() : int.tryParse('$v') ?? d;

  factory ExamPolicy.fromJson(Map<String, dynamic> j) {
    final d = j['defaults'] is Map ? Map<String, dynamic>.from(j['defaults'] as Map) : const <String, dynamic>{};
    final l = j['limits'] is Map ? Map<String, dynamic>.from(j['limits'] as Map) : const <String, dynamic>{};
    const f = fallback;
    String pick(Object? v, List<String> allowed, String dflt) => allowed.contains('$v') ? '$v' : dflt;
    return ExamPolicy(
      durationMinutes: _int(d['duration_minutes'], f.durationMinutes).clamp(1, 24 * 60),
      maxAttempts: _int(d['max_attempts'], f.maxAttempts).clamp(0, 100),
      shuffle: d['shuffle'] is bool ? d['shuffle'] as bool : f.shuffle,
      resultsPolicy: pick(d['results_policy'], kResultsPolicies, f.resultsPolicy),
      resultsView: pick(d['results_view'], kResultsViews, f.resultsView),
      passingPercent: (d['passing_percent'] is num ? (d['passing_percent'] as num).toDouble() : f.passingPercent).clamp(0, 100),
      highStakes: d['high_stakes'] is bool ? d['high_stakes'] as bool : f.highStakes,
      maxDurationMinutes: _int(l['max_duration_minutes'], 0).clamp(0, 24 * 60),
      attemptsCap: _int(l['max_attempts'], 100).clamp(1, 100),
      allowUnlimitedAttempts: l['allow_unlimited_attempts'] != false,
      maxQuestions: _int(l['max_questions'], 0).clamp(0, 1000),
      allowAnswerKey: l['allow_answer_key'] != false,
    );
  }

  Map<String, dynamic> defaultsJson() => {
        'duration_minutes': durationMinutes,
        'max_attempts': maxAttempts,
        'shuffle': shuffle,
        'results_policy': resultsPolicy,
        'results_view': resultsView,
        'passing_percent': passingPercent,
        'high_stakes': highStakes,
      };

  Map<String, dynamic> limitsJson() => {
        'max_duration_minutes': maxDurationMinutes,
        'max_attempts': attemptsCap,
        'allow_unlimited_attempts': allowUnlimitedAttempts,
        'max_questions': maxQuestions,
        'allow_answer_key': allowAnswerKey,
      };

  ExamPolicy copyWith({
    int? durationMinutes,
    int? maxAttempts,
    bool? shuffle,
    String? resultsPolicy,
    String? resultsView,
    double? passingPercent,
    bool? highStakes,
    int? maxDurationMinutes,
    int? attemptsCap,
    bool? allowUnlimitedAttempts,
    int? maxQuestions,
    bool? allowAnswerKey,
  }) =>
      ExamPolicy(
        durationMinutes: durationMinutes ?? this.durationMinutes,
        maxAttempts: maxAttempts ?? this.maxAttempts,
        shuffle: shuffle ?? this.shuffle,
        resultsPolicy: resultsPolicy ?? this.resultsPolicy,
        resultsView: resultsView ?? this.resultsView,
        passingPercent: passingPercent ?? this.passingPercent,
        highStakes: highStakes ?? this.highStakes,
        maxDurationMinutes: maxDurationMinutes ?? this.maxDurationMinutes,
        attemptsCap: attemptsCap ?? this.attemptsCap,
        allowUnlimitedAttempts: allowUnlimitedAttempts ?? this.allowUnlimitedAttempts,
        maxQuestions: maxQuestions ?? this.maxQuestions,
        allowAnswerKey: allowAnswerKey ?? this.allowAnswerKey,
      );

  /// A duration the engine accepts: at most the limit (when there is one), at least a minute.
  int clampDuration(int minutes) => maxDurationMinutes > 0 && minutes > maxDurationMinutes ? maxDurationMinutes : (minutes < 1 ? 1 : minutes);

  /// Attempts the engine accepts (0 = unlimited, only when allowed).
  int clampAttempts(int n) {
    if (n == 0) return allowUnlimitedAttempts ? 0 : attemptsCap.clamp(1, 100);
    return n > attemptsCap ? attemptsCap : n;
  }

  /// The client-side check of the same limits the engine enforces: the codes of [examPolicyCodeText].
  List<String> check({required int durationMinutes, required int maxAttempts, String? resultsView, int? questions}) => [
        if (maxDurationMinutes > 0 && durationMinutes > maxDurationMinutes) 'policy_duration',
        if (maxAttempts == 0 && !allowUnlimitedAttempts) 'policy_unlimited_attempts',
        if (maxAttempts > attemptsCap) 'policy_attempts',
        if (resultsView == 'answers_key' && !allowAnswerKey) 'policy_answer_key',
        if (questions != null && maxQuestions > 0 && questions > maxQuestions) 'policy_questions',
      ];

  /// Reads the policy (at most once a minute unless [force]); keeps the last one on any failure.
  static Future<ExamPolicy> load({bool force = false}) async {
    final at = _readAt;
    if (!force && at != null && DateTime.now().difference(at) < const Duration(minutes: 1)) return current;
    try {
      final data = await ApiClient().get(kExamPolicyPath).timeout(const Duration(seconds: 4));
      if (data is Map) {
        current = ExamPolicy.fromJson(Map<String, dynamic>.from(data));
        _readAt = DateTime.now();
      }
    } catch (_) {
      // an older server, offline, slow: the last policy (or the fallback) stands, the engine still enforces
    }
    return current;
  }

  /// Tests and sign-out.
  static void reset() {
    current = fallback;
    _readAt = null;
  }
}

/// The engine's 422 codes (and the client check's) in words; null for any other code.
String? examPolicyCodeText(String code, {ExamPolicy? policy, int? limit}) {
  final p = policy ?? ExamPolicy.current;
  return switch (code) {
    'policy_duration' => t('أطول مدة مسموح بها على المنصة ${limit ?? p.maxDurationMinutes} دقيقة',
        'The longest duration allowed on the platform is ${limit ?? p.maxDurationMinutes} minutes'),
    'policy_attempts' => t('أقصى عدد محاولات مسموح به على المنصة ${limit ?? p.attemptsCap}',
        'At most ${limit ?? p.attemptsCap} attempts are allowed on the platform'),
    'policy_unlimited_attempts' => t('المحاولات غير المحدودة غير مسموحة على المنصة', 'Unlimited attempts are not allowed on the platform'),
    'policy_answer_key' => t('إظهار الإجابات النموذجية للطلاب غير مسموح على المنصة',
        'Showing the answer key to students is not allowed on the platform'),
    'policy_questions' => t('أقصى عدد أسئلة مسموح به على المنصة ${limit ?? p.maxQuestions}',
        'At most ${limit ?? p.maxQuestions} questions are allowed on the platform'),
    _ => null,
  };
}

String policyResultsWhenLabel(String v) => switch (v) {
      'after_submit' => t('بعد التسليم مباشرة', 'Right after submitting'),
      'when_published' => t('عندما ينشرها المعلم', 'When the teacher publishes them'),
      _ => t('لا تظهر للطالب', 'Never shown to the student'),
    };

String resultsViewLabel(String v) => switch (v) {
      'answers' => t('الدرجة وإجاباته', 'The score and their answers'),
      'answers_key' => t('الدرجة وإجاباته والإجابات النموذجية', 'The score, their answers and the answer key'),
      _ => t('الدرجة فقط', 'The score only'),
    };
