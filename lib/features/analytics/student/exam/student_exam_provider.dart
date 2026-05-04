import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_education_app/core/api_client.dart';
import '../../teacher/exam/exam_model.dart';
import 'student_exam_api.dart';

// ── Quiz session state (one active exam being taken) ─────────────────────────

class QuizSession {
  final StudentExamListItem exam;
  final List<Question> questions;

  /// questionIndex → answer string chosen by student
  final Map<int, String> answers = {};

  /// questionIndex → server response after submit (for auto-graded MCQ)
  final Map<int, Map<String, dynamic>> serverResponses = {};

  int currentIndex = 0;
  bool submitting = false;
  bool submitted = false;
  String? submitError;
  StudentMyResult? result; // filled after final submission

  QuizSession({required this.exam, required this.questions});

  Question get currentQuestion => questions[currentIndex];
  bool get isLast => currentIndex == questions.length - 1;
  bool get isFirst => currentIndex == 0;
  int get answeredCount => answers.length;
}

// ── Provider ──────────────────────────────────────────────────────────────────

class StudentExamProvider extends ChangeNotifier {
  final StudentExamApi _api;

  StudentExamProvider({StudentExamApi? api})
      : _api = api ?? StudentExamApi();

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
  // Start a quiz — load questions then open session
  // ══════════════════════════════════════════════════════════════════════════

  Future<bool> startExam(StudentExamListItem exam) async {
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
  // Submit exam  — sends all answers sequentially then fetches result
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> submitExam() async {
    final s = _session;
    if (s == null || s.submitting || s.submitted) return;

    _stopTimer();
    s.submitting = true;
    s.submitError = null;
    notifyListeners();

    try {
      // Submit each answered question (upsert on server side)
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
          // Continue even if one answer fails; collect what we can
        }
      }

      // Fetch final result from server
      try {
        s.result = await _api.fetchMyResult(s.exam.id);
      } catch (_) {
        // If result fetch fails we still mark submitted; result stays null
      }

      s.submitted = true;
      // Refresh the list so this exam shows as submitted
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
        // Time's up — auto-submit
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

  void _markSubmittedInList(int examId, StudentMyResult? result) {
    final idx = _myExams.indexWhere((e) => e.id == examId);
    if (idx == -1) return;
    final old = _myExams[idx];
    _myExams[idx] = StudentExamListItem(
      id: old.id,
      name: old.name,
      description: old.description,
      courseId: old.courseId,
      courseName: old.courseName,
      startDate: old.startDate,
      duration: old.duration,
      totalMarks: old.totalMarks,
      passingScore: old.passingScore,
      isSubmitted: true,
      answeredCount: result?.answeredCount ?? old.answeredCount,
      questionCount: old.questionCount,
      marksObtained: result?.marksObtained,
      percentage: result?.percentage,
      passed: result?.passed,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }
}
