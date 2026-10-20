// lib/features/student/analysis/attendance/student_attendance_model.dart
// Models of the student analytics module (attendance itself uses FullAttendance from the teacher module).
import 'package:flutter_education_app/config/app_config.dart';

int _int(dynamic v, [int d = 0]) => v is num ? v.toInt() : (int.tryParse('${v ?? ''}') ?? d);
int? _intOrNull(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
double? _dbl(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');

// ── Enrolled course summary (for the hub screen) ──────────────────────────────

class EnrolledCourse {
  final int id;
  final String title;
  final String? imageUrl;
  final String? teacherName;
  final int sessionsCount;
  final int progress;

  EnrolledCourse({
    required this.id,
    required this.title,
    this.imageUrl,
    this.teacherName,
    this.sessionsCount = 0,
    this.progress = 0,
  });

  factory EnrolledCourse.fromCourseJson(Map<String, dynamic> course, int progress) {
    final other = AppConfig.lang == 'ar' ? 'en' : 'ar';
    final title = (course['name_${AppConfig.lang}'] ?? course['name_$other'] ?? course['name'] ?? '').toString();
    return EnrolledCourse(
      id: _int(course['id']),
      title: title,
      imageUrl: course['image_url'] as String?,
      teacherName: (course['course_teacher_name'] ?? course['teacher_name']) as String?,
      sessionsCount: _int(course['sessions_count']),
      progress: progress.clamp(0, 100).toInt(),
    );
  }
}

// ── Student exam summary ──────────────────────────────────────────────────────
// Populated from GET /api/v1/student/exams.

class StudentExamSummary {
  final int examId;
  final String examName;
  final int? courseId;
  final String? courseName;
  final DateTime? startDate;
  final int? duration;
  final double? totalMarks;
  final double? passingScore;
  final double? marksObtained;
  final double? percentage;
  final bool? passed;
  final bool attempted;

  StudentExamSummary({
    required this.examId,
    required this.examName,
    this.courseId,
    this.courseName,
    this.startDate,
    this.duration,
    this.totalMarks,
    this.passingScore,
    this.marksObtained,
    this.percentage,
    this.passed,
    required this.attempted,
  });

  factory StudentExamSummary.fromJson(Map<String, dynamic> j) => StudentExamSummary(
    examId: _int(j['id']),
    examName: '${j['name'] ?? ''}',
    courseId: _intOrNull(j['course_id']),
    courseName: j['course_name'] as String?,
    startDate: DateTime.tryParse('${j['start_date'] ?? ''}')?.toLocal(),
    duration: _intOrNull(j['duration']),
    totalMarks: _dbl(j['total_marks']),
    passingScore: _dbl(j['passing_score']),
    marksObtained: _dbl(j['marks_obtained']),
    // keep one decimal: 59.96 must not be shown as 59 next to a 60 % pass mark
    percentage: _dbl(j['percentage']) == null ? null : (_dbl(j['percentage'])! * 10).floorToDouble() / 10,
    passed: j['passed'] as bool?,
    attempted: j['attempted'] == true,
  );

  bool get isUpcoming => !attempted && startDate != null && startDate!.isAfter(DateTime.now());

  /// Localised status (it used to be hard-coded Arabic).
  String get statusLabel {
    if (attempted) return passed == true ? 'sa_status_passed'.tr : 'sa_status_failed'.tr;
    if (isUpcoming) return 'sa_status_upcoming'.tr;
    return 'sa_status_not_taken'.tr;
  }
}
