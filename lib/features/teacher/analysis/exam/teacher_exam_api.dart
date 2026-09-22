import 'package:flutter_education_app/core/api_client.dart';
import '../../../shared/models/exam_model.dart';

class TeacherExamApi {
  final ApiClient _api;

  TeacherExamApi({ApiClient? api}) : _api = api ?? ApiClient();

  // ── Exams ───────────────────────────────────────────────────────────────────

  /// GET /api/v1/courses/{courseId}/exams/all
  Future<List<ExamModel>> fetchCourseExams(int courseId) async {
    final data = await _api.get('/api/v1/courses/$courseId/exams/all');
    if (data is! List) return [];
    return (data).cast<Map<String, dynamic>>().map(ExamModel.fromJson).toList();
  }

  /// POST /api/v1/exams
  Future<ExamModel> createExam({
    required String name,
    String? description,
    required int courseId,
    int? sessionId,
    DateTime? startDate,
    DateTime? endDate,
    int? duration,
    int? maxSubmissions,
    double? passingScore,
    double? totalMarks,
    String? passcode,
  }) async {
    final data = await _api.post('/api/v1/exams', body: {
      'name': name,
      'course_id': courseId,
      'session_id': ?sessionId,
      'description': ?description,
      if (startDate != null) 'start_date': startDate.toUtc().toIso8601String(),
      if (endDate != null) 'end_date': endDate.toUtc().toIso8601String(),
      'duration': ?duration,
      'max_submissions': ?maxSubmissions,
      'passing_score': ?passingScore,
      'total_marks': ?totalMarks,
      'passcode': ?passcode,
    });
    return ExamModel.fromJson(data as Map<String, dynamic>);
  }

  /// PUT /api/v1/exams/{id}/session — attach the exam to a session
  /// ([sessionId] = null detaches it). Students must pass an attached,
  /// published exam before the sessions after it unlock.
  Future<void> assignExamToSession(int examId, int? sessionId) async {
    await _api.put('/api/v1/exams/$examId/session',
        body: {'session_id': sessionId});
  }

  /// GET /api/v1/courses/{courseId}/sessions — every session (all pages),
  /// sorted by order, for the "attach to session" picker.
  Future<List<SessionOption>> fetchCourseSessions(int courseId) async {
    const pageSize = 100;
    final all = <SessionOption>[];
    var skip = 0;
    while (true) {
      final data = await _api.get(
        '/api/v1/courses/$courseId/sessions',
        queryParams: {'skip': skip, 'limit': pageSize},
      );
      if (data is! Map || data['items'] is! List) break;
      final page = (data['items'] as List)
          .whereType<Map<String, dynamic>>()
          .map(SessionOption.fromJson)
          .toList();
      all.addAll(page);
      if (page.length < pageSize) break;
      skip += page.length;
    }
    all.sort((a, b) => a.order.compareTo(b.order));
    return all;
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
    return (data).cast<Map<String, dynamic>>().map(Question.fromJson).toList();
  }

  /// POST /api/v1/questions — QuestionCreate schema
  Future<Question> addQuestion({
    required int examId,
    required String title,
    required List<String> options,
    String? correctAnswer,
    required double marks,
    required int order,
  }) async {
    final data = await _api.post('/api/v1/questions', body: {
      'exam_id': examId,
      'title': title,
      'marks': marks,
      'order': order,
      if (options.isNotEmpty) 'options': options,
      if (correctAnswer != null && correctAnswer.isNotEmpty)
        'correct_answer': correctAnswer,
    });
    return Question.fromJson(data as Map<String, dynamic>);
  }

  /// PUT /api/v1/questions/{questionId} — QuestionCreate schema (same body)
  Future<Question> updateQuestion({
    required int questionId,
    required int examId,
    required String title,
    required List<String> options,
    String? correctAnswer,
    required double marks,
    required int order,
  }) async {
    final data = await _api.put('/api/v1/questions/$questionId', body: {
      'exam_id': examId,
      'title': title,
      'marks': marks,
      'order': order,
      if (options.isNotEmpty) 'options': options,
      if (correctAnswer != null && correctAnswer.isNotEmpty)
        'correct_answer': correctAnswer,
    });
    return Question.fromJson(data as Map<String, dynamic>);
  }

  /// DELETE /api/v1/questions/{id}
  Future<void> deleteQuestion(int questionId) async {
    await _api.delete('/api/v1/questions/$questionId');
  }

  // ── Results ─────────────────────────────────────────────────────────────────

  /// GET /api/v1/exams/{examId}/attendance-results
  Future<List<StudentExamResult>> fetchExamResults(int examId) async {
    final data = await _api.get('/api/v1/exams/$examId/attendance-results');
    if (data is! List) return [];
    return (data)
        .cast<Map<String, dynamic>>()
        .map(StudentExamResult.fromJson)
        .toList();
  }
}
