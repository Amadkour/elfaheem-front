// lib/features/student/analysis/student_analytics_api.dart
// Every request of the student analytics module in one place:
//   enrolments · attendance · exams  (platform data)
//   analytics profile                (Data Lab: progress, flags, the marks the teacher published, class averages)
import 'package:flutter/foundation.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/courses/course_scope.dart' show modeCourseScopeQuery;

import 'package:flutter_education_app/features/attendance/analysis/teacher/attendance_model.dart';
import '../../teacher/data_lab/data_lab_api.dart';
import '../../teacher/data_lab/data_lab_models.dart';
import 'package:flutter_education_app/features/attendance/analysis/student/student_attendance_model.dart';

class StudentAnalyticsApi {
  StudentAnalyticsApi({ApiClient? api, DataLabApi? dataLab})
      : _api = api ?? ApiClient(),
        _lab = dataLab ?? DataLabApi(api: api);

  final ApiClient _api;
  final DataLabApi _lab;

  /// Accepts a bare list OR a wrapped one: {items|courses|enrollments|data: [...]}.
  static List? _list(dynamic r) => r is List
      ? r
      : (r is Map ? (r['items'] ?? r['courses'] ?? r['enrollments'] ?? r['exams'] ?? r['data']) as List? : null);

  // ── My enrolled courses ───────────────────────────────────────────────────
  Future<List<EnrolledCourse>> fetchMyEnrollments() async {
    dynamic r;
    try {
      // the mode's side (the server's default is the personal account)
      r = await _api.get('/api/v1/my-enrolled-courses', queryParams: {'limit': 100, ...modeCourseScopeQuery()});
    } on ApiException catch (e) {
      if (e.statusCode != 404) rethrow; // route name differs on some backends
      r = await _api.get('/api/v1/my-enrollments');
    }
    return parseEnrollments(r);
  }

  /// The courses of a `GET /my-enrolled-courses` answer, each with the enrolment's live progress (pure, tested on the
  /// real payload in test/fixtures/real/).
  static List<EnrolledCourse> parseEnrollments(dynamic r) {
    final list = _list(r);
    if (list == null) {
      debugPrint('my-enrolled-courses: unexpected response ${r.runtimeType}');
      return [];
    }
    final out = <EnrolledCourse>[];
    for (final e in list) {
      if (e is! Map) continue;
      try {
        final j = e.cast<String, dynamic>();
        final courseJson = (j['course'] as Map?)?.cast<String, dynamic>() ?? j;
        final progress = ((j['progress'] ?? j['progress_percentage'] ?? courseJson['progress']) as num?)?.round() ?? 0;
        out.add(EnrolledCourse.fromCourseJson(courseJson, progress));
      } catch (err) {
        debugPrint('my-enrolled-courses: skipped item ($err): $e'); // one bad item must not hide the others
      }
    }
    return out;
  }

  // ── My attendance for one course ──────────────────────────────────────────
  Future<List<FullAttendance>> fetchMyCourseAttendance(int courseId) async {
    final list = _list(await _api.get('/api/v1/sessions/$courseId/course_attendance/me'));
    if (list == null) return [];
    return list.whereType<Map>().map((e) => FullAttendance.fromJson(e.cast<String, dynamic>())).toList();
  }

  // ── My exams (all courses, or one) ────────────────────────────────────────
  Future<List<StudentExamSummary>> fetchMyExams({int? courseId}) async {
    final list = _list(await _api.get('/api/v1/student/exams'));
    if (list == null) return [];
    final out = <StudentExamSummary>[];
    for (final e in list.whereType<Map>()) {
      try {
        final x = StudentExamSummary.fromJson(e.cast<String, dynamic>());
        if (courseId == null || x.courseId == courseId) out.add(x);
      } catch (err) {
        debugPrint('student/exams: skipped item ($err)');
      }
    }
    return out;
  }

  @Deprecated('Use fetchMyExams(courseId: …)')
  Future<List<StudentExamSummary>> fetchMyExamsForCourse(int courseId) => fetchMyExams(courseId: courseId);

  // ── Analytics profile (Data Lab) ──────────────────────────────────────────
  /// The student's own profile: overall numbers + one block per course (progress, attendance, exams, flags and the
  /// marks the teacher published, each with the class average).
  /// Returns null — never throws — when Data Lab is switched off or the profile is not available: the rest of the
  /// analytics still work without it.
  Future<DlProfile?> fetchMyProfile({int? courseId}) async {
    try {
      final p = await _lab.myProfile(courseId: courseId, lang: AppConfig.lang);
      return p;
    } catch (e) {
      debugPrint('analytics profile not available: $e');
      return null;
    }
  }
}
