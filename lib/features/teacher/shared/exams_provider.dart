/// shared/exams_provider.dart
/// Teacher CRUD + student submit/results.
///
/// API:
///   POST /api/v1/exams                    create exam (teacher)
///   POST /api/v1/questions                add question (teacher)
///   GET  /api/v1/exams/{id}/questions     list questions
///   POST /api/v1/exam-answers             submit answer (student)
///   GET  /api/v1/exams/{id}/results       results (student own / teacher all)
import '../../../core/api_client.dart';
import '../../../core/base_provider.dart';
import 'live_models.dart';

class ExamsProvider extends BaseProvider {
  final ApiClient _api;

  ExamsProvider({ApiClient? api}) : _api = api ?? ApiClient();

  List<ExamModel> _exams = [];
  List<ExamResult> _results = [];
  ExamModel? _current;

  List<QuestionModel> questions = [];

  List<ExamModel> get exams => List.unmodifiable(_exams);

  List<ExamResult> get results => List.unmodifiable(_results);

  ExamModel? get current => _current;

  // ── Teacher: Create exam ─────────────────────────────────────────────────
  Future<ExamModel?> createExam({
    required int courseId,
    required String name,
    String? description,
    int? duration,
    double? passingScore,
    double? totalMarks,
    String? passcode,
  }) async {
    final r = await run(() => _api.post('/api/v1/exams', body: {
          'course_id': courseId,
          'name': name,
          if (description != null) 'description': description,
          if (duration != null) 'duration': duration,
          if (passingScore != null) 'passing_score': passingScore,
          if (totalMarks != null) 'total_marks': totalMarks,
          if (passcode != null) 'passcode': passcode,
        }));
    if (r is Map<String, dynamic>) {
      _current = ExamModel.fromJson(r);
      _exams = [..._exams, _current!];
      notifyListeners();
      return _current;
    }
    return null;
  }

  // ── Teacher: Add question ────────────────────────────────────────────────
  Future<QuestionModel?> addQuestion({
    required int examId,
    required String title,
    List<String>? options,
    String? correctAnswer,
    double marks = 1,
    int order = 0,
  }) async {
    final r = await run(() => _api.post('/api/v1/questions', body: {
          'exam_id': examId,
          'title': title,
          'marks': marks,
          'order': order,
          if (options != null) 'options': options,
          if (correctAnswer != null) 'correct_answer': correctAnswer,
        }));
    if (r is Map<String, dynamic>) {
      final q = QuestionModel.fromJson(r);
      // Merge into current exam
      if (_current != null && _current!.id == examId) {
        final newList = [..._current!.questions, q]
          ..sort((a, b) => a.order.compareTo(b.order));
        _current = ExamModel.fromJson({
          ..._toJson(_current!),
          'questions': newList.map((x) => _questionJson(x)).toList(),
        });
      }
      notifyListeners();
      return q;
    }
    return null;
  }

  bool isLoadingExam = false;

  // ── Load questions for an exam ───────────────────────────────────────────
  Future<void> fetchQuestions(int examId) async {
    isLoadingExam = true;
    notifyListeners();
    final r = await run(() => _api.get('/api/v1/exams/$examId/questions'));
    if (r is List) {
      questions = r
          .map((e) => QuestionModel.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.order.compareTo(b.order));
    }
    isLoadingExam = false;
    notifyListeners();
  }

  /// Fetch exams that are published and not yet shown during this live session.
  Future<List<ExamModel>> fetchActiveExams(int courseId,
      {required Set<int> alreadyShownIds}) async {
    // Uses the questions endpoint per exam — we fetch course exams first
    // then pull questions per exam that hasn't been shown yet.
    // Backend should expose GET /api/v1/courses/{id}/exams — until then
    // we rely on the caller passing exam ids via previous polling.
    // Return empty list if no API; override in subclass or route if available.
    return [];
  }

  // ── Student: Submit answers ──────────────────────────────────────────────
  Future<bool> submitAllAnswers(int examId, Map<int, String> answers) async {
    bool allOk = true;
    for (final entry in answers.entries) {
      final r = await run(() => _api.post('/api/v1/exam-answers', body: {
            'exam_id': examId,
            'question_id': entry.key,
            'answer': entry.value,
          }));
      if (r == null) allOk = false;
    }
    return allOk;
  }

  Future<bool> submitSingle({
    required int examId,
    required int questionId,
    required String answer,
    int? rate,
  }) async {
    final r = await run(() => _api.post('/api/v1/exam-answers', body: {
          'exam_id': examId,
          'question_id': questionId,
          'answer': answer,
          if (rate != null) 'rate': rate,
        }));
    return r != null;
  }

  // ── Results ──────────────────────────────────────────────────────────────
  Future<ExamResult?> fetchResults(int examId) async {
    final r = await run(() => _api.get('/api/v1/exams/$examId/results'));
    ExamResult? result;
    if (r is List) {
      _results =
          r.map((e) => ExamResult.fromJson(e as Map<String, dynamic>)).toList();
      if (_results.isNotEmpty) result = _results.first;
    } else if (r is Map<String, dynamic>) {
      result = ExamResult.fromJson(r);
      _results = [result];
    }
    notifyListeners();
    return result;
  }

  Future<dynamic> deleteQuestion(int id) async {}

  static Map<String, dynamic> _toJson(ExamModel e) => {
        'id': e.id,
        'course_id': e.courseId,
        'name': e.name,
        'is_published': e.isPublished,
        'questions': []
      };

  static Map<String, dynamic> _questionJson(QuestionModel q) => {
        'id': q.id,
        'exam_id': q.examId,
        'title': q.title,
        'options': q.options,
        'correct_answer': q.correctAnswer,
        'marks': q.marks,
        'order': q.order
      };
}
