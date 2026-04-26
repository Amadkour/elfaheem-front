// features/student/analytics/student_analytics_provider.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_education_app/core/api_client.dart';
import '../teacher/attendance_model.dart';
import 'student_attendance_model.dart';
import 'student_analytics_api.dart';

// ── Hub provider (enrolled courses list) ──────────────────────────────────────

class StudentAnalyticsProvider extends ChangeNotifier {
  final StudentAnalyticsApi _api;
  StudentAnalyticsProvider({StudentAnalyticsApi? api})
      : _api = api ?? StudentAnalyticsApi();

  bool _loading = false;
  bool get loading => _loading;

  List<EnrolledCourse> _courses = [];
  List<EnrolledCourse> get courses => _courses;

  String _search = '';
  String get search => _search;

  String? _error;
  String? get error => _error;

  List<EnrolledCourse> get filtered {
    if (_search.trim().isEmpty) return _courses;
    final q = _search.trim().toLowerCase();
    return _courses.where((c) => c.title.toLowerCase().contains(q)).toList();
  }

  void setSearch(String q) {
    _search = q;
    notifyListeners();
  }

  Future<void> loadCourses() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _courses = await _api.fetchMyEnrollments();
    } on ApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}

// ── Per-course detail provider (attendance + exams) ───────────────────────────

class StudentCourseAnalyticsProvider extends ChangeNotifier {
  final StudentAnalyticsApi _api;
  final int courseId;

  StudentCourseAnalyticsProvider({
    required this.courseId,
    StudentAnalyticsApi? api,
  }) : _api = api ?? StudentAnalyticsApi();

  // Attendance
  bool _loadingAtt = false;
  bool get loadingAtt => _loadingAtt;
  List<FullAttendance> _attendance = [];
  List<FullAttendance> get attendance => _attendance;
  String? _attError;
  String? get attError => _attError;

  // Exams
  bool _loadingExams = false;
  bool get loadingExams => _loadingExams;
  List<StudentExamSummary> _exams = [];
  List<StudentExamSummary> get exams => _exams;
  String? _examsError;
  String? get examsError => _examsError;

  // ── Computed stats ─────────────────────────────────────────────────────────

  int get presentCount => _attendance.where((a) => a.attendance.first.isPresent).length;
  int get totalSessions => _attendance.length;
  double get attendanceRate =>
      totalSessions == 0 ? 0.0 : presentCount / totalSessions * 100;

  int get attemptedCount => _exams.where((e) => e.attempted).length;
  int get passedCount    => _exams.where((e) => e.passed == true).length;
  double get avgScore {
    final done = _exams.where((e) => e.percentage != null).toList();
    if (done.isEmpty) return 0.0;
    return done.fold(0.0, (s, e) => s + e.percentage!) / done.length;
  }

  // ── Load ───────────────────────────────────────────────────────────────────

  Future<void> loadAll() =>
      Future.wait([loadAttendance(), loadExams()]);

  Future<void> loadAttendance() async {
    _loadingAtt = true;
    _attError = null;
    notifyListeners();
    try {
      _attendance = await _api.fetchMyCourseAttendance(courseId);
    } on ApiException catch (e) {
      _attError = e.message;
    } catch (e) {
      _attError = e.toString();
    } finally {
      _loadingAtt = false;
      notifyListeners();
    }
  }

  Future<void> loadExams() async {
    _loadingExams = true;
    _examsError = null;
    notifyListeners();
    try {
      _exams = await _api.fetchMyExamsForCourse(courseId);
    } on ApiException catch (e) {
      _examsError = e.message;
    } catch (e) {
      _examsError = e.toString();
    } finally {
      _loadingExams = false;
      notifyListeners();
    }
  }
}
