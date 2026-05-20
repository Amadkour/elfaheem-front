import 'package:flutter_education_app/core/api_client.dart';
import 'attendance_model.dart';

class TeacherAttendanceApi {
  final ApiClient _api;

  TeacherAttendanceApi({ApiClient? api}) : _api = api ?? ApiClient();

  Future<List<FullAttendance>> fetchCourseAttendance(int courseId) async {
    final data = await _api.get('/api/v1/sessions/$courseId/course_attendance');
    if (data is! List) return [];
    return (data)
        .cast<Map<String, dynamic>>()
        .map(FullAttendance.fromJson)
        .toList();
  }
  Future<List<FullAttendance>> fetchMyCourseAttendance(int courseId) async {
    final data = await _api.get('/api/v1/sessions/$courseId/course_attendance/me');
    if (data is! List) return [];
    return (data)
        .cast<Map<String, dynamic>>()
        .map(FullAttendance.fromJson)
        .toList();
  }

  Future<bool> forceAttendance(int sessionId, int studentId, bool value) async {
    final data = await _api.get('/api/v1/live-sessions/$sessionId/force_attend',
        queryParams: {'student_id': studentId, 'attendance': value});
    if (data is! bool) return false;
    return data;
  }
}
