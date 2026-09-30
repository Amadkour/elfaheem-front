import 'package:flutter_education_app/core/api_client.dart';

import '../../../shared/models/exam_model.dart';

// ── Student-specific response shapes ─────────────────────────────────────────

/// Returned by GET /api/v1/student/exams and /courses/{id}/exams/student
class StudentExamListItem {
  final int id;
  final String name;
  final String? description;
  final int courseId;
  final String? courseName;
  /// Session this exam is attached to (null = course-level exam).
  final int? sessionId;
  final DateTime? startDate;
  final int? duration;
  final double? totalMarks;
  final double? passingScore;
  final bool isSubmitted;
  final int answeredCount;
  final int questionCount;
  final int? maxSubmissions;
  final int submissionCount;
  final int? remainingSubmissions;  // ← NEW: server-computed
  final DateTime? endDate;
  final bool enablePasscode;
  final String? passcode;
  // Best score across all submissions (null if not submitted)
  final double? marksObtained;
  final double? percentage;
  final bool? passed;

  const StudentExamListItem({
    required this.id,
    required this.name,
    this.description,
    required this.courseId,
    this.courseName,
    this.sessionId,
    this.startDate,
    this.duration,
    this.totalMarks,
    this.passingScore,
    required this.isSubmitted,
    required this.answeredCount,
    required this.questionCount,
    this.maxSubmissions,
    this.submissionCount = 0,
    this.remainingSubmissions,
    this.endDate,
    this.marksObtained,
    this.percentage,
    this.passed, required this.enablePasscode, this.passcode,
  });

  factory StudentExamListItem.fromJson(Map<String, dynamic> j) {
    return StudentExamListItem(
      id: j['id'] as int,
      name: j['name'] as String,
      description: j['description'] as String?,
      courseId: j['course_id'] as int,
      courseName: j['course_name'] as String?,
      sessionId: j['session_id'] as int?,
      startDate: j['start_date'] != null
          ? DateTime.tryParse(j['start_date'].toString())
          : null,
      duration: j['duration'] as int?,
      totalMarks: (j['total_marks'] as num?)?.toDouble(),
      passingScore: (j['passing_score'] as num?)?.toDouble(),
      isSubmitted: j['is_submitted'] as bool? ?? false,
      answeredCount: j['answered_count'] as int? ?? 0,
      questionCount: j['question_count'] as int? ?? 0,
      maxSubmissions: j['max_submissions'] as int?,
      submissionCount: j['submission_count'] as int? ?? 0,
      remainingSubmissions: j['remaining_submissions'] as int?,
      endDate: j['end_date'] != null
          ? DateTime.tryParse(j['end_date'].toString())
          : null,
      marksObtained: (j['marks_obtained'] as num?)?.toDouble(),
      percentage: (j['percentage'] as num?)?.toDouble(),
      passed: j['passed'] as bool?,
      enablePasscode: j['enable_passcode'] as bool? ?? false,
      passcode: j['passcode'] as String?,
    );
  }

  ExamStatus get status {
    if (isSubmitted) return ExamStatus.ended;
    if (startDate == null) return ExamStatus.active;
    final now = DateTime.now();
    if (startDate!.isAfter(now)) return ExamStatus.scheduled;
    final end = startDate!.add(Duration(minutes: duration ?? 60));
    if (now.isAfter(end)) return ExamStatus.ended;
    return ExamStatus.active;
  }

  bool get isDeadlineFrozen =>
      endDate != null && DateTime.now().isAfter(endDate!);

  bool get isSubmissionsFrozen =>
      maxSubmissions != null &&
          maxSubmissions! > 0 &&
          submissionCount >= maxSubmissions!;

  bool get isFrozen => isDeadlineFrozen || isSubmissionsFrozen;

  /// Computed locally as fallback when server doesn't return remainingSubmissions
  int? get computedRemainingSubmissions {
    if (remainingSubmissions != null) return remainingSubmissions;
    if (maxSubmissions == null || maxSubmissions! <= 0) return null;
    return (maxSubmissions! - submissionCount).clamp(0, maxSubmissions!);
  }

  /// Whether the student can attempt again (has remaining submissions)
  bool get canRetry =>
      !isDeadlineFrozen &&
          (maxSubmissions == null ||
              maxSubmissions! <= 0 ||
              submissionCount < maxSubmissions!);
}

/// Returned by GET /api/v1/exams/{id}/results — BEST submission
class StudentMyResult {
  final int examId;
  final double marksObtained;
  final double totalMarks;
  final double percentage;
  final bool passed;

  final int answeredCount;
  final int questionCount;
  final int submissionCount;
  final int? remainingSubmissions;
  final double? bestPercentage;    // ← NEW: best across all rounds
  final double? currentPercentage; // ← NEW: current round's score

  const StudentMyResult({
    required this.examId,
    required this.marksObtained,
    required this.totalMarks,
    required this.percentage,
    required this.passed,
    required this.answeredCount,
    required this.questionCount,
    this.submissionCount = 0,
    this.remainingSubmissions,
    this.bestPercentage,
    this.currentPercentage,
  });

  factory StudentMyResult.fromJson(Map<String, dynamic> j, int examId) =>
      StudentMyResult(
        examId: examId,
        marksObtained: (j['marks_obtained'] as num?)?.toDouble() ?? 0,
        totalMarks: (j['total_marks'] as num?)?.toDouble() ?? 0,
        percentage: (j['percentage'] as num?)?.toDouble() ?? 0,
        passed: j['passed'] as bool? ?? false,
        answeredCount: j['answered_count'] as int? ?? 0,
        questionCount: j['question_count'] as int? ?? 0,
        submissionCount: j['submission_count'] as int? ?? 0,
        remainingSubmissions: j['remaining_submissions'] as int?,
        bestPercentage: (j['best_percentage'] as num?)?.toDouble(),
        currentPercentage: (j['current_percentage'] as num?)?.toDouble(),
      );
}

// ── API class ─────────────────────────────────────────────────────────────────

class StudentExamApi {
  final ApiClient _api;
  StudentExamApi({ApiClient? api}) : _api = api ?? ApiClient();

  Future<List<StudentExamListItem>> fetchMyExams() async {
    final data = await _api.get('/api/v1/student/exams');
    if (data is! List) return [];
    return data.cast<Map<String, dynamic>>().map(StudentExamListItem.fromJson).toList();
  }

  Future<List<Map<String, dynamic>>> fetchActiveExamsForCourse(int courseId) async {
    final data = await _api.get('/api/v1/courses/$courseId/exams/active');
    if (data is! List) return [];
    return data.cast<Map<String, dynamic>>();
  }

  Future<List<Question>> fetchQuestions(int examId) async {
    final data = await _api.get('/api/v1/exams/$examId/questions');
    if (data is! List) return [];
    return data.cast<Map<String, dynamic>>().map(Question.fromJson).toList();
  }

  Future<Map<String, dynamic>> submitAnswer({
    required int examId,
    required int questionId,
    required String answer,
  }) async {
    final data = await _api.post('/api/v1/exam-answers', body: {
      'exam_id': examId,
      'question_id': questionId,
      'answer': answer,
    });
    return data as Map<String, dynamic>;
  }

  Future<StudentMyResult> fetchMyResult(int examId) async {
    final data = await _api.get('/api/v1/exams/$examId/results');
    return StudentMyResult.fromJson(data as Map<String, dynamic>, examId);
  }

  Future<List<StudentExamListItem>> fetchCourseExams(String courseId) async {
    final data = await _api.get('/api/v1/courses/$courseId/exams/student');
    if (data is! List) return [];
    return data.cast<Map<String, dynamic>>().map(StudentExamListItem.fromJson).toList();
  }
}