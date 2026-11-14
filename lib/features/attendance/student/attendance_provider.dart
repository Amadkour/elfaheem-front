/// attendance/attendance_provider.dart
/// Student self-attendance state. Wraps SessionsProvider attendance calls
/// and persists check-in state per session across the session detail flow.
library;
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/base_provider.dart';
import 'package:flutter_education_app/features/home/student/models.dart';

class StudentAttendanceProvider extends BaseProvider {
  final ApiClient _api;
  StudentAttendanceProvider({ApiClient? api}) : _api = api ?? ApiClient();

  // sessionId → AttendanceRecord
  final Map<int,AttendanceRecord> _records = {};
  int? _activeSessionId;

  AttendanceRecord? get activeRecord =>
      _activeSessionId!=null?_records[_activeSessionId]:null;
  bool get isCheckedIn => activeRecord?.isCheckedIn??false;

  void setActiveSession(int sessionId) {
    _activeSessionId=sessionId; notifyListeners();
  }

  Future<bool> checkIn(int sessionId) async {
    final r=await run(()=>_api.post('/api/v1/attendance/check-in',
        queryParams:{'session_id':sessionId}));
    if(r!=null){
      _records[sessionId]=AttendanceRecord(sessionId:sessionId,isCheckedIn:true,
          checkInAt:DateTime.now().toIso8601String());
      notifyListeners();return true;
    }
    return false;
  }

  Future<bool> checkOut(int sessionId) async {
    final r=await run(()=>_api.post('/api/v1/attendance/check-out',
        queryParams:{'session_id':sessionId}));
    if(r!=null){
      final existing=_records[sessionId];
      _records[sessionId]=AttendanceRecord(sessionId:sessionId,isCheckedIn:false,
          checkInAt:existing?.checkInAt,checkOutAt:DateTime.now().toIso8601String());
      notifyListeners();return true;
    }
    return false;
  }
}
