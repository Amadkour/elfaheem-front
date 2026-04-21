/// shared/teacher_models.dart
///
/// Data models used across the teacher feature.
/// ScheduleSession now matches the dashboard_service.py output which is
/// derived from CourseSchedule (not SessionModel.scheduled_at).
library;

class CourseSchedule {
  final int id;
  final int courseId;
  final String day, startTime, endTime;

  const CourseSchedule(
      {required this.id,
      required this.courseId,
      required this.day,
      required this.startTime,
      required this.endTime});

  String get dayLabel =>
      const {
        'monday': 'الإثنين',
        'tuesday': 'الثلاثاء',
        'wednesday': 'الأربعاء',
        'thursday': 'الخميس',
        'friday': 'الجمعة',
        'saturday': 'السبت',
        'sunday': 'الأحد'
      }[day] ??
      day;

  factory CourseSchedule.fromJson(Map<String, dynamic> j) => CourseSchedule(
      id: j['id'] as int,
      courseId: j['course_id'] as int? ?? 0,
      day: j['day'] as String? ?? '',
      startTime: j['start_time'] as String? ?? '',
      endTime: j['end_time'] as String? ?? '');
}

// ── CourseCertificate ─────────────────────────────────────────────────────────
class CourseCertificate {
  final int id, courseId;
  final String title;
  final String? description;

  const CourseCertificate(
      {required this.id,
      required this.courseId,
      required this.title,
      this.description});

  factory CourseCertificate.fromJson(Map<String, dynamic> j) =>
      CourseCertificate(
          id: j['id'] as int,
          courseId: j['course_id'] as int? ?? 0,
          title: j['title'] as String? ?? '',
          description: j['description'] as String?);
}

// ── CourseTool ────────────────────────────────────────────────────────────────
class CourseTool {
  final int id, courseId;
  final String name;
  final String? description;

  const CourseTool(
      {required this.id,
      required this.courseId,
      required this.name,
      this.description});

  factory CourseTool.fromJson(Map<String, dynamic> j) => CourseTool(
      id: j['id'] as int,
      courseId: j['course_id'] as int? ?? 0,
      name: j['name'] as String? ?? '',
      description: j['description'] as String?);
}

// ── CoursePrerequisite ────────────────────────────────────────────────────────
class CoursePrerequisite {
  final int id, courseId;
  final String title;
  final String? description;

  const CoursePrerequisite(
      {required this.id,
      required this.courseId,
      required this.title,
      this.description});

  factory CoursePrerequisite.fromJson(Map<String, dynamic> j) =>
      CoursePrerequisite(
          id: j['id'] as int,
          courseId: j['course_id'] as int? ?? 0,
          title: j['title'] as String? ?? '',
          description: j['description'] as String?);
}

// ─────────────────────────────────────────────
//  TeacherStats
// ─────────────────────────────────────────────
enum TeacherCourseStatus { all, published, draft }
class TeacherStats {
  final double overallRating;
  final int    totalStudents;
  final int    totalCourses;

  const TeacherStats({
    required this.overallRating,
    required this.totalStudents,
    required this.totalCourses,
  });

  factory TeacherStats.fromJson(Map<String, dynamic> j) => TeacherStats(
    overallRating: (j['overall_rating'] as num?)?.toDouble() ?? 0.0,
    totalStudents: j['total_students'] as int? ?? 0,
    totalCourses:  j['total_courses']  as int? ?? 0,
  );

  static const empty = TeacherStats(
      overallRating: 0, totalStudents: 0, totalCourses: 0);
}

// ─────────────────────────────────────────────
//  ScheduleSession
//  Represents one upcoming slot from dashboard_service._get_upcoming_sessions()
//  Fields match the dict the Python method returns.
// ─────────────────────────────────────────────

class ScheduleSession {
  // Identity
  final int    scheduleId;
  final int    courseId;
  final String courseName;
  final String? courseImage;

  // When
  final String  day;            // 'monday' … 'sunday'
  final String  dayLabel;       // Arabic label (localised server-side or client-side)
  final String  startTime;      // 'HH:MM'
  final String  endTime;        // 'HH:MM'
  final String? scheduledDate;  // 'YYYY-MM-DD' — concrete date of next occurrence

  // Duration & capacity
  final int  durationMinutes;
  final int? maxStudents;

  // Live state
  final bool isToday;
  final bool isOngoing;
  final int? minutesUntilStart; // null → other day; ≤0 → already started
  final int? minutesUntilEnd;   // non-null only when isOngoing

  // Day labels map (fallback when server sends English key only)
  static const _labels = {
    'monday': 'الاثنين', 'tuesday': 'الثلاثاء',
    'wednesday': 'الأربعاء', 'thursday': 'الخميس',
    'friday': 'الجمعة', 'saturday': 'السبت', 'sunday': 'الأحد',
  };

  const ScheduleSession({
    required this.scheduleId, required this.courseId,
    required this.courseName, required this.day,
    required this.dayLabel, required this.startTime,
    required this.endTime, required this.durationMinutes,
    required this.isToday, required this.isOngoing,
    this.courseImage, this.scheduledDate,
    this.maxStudents, this.minutesUntilStart, this.minutesUntilEnd,
  });

  factory ScheduleSession.fromJson(Map<String, dynamic> j) {
    final day = j['day'] as String;
    return ScheduleSession(
      scheduleId:        j['schedule_id']        as int,
      courseId:          j['course_id']           as int,
      courseName:        j['course_name']         as String,
      courseImage:       j['course_image']        as String?,
      day:               day,
      dayLabel:          j['day_label']           as String? ??
                         _labels[day] ?? day,
      startTime:         j['start_time']          as String,
      endTime:           j['end_time']            as String,
      scheduledDate:     j['scheduled_date']      as String?,
      durationMinutes:   j['duration_minutes']    as int? ?? 0,
      maxStudents:       j['max_students']        as int?,
      isToday:           j['is_today']            as bool? ?? false,
      isOngoing:         j['is_ongoing']          as bool? ?? false,
      minutesUntilStart: j['minutes_until_start'] as int?,
      minutesUntilEnd:   j['minutes_until_end']   as int?,
    );
  }

  // ── Derived helpers ────────────────────────────────────────────────

  /// Human-readable "when" label shown on the card.
  String get whenLabel {
    if (isOngoing) {
      final left = minutesUntilEnd ?? 0;
      if (left <= 0) return 'انتهت للتو';
      return 'جارية — تنتهي بعد $leftد';
    }
    if (!isToday) {
      return scheduledDate != null
          ? '$dayLabel  $startTime'
          : dayLabel;
    }
    final mu = minutesUntilStart ?? 0;
    if (mu <= 0) return 'بدأت للتو';
    if (mu < 60) return 'اليوم — بعد $muد';
    return 'اليوم — بعد ${mu ~/ 60}س${mu % 60 > 0 ? " ${mu % 60}د" : ""}';
  }

  /// Default session name to pre-fill the "create session" form.
  String get defaultSessionName =>
      'حصة $dayLabel — $startTime';
}


// ── TeacherCourse ─────────────────────────────────────────────────────────────
class TeacherCourse {
  final int id, studentsCount, sessionsCount;
  final String title, imageUrl, type;
  final double totalHours, averageRating, price;
  final String? categoryName, description;
  final bool isPublished;
  final List<CourseSchedule> schedules;
  final List<CourseCertificate> certificates;
  final List<CourseTool> tools;
  final List<CoursePrerequisite> prerequisites;

  const TeacherCourse({
    required this.id,
    required this.title,
    required this.imageUrl,
    required this.totalHours,
    required this.type,
    this.studentsCount = 0,
    this.sessionsCount = 0,
    this.averageRating = 0.0,
    this.price = 0,
    this.categoryName,
    this.isPublished = false,
    this.description,
    this.schedules = const [],
    this.certificates = const [],
    this.tools = const [],
    this.prerequisites = const [],
  });

  factory TeacherCourse.fromJson(Map<String, dynamic> j) => TeacherCourse(
        id: j['id'] as int,
        title: j['name'] as String? ?? '',
        imageUrl: j['image_url'] as String? ?? j['logo_url'] as String? ?? '',
        studentsCount: j['students_count'] as int? ?? 0,
        sessionsCount: j['sessions_count'] as int? ?? 0,
        averageRating: (j['average_rating'] as num?)?.toDouble() ?? 0.0,
        totalHours: (j['total_hours'] as num?)?.toDouble() ?? 0,
        price: (j['fees'] as num?)?.toDouble() ?? 0,
        categoryName:
            (j['category'] as Map<String, dynamic>?)?['name'] as String?,
        isPublished: j['is_published'] as bool? ?? false,
        description: j['description'] as String?,
        type: j['type'] as String? ?? 'recorded',
        schedules: (j['schedules'] as List? ?? [])
            .map((e) => CourseSchedule.fromJson(e as Map<String, dynamic>))
            .toList(),
        certificates: (j['certificates'] as List? ?? [])
            .map((e) => CourseCertificate.fromJson(e as Map<String, dynamic>))
            .toList(),
        tools: (j['tools'] as List? ?? [])
            .map((e) => CourseTool.fromJson(e as Map<String, dynamic>))
            .toList(),
        prerequisites: (j['prerequisites'] as List? ?? [])
            .map((e) => CoursePrerequisite.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  TeacherCourse copyWith(
          {bool? isPublished,
          String? imageUrl,
          List<CourseSchedule>? schedules,
          List<CourseCertificate>? certificates,
          List<CourseTool>? tools,
          List<CoursePrerequisite>? prerequisites}) =>
      TeacherCourse(
          id: id,
          title: title,
          imageUrl: imageUrl ?? this.imageUrl,
          totalHours: totalHours,
          type: type,
          studentsCount: studentsCount,
          sessionsCount: sessionsCount,
          averageRating: averageRating,
          price: price,
          categoryName: categoryName,
          isPublished: isPublished ?? this.isPublished,
          description: description,
          schedules: schedules ?? this.schedules,
          certificates: certificates ?? this.certificates,
          tools: tools ?? this.tools,
          prerequisites: prerequisites ?? this.prerequisites);
}

// ── TeacherDashboardData ──────────────────────────────────────────────────────
class TeacherDashboardData {
  final TeacherStats stats;
  final List<TeacherCourse> courses;
  final List<ScheduleSession> schedule;

  const TeacherDashboardData(
      {required this.stats, required this.courses, required this.schedule});

  factory TeacherDashboardData.fromJson(Map<String, dynamic> j) {
    final s = j['stats'] as Map<String, dynamic>? ?? {};
    return TeacherDashboardData(
        stats: TeacherStats.fromJson(s),
        courses: (j['courses'] as List? ?? [])
            .map((e) => TeacherCourse.fromJson(e as Map<String, dynamic>))
            .toList(),
        schedule:
            (j['schedule'] as List? ?? j['upcoming_sessions'] as List? ?? [])
                .map((e) => ScheduleSession.fromJson(e as Map<String, dynamic>))
                .toList());
  }
}