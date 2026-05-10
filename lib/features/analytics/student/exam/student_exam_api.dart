// features/student/exam/student_exam_api.dart
//
// Endpoints consumed:
//   GET  /api/v1/student/exams                         → all exams across enrolled courses
//   GET  /api/v1/courses/{id}/exams/active             → live-screen poll (unanswered only)
//   GET  /api/v1/exams/{id}/questions                  → questions for one exam
//   POST /api/v1/exam-answers                          → submit one answer  (upsert)
//   GET  /api/v1/exams/{id}/results                    → student's own result

import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/analytics/teacher/exam/exam_model.dart';
// ── Student-specific response shapes ─────────────────────────────────────────

/// Returned by GET /api/v1/student/exams
class StudentExamListItem {
  final int id;
  final String name;
  final String? description;
  final int courseId;
  final String? courseName;
  final DateTime? startDate;
  final int? duration;
  final double? totalMarks;
  final double? passingScore;
  final bool isSubmitted;
  final int answeredCount;
  final int questionCount;
  final int? maxSubmissions;
  final int submissionCount;
  final DateTime? endDate;

  // score fields (null if not submitted)
  final double? marksObtained;
  final double? percentage;
  final bool? passed;

  const StudentExamListItem({
    required this.id,
    required this.name,
    this.description,
    required this.courseId,
    this.courseName,
    this.startDate,
    this.duration,
    this.totalMarks,
    this.passingScore,
    required this.isSubmitted,
    required this.answeredCount,
    required this.questionCount,
    this.maxSubmissions,
    this.submissionCount = 0,
    this.endDate,
    this.marksObtained,
    this.percentage,
    this.passed,
  });

  factory StudentExamListItem.fromJson(Map<String, dynamic> j) {
    print(j);
    print(j.keys);
    return StudentExamListItem(
        id: j['id'] as int,
        name: j['name'] as String,
        description: j['description'] as String?,
        courseId: j['course_id'] as int,
        courseName: j['course_name'] as String?,
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
        endDate: j['end_date'] != null
            ? DateTime.tryParse(j['end_date'].toString())
            : null,
        marksObtained: (j['marks_obtained'] as num?)?.toDouble(),
        percentage: (j['percentage'] as num?)?.toDouble(),
        passed: j['passed'] as bool?,
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

  /// True when the deadline (end_date) has passed.
  bool get isDeadlineFrozen =>
      endDate != null && DateTime.now().isAfter(endDate!);

  /// True when the student has used all allowed submission attempts.
  bool get isSubmissionsFrozen =>
      maxSubmissions != null &&
          maxSubmissions! > 0 &&
          submissionCount >= maxSubmissions!;

  /// True when student cannot submit any more answers.
  bool get isFrozen => isDeadlineFrozen || isSubmissionsFrozen;

  /// How many more times the student can re-submit (null = unlimited).
  int? get remainingSubmissions {
    if (maxSubmissions == null || maxSubmissions! <= 0) return null;
    return (maxSubmissions! - submissionCount).clamp(0, maxSubmissions!);
  }
}

/// Returned by GET /api/v1/student/exams/{id}/results
class StudentMyResult {
  final int examId;
  final double marksObtained;
  final double totalMarks;
  final double percentage;
  final bool passed;
  final int answeredCount;
  final int questionCount;

  const StudentMyResult({
    required this.examId,
    required this.marksObtained,
    required this.totalMarks,
    required this.percentage,
    required this.passed,
    required this.answeredCount,
    required this.questionCount,
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
      );
}

// ── API class ─────────────────────────────────────────────────────────────────

class StudentExamApi {
  final ApiClient _api;
  StudentExamApi({ApiClient? api}) : _api = api ?? ApiClient();

  /// GET /api/v1/student/exams
  Future<List<StudentExamListItem>> fetchMyExams() async {
    final data = await _api.get('/api/v1/student/exams');
    if (data is! List) return [];
    return (data)
        .cast<Map<String, dynamic>>()
        .map(StudentExamListItem.fromJson)
        .toList();
  }

  /// GET /api/v1/courses/{courseId}/exams/active
  /// Returns exams that have full question lists embedded.
  Future<List<Map<String, dynamic>>> fetchActiveExamsForCourse(
      int courseId) async {
    final data = await _api.get('/api/v1/courses/$courseId/exams/active');
    if (data is! List) return [];
    return (data).cast<Map<String, dynamic>>();
  }

  /// GET /api/v1/exams/{examId}/questions
  Future<List<Question>> fetchQuestions(int examId) async {
    final data = await _api.get('/api/v1/exams/$examId/questions');
    if (data is! List) return [];
    return (data)
        .cast<Map<String, dynamic>>()
        .map(Question.fromJson)
        .toList();
  }

  /// POST /api/v1/exam-answers  (upsert — one call per question)
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

  /// GET /api/v1/exams/{examId}/results
  Future<StudentMyResult> fetchMyResult(int examId) async {
    final data = await _api.get('/api/v1/exams/$examId/results');
    return StudentMyResult.fromJson(data as Map<String, dynamic>, examId);
  }

  /// GET /api/v1/courses/{courseId}/exams/student
  /// Exams for a specific course (used in course profile widget).
  Future<List<StudentExamListItem>> fetchCourseExams(String courseId) async {
    final data = await _api.get('/api/v1/courses/$courseId/exams/student');
    if (data is! List) return [];
    return (data)
        .cast<Map<String, dynamic>>()
        .map(StudentExamListItem.fromJson)
        .toList();
  }
}