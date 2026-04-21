/// shared/attendance_provider.dart
/// Student check-in/out + teacher fetch list + teacher manual override.
///
/// API:
///   POST /api/v1/attendance/check-in?session_id={}     student
///   POST /api/v1/attendance/check-out?session_id={}    student
///   GET  /api/v1/sessions/{id}/attendance              teacher: per-session list
library;
import '../../../core/api_client.dart';
import '../../../core/base_provider.dart';
import 'live_models.dart';

class AttendanceProvider extends BaseProvider {
  final ApiClient _api;
  AttendanceProvider({ApiClient? api}) : _api = api ?? ApiClient();

  // student state
  final Map<int, bool>              _checkedIn = {};
  final Map<int, AttendanceRecord?> _myRecords = {};
  // teacher state
  List<AttendanceDetail>  _list       = [];
  bool                    _listLoading = false;

  bool isCheckedIn(int sid)           => _checkedIn[sid] ?? false;
  AttendanceRecord? myRecord(int sid) => _myRecords[sid];
  List<AttendanceDetail> get list     => List.unmodifiable(_list);
  bool get listLoading                => _listLoading;
  int get presentCount  => _list.where((r) => r.isPresent).length;
  int get absentCount   => _list.where((r) => !r.isPresent).length;

  // ── Student ─────────────────────────────────────────────────────────────────
  Future<bool> checkIn(int sessionId) async {
    final r = await run(()=>_api.post('/api/v1/attendance/check-in',
        queryParams:{'session_id':sessionId}));
    if (r != null) {
      _checkedIn[sessionId] = true;
      if (r is Map<String,dynamic>) _myRecords[sessionId] = AttendanceRecord.fromJson(r);
      notifyListeners(); return true;
    }
    return false;
  }

  Future<bool> checkOut(int sessionId) async {
    final r = await run(()=>_api.post('/api/v1/attendance/check-out',
        queryParams:{'session_id':sessionId}));
    if (r != null) {
      _checkedIn[sessionId] = false;
      if (r is Map<String,dynamic>) _myRecords[sessionId] = AttendanceRecord.fromJson(r);
      notifyListeners(); return true;
    }
    return false;
  }

  // ── Teacher ──────────────────────────────────────────────────────────────────
  Future<void> fetchList(int sessionId) async {
    _listLoading = true; notifyListeners();
    final r = await run(()=>_api.get('/api/v1/sessions/$sessionId/attendance'));
    _listLoading = false;
    if (r is Map && r['attendance'] is List) {
      _list = (r['attendance'] as List)
          .map((e) => AttendanceDetail.fromJson(e as Map<String,dynamic>))
          .toList();
    }
    notifyListeners();
  }

  /// Teacher manually marks a student present (creates attendance record server-side).
  /// Uses the same check-in endpoint with admin privileges.
  Future<bool> manualCheckIn(int sessionId, int studentId) async {
    final r = await run(()=>_api.post('/api/v1/attendance/teacher/check-in',
        queryParams:{'session_id':sessionId,'student_id':studentId}));
    if (r != null) {
      // Refresh the list
      await fetchList(sessionId);
      return true;
    }
    return false;
  }

  void resetState() { _list = []; _listLoading = false; notifyListeners(); }
}
