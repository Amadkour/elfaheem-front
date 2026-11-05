// courses/details/session_exam_gate.dart
//
// The exam(s) a teacher attached to ONE session. A published exam attached to
// a session must be PASSED before the sessions that come after it unlock.
//
// Parsed from the same JSON item the sessions list already returns
// (GET /api/v1/courses/{id}/sessions → items[i]["exams"]), so SessionModel
// itself does not need to change.

import '../../../shared/exam_engine/engine_exams_section.dart' show engineExamStartable;

/// Where tapping an engine gate goes: straight into the engine exam, or to the course's Exams tab (a passcode to ask
/// for, a paper / offline exam, not startable yet, or the exam is not in the student's engine list), which explains why.
enum EngineGateTarget { engineExam, examsTab }

/// [exam] is the gate's entry in the student's engine list (`GET /exam/student/exams`), null when it is not there.
EngineGateTarget engineGateTarget(Map<String, dynamic>? exam) {
  if (exam == null || exam['paper_only'] == true || exam['offline'] == true) return EngineGateTarget.examsTab;
  final open = exam['open_attempt_id'] != null;
  if (!engineExamStartable(exam) && !open) return EngineGateTarget.examsTab;
  if (exam['has_passcode'] == true && !open) return EngineGateTarget.examsTab;
  return EngineGateTarget.engineExam;
}

class SessionExamInfo {
  final int id;
  final String name;

  /// Required percentage to pass (0 when the teacher set none).
  final double passingScore;
  final int? duration; // minutes
  final int questionCount;
  final int submissionCount;
  final int? maxSubmissions;
  final int? remainingSubmissions;
  final double? bestPercentage;
  final bool attempted;
  final bool passed;
  final DateTime? startDate;
  final DateTime? endDate;

  /// An Exam Engine exam (D-197): its attempts are the engine's, so the tile opens the engine exam, not the legacy one.
  final bool engine;
  final int? engineExamId;

  /// The id to open in the engine (`engine_exam_id`, else the entry's own id).
  int get engineId => engineExamId ?? id;

  const SessionExamInfo({
    required this.id,
    required this.name,
    required this.passingScore,
    this.duration,
    required this.questionCount,
    required this.submissionCount,
    this.maxSubmissions,
    this.remainingSubmissions,
    this.bestPercentage,
    required this.attempted,
    required this.passed,
    this.startDate,
    this.endDate,
    this.engine = false,
    this.engineExamId,
  });

  factory SessionExamInfo.fromJson(Map<String, dynamic> j) => SessionExamInfo(
        id: (j['id'] as num?)?.toInt() ?? (j['engine_exam_id'] as num?)?.toInt() ?? 0,
        name: (j['name'] as String?) ?? '',
        passingScore: (j['passing_score'] as num?)?.toDouble() ?? 0,
        duration: (j['duration'] as num?)?.toInt(),
        questionCount: (j['question_count'] as num?)?.toInt() ?? 0,
        submissionCount: (j['submission_count'] as num?)?.toInt() ?? 0,
        maxSubmissions: (j['max_submissions'] as num?)?.toInt(),
        remainingSubmissions: (j['remaining_submissions'] as num?)?.toInt(),
        bestPercentage: (j['best_percentage'] as num?)?.toDouble(),
        attempted: j['attempted'] as bool? ?? false,
        passed: j['passed'] as bool? ?? false,
        startDate: j['start_date'] != null
            ? DateTime.tryParse(j['start_date'] as String)
            : null,
        endDate: j['end_date'] != null
            ? DateTime.tryParse(j['end_date'] as String)
            : null,
        engine: j['engine'] == true,
        engineExamId: (j['engine_exam_id'] as num?)?.toInt(),
      );

  /// 0 attempts allowed = unlimited (engine exams): never exhausted.
  bool get unlimitedAttempts => maxSubmissions == 0;

  bool get attemptsExhausted =>
      !unlimitedAttempts && remainingSubmissions != null && remainingSubmissions! <= 0;
  bool get startsLater =>
      startDate != null && startDate!.isAfter(DateTime.now());
  bool get isClosed => endDate != null && endDate!.isBefore(DateTime.now());

  /// Can the student take (or retake) it right now?
  bool get canStart =>
      !passed && !attemptsExhausted && !isClosed && !startsLater;
}

class SessionExamGate {
  final List<SessionExamInfo> exams;

  const SessionExamGate(this.exams);

  static const empty = SessionExamGate([]);

  /// [raw] is the `exams` value of one session item (may be null / missing).
  factory SessionExamGate.fromJson(Object? raw) {
    if (raw is! List) return empty;
    return SessionExamGate(
      raw
          .whereType<Map<String, dynamic>>()
          .map(SessionExamInfo.fromJson)
          .toList(),
    );
  }

  bool get isEmpty => exams.isEmpty;
  bool get allPassed => exams.every((e) => e.passed);

  /// First exam the student still has to pass (null when all are passed).
  SessionExamInfo? get firstPending {
    for (final e in exams) {
      if (!e.passed) return e;
    }
    return null;
  }
}
