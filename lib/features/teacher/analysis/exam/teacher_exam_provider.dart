import 'package:flutter/cupertino.dart';
import 'package:flutter_education_app/features/teacher/analysis/exam/teacher_exam_api.dart';

import '../../../../config/app_config.dart';
import '../../../../core/api_client.dart';
import 'package:flutter_education_app/core/api_error_text.dart';
import '../../../shared/models/exam_model.dart';
import 'package:flutter_education_app/features/live/room/widgets/live_quiz.dart';
import 'exam_files.dart';

class TeacherExamProvider extends ChangeNotifier {
  final TeacherExamApi _api;
  final int courseId;

  TeacherExamProvider({required this.courseId, TeacherExamApi? api})
      : _api = api ?? TeacherExamApi();

  // ── Exam list ──────────────────────────────────────────────────────────────
  bool _loadingExams = false;
  bool get loadingExams => _loadingExams;

  List<ExamModel> _exams = [];
  List<ExamModel> get exams => _exams;

  String? _examsError;
  String? get examsError => _examsError;

  // ── Sessions of the course (for "attach exam to a session") ────────────────
  List<SessionOption> _sessions = [];
  List<SessionOption> get sessions => _sessions;
  bool _sessionsLoaded = false;
  bool get sessionsLoaded => _sessionsLoaded;

  String? sessionNameFor(ExamModel e) {
    if (e.sessionName != null) return e.sessionName;
    final id = e.sessionId;
    if (id == null) return null;
    for (final s in _sessions) {
      if (s.id == id) return s.name;
    }
    return null;
  }

  Future<void> loadSessions() async {
    try {
      _sessions = await _api.fetchCourseSessions(courseId);
    } catch (_) {
      // Not fatal: exams still work, the picker just has no sessions to offer.
    } finally {
      _sessionsLoaded = true;
      notifyListeners();
    }
  }

  // ── Results ────────────────────────────────────────────────────────────────
  bool _loadingResults = false;
  bool get loadingResults => _loadingResults;

  ExamModel? _selectedExam;
  ExamModel? get selectedExam => _selectedExam;

  List<StudentExamResult> _results = [];
  List<StudentExamResult> get results => _results;

  String? _resultsError;
  String? get resultsError => _resultsError;

  // ── Questions — keyed by examId so each exam has its own list ─────────────
  // { examId → List<Question> }
  final Map<int, List<Question>> _questionsByExam = {};
  final Map<int, bool> _loadingQuestionsByExam = {};
  final Map<int, String?> _questionErrorByExam = {};

  List<Question> questionsFor(int examId) =>
      _questionsByExam[examId] ?? [];

  bool loadingQuestionsFor(int examId) =>
      _loadingQuestionsByExam[examId] ?? false;

  String? questionErrorFor(int examId) => _questionErrorByExam[examId];

  // ── Saving ─────────────────────────────────────────────────────────────────
  bool _saving = false;
  bool get saving => _saving;

  // ── Tab (0 = exams, 1 = results) ──────────────────────────────────────────
  int _tab = 0;
  int get tab => _tab;
  void setTab(int t) {
    _tab = t;
    notifyListeners();
  }

  // ── Summary stats over results ─────────────────────────────────────────────
  int get attendedCount  => _results.where((r) => r.isAttended).length;
  int get attemptedCount => _results.where((r) => r.attempted).length;
  int get passedCount    => _results.where((r) => r.passed == true).length;
  double get avgScore {
    final done = _results.where((r) => r.percentage != null).toList();
    if (done.isEmpty) return 0;
    return done.fold(0.0, (s, r) => s + r.percentage!) / done.length;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Exams CRUD
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> loadExams() async {
    loadSessions(); // in parallel; fills the "session" chip on each exam
    _loadingExams = true;
    _examsError = null;
    notifyListeners();
    try {
      _exams = await _api.fetchCourseExams(courseId);
    } on ApiException catch (e) {
      _examsError = e.message;
    } catch (e) {
      _examsError = apiErrorText(ApiException.from(e));
    } finally {
      _loadingExams = false;
      if(exams.isNotEmpty){
        await loadResults(null);
      }
      notifyListeners();
    }

  }

  Future<bool> createExam({
    required String name,
    String? description,
    int? sessionId,
    DateTime? startDate,
    DateTime? endDate,
    int? duration,
    double? passingScore,
    double? totalMarks,
    String? passcode,
    int? maxSubmissions,
    int? questionsPerStudent,
    bool shuffleQuestions = false,
    bool shuffleOptions = false,
  }) async {
    _saving = true;
    notifyListeners();
    try {
      final created = await _api.createExam(
        name: name,
        description: description,
        courseId: courseId,
        sessionId: sessionId,
        startDate: startDate,
        endDate: endDate,
        duration: duration,
        passingScore: passingScore,
        totalMarks: totalMarks,
        passcode: passcode,
        maxSubmissions: maxSubmissions,
        questionsPerStudent: questionsPerStudent,
        shuffleQuestions: shuffleQuestions,
        shuffleOptions: shuffleOptions,
      );
      _exams.insert(0, created);
      return true;
    } on ApiException catch (e) {
      _examsError = e.message;
      return false;
    } catch (e) {
      _examsError = apiErrorText(ApiException.from(e));
      return false;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  /// Returns null on success, error string on failure.
  Future<String?> togglePublish(ExamModel exam) async {
    if (!exam.isPublished && exam.questionCount == 0) {
      return 'exam_cannot_publish_empty'.tr;
    }
    try {
      final updated = exam.isPublished
          ? await _api.unpublishExam(exam.id)
          : await _api.publishExam(exam.id);
      _replaceExam(updated);
      // the teacher's open live room tells its students over LiveKit (topic 'quiz'): they fetch /exams/active
      if (!exam.isPublished) LiveQuizBroadcast.started(examId: exam.id, courseId: courseId);
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (e) {
      return apiErrorText(ApiException.from(e));
    }
  }

  /// Change attempts / random-paper rules. Returns null on success, else an
  /// error message. Papers already handed out keep their layout.
  Future<String?> updateExamRules(ExamModel exam, ExamRules rules) async {
    _saving = true;
    notifyListeners();
    try {
      final updated = await _api.updateExamSettings(exam.id, rules);
      _replaceExam(updated);
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (e) {
      return apiErrorText(ApiException.from(e));
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  /// Attach the exam to [sessionId] (or detach with null).
  /// Returns null on success, an error message on failure.
  Future<String?> assignSession(ExamModel exam, int? sessionId) async {
    try {
      await _api.assignExamToSession(exam.id, sessionId);
      final idx = _exams.indexWhere((e) => e.id == exam.id);
      if (idx != -1) {
        _exams[idx] = _exams[idx]
            .copyWith(sessionId: sessionId, clearSession: sessionId == null);
      }
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (e) {
      return apiErrorText(ApiException.from(e));
    }
  }

  Future<bool> deleteExam(int examId) async {
    try {
      await _api.deleteExam(examId);
      _exams.removeWhere((e) => e.id == examId);
      _questionsByExam.remove(examId);
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _examsError = e.message;
      notifyListeners();
      return false;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Results
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> loadResults(ExamModel? exam) async {
    _results = [];
    _resultsError = null;
    _loadingResults = true;
    if(exam!=null) {
      _tab = 1;
      _selectedExam = exam;
    }else{
      _tab = 0;
      _selectedExam = exams.first;

    }
    notifyListeners();
    try {
      _results = await _api.fetchExamResults(exam?.id??exams[0].id);
    } on ApiException catch (e) {
      _resultsError = e.message;
    } catch (e) {
      _resultsError = apiErrorText(ApiException.from(e));
    } finally {
      _loadingResults = false;
      notifyListeners();
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Questions
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> loadQuestions(int examId) async {
    _loadingQuestionsByExam[examId] = true;
    _questionErrorByExam[examId] = null;
    notifyListeners();
    try {
      _questionsByExam[examId] = await _api.fetchQuestions(examId);
    } on ApiException catch (e) {
      _questionErrorByExam[examId] = e.message;
    } catch (e) {
      _questionErrorByExam[examId] = apiErrorText(ApiException.from(e));
    } finally {
      _loadingQuestionsByExam[examId] = false;
      notifyListeners();
    }
  }

  /// Add a new question. Returns the created [Question] or null on error.
  Future<Question?> addQuestion({
    required int examId,
    required String title,
    required List<String> options,
    String? correctAnswer,
    required double marks,
  }) async {
    _saving = true;
    notifyListeners();
    try {
      final nextOrder = (questionsFor(examId).length);
      final q = await _api.addQuestion(
        examId: examId,
        title: title,
        options: options,
        correctAnswer: correctAnswer,
        marks: marks,
        order: nextOrder,
      );
      _questionsByExam.putIfAbsent(examId, () => []).add(q);
      _bumpQuestionCount(examId, 1);
      return q;
    } catch (_) {
      return null;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  /// Update an existing question. Returns the updated [Question] or null on error.
  Future<Question?> updateQuestion({
    required int questionId,
    required int examId,
    required String title,
    required List<String> options,
    String? correctAnswer,
    required double marks,
  }) async {
    _saving = true;
    notifyListeners();
    try {
      final list = questionsFor(examId);
      final idx = list.indexWhere((q) => q.id == questionId);
      final order = idx != -1 ? list[idx].order : 0;

      final updated = await _api.updateQuestion(
        questionId: questionId,
        examId: examId,
        title: title,
        options: options,
        correctAnswer: correctAnswer,
        marks: marks,
        order: order,
      );
      if (idx != -1) {
        _questionsByExam[examId]![idx] = updated;
      }
      return updated;
    } catch (_) {
      return null;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  /// Delete a question. Returns true on success.
  Future<bool> deleteQuestion({
    required int questionId,
    required int examId,
  }) async {
    try {
      await _api.deleteQuestion(questionId);
      _questionsByExam[examId]?.removeWhere((q) => q.id == questionId);
      _bumpQuestionCount(examId, -1);
      return true;
    } catch (_) {
      return false;
    } finally {
      notifyListeners();
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Import / export
  // ══════════════════════════════════════════════════════════════════════════

  /// Downloads + saves the sample .xlsx. Returns null on success, else an error.
  Future<String?> downloadTemplate() async {
    try {
      await saveExamFile(await _api.downloadImportTemplate());
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (e) {
      return apiErrorText(ApiException.from(e));
    }
  }

  /// Imports questions from an Excel / CSV file into [examId].
  Future<({ImportResult? result, String? error})> importQuestions(
      int examId, ExamFile file) async {
    _saving = true;
    notifyListeners();
    try {
      final r = await _api.importQuestions(examId, file);
      final idx = _exams.indexWhere((e) => e.id == examId);
      if (idx != -1) {
        _exams[idx] = _exams[idx].copyWith(questionCount: r.questionsCount);
      }
      await loadQuestions(examId); // refresh the list the teacher is looking at
      return (result: r, error: null);
    } on ApiException catch (e) {
      return (result: null, error: e.message);
    } catch (e) {
      return (result: null, error: apiErrorText(ApiException.from(e)));
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  /// Exports [kind] = questions | marks | answers | all as .xlsx and saves it.
  /// Returns null on success, else an error message.
  Future<String?> exportExam(int examId, String kind) async {
    try {
      await saveExamFile(await _api.exportExam(examId, kind));
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (e) {
      return apiErrorText(ApiException.from(e));
    }
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  void _replaceExam(ExamModel updated) {
    final idx = _exams.indexWhere((e) => e.id == updated.id);
    if (idx != -1) {
      final old = _exams[idx];
      // publish/unpublish return the bare exam (no question count / session
      // name) — keep what we already know instead of blanking it.
      _exams[idx] = updated.copyWith(
        questionCount: updated.questionCount == 0 ? old.questionCount : null,
        sessionName: updated.sessionName ?? old.sessionName,
      );
    }
    notifyListeners();
  }

  void _bumpQuestionCount(int examId, int delta) {
    final idx = _exams.indexWhere((e) => e.id == examId);
    if (idx == -1) return;
    final old = _exams[idx];
    _exams[idx] = old.copyWith(
      questionCount: (old.questionCount + delta).clamp(0, 9999),
    );
  }
}