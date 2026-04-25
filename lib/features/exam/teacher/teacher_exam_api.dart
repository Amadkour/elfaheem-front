// features/teacher/exam/teacher_exam_api.dart
// Server endpoints (from exams_provider.dart comments & schemas.py):
//   GET  /api/v1/exams?course_id={id}          → list exams for course
//   POST /api/v1/exams                          → create exam   (ExamCreate)
//   POST /api/v1/exams/{id}/publish             → publish exam
//   POST /api/v1/exams/{id}/unpublish           → unpublish exam
//   DELETE /api/v1/exams/{id}                   → delete exam
//   GET  /api/v1/exams/{id}/questions           → questions (teacher view, includes correct_answer)
//   POST /api/v1/questions                      → add question  (QuestionCreate)
//   DELETE /api/v1/questions/{id}               → delete question
//   GET  /api/v1/exams/{id}/results             → student results for this exam

import 'package:flutter_education_app/core/api_client.dart';
import 'exam_model.dart';

class TeacherExamApi {
  final ApiClient _api;
  TeacherExamApi({ApiClient? api}) : _api = api ?? ApiClient();

  // ── Exams ───────────────────────────────────────────────────────────────────

  /// GET /api/v1/exams?course_id={courseId}
  Future<List<ExamModel>> fetchCourseExams(int courseId) async {
    final data = await _api.get(
      '/api/v1/exams',
      queryParams: {'course_id': courseId},
    );
    if (data is! List) return [];
    return (data as List)
        .cast<Map<String, dynamic>>()
        .map(ExamModel.fromJson)
        .toList();
  }

  /// POST /api/v1/exams  — body: ExamCreate schema
  Future<ExamModel> createExam({
    required String name,
    String? description,
    required int courseId,
    DateTime? startDate,
    int? duration,
    double? passingScore,
    double? totalMarks,
    String? passcode,
  }) async {
    final data = await _api.post('/api/v1/exams', body: {
      'name': name,
      'course_id': courseId,
      if (description != null) 'description': description,
      if (startDate != null) 'start_date': startDate.toUtc().toIso8601String(),
      if (duration != null) 'duration': duration,
      if (passingScore != null) 'passing_score': passingScore,
      if (totalMarks != null) 'total_marks': totalMarks,
      if (passcode != null) 'passcode': passcode,
    });
    return ExamModel.fromJson(data as Map<String, dynamic>);
  }

  /// POST /api/v1/exams/{id}/publish
  Future<ExamModel> publishExam(int examId) async {
    final data = await _api.post('/api/v1/exams/$examId/publish');
    return ExamModel.fromJson(data as Map<String, dynamic>);
  }

  /// POST /api/v1/exams/{id}/unpublish
  Future<ExamModel> unpublishExam(int examId) async {
    final data = await _api.post('/api/v1/exams/$examId/unpublish');
    return ExamModel.fromJson(data as Map<String, dynamic>);
  }

  /// DELETE /api/v1/exams/{id}
  Future<void> deleteExam(int examId) async {
    await _api.delete('/api/v1/exams/$examId');
  }

  // ── Questions ───────────────────────────────────────────────────────────────

  /// GET /api/v1/exams/{examId}/questions
  Future<List<Question>> fetchQuestions(int examId) async {
    final data = await _api.get('/api/v1/exams/$examId/questions');
    if (data is! List) return [];
    return (data as List)
        .cast<Map<String, dynamic>>()
        .map(Question.fromJson)
        .toList();
  }

  /// POST /api/v1/questions  — body: QuestionCreate schema
  Future<Question> addQuestion({
    required int examId,
    required String title,
    required List<String> options,
    String? correctAnswer,
    double marks = 1.0,
    int order = 0,
  }) async {
    final data = await _api.post('/api/v1/questions', body: {
      'exam_id': examId,
      'title': title,
      'marks': marks,
      'order': order,
      if (options.isNotEmpty) 'options': options,
      if (correctAnswer != null) 'correct_answer': correctAnswer,
    });
    return Question.fromJson(data as Map<String, dynamic>);
  }

  /// DELETE /api/v1/questions/{id}
  Future<void> deleteQuestion(int questionId) async {
    await _api.delete('/api/v1/questions/$questionId');
  }

  // ── Results ─────────────────────────────────────────────────────────────────

  /// GET /api/v1/exams/{examId}/results
  /// Returns list of StudentExamResult (teacher view with all students).
  Future<List<StudentExamResult>> fetchExamResults(int examId) async {
    final data = await _api.get('/api/v1/exams/$examId/results');
    if (data is! List) return [];
    return (data as List)
        .cast<Map<String, dynamic>>()
        .map(StudentExamResult.fromJson)
        .toList();
  }
}
