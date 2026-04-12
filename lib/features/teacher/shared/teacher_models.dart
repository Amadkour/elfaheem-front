// /// shared/teacher_models.dart
// /// Single source of truth for all teacher data models.
// library;
//
// enum TeacherCourseStatus { all, published, draft }
//
// // ── TeacherStats ──────────────────────────────────────────────────────────────
// class TeacherStats {
//   final double overallRating;
//   final int totalStudents;
//   final int totalCourses;
//
//   const TeacherStats(
//       {this.overallRating = 0.0,
//       this.totalStudents = 0,
//       this.totalCourses = 0});
//
//   factory TeacherStats.fromJson(Map<String, dynamic> j) => TeacherStats(
//         overallRating: (j['overall_rating'] as num?)?.toDouble() ??
//             (j['rating'] as num?)?.toDouble() ??
//             0.0,
//         totalStudents: j['total_students'] as int? ?? 0,
//         totalCourses: j['total_courses'] as int? ?? 0,
//       );
// }
//
// // ── CourseSchedule ────────────────────────────────────────────────────────────
// class CourseSchedule {
//   final int id;
//   final int courseId;
//   final String day, startTime, endTime;
//
//   const CourseSchedule(
//       {required this.id,
//       required this.courseId,
//       required this.day,
//       required this.startTime,
//       required this.endTime});
//
//   String get dayLabel =>
//       const {
//         'monday': 'الإثنين',
//         'tuesday': 'الثلاثاء',
//         'wednesday': 'الأربعاء',
//         'thursday': 'الخميس',
//         'friday': 'الجمعة',
//         'saturday': 'السبت',
//         'sunday': 'الأحد'
//       }[day] ??
//       day;
//
//   factory CourseSchedule.fromJson(Map<String, dynamic> j) => CourseSchedule(
//       id: j['id'] as int,
//       courseId: j['course_id'] as int? ?? 0,
//       day: j['day'] as String? ?? '',
//       startTime: j['start_time'] as String? ?? '',
//       endTime: j['end_time'] as String? ?? '');
// }
//
// // ── CourseCertificate ─────────────────────────────────────────────────────────
// class CourseCertificate {
//   final int id, courseId;
//   final String title;
//   final String? description;
//
//   const CourseCertificate(
//       {required this.id,
//       required this.courseId,
//       required this.title,
//       this.description});
//
//   factory CourseCertificate.fromJson(Map<String, dynamic> j) =>
//       CourseCertificate(
//           id: j['id'] as int,
//           courseId: j['course_id'] as int? ?? 0,
//           title: j['title'] as String? ?? '',
//           description: j['description'] as String?);
// }
//
// // ── CourseTool ────────────────────────────────────────────────────────────────
// class CourseTool {
//   final int id, courseId;
//   final String name;
//   final String? description;
//
//   const CourseTool(
//       {required this.id,
//       required this.courseId,
//       required this.name,
//       this.description});
//
//   factory CourseTool.fromJson(Map<String, dynamic> j) => CourseTool(
//       id: j['id'] as int,
//       courseId: j['course_id'] as int? ?? 0,
//       name: j['name'] as String? ?? '',
//       description: j['description'] as String?);
// }
//
// // ── CoursePrerequisite ────────────────────────────────────────────────────────
// class CoursePrerequisite {
//   final int id, courseId;
//   final String title;
//   final String? description;
//
//   const CoursePrerequisite(
//       {required this.id,
//       required this.courseId,
//       required this.title,
//       this.description});
//
//   factory CoursePrerequisite.fromJson(Map<String, dynamic> j) =>
//       CoursePrerequisite(
//           id: j['id'] as int,
//           courseId: j['course_id'] as int? ?? 0,
//           title: j['title'] as String? ?? '',
//           description: j['description'] as String?);
// }
//
// // ── TeacherSessionItem ────────────────────────────────────────────────────────
// class TeacherSessionItem {
//   final int id, courseId, durationMinutes, order;
//   final String name;
//   final String? description,
//       type,
//       scheduledAt,
//       roomUrl,
//       recordingUrl,
//       recordingStatus;
//   final bool isLiveActive;
//
//   const TeacherSessionItem({
//     required this.id,
//     required this.courseId,
//     required this.name,
//     required this.durationMinutes,
//     required this.order,
//     this.description,
//     this.type,
//     this.scheduledAt,
//     this.isLiveActive = false,
//     this.roomUrl,
//     this.recordingUrl,
//     this.recordingStatus,
//   });
//
//   bool get isLive => type == 'live';
//
//   bool get hasRecording =>
//       recordingStatus == 'uploaded' && recordingUrl != null;
//
//   String get scheduledLabel {
//     if (scheduledAt == null) return '';
//     try {
//       final dt = DateTime.parse(scheduledAt!).toLocal();
//       return '${dt.day}/${dt.month}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
//     } catch (_) {
//       return scheduledAt!;
//     }
//   }
//
//   factory TeacherSessionItem.fromJson(Map<String, dynamic> j) =>
//       TeacherSessionItem(
//           id: j['id'] as int,
//           courseId: j['course_id'] as int? ?? 0,
//           name: j['name'] as String? ?? '',
//           description: j['description'] as String?,
//           type: j['type'] as String?,
//           scheduledAt: j['scheduled_at'] as String?,
//           durationMinutes: j['duration_minutes'] as int? ?? 0,
//           order: j['order'] as int? ?? 0,
//           isLiveActive: j['is_live_active'] as bool? ?? false,
//           roomUrl: j['room_url'] as String?,
//           recordingUrl: j['recording_url'] as String?,
//           recordingStatus: j['recording_status'] as String?);
//
//   TeacherSessionItem copyWith(
//           {String? name,
//           String? description,
//           String? scheduledAt,
//           int? durationMinutes,
//           int? order,
//           bool? isLiveActive,
//           String? roomUrl,
//           String? recordingUrl,
//           String? recordingStatus}) =>
//       TeacherSessionItem(
//           id: id,
//           courseId: courseId,
//           name: name ?? this.name,
//           description: description ?? this.description,
//           type: type,
//           scheduledAt: scheduledAt ?? this.scheduledAt,
//           durationMinutes: durationMinutes ?? this.durationMinutes,
//           order: order ?? this.order,
//           isLiveActive: isLiveActive ?? this.isLiveActive,
//           roomUrl: roomUrl ?? this.roomUrl,
//           recordingUrl: recordingUrl ?? this.recordingUrl,
//           recordingStatus: recordingStatus ?? this.recordingStatus);
// }
//
// // ── AttendanceRecord ──────────────────────────────────────────────────────────
// class AttendanceRecord {
//   final int studentId;
//   final String studentName;
//   final String? studentImageUrl, checkInDate, checkOutDate;
//   final bool isPresent;
//
//   const AttendanceRecord(
//       {required this.studentId,
//       required this.studentName,
//       required this.isPresent,
//       this.studentImageUrl,
//       this.checkInDate,
//       this.checkOutDate});
//
//   String get durationLabel {
//     if (checkInDate == null || checkOutDate == null) return '—';
//     try {
//       return '${DateTime.parse(checkOutDate!).difference(DateTime.parse(checkInDate!)).inMinutes} دقيقة';
//     } catch (_) {
//       return '—';
//     }
//   }
//
//   factory AttendanceRecord.fromJson(Map<String, dynamic> j) => AttendanceRecord(
//       studentId: j['student_id'] as int? ?? 0,
//       studentName: j['student_name'] as String? ?? '',
//       studentImageUrl: j['image_url'] as String?,
//       checkInDate: j['check_in_date'] as String?,
//       checkOutDate: j['check_out_date'] as String?,
//       isPresent: j['is_present'] as bool? ?? true);
// }
//
// // ── TeacherCourse ─────────────────────────────────────────────────────────────
// class TeacherCourse {
//   final int id, studentsCount, sessionsCount;
//   final String title, imageUrl, type;
//   final double totalHours, averageRating, price;
//   final String? categoryName, description;
//   final bool isPublished;
//   final List<CourseSchedule> schedules;
//   final List<CourseCertificate> certificates;
//   final List<CourseTool> tools;
//   final List<CoursePrerequisite> prerequisites;
//
//   const TeacherCourse({
//     required this.id,
//     required this.title,
//     required this.imageUrl,
//     required this.totalHours,
//     required this.type,
//     this.studentsCount = 0,
//     this.sessionsCount = 0,
//     this.averageRating = 0.0,
//     this.price = 0,
//     this.categoryName,
//     this.isPublished = false,
//     this.description,
//     this.schedules = const [],
//     this.certificates = const [],
//     this.tools = const [],
//     this.prerequisites = const [],
//   });
//
//   factory TeacherCourse.fromJson(Map<String, dynamic> j) => TeacherCourse(
//         id: j['id'] as int,
//         title: j['name'] as String? ?? '',
//         imageUrl: j['image_url'] as String? ?? j['logo_url'] as String? ?? '',
//         studentsCount: j['students_count'] as int? ?? 0,
//         sessionsCount: j['sessions_count'] as int? ?? 0,
//         averageRating: (j['average_rating'] as num?)?.toDouble() ?? 0.0,
//         totalHours: (j['total_hours'] as num?)?.toDouble() ?? 0,
//         price: (j['fees'] as num?)?.toDouble() ?? 0,
//         categoryName:
//             (j['category'] as Map<String, dynamic>?)?['name'] as String?,
//         isPublished: j['is_published'] as bool? ?? false,
//         description: j['description'] as String?,
//         type: j['type'] as String? ?? 'recorded',
//         schedules: (j['schedules'] as List? ?? [])
//             .map((e) => CourseSchedule.fromJson(e as Map<String, dynamic>))
//             .toList(),
//         certificates: (j['certificates'] as List? ?? [])
//             .map((e) => CourseCertificate.fromJson(e as Map<String, dynamic>))
//             .toList(),
//         tools: (j['tools'] as List? ?? [])
//             .map((e) => CourseTool.fromJson(e as Map<String, dynamic>))
//             .toList(),
//         prerequisites: (j['prerequisites'] as List? ?? [])
//             .map((e) => CoursePrerequisite.fromJson(e as Map<String, dynamic>))
//             .toList(),
//       );
//
//   TeacherCourse copyWith(
//           {bool? isPublished,
//           String? imageUrl,
//           List<CourseSchedule>? schedules,
//           List<CourseCertificate>? certificates,
//           List<CourseTool>? tools,
//           List<CoursePrerequisite>? prerequisites}) =>
//       TeacherCourse(
//           id: id,
//           title: title,
//           imageUrl: imageUrl ?? this.imageUrl,
//           totalHours: totalHours,
//           type: type,
//           studentsCount: studentsCount,
//           sessionsCount: sessionsCount,
//           averageRating: averageRating,
//           price: price,
//           categoryName: categoryName,
//           isPublished: isPublished ?? this.isPublished,
//           description: description,
//           schedules: schedules ?? this.schedules,
//           certificates: certificates ?? this.certificates,
//           tools: tools ?? this.tools,
//           prerequisites: prerequisites ?? this.prerequisites);
// }
//
// // ── ScheduleSession ───────────────────────────────────────────────────────────
// class ScheduleSession {
//   final int id, durationMinutes, studentsCount;
//   final String courseTitle, sessionTitle;
//   final String? scheduledAt, roomUrl;
//
//   const ScheduleSession(
//       {required this.id,
//       required this.courseTitle,
//       required this.sessionTitle,
//       required this.durationMinutes,
//       this.scheduledAt,
//       this.studentsCount = 0,
//       this.roomUrl});
//
//   String get timeLabel {
//     if (scheduledAt == null) return '';
//     try {
//       final dt = DateTime.parse(scheduledAt!).toLocal();
//       return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
//     } catch (_) {
//       return scheduledAt!;
//     }
//   }
//
//   String get dateLabel {
//     if (scheduledAt == null) return '';
//     try {
//       final dt = DateTime.parse(scheduledAt!).toLocal();
//       return '${dt.day}/${dt.month}/${dt.year}';
//     } catch (_) {
//       return '';
//     }
//   }
//
//   factory ScheduleSession.fromJson(Map<String, dynamic> j) => ScheduleSession(
//       id: j['session_id'] as int? ?? j['id'] as int? ?? 0,
//       courseTitle: j['course_name'] as String? ??
//           (j['course'] as Map<String, dynamic>?)?['name'] as String? ??
//           '',
//       sessionTitle: j['session_name'] as String? ?? j['name'] as String? ?? '',
//       scheduledAt: j['scheduled_at'] as String?,
//       durationMinutes: j['duration_minutes'] as int? ?? 60,
//       studentsCount:
//           j['max_students'] as int? ?? j['students_count'] as int? ?? 0,
//       roomUrl: j['room_url'] as String?);
// }
//
// // ── TeacherDashboardData ──────────────────────────────────────────────────────
// class TeacherDashboardData {
//   final TeacherStats stats;
//   final List<TeacherCourse> courses;
//   final List<ScheduleSession> schedule;
//
//   const TeacherDashboardData(
//       {required this.stats, required this.courses, required this.schedule});
//
//   factory TeacherDashboardData.fromJson(Map<String, dynamic> j) {
//     final s = j['stats'] as Map<String, dynamic>? ?? {};
//     return TeacherDashboardData(
//         stats: TeacherStats.fromJson(s),
//         courses: (j['courses'] as List? ?? [])
//             .map((e) => TeacherCourse.fromJson(e as Map<String, dynamic>))
//             .toList(),
//         schedule:
//             (j['schedule'] as List? ?? j['upcoming_sessions'] as List? ?? [])
//                 .map((e) => ScheduleSession.fromJson(e as Map<String, dynamic>))
//                 .toList());
//   }
// }
