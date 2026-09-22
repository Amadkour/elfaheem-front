library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_education_app/core/api_client.dart';
import '../../../shared/models/exam_model.dart';
import '../../../teacher/analysis/exam/exam_model.dart';
import 'student_exam_api.dart';

// ── Quiz session state ────────────────────────────────────────────────────────

class QuizSession {
  final StudentExamListItem exam;
  final List<Question> questions;

  final Map<int, String> answers = {};
  final Map<int, Map<String, dynamic>> serverResponses = {};

  int currentIndex = 0;
  bool submitting = false;
  bool submitted = false;
  String? submitError;
  StudentMyResult? result;

  // Populated after result is fetched
  int? remainingSubmissions;
  double? bestPercentage;

  QuizSession({required this.exam, required this.questions});

  Question get currentQuestion => questions[currentIndex];

  bool get isLast => currentIndex == questions.length - 1;

  bool get isFirst => currentIndex == 0;

  int get answeredCount => answers.length;

  /// True when the student can retry (remaining attempts > 0 and deadline ok)
  bool get canRetry {
    if (exam.isDeadlineFrozen) return false;
    if (remainingSubmissions == null) return false; // unlimited handled below
    if (exam.maxSubmissions == null || exam.maxSubmissions! <= 0) return true;
    return remainingSubmissions! > 0;
  }

  /// Whether the current result matches the best-ever
  bool get isCurrentBest =>
      result != null &&
          (bestPercentage == null || result!.percentage >= bestPercentage!);
}

// ── Provider ──────────────────────────────────────────────────────────────────

class StudentExamProvider extends ChangeNotifier {
  final StudentExamApi _api;

  StudentExamProvider({StudentExamApi? api}) : _api = api ?? StudentExamApi();

  // ── My-exams list ──────────────────────────────────────────────────────────
  bool _loadingList = false;

  bool get loadingList => _loadingList;
  List<StudentExamListItem> _myExams = [];

  List<StudentExamListItem> get myExams => List.unmodifiable(_myExams);
  String? _listError;

  String? get listError => _listError;

  // ── Active quiz session ────────────────────────────────────────────────────
  QuizSession? _session;

  QuizSession? get session => _session;
  bool _loadingQuestions = false;

  bool get loadingQuestions => _loadingQuestions;
  String? _questionsError;

  String? get questionsError => _questionsError;

  // ── Course-specific exam lists ─────────────────────────────────────────────
  final Map<String, List<StudentExamListItem>> _courseExams = {};
  final Map<String, bool> _loadingCourseExams = {};
  final Map<String, String?> _courseExamsError = {};

  List<StudentExamListItem> courseExamsFor(String courseId) =>
      _courseExams[courseId] ?? [];

  bool loadingCourseExamsFor(String courseId) =>
      _loadingCourseExams[courseId] ?? false;

  String? courseExamsErrorFor(String courseId) => _courseExamsError[courseId];

  /// True once a load for [courseId] has finished successfully (even if the
  /// course has no exams) — lets many session cards share one request.
  bool courseExamsLoadedFor(String courseId) =>
      _courseExams.containsKey(courseId);

  /// The exam attached to [sessionId], or null if that session has none.
  StudentExamListItem? examForSession(String courseId, int sessionId) {
    for (final e in courseExamsFor(courseId)) {
      if (e.sessionId == sessionId) return e;
    }
    return null;
  }

  // ── Timer ──────────────────────────────────────────────────────────────────
  int _secondsLeft = 0;

  int get secondsLeft => _secondsLeft;
  Timer? _timer;

  String get timerDisplay {
    final m = _secondsLeft ~/ 60;
    final s = _secondsLeft % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  bool get timerCritical => _secondsLeft < 120;

  bool get timerWarning => _secondsLeft < 300 && !timerCritical;

  // ══════════════════════════════════════════════════════════════════════════
  // My Exams list
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> loadMyExams() async {
    _loadingList = true;
    _listError = null;
    notifyListeners();
    try {
      _myExams = await _api.fetchMyExams();
    } on ApiException catch (e) {
      _listError = e.message;
    } catch (e) {
      _listError = e.toString();
    } finally {
      _loadingList = false;
      notifyListeners();
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Course-specific exams
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> loadCourseExams(String courseId) async {
    _loadingCourseExams[courseId] = true;
    _courseExamsError[courseId] = null;
    notifyListeners();
    try {
      _courseExams[courseId] = await _api.fetchCourseExams(courseId);
    } on ApiException catch (e) {
      _courseExamsError[courseId] = e.message;
    } catch (e) {
      _courseExamsError[courseId] = e.toString();
    } finally {
      _loadingCourseExams[courseId] = false;
      notifyListeners();
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Start a quiz (first attempt OR retry)
  // ══════════════════════════════════════════════════════════════════════════

  Future<bool> startExam(StudentExamListItem exam) async {
    if (exam.isFrozen) {
      _questionsError = exam.isDeadlineFrozen
          ? 'انتهى الموعد النهائي لهذا الاختبار'
          : 'لقد استنفدت جميع محاولاتك المسموح بها';
      notifyListeners();
      return false;
    }
    _loadingQuestions = true;
    _questionsError = null;
    notifyListeners();
    try {
      final questions = await _api.fetchQuestions(exam.id);
      if (questions.isEmpty) {
        _questionsError = 'هذا الاختبار لا يحتوي على أسئلة بعد';
        return false;
      }
      _session = QuizSession(exam: exam, questions: questions);
      _startTimer(exam.duration ?? 60);
      return true;
    } on ApiException catch (e) {
      _questionsError = e.message;
      return false;
    } catch (e) {
      _questionsError = e.toString();
      return false;
    } finally {
      _loadingQuestions = false;
      notifyListeners();
    }
  }

  /// Re-start the same exam for a new attempt (retry flow).
  Future<bool> retryExam() async {
    final s = _session;
    if (s == null) return false;
    // Build updated exam item reflecting the new submission count
    final updatedExam = _findUpdatedExam(s.exam.id) ?? s.exam;
    _stopTimer();
    _session = null;
    return startExam(updatedExam);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Quiz navigation
  // ══════════════════════════════════════════════════════════════════════════

  void selectAnswer(String answer) {
    if (_session == null) return;
    _session!.answers[_session!.currentIndex] = answer;
    notifyListeners();
  }

  void goToQuestion(int index) {
    if (_session == null) return;
    _session!.currentIndex = index.clamp(0, _session!.questions.length - 1);
    notifyListeners();
  }

  void nextQuestion() {
    if (_session == null || _session!.isLast) return;
    _session!.currentIndex++;
    notifyListeners();
  }

  void prevQuestion() {
    if (_session == null || _session!.isFirst) return;
    _session!.currentIndex--;
    notifyListeners();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Submit exam — sends answers sequentially, fetches BEST result
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> submitExam() async {
    final s = _session;
    if (s == null || s.submitting || s.submitted) return;

    _stopTimer();
    s.submitting = true;
    s.submitError = null;
    notifyListeners();

    try {
      // Submit each answered question
      for (int i = 0; i < s.questions.length; i++) {
        final answer = s.answers[i];
        if (answer == null) continue;
        final q = s.questions[i];
        try {
          final resp = await _api.submitAnswer(
            examId: s.exam.id,
            questionId: q.id,
            answer: answer,
          );
          s.serverResponses[i] = resp;
        } catch (_) {
          // Continue even if one answer fails
        }
      }

      // Fetch BEST result from server
      try {
        s.result = await _api.fetchMyResult(s.exam.id);
        s.remainingSubmissions = s.result!.remainingSubmissions;
        s.bestPercentage = s.result!.bestPercentage;
      } catch (_) {
        // Result fetch failed — still mark submitted
      }

      s.submitted = true;
      _markSubmittedInList(s.exam.id, s.result);
    } catch (e) {
      s.submitError = e is ApiException ? e.message : e.toString();
    } finally {
      s.submitting = false;
      notifyListeners();
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Tear-down
  // ══════════════════════════════════════════════════════════════════════════

  void closeSession() {
    _stopTimer();
    _session = null;
    notifyListeners();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Timer helpers
  // ══════════════════════════════════════════════════════════════════════════

  void _startTimer(int durationMinutes) {
    _stopTimer();
    _secondsLeft = durationMinutes * 60;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_secondsLeft > 0) {
        _secondsLeft--;
        notifyListeners();
      } else {
        submitExam();
      }
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Private helpers
  // ══════════════════════════════════════════════════════════════════════════

  StudentExamListItem? _findUpdatedExam(int examId) =>
      _myExams.where((e) => e.id == examId).firstOrNull;

  void _markSubmittedInList(int examId, StudentMyResult? result) {
    final idx = _myExams.indexWhere((e) => e.id == examId);
    if (idx == -1) return;
    final old = _myExams[idx];
    final newSubCount = old.submissionCount + 1;
    final maxSub = old.maxSubmissions;
    _myExams[idx] = StudentExamListItem(
      id: old.id,
      name: old.name,
      description: old.description,
      courseId: old.courseId,
      courseName: old.courseName,
      sessionId: old.sessionId,
      startDate: old.startDate,
      endDate: old.endDate,
      duration: old.duration,
      totalMarks: old.totalMarks,
      passingScore: old.passingScore,
      maxSubmissions: maxSub,
      submissionCount: newSubCount,
      remainingSubmissions: maxSub != null && maxSub > 0
          ? (maxSub - newSubCount).clamp(0, maxSub)
          : null,
      isSubmitted: true,
      answeredCount: result?.answeredCount ?? old.answeredCount,
      questionCount: old.questionCount,
      marksObtained: result?.marksObtained,
      percentage: result?.percentage,
      passed: result?.passed,
      enablePasscode: old.enablePasscode,
      passcode: old.passcode,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }
}