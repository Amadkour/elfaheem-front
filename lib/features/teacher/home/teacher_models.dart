/// shared/teacher_models.dart
///
/// Data models used across the teacher feature.
/// ScheduleSession now matches the dashboard_service.py output which is
/// derived from CourseSchedule (not SessionModel.scheduled_at).
library;

import 'package:flutter_education_app/features/student/models.dart';

import '../courses/component/teacher_stats.dart';

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

  /// Lightweight constructor for pending (not-yet-saved) entries.
  factory CourseSchedule.pending({
    required String day,
    required String startTime,
    required String endTime,
  }) =>
      CourseSchedule(
        id: -1,
        courseId: -1,
        day: day,
        startTime: startTime,
        endTime: endTime,
      );

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
      name: j['title'] as String? ?? '',
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

// ─────────────────────────────────────────────
//  ScheduleSession
//  Represents one upcoming slot from dashboard_service._get_upcoming_sessions()
//  Fields match the dict the Python method returns.
// ─────────────────────────────────────────────

// ── ScheduleSession model (updated) ──────────────────────────────────────────

class ScheduleSession {
  // Identity
  final int scheduleId;
  final int courseId;
  final String courseName;
  final String? courseImage;

  // When
  final String day;
  final String dayLabel;
  final String startTime;
  final String endTime;
  final DateTime scheduledDate;

  // Duration & capacity
  final int durationMinutes;
  final int? maxStudents;

  // Live state
  final bool isToday;
  final bool isOngoing;
  final int? minutesUntilStart;
  final int? minutesUntilEnd;

  // ── NEW: live session fields returned by the updated backend ──────────────
  final int? sessionId; // SessionModel.id  – null if not yet created
  final int? onlineSessionId; // OnlineSession.id – null if not yet created
  final String? roomName; // LiveKit room name
  final String? provider; // 'livekit' | 'zoom' | …
  final bool isLive; // OnlineSession.is_active
  final String? joinUrl; // OnlineSession.url  (room join URL)
  final String? hostUrl; // OnlineSession.host_url
  final String? token; // OnlineSession.host_url

  static const _labels = {
    'monday': 'الاثنين',
    'tuesday': 'الثلاثاء',
    'wednesday': 'الأربعاء',
    'thursday': 'الخميس',
    'friday': 'الجمعة',
    'saturday': 'السبت',
    'sunday': 'الأحد',
  };

  /// Convenience: a session can be joined when it has been created AND
  /// it is today (or ongoing).
  bool get canJoinNow =>
      sessionId != null && (isOngoing || isToday) && joinUrl != null;

  String get defaultSessionName => '$courseName – $dayLabel $startTime';

  const ScheduleSession({
    required this.scheduleId,
    required this.courseId,
    required this.courseName,
    required this.day,
    required this.dayLabel,
    required this.startTime,
    required this.endTime,
    required this.durationMinutes,
    required this.isToday,
    required this.isOngoing,
    this.courseImage,
    required this.scheduledDate,
    this.maxStudents,
    this.minutesUntilStart,
    this.minutesUntilEnd,
    // new
    this.sessionId,
    this.onlineSessionId,
    this.roomName,
    this.provider,
    this.isLive = false,
    this.joinUrl,
    this.hostUrl,
    this.token,
  });

  factory ScheduleSession.fromJson(Map<String, dynamic> j) {
    final day = j['day'] as String;
    return ScheduleSession(
      scheduleId: j['schedule_id'] as int,
      courseId: j['course_id'] as int,
      courseName: j['course_name'] as String,
      courseImage: j['course_image'] as String?,
      day: day,
      dayLabel: j['day_label'] as String? ?? _labels[day] ?? day,
      startTime: j['start_time'] as String,
      endTime: j['end_time'] as String,
      scheduledDate: DateTime.parse(j['scheduled_date'] as String),
      durationMinutes: j['duration_minutes'] as int? ?? 0,
      maxStudents: j['max_students'] as int?,
      isToday: j['is_today'] as bool? ?? false,
      isOngoing: j['is_ongoing'] as bool? ?? false,
      minutesUntilStart: j['minutes_until_start'] as int?,
      minutesUntilEnd: j['minutes_until_end'] as int?,
      // new
      sessionId: j['session_id'] as int?,
      onlineSessionId: j['online_session_id'] as int?,
      roomName: j['room_name'] as String?,
      provider: j['provider'] as String?,
      isLive: j['is_live'] as bool? ?? false,
      joinUrl: j['join_url'] as String?,
      hostUrl: j['host_url'] as String?,
      token: j['token'] as String?,
    );
  }
}

// ── TeacherCourse ─────────────────────────────────────────────────────────────
class TeacherCourse {
  final int id, studentsCount, sessionsCount;
  final String title, imageUrl, type;
  final double totalHours, averageRating, price, progress,expectedHours;
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
    required this.progress,
    required this.expectedHours,
  });

  factory TeacherCourse.fromJson(Map<String, dynamic> j) => TeacherCourse(
        id: j['id'] as int,
        title: j['name'] as String? ?? '',
        imageUrl: j['image_url'] as String? ?? '',
        studentsCount: j['students_count'] as int? ?? 0,
        expectedHours: j['expected_hours'] as double? ?? 0.0,
        sessionsCount: j['sessions_count'] as int? ?? 0,
        averageRating: (j['average_rating'] as num?)?.toDouble() ?? 0.0,
        totalHours: (j['total_hours'] as num?)?.toDouble() ?? 0,
        price: (j['fees'] as num?)?.toDouble() ?? 0,
        progress: (j['progress'] as num?)?.toDouble() ?? 0.0,
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

  CourseModel get toCourseModel => CourseModel(
        id: id.toString(),
        name: title,
        imageUrl: imageUrl,
        price: price,
        progress: progress,
        type: type,
        isEnrolled: false,
        averageRating: averageRating,
        certificates: certificates,
        tools: tools,
        prerequisites: prerequisites,
        schedules: schedules,
        description: description,
        studentsCount: studentsCount,
        sessionsCount: sessionsCount,
        totalHours: totalHours,
        expectedHours: expectedHours,
        categoryName: categoryName,
        isPublished: isPublished,
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
          progress: progress,
          imageUrl: imageUrl ?? this.imageUrl,
          totalHours: totalHours,
          type: type,
          expectedHours: expectedHours,
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
    return TeacherDashboardData(
        stats: TeacherStats.fromJson(j),
        courses: (j['courses'] as List? ?? [])
            .map((e) => TeacherCourse.fromJson(e as Map<String, dynamic>))
            .toList(),
        schedule:
            (j['schedule'] as List? ?? j['upcoming_sessions'] as List? ?? [])
                .map((e) => ScheduleSession.fromJson(e as Map<String, dynamic>))
                .toList());
  }
}
