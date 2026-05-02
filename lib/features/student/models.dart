/// features/courses/models.dart  —  Student data models v3.2.0
library;

import '../category/model.dart';
import '../teacher/home/teacher_models.dart';

enum CourseStatus { all, inProgress, completed }

enum CourseDetailTab { lessons, about, live }

// class CourseSchedule {
//   final int id, courseId;
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
//       id: j['id'] as int? ?? -1,
//       courseId: j['course_id'] as int? ?? 0,
//       day: j['day'] as String? ?? '',
//       startTime: j['start_time'] as String? ?? '',
//       endTime: j['end_time'] as String? ?? '');
// }

class CourseInfoItem {
  final int id;
  final String title;
  final String? description;

  const CourseInfoItem(
      {required this.id, required this.title, this.description});

  factory CourseInfoItem.fromJson(Map<String, dynamic> j) => CourseInfoItem(
      id: j['id'] as int? ?? -1,
      title: j['title'] as String? ?? j['name'] as String? ?? '',
      description: j['description'] as String? ?? '');
}

class SessionModel {
  final int id, courseId, durationMinutes, order;
  final String name, type;
  final String? description, scheduledAt, recordingStatus;
  String? recordingUrl;
  bool isCompleted;
  SessionModel(
      {required this.id,
      required this.courseId,
      required this.name,
      required this.type,
      required this.durationMinutes,
      required this.order,
      this.description,
      this.scheduledAt,
      this.recordingUrl,
      this.recordingStatus,
      this.isCompleted = false});

  bool get isLive => type == 'live';

  bool get hasRecording =>
      recordingStatus == 'uploaded' && recordingUrl != null;

  String get scheduledLabel {
    if (scheduledAt == null) return '';
    try {
      final dt = DateTime.parse(scheduledAt!).toLocal();
      return '${dt.day}/${dt.month}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return scheduledAt!;
    }
  }

  factory SessionModel.fromJson(Map<String, dynamic> j) => SessionModel(
      id: j['id'] as int? ?? -1,
      courseId: j['course_id'] as int? ?? 0,
      name: j['name'] as String? ?? '',
      description: j['description'] as String? ?? '',
      type: j['type'] as String? ?? 'pre-recorded',
      durationMinutes: j['duration_minutes'] as int? ?? 0,
      order: j['order'] as int? ?? 0,
      scheduledAt: j['scheduled_at'] as String? ?? '',
      recordingUrl: j['recording_url'] as String? ?? '',
      recordingStatus: j['recording_status'] as String? ?? '');

  SessionModel copyWith({bool? isCompleted, String? type}) => SessionModel(
      id: id,
      courseId: courseId,
      name: name,
      type: type ?? this.type,
      durationMinutes: durationMinutes,
      order: order,
      description: description,
      scheduledAt: scheduledAt,
      recordingUrl: recordingUrl,
      recordingStatus: recordingStatus,
      isCompleted: isCompleted ?? this.isCompleted);
}

// ── TeacherSessionItem ────────────────────────────────────────────────────────
class TeacherSessionItem {
  final int id, courseId, durationMinutes, order;
  final String name;
  final String? description,
      type,
      roomUrl,
      recordingUrl,
      recordingStatus;
  final bool isLiveActive;
  final DateTime scheduledAt;

  const TeacherSessionItem({
    required this.id,
    required this.courseId,
    required this.name,
    required this.durationMinutes,
    required this.order,
    this.description,
    this.type,
    required this.scheduledAt,
    this.isLiveActive = false,
    this.roomUrl,
    this.recordingUrl,
    this.recordingStatus,
  });

  bool get isLive => type == 'live';

  bool get hasRecording =>
      recordingStatus == 'uploaded' && recordingUrl != null;

  String get scheduledLabel {
    if (scheduledAt == null) return '';
    try {
      final dt = scheduledAt.toLocal();
      return '${dt.day}/${dt.month}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return scheduledAt.toIso8601String();
    }
  }

  factory TeacherSessionItem.fromJson(Map<String, dynamic> j) =>
      TeacherSessionItem(
          id: j['id'] as int,
          courseId: j['course_id'] as int? ?? 0,
          name: j['name'] as String? ?? '',
          description: j['description'] as String?,
          type: j['type'] as String?,
          scheduledAt: DateTime.parse(j['scheduled_at'] as String),
          durationMinutes: j['duration_minutes'] as int? ?? 0,
          order: j['order'] as int? ?? 0,
          isLiveActive: j['is_live_active'] as bool? ?? false,
          roomUrl: j['room_url'] as String?,
          recordingUrl: j['recording_url'] as String?,
          recordingStatus: j['recording_status'] as String?);

  TeacherSessionItem copyWith(
      {String? name,
        String? description,
        DateTime? scheduledAt,
        int? durationMinutes,
        int? order,
        bool? isLiveActive,
        String? roomUrl,
        String? recordingUrl,
        String? recordingStatus}) =>
      TeacherSessionItem(
          id: id,
          courseId: courseId,
          name: name ?? this.name,
          description: description ?? this.description,
          type: type,
          scheduledAt: scheduledAt ?? this.scheduledAt,
          durationMinutes: durationMinutes ?? this.durationMinutes,
          order: order ?? this.order,
          isLiveActive: isLiveActive ?? this.isLiveActive,
          roomUrl: roomUrl ?? this.roomUrl,
          recordingUrl: recordingUrl ?? this.recordingUrl,
          recordingStatus: recordingStatus ?? this.recordingStatus);
}

class CourseModel {
  final String id, name, imageUrl, type;
  final String? categoryId, categoryName, teacherName, description;
  final double price, averageRating, totalHours;
  final int studentsCount, sessionsCount;
   bool isEnrolled;
  bool isFavorite;
  bool isSubscribed;
  double progress;
  late List<SessionModel> sessions;
  final List<CourseSchedule> schedules;
  final List<CourseInfoItem> certificates, tools, prerequisites;

  CourseModel(
      {required this.id,
      required this.name,
      required this.imageUrl,
      required this.price,
      required this.type,
      this.categoryId,
      this.categoryName,
      this.teacherName,
      this.description,
      this.averageRating = 0.0,
      this.studentsCount = 0,
      this.sessionsCount = 0,
      this.totalHours = 0.0,
      this.isFavorite = false,
      this.isSubscribed = false,
      this.progress = 0.0,
      this.sessions = const [],
      this.schedules = const [],
      this.certificates = const [],
      this.tools = const [],
      this.prerequisites = const [], required this.isEnrolled});

  String get title => name;

  String get instructorName => teacherName ?? '';

  double? get rate => averageRating > 0 ? averageRating : null;

  int get hoursCount => totalHours.round();

  factory CourseModel.fromCategoryModel(CategoryCourseModel cat) => CourseModel(
        id: cat.id,
        name: cat.title,
        categoryId: cat.categoryId,
        imageUrl: cat.imageUrl,
        price: cat.price,
        averageRating: cat.rating,
        teacherName: cat.instructorName,
        type: 'recorded',
        certificates: [],
        tools: [],
        schedules: [],
        prerequisites: [], 
    isEnrolled: false,
      );

  factory CourseModel.fromJson(Map<String, dynamic> j) => CourseModel(
      id: j['id'].toString(),
      name: j['name'] as String? ?? '',
      imageUrl: j['image_url'] as String? ?? '',
      categoryId: j['category_id']?.toString(),
      categoryName:
          (j['category'] as Map<String, dynamic>?)?['name'] as String? ??
              j['category_name'] as String? ??
              '',
      price: (j['fees'] as num?)?.toDouble() ?? 0.0,
      averageRating: (j['average_rating'] as num?)?.toDouble() ??
          (j['rating'] as num?)?.toDouble() ??
          0.0,
      studentsCount:
          j['students_count'] as int? ?? j['enrollment_count'] as int? ?? 0,
      sessionsCount: j['sessions_count'] as int? ?? 0,
      totalHours: (j['total_hours'] as num?)?.toDouble() ?? 0.0,
      teacherName:
          (j['teacher'] as Map<String, dynamic>?)?['name'] as String? ??
              j['teacher_name'] as String? ??
              '',
      description: j['description'] as String? ?? '',
      type: j['type'] as String? ?? 'recorded',
      isSubscribed: j['is_subscribed'] as bool? ?? false,
      isFavorite: j['is_favorite'] as bool? ?? false,
      sessions: (j['sessions'] as List? ?? [])
          .map((e) => SessionModel.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.order.compareTo(b.order)),
      schedules: (j['schedules'] as List? ?? [])
          .map((e) => CourseSchedule.fromJson(e as Map<String, dynamic>))
          .toList(),
      certificates: (j['certificates'] as List? ?? [])
          .map((e) => CourseInfoItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      tools: (j['tools'] as List? ?? [])
          .map((e) => CourseInfoItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      prerequisites: (j['prerequisites'] as List? ?? [])
          .map((e) => CourseInfoItem.fromJson(e as Map<String, dynamic>))
          .toList(), isEnrolled: j['is_enrolled']);

  CourseModel copyWith(
          {bool? isFavorite,
          double? progress,
          List<SessionModel>? sessions,
          String? categoryName,
          double? averageRating,
          int? studentsCount}) =>
      CourseModel(
          id: id,
          name: name,
          imageUrl: imageUrl,
          price: price,
          type: type,
          categoryId: categoryId,
          categoryName: categoryName ?? this.categoryName,
          averageRating: averageRating ?? this.averageRating,
          studentsCount: studentsCount ?? this.studentsCount,
          sessionsCount: sessionsCount,
          totalHours: totalHours,
          teacherName: teacherName,
          description: description,
          isFavorite: isFavorite ?? this.isFavorite,
          progress: progress ?? this.progress,
          sessions: sessions ?? this.sessions,
          schedules: schedules,
          certificates: certificates,
          tools: tools,
          prerequisites: prerequisites, isEnrolled: this.isEnrolled);
}

class AttendanceRecord {
  final int sessionId;
  final bool isCheckedIn;
  final String? checkInAt, checkOutAt;

  const AttendanceRecord(
      {required this.sessionId,
      required this.isCheckedIn,
      this.checkInAt,
      this.checkOutAt});

  factory AttendanceRecord.fromJson(Map<String, dynamic> j) => AttendanceRecord(
      sessionId: j['session_id'] as int? ?? 0,
      isCheckedIn: j['check_in_date'] != null,
      checkInAt: j['check_in_date'] as String? ?? '',
      checkOutAt: j['check_out_date'] as String? ?? '');
}