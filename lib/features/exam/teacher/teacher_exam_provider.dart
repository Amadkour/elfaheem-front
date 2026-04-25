// features/teacher/exam/teacher_exam_provider.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'exam_model.dart';
import 'teacher_exam_api.dart';

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

  // ── Results ────────────────────────────────────────────────────────────────
  bool _loadingResults = false;
  bool get loadingResults => _loadingResults;

  ExamModel? _selectedExam;
  ExamModel? get selectedExam => _selectedExam;

  List<StudentExamResult> _results = [];
  List<StudentExamResult> get results => _results;

  String? _resultsError;
  String? get resultsError => _resultsError;

  // ── Questions (for the add-question sheet) ─────────────────────────────────
  bool _loadingQuestions = false;
  bool get loadingQuestions => _loadingQuestions;

  List<Question> _questions = [];
  List<Question> get questions => _questions;

  // ── Saving ─────────────────────────────────────────────────────────────────
  bool _saving = false;
  bool get saving => _saving;

  // ── Tab (0=exams, 1=results) ───────────────────────────────────────────────
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

  // ── Load exams ─────────────────────────────────────────────────────────────

  Future<void> loadExams() async {
    _loadingExams = true;
    _examsError = null;
    notifyListeners();
    try {
      _exams = await _api.fetchCourseExams(courseId);
    } on ApiException catch (e) {
      _examsError = e.message;
    } catch (e) {
      _examsError = e.toString();
    } finally {
      _loadingExams = false;
      notifyListeners();
    }
  }

  // ── Create exam ────────────────────────────────────────────────────────────

  Future<bool> createExam({
    required String name,
    String? description,
    DateTime? startDate,
    int? duration,
    double? passingScore,
    double? totalMarks,
    String? passcode,
  }) async {
    _saving = true;
    notifyListeners();
    try {
      final created = await _api.createExam(
        name: name,
        description: description,
        courseId: courseId,
        startDate: startDate,
        duration: duration,
        passingScore: passingScore,
        totalMarks: totalMarks,
        passcode: passcode,
      );
      _exams.insert(0, created);
      return true;
    } on ApiException catch (e) {
      _examsError = e.message;
      return false;
    } catch (e) {
      _examsError = e.toString();
      return false;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  // ── Toggle publish ─────────────────────────────────────────────────────────

  /// Returns null on success, error message on failure.
  Future<String?> togglePublish(ExamModel exam) async {
    if (!exam.isPublished && exam.questionCount == 0) {
      return 'لا يمكن نشر اختبار بدون أسئلة';
    }
    try {
      final updated = exam.isPublished
          ? await _api.unpublishExam(exam.id)
          : await _api.publishExam(exam.id);
      final idx = _exams.indexWhere((e) => e.id == exam.id);
      if (idx != -1) _exams[idx] = updated;
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  // ── Delete exam ────────────────────────────────────────────────────────────

  Future<bool> deleteExam(int examId) async {
    try {
      await _api.deleteExam(examId);
      _exams.removeWhere((e) => e.id == examId);
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _examsError = e.message;
      notifyListeners();
      return false;
    }
  }

  // ── Load results for a selected exam ──────────────────────────────────────

  Future<void> loadResults(ExamModel exam) async {
    _selectedExam = exam;
    _results = [];
    _resultsError = null;
    _loadingResults = true;
    _tab = 1;
    notifyListeners();
    try {
      _results = await _api.fetchExamResults(exam.id);
    } on ApiException catch (e) {
      _resultsError = e.message;
    } catch (e) {
      _resultsError = e.toString();
    } finally {
      _loadingResults = false;
      notifyListeners();
    }
  }

  // ── Questions ──────────────────────────────────────────────────────────────

  Future<void> loadQuestions(int examId) async {
    _loadingQuestions = true;
    notifyListeners();
    try {
      _questions = await _api.fetchQuestions(examId);
    } finally {
      _loadingQuestions = false;
      notifyListeners();
    }
  }

  Future<bool> addQuestion({
    required int examId,
    required String title,
    required List<String> options,
    String? correctAnswer,
    double marks = 1.0,
    int order = 0,
  }) async {
    try {
      final q = await _api.addQuestion(
        examId: examId,
        title: title,
        options: options,
        correctAnswer: correctAnswer,
        marks: marks,
        order: order,
      );
      _questions.add(q);
      // bump local question count
      final idx = _exams.indexWhere((e) => e.id == examId);
      if (idx != -1) {
        final old = _exams[idx];
        _exams[idx] = ExamModel(
          id: old.id, name: old.name, description: old.description,
          courseId: old.courseId, startDate: old.startDate, duration: old.duration,
          passingScore: old.passingScore, totalMarks: old.totalMarks,
          passcode: old.passcode, isPublished: old.isPublished,
          createdAt: old.createdAt,
          questionCount: old.questionCount + 1,
        );
      }
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteQuestion(int questionId, int examId) async {
    try {
      await _api.deleteQuestion(questionId);
      _questions.removeWhere((q) => q.id == questionId);
      final idx = _exams.indexWhere((e) => e.id == examId);
      if (idx != -1) {
        final old = _exams[idx];
        _exams[idx] = ExamModel(
          id: old.id, name: old.name, description: old.description,
          courseId: old.courseId, startDate: old.startDate, duration: old.duration,
          passingScore: old.passingScore, totalMarks: old.totalMarks,
          passcode: old.passcode, isPublished: old.isPublished,
          createdAt: old.createdAt,
          questionCount: (old.questionCount - 1).clamp(0, 9999),
        );
      }
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }
}
