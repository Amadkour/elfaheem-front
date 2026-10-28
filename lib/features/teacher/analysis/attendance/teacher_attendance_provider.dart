// features/teacher/attendance/teacher_attendance_provider.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/api_error_text.dart';
import 'attendance_model.dart';
import 'teacher_attendance_api.dart';

enum AttendanceLoadState { idle, loadingSessions, loadingStudents, error }

class TeacherAttendanceProvider extends ChangeNotifier {
  final TeacherAttendanceApi _api;
  final int courseId;

  TeacherAttendanceProvider({required this.courseId, TeacherAttendanceApi? api})
      : _api = api ?? TeacherAttendanceApi();

  // ── State ──────────────────────────────────────────────────────────────────
  AttendanceLoadState _state = AttendanceLoadState.idle;

  AttendanceLoadState get state => _state;
  List<FullAttendance> fullAttendance = [];

  List<SessionOption> get sessions =>
      fullAttendance.map((e) => e.sessions).toList();

  SessionOption? _selectedSession;

  SessionOption? get selectedSession => _selectedSession;

  List<AttendanceStudent> _allStudents = [];

  List<AttendanceStudent> get allStudents => _allStudents;

  String _search = '';

  String get search => _search;

  String? _errorMessage;

  bool saving = false;

  List<Map<String, dynamic>> changes = [];

  String? get errorMessage => _errorMessage;

  // ── Derived ────────────────────────────────────────────────────────────────
  bool get isLoadingSessions => _state == AttendanceLoadState.loadingSessions;

  bool get isLoadingStudents => _state == AttendanceLoadState.loadingStudents;

  bool get hasError => _state == AttendanceLoadState.error;

  int get presentCount => _allStudents.where((s) => s.isPresent).length;

  int get absentCount => _allStudents.length - presentCount;

  List<AttendanceStudent> get filtered {
    if (_search.trim().isEmpty) return _allStudents;
    final q = _search.trim().toLowerCase();
    return _allStudents.where((s) => s.name.toLowerCase().contains(q)).toList();
  }

  // ── Load sessions ──────────────────────────────────────────────────────────

  Future<void> loadSessions(int? sessionId) async {
    _setState(AttendanceLoadState.loadingSessions);
    try {
      fullAttendance = await _api.fetchCourseAttendance(courseId);
      _errorMessage = null;
      _setState(AttendanceLoadState.idle);
      if (sessions.isNotEmpty) await selectSession(sessionId!=null? sessions.firstWhere((e)=>e.id==sessionId): sessions.first);
    } on ApiException catch (e) {
      _errorMessage = e.message;
      _setState(AttendanceLoadState.error);
    } catch (e) {
      _errorMessage = apiErrorText(ApiException.from(e));
      _setState(AttendanceLoadState.error);
    }
  }

  // ── Select session → load its attendance ──────────────────────────────────

  Future<void> selectSession(SessionOption session) async {
    _selectedSession = session;
    _allStudents = [];
    _setState(AttendanceLoadState.loadingStudents);
    try {
      _allStudents = fullAttendance
          .firstWhere((e) => e.sessions.id == session.id)
          .attendance;
      _errorMessage = null;
      _setState(AttendanceLoadState.idle);
    } on ApiException catch (e) {
      _errorMessage = e.message;
      _setState(AttendanceLoadState.error);
    } catch (e) {
      _errorMessage = apiErrorText(ApiException.from(e));
      _setState(AttendanceLoadState.error);
    }
  }

  // ── Mutations ──────────────────────────────────────────────────────────────

  void toggleStudent(int studentId, bool isPresent) {
    final idx = _allStudents.indexWhere((s) => s.id == studentId);
    if (idx == -1) return;
    changes.add({'id': studentId, 'value': isPresent});
    _allStudents[idx].isPresent = isPresent;
    notifyListeners();
  }

  Future<bool> markAll(bool present) async {
    bool b=await saveAttendance(_allStudents.map((e)=>{'id':e.id,'value':present}).toList());
    if (b) {
      for (final s in _allStudents) {
        s.isPresent = present;
      }
      clearChanges();
    }
    notifyListeners();
    return b;
  }

  void setSearch(String q) {
    _search = q;
    notifyListeners();
  }

  // ── Save — locally stored; extend with a real PUT endpoint when available ──

  Future<bool> saveAttendance(List<Map<String, dynamic>> changes) async {
    bool b = false;
    try {
      for (Map<String, dynamic> c in changes) {
        bool res = await _api.forceAttendance(
            selectedSession!.id, c['id'], c['value']);
        if (!res) {
          b = false;
          break;
        }
        b=true;
      }
      return b;
    } catch (_) {
      return false;
    }
  }

  // ── Private ────────────────────────────────────────────────────────────────

  void _setState(AttendanceLoadState s) {
    _state = s;
    notifyListeners();
  }

  void clearChanges() {
    changes.clear();
    notifyListeners();
  }
}
