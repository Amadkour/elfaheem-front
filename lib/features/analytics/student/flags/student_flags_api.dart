// features/analytics/student/flags/student_flags_api.dart
//
// Review flags (bookmarks taken during an exam) and read flags (wrong answers).
//   GET    /api/v1/student/flags/settings
//   GET    /api/v1/student/review-flags?course_id=&exam_id=
//   POST   /api/v1/student/review-flags/{questionId}
//   DELETE /api/v1/student/review-flags/{questionId}
//   GET    /api/v1/student/read-flags?course_id=
//   POST   /api/v1/student/exams/{examId}/sync-read-flags
import 'package:flutter_education_app/core/api_client.dart';

/// What the admin allows. Defaults = everything off until the server answers.
class FlagSettings {
  final bool allowReview;
  final bool allowRead;
  final int limitExam; // 0 = unlimited
  final int limitCourse; // 0 = unlimited

  const FlagSettings({
    this.allowReview = false,
    this.allowRead = false,
    this.limitExam = 0,
    this.limitCourse = 0,
  });

  factory FlagSettings.fromJson(Map<String, dynamic> j) => FlagSettings(
    allowReview: j['allow_review_flags'] as bool? ?? false,
    allowRead: j['allow_read_flags'] as bool? ?? false,
    limitExam: (j['review_limit_per_exam'] as num?)?.toInt() ?? 0,
    limitCourse: (j['review_limit_per_course'] as num?)?.toInt() ?? 0,
  );
}

/// Active review flags used vs. the admin's limits (0 limit = unlimited).
class FlagUsage {
  final int? examUsed;
  final int examLimit;
  final int? courseUsed;
  final int courseLimit;

  const FlagUsage({
    this.examUsed,
    this.examLimit = 0,
    this.courseUsed,
    this.courseLimit = 0,
  });

  factory FlagUsage.fromJson(Map<String, dynamic> j) => FlagUsage(
    examUsed: (j['exam_used'] as num?)?.toInt(),
    examLimit: (j['exam_limit'] as num?)?.toInt() ?? 0,
    courseUsed: (j['course_used'] as num?)?.toInt(),
    courseLimit: (j['course_limit'] as num?)?.toInt() ?? 0,
  );
}

/// One question in the review bank or the read-flag bank.
class FlaggedQuestion {
  final int questionId;
  final int examId;
  final String examName;
  final int courseId;
  final String title;
  final List<String> options;
  final double marks;
  final String? correctAnswer; // null until the exam has been submitted
  // read flags only
  final int wrongCount;
  final double score;
  final String? lastWrongAnswer;

  const FlaggedQuestion({
    required this.questionId,
    required this.examId,
    required this.examName,
    required this.courseId,
    required this.title,
    required this.options,
    required this.marks,
    this.correctAnswer,
    this.wrongCount = 0,
    this.score = 0,
    this.lastWrongAnswer,
  });

  factory FlaggedQuestion.fromJson(Map<String, dynamic> j) => FlaggedQuestion(
    questionId: (j['question_id'] as num).toInt(),
    examId: (j['exam_id'] as num?)?.toInt() ?? 0,
    examName: j['exam_name'] as String? ?? '',
    courseId: (j['course_id'] as num?)?.toInt() ?? 0,
    title: j['title'] as String? ?? '',
    options: (j['options'] as List? ?? []).map((o) => o.toString()).toList(),
    marks: (j['marks'] as num?)?.toDouble() ?? 0,
    correctAnswer: j['correct_answer'] as String?,
    wrongCount: (j['wrong_count'] as num?)?.toInt() ?? 0,
    score: (j['score'] as num?)?.toDouble() ?? 0,
    lastWrongAnswer: j['last_wrong_answer'] as String?,
  );
}

class ReviewBank {
  final List<FlaggedQuestion> items;
  final FlagSettings settings;
  final FlagUsage? usage;
  const ReviewBank(this.items, this.settings, this.usage);
}

class ReadBank {
  final List<FlaggedQuestion> items;
  final FlagSettings settings;
  final double totalScore;
  final int totalWrong;
  const ReadBank(this.items, this.settings, this.totalScore, this.totalWrong);
}

class StudentFlagsApi {
  final ApiClient _api;
  StudentFlagsApi({ApiClient? api}) : _api = api ?? ApiClient();

  Future<FlagSettings> fetchSettings() async {
    final d = await _api.get('/api/v1/student/flags/settings');
    return FlagSettings.fromJson(d as Map<String, dynamic>);
  }

  Future<ReviewBank> fetchReview({int? courseId, int? examId}) async {
    final d = await _api.get('/api/v1/student/review-flags', queryParams: {
      if (courseId != null) 'course_id': courseId,
      if (examId != null) 'exam_id': examId,
    }) as Map<String, dynamic>;
    return ReviewBank(
      (d['items'] as List? ?? [])
          .cast<Map<String, dynamic>>()
          .map(FlaggedQuestion.fromJson)
          .toList(),
      FlagSettings.fromJson((d['settings'] as Map?)?.cast<String, dynamic>() ?? {}),
      d['usage'] is Map
          ? FlagUsage.fromJson((d['usage'] as Map).cast<String, dynamic>())
          : null,
    );
  }

  Future<FlagUsage> addReview(int questionId) async {
    final d = await _api.post('/api/v1/student/review-flags/$questionId')
    as Map<String, dynamic>;
    return FlagUsage.fromJson((d['usage'] as Map).cast<String, dynamic>());
  }

  Future<FlagUsage> removeReview(int questionId) async {
    final d = await _api.delete('/api/v1/student/review-flags/$questionId')
    as Map<String, dynamic>;
    return FlagUsage.fromJson((d['usage'] as Map).cast<String, dynamic>());
  }

  Future<ReadBank> fetchRead({int? courseId}) async {
    final d = await _api.get('/api/v1/student/read-flags', queryParams: {
      if (courseId != null) 'course_id': courseId,
    }) as Map<String, dynamic>;
    return ReadBank(
      (d['items'] as List? ?? [])
          .cast<Map<String, dynamic>>()
          .map(FlaggedQuestion.fromJson)
          .toList(),
      FlagSettings.fromJson((d['settings'] as Map?)?.cast<String, dynamic>() ?? {}),
      (d['total_score'] as num?)?.toDouble() ?? 0,
      (d['total_wrong'] as num?)?.toInt() ?? 0,
    );
  }

  /// Right after an attempt is submitted: wrong answers → read flags,
  /// correct answers clear their read flag. Idempotent.
  Future<void> syncReadFlags(int examId) async {
    await _api.post('/api/v1/student/exams/$examId/sync-read-flags');
  }
}
