
// ── Enrolled course summary (for the hub screen) ──────────────────────────────
// Derived from CourseModel, carries only what the analytics hub needs.

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

  // Built from the CourseModel returned by my-enrollments
  factory EnrolledCourse.fromCourseJson(
    Map<String, dynamic> course,
    int progress,
  ) =>
      EnrolledCourse(
        id: int.parse(course['id'].toString()),
        title: course['course_name'] as String? ?? '',
        imageUrl: course['image_url'] as String?,
        teacherName: course['course_teacher_name'] as String?,

        sessionsCount: course['sessions_count'] as int? ?? 0,
        progress: progress,
      );
}

// ── Student exam summary ──────────────────────────────────────────────────────
// Re-declared here to keep the student module self-contained.
// Populated from GET /api/v1/student/exams (filtered to one course).

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

  factory StudentExamSummary.fromJson(Map<String, dynamic> j) =>
      StudentExamSummary(
        examId: j['id'] as int,
        examName: j['name'] as String,
        courseId: j['course_id'] as int?,
        courseName: j['course_name'] as String?,
        startDate: j['start_date'] != null
            ? DateTime.tryParse(j['start_date'] as String)
            : null,
        duration: j['duration'] as int?,
        totalMarks: (j['total_marks'] as num?)?.toDouble(),
        passingScore: (j['passing_score'] as num?)?.toDouble(),
        marksObtained: (j['marks_obtained'] as num?)?.toDouble(),
        percentage: (j['percentage'] as num?)?.toDouble().floorToDouble(),
        passed: j['passed'] as bool?,
        attempted: j['attempted'] as bool? ?? false,
      );

  String get statusLabel {
    if (attempted) return passed == true ? 'نجحت ✓' : 'راسب ✗';
    if (startDate != null && startDate!.isAfter(DateTime.now())) return 'قادم';
    return 'لم تؤدِّه';
  }
}
