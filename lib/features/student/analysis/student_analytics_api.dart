// features/student/analytics/student_analytics_api.dart
import 'package:flutter/foundation.dart';
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
    dynamic r;
    try {
      r = await _api.get('/api/v1/my-enrolled-courses');
    } on ApiException catch (e) {
      // Route name differs on some backends → try the documented one.
      if (e.statusCode != 404) rethrow;
      r = await _api.get('/api/v1/my-enrollments');
    }

    // Accept a bare list OR a wrapped one: {items|courses|data|enrollments: [...]}
    final list = r is List
        ? r
        : (r is Map
        ? (r['items'] ?? r['courses'] ?? r['enrollments'] ?? r['data'])
        : null);
    if (list is! List) {
      debugPrint('my-enrolled-courses: unexpected response ${r.runtimeType}');
      return [];
    }

    final out = <EnrolledCourse>[];
    for (final e in list) {
      if (e is! Map) continue;
      try {
        final j = e.cast<String, dynamic>();
        final courseJson =
            (j['course'] as Map?)?.cast<String, dynamic>() ?? j;
        final progress = ((j['progress'] ??
            j['progress_percentage'] ??
            courseJson['progress']) as num?)
            ?.toInt() ??
            0;
        out.add(EnrolledCourse.fromCourseJson(courseJson, progress));
      } catch (err) {
        // One malformed item must not hide every other course.
        debugPrint('my-enrolled-courses: skipped item ($err): $e');
      }
    }
    return out;
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