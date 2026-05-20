// features/student/analytics/student_analytics_api.dart
import 'package:flutter_education_app/core/api_client.dart';
import '../../teacher/analysis/attendance/attendance_model.dart';
import 'attendance/student_attendance_model.dart';

class StudentAnalyticsApi {
  final ApiClient _api;
  StudentAnalyticsApi({ApiClient? api}) : _api = api ?? ApiClient();

  // ── My enrolled courses ───────────────────────────────────────────────────
  // GET /api/v1/my-enrollments
  // Returns a list of enrollment objects, each containing a nested `course`.
  // Response item shape:
  //   { "progress": float, "course": { CourseModel fields } }
  Future<List<EnrolledCourse>> fetchMyEnrollments() async {
    final r = await _api.get('/api/v1/my-enrolled-courses');
    if (r is! List) return [];
    return (r).map((e) {
      final j = e as Map<String, dynamic>;
      final courseJson = j['course'] as Map<String, dynamic>? ?? j;
      final progress = (j['progress'] as num?)?.toDouble() ?? 0.0;
      return EnrolledCourse.fromCourseJson(courseJson, progress);
    }).toList();
  }

  // ── My attendance for one course ──────────────────────────────────────────
  // GET /api/v1/sessions/{courseId}/course_attendance/me
  // Returns a list of FullAttendance — one entry per session in the course.
  Future<List<FullAttendance>> fetchMyCourseAttendance(int courseId) async {
    final data =
        await _api.get('/api/v1/sessions/$courseId/course_attendance/me');
    if (data is! List) return [];
    return (data)
        .cast<Map<String, dynamic>>()
        .map(FullAttendance.fromJson)
        .toList();
  }

  // ── My exams for one course ───────────────────────────────────────────────
  // GET /api/v1/student/exams  (returns all courses; we filter by courseId)
  Future<List<StudentExamSummary>> fetchMyExamsForCourse(int courseId) async {
    final data = await _api.get('/api/v1/student/exams');
    if (data is! List) return [];
    return (data)
        .cast<Map<String, dynamic>>()
        .map(StudentExamSummary.fromJson)
        .where((e) => e.courseId == courseId)
        .toList();
  }
}
