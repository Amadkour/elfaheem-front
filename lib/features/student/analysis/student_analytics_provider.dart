// lib/features/student/analysis/student_analytics_provider.dart
// State of the student analytics module.
//
//   StudentAnalyticsProvider        the hub: enrolled courses + the analytics profile (Data Lab) of every course
//   StudentCourseAnalyticsProvider  one course: attendance + exams + that course's profile block
//
// The profile is optional: when the admin switched Data Lab off (or the course hides it) everything still works with
// the platform data only — the extra numbers (progress, published marks, class averages, flags) simply do not show.
import 'package:flutter/foundation.dart';
import 'package:flutter_education_app/core/api_client.dart';

import '../../../core/base_provider.dart';
import '../../teacher/analysis/attendance/attendance_model.dart';
import '../../teacher/data_lab/data_lab_models.dart';
import 'attendance/student_attendance_model.dart';
import 'student_analytics_api.dart';

/// Present when the session has an attendance record that says so (an empty record = absent, never a crash).
bool anIsPresent(FullAttendance r) => r.attendance.isNotEmpty && r.attendance.first.isPresent;

/// Average of the values that exist (null when none).
double? anAverage(Iterable<double?> xs) {
  final v = xs.whereType<double>().toList();
  return v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
}

/// Overall performance of a course: the average of progress, attendance and exams — only those that exist.
double? anOverall({double? progress, double? attendance, double? exams}) => anAverage([progress, attendance, exams]);

/// A course needs attention when attendance or exams are clearly low.
bool anNeedsAttention({double? attendance, double? exams}) =>
    (attendance != null && attendance < 60) || (exams != null && exams < 50);

enum AnSort { name, attention, progress }

// ── Hub provider ──────────────────────────────────────────────────────────────

class StudentAnalyticsProvider extends BaseProvider {
  StudentAnalyticsProvider({StudentAnalyticsApi? api}) : _api = api ?? StudentAnalyticsApi();

  final StudentAnalyticsApi _api;

  bool _loading = false;
  bool get loading => _loading;

  List<EnrolledCourse> _courses = [];
  List<EnrolledCourse> get courses => _courses;

  DlProfile? _profile;

  /// The Data Lab profile of the student (null when it is switched off / not available).
  DlProfile? get profile => _profile;
  Map<int, DlCourseBlock> _blocks = {};

  String _search = '';
  String get search => _search;

  AnSort _sort = AnSort.name;
  AnSort get sort => _sort;

  String? _error;
  String? get error => _error;

  bool _loadedOnce = false;

  /// True after the first load finished (the dashboard may have loaded it before the screen opens).
  bool get loadedOnce => _loadedOnce;

  int _gen = 0;

  DlCourseBlock? blockOf(int courseId) => _blocks[courseId];

  /// Best known progress of a course: the profile's (it follows lessons AND the teacher's corrections), else the
  /// enrolment's.
  double progressOf(EnrolledCourse c) => _blocks[c.id]?.progress ?? c.progress.toDouble();

  double? overallOf(EnrolledCourse c) {
    final b = _blocks[c.id];
    return anOverall(progress: progressOf(c), attendance: b?.attendance, exams: b?.examAvg);
  }

  bool needsAttention(EnrolledCourse c) {
    final b = _blocks[c.id];
    return anNeedsAttention(attendance: b?.attendance, exams: b?.examAvg);
  }

  int get attentionCount => _courses.where(needsAttention).length;

  double? get avgProgress => _courses.isEmpty ? null : anAverage(_courses.map(progressOf));

  List<EnrolledCourse> get filtered {
    final q = _search.trim().toLowerCase();
    final out = q.isEmpty
        ? List<EnrolledCourse>.of(_courses)
        : _courses
        .where((c) => c.title.toLowerCase().contains(q) || (c.teacherName ?? '').toLowerCase().contains(q))
        .toList();
    switch (_sort) {
      case AnSort.name:
        out.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case AnSort.attention:
        // lowest overall first; courses without numbers at the end
        out.sort((a, b) => (overallOf(a) ?? 1000).compareTo(overallOf(b) ?? 1000));
      case AnSort.progress:
        out.sort((a, b) => progressOf(b).compareTo(progressOf(a)));
    }
    return out;
  }

  void setSearch(String q) {
    _search = q;
    notifyListeners();
  }

  void setSort(AnSort s) {
    if (s == _sort) return;
    _sort = s;
    notifyListeners();
  }

  /// Enrolments and the analytics profile load side by side; a missing profile is not an error.
  Future<void> loadCourses() async {
    final gen = ++_gen;
    _loading = _courses.isEmpty; // a refresh keeps the list on screen
    _error = null;
    notifyListeners();
    try {
      final results = await Future.wait<Object?>([_api.fetchMyEnrollments(), _api.fetchMyProfile()]);
      if (gen != _gen) return;
      _courses = results[0] as List<EnrolledCourse>;
      _profile = results[1] as DlProfile?;
      _blocks = {for (final b in _profile?.courses ?? const <DlCourseBlock>[]) b.courseId: b};
    } on ApiException catch (e) {
      if (gen == _gen) _error = e.message;
    } catch (e) {
      if (gen == _gen) _error = e.toString();
    } finally {
      if (gen == _gen) {
        _loading = false;
        _loadedOnce = true;
        notifyListeners();
      }
    }
  }
}

// ── Per-course provider ───────────────────────────────────────────────────────

class StudentCourseAnalyticsProvider extends ChangeNotifier {
  StudentCourseAnalyticsProvider({required this.courseId, StudentAnalyticsApi? api, DlCourseBlock? initialBlock})
      : _api = api ?? StudentAnalyticsApi(),
        _block = initialBlock;

  final StudentAnalyticsApi _api;
  final int courseId;
  bool _disposed = false;

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

  // Analytics profile block (Data Lab)
  bool _loadingBlock = false;
  bool get loadingBlock => _loadingBlock;
  DlCourseBlock? _block;

  /// Progress, flags, published marks and class averages of this course — null when not available.
  DlCourseBlock? get block => _block;
  bool _blockChecked = false;

  /// True once we know the course has no analytics profile (Data Lab off / hidden for students).
  bool get profileUnavailable => _blockChecked && _block == null;

  bool get loadingAny => _loadingAtt || _loadingExams;

  // ── Computed stats ─────────────────────────────────────────────────────────

  int get presentCount => _attendance.where(anIsPresent).length;
  int get totalSessions => _attendance.length;
  int get missedCount => totalSessions - presentCount;
  double get attendanceRate => totalSessions == 0 ? 0.0 : presentCount / totalSessions * 100;

  int get attemptedCount => _exams.where((e) => e.attempted).length;
  int get passedCount => _exams.where((e) => e.passed == true).length;
  int get pendingCount => _exams.where((e) => !e.attempted).length;

  double get avgScore {
    final done = _exams.where((e) => e.attempted && e.percentage != null).toList();
    if (done.isEmpty) return 0.0;
    return done.fold(0.0, (s, e) => s + e.percentage!) / done.length;
  }

  double? get progress => _block?.progress;

  /// Average of progress, attendance and exams — only the parts that exist.
  double? get overall => anOverall(
    progress: progress,
    attendance: totalSessions == 0 ? null : attendanceRate,
    exams: attemptedCount == 0 ? null : avgScore,
  );

  /// Class average of a profile column ('progress', 'attendance', 'exam_avg' …), when the teacher shares it.
  double? classAvg(String key) {
    for (final c in _block?.columns ?? const <DlProfileColumn>[]) {
      if (c.key == key) return c.classAvg;
    }
    return null;
  }

  /// Exam scores in date order (oldest first) — for the trend.
  List<StudentExamSummary> get scoredExams {
    final l = _exams.where((e) => e.attempted && e.percentage != null).toList();
    l.sort((a, b) => (a.startDate ?? DateTime(2000)).compareTo(b.startDate ?? DateTime(2000)));
    return l;
  }

  /// +n when the last exam is better than the average of the ones before it, −n when worse, null with < 2 exams.
  double? get trend {
    final s = scoredExams;
    if (s.length < 2) return null;
    final before = s.sublist(0, s.length - 1).fold(0.0, (a, e) => a + e.percentage!) / (s.length - 1);
    return s.last.percentage! - before;
  }

  // ── Load ───────────────────────────────────────────────────────────────────

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> loadAll() => Future.wait([loadAttendance(), loadExams(), loadBlock()]);

  Future<void> loadAttendance() async {
    _loadingAtt = true;
    _attError = null;
    _notify();
    try {
      _attendance = await _api.fetchMyCourseAttendance(courseId);
    } on ApiException catch (e) {
      _attError = e.message;
    } catch (e) {
      _attError = e.toString();
    } finally {
      _loadingAtt = false;
      _notify();
    }
  }

  Future<void> loadExams() async {
    _loadingExams = true;
    _examsError = null;
    _notify();
    try {
      _exams = await _api.fetchMyExams(courseId: courseId);
    } on ApiException catch (e) {
      _examsError = e.message;
    } catch (e) {
      _examsError = e.toString();
    } finally {
      _loadingExams = false;
      _notify();
    }
  }

  Future<void> loadBlock() async {
    _loadingBlock = true;
    _notify();
    final p = await _api.fetchMyProfile(courseId: courseId);
    DlCourseBlock? b;
    for (final x in p?.courses ?? const <DlCourseBlock>[]) {
      if (x.courseId == courseId) b = x;
    }
    _block = b;
    _blockChecked = true;
    _loadingBlock = false;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
