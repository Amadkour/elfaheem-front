/// features/courses/models.dart  —  Student data models v3.2.0
library;

import 'package:flutter_education_app/features/category/categories_provider.dart';

import '../category/model.dart';
import '../teacher/home/teacher_models.dart';

enum CourseStatus { all, inProgress, completed }

enum CourseDetailTab { lessons, about, live, exam }

class SessionModel {
  final int id,
      courseId,
      durationMinutes,
      order,
      totalMaterial,
      completeMaterial;
  final String name, type;
  final String? description, recordingStatus;
  final DateTime? scheduledAt;
  final DateTime createdAt;
  String? recordingUrl;
  bool isCompleted;
  final bool isLiveActive;
  final double progress;

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
      this.isCompleted = false,
      required this.createdAt,
      required this.isLiveActive,
      required this.totalMaterial,
      required this.completeMaterial,
      required this.progress});

  bool get isLive => type == 'live';

  bool get hasRecording =>
      recordingStatus == 'uploaded' && recordingUrl != null;

  String get scheduledLabel {
    if (scheduledAt == null) return '';
    try {
      final dt = scheduledAt ?? DateTime.now();
      return '${dt.day}/${dt.month}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return scheduledAt!.timeZoneName;
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
        isLiveActive: j['is_live_active'] as bool? ?? false,
        scheduledAt: j['scheduled_at'] != null
            ? DateTime.parse(j['scheduled_at'] as String)
            : null,
        createdAt: j['created_at'] != null
            ? DateTime.parse(j['created_at'] as String)
            : DateTime.now(),
        recordingUrl: j['recording_url'] as String? ?? '',
        recordingStatus: j['recording_status'] as String? ?? '',
        totalMaterial: j['total_materials'] as int? ?? 0,
        completeMaterial: j['complete_materials'] as int? ?? 0,
        progress: j['progress'] as double? ?? 0.0,
      );

  TeacherSessionItem get toTeacher => TeacherSessionItem(
        id: id,
        courseId: courseId,
        name: name,
        description: description,
        durationMinutes: durationMinutes,
        order: order,
        scheduledAt: scheduledAt,
        isLiveActive: isLiveActive,
        createdAt: createdAt,
        totalMaterial: totalMaterial,
        completeMaterial: completeMaterial,
        progress: progress,
      );

  SessionModel copyWith({bool? isCompleted, String? type}) => SessionModel(
      id: id,
      courseId: courseId,
      name: name,
      type: type ?? this.type,
      durationMinutes: durationMinutes,
      order: order,
      description: description,
      scheduledAt: scheduledAt,
      createdAt: createdAt,
      isLiveActive: isLiveActive,
      recordingUrl: recordingUrl,
      recordingStatus: recordingStatus,
      isCompleted: isCompleted ?? this.isCompleted,
      totalMaterial: totalMaterial,
      completeMaterial: completeMaterial,
      progress: progress);
}

// ── TeacherSessionItem ────────────────────────────────────────────────────────
class TeacherSessionItem {
  final int id,
      courseId,
      durationMinutes,
      order,
      totalMaterial,
      completeMaterial;
  final String name;
  final String? description, type, roomUrl, recordingUrl, recordingStatus;
  final bool isLiveActive;
  final DateTime? scheduledAt;
  final DateTime createdAt;
  final double progress;

  const TeacherSessionItem({
    required this.id,
    required this.courseId,
    required this.name,
    required this.durationMinutes,
    required this.order,
    this.description,
    this.type,
    required this.scheduledAt,
    required this.isLiveActive,
    this.roomUrl,
    this.recordingUrl,
    this.recordingStatus,
    required this.createdAt,
    required this.totalMaterial,
    required this.completeMaterial,
    required this.progress,
  });

  bool get isLive => type == 'live';

  bool get hasRecording =>
      recordingStatus == 'uploaded' && recordingUrl != null;

  String? get scheduledLabel {
    try {
      if (scheduledAt == null) return null;
      final dt = scheduledAt!.toLocal();
      return '${dt.day}/${dt.month}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return scheduledAt!.toIso8601String();
    }
  }

  factory TeacherSessionItem.fromJson(Map<String, dynamic> j) {
    return TeacherSessionItem(
      id: j['id'] as int,
      courseId: j['course_id'] as int? ?? 0,
      name: j['name'] as String? ?? '',
      description: j['description'] as String?,
      type: j['type'] as String?,
      scheduledAt: j['scheduled_at'] != null
          ? DateTime.parse(j['scheduled_at'] as String)
          : null,
      createdAt: j['created_at'] != null
          ? DateTime.parse(j['created_at'] as String)
          : DateTime.now(),
      durationMinutes: j['duration_minutes'] as int? ?? 0,
      order: j['order'] as int? ?? 0,
      isLiveActive: j['is_live_active'] as bool? ?? false,
      roomUrl: j['room_url'] as String?,
      recordingUrl: j['recording_url'] as String?,
      recordingStatus: j['recording_status'] as String?,
      totalMaterial: j['total_materials'] as int? ?? 0,
      completeMaterial: j['complete_materials'] as int? ?? 0,
      progress: j['progress'] as double? ?? 0.0,
    );
  }

  TeacherSessionItem copyWith(
          {String? name,
          String? description,
          DateTime? scheduledAt,
          DateTime? createdAt,
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
        recordingStatus: recordingStatus ?? this.recordingStatus,
        createdAt: createdAt ?? this.createdAt,
        totalMaterial: totalMaterial,
        completeMaterial: completeMaterial,
        progress: progress,
      );
}

class TeacherProfileData {
  final int id;
  final String name;
  final String gmail;
  final String? phone;
  final String role;
  final String? country;
  final String? imageUrl;
  final bool isVerified;
  final bool isActive;
  final int loginTimes;
  final String registrationStep;
  final DateTime createdAt;
  final TeacherProfileDetail? teacherProfile;

  const TeacherProfileData({
    required this.id,
    required this.name,
    required this.gmail,
    this.phone,
    required this.role,
    this.country,
    this.imageUrl,
    required this.isVerified,
    required this.isActive,
    required this.loginTimes,
    required this.registrationStep,
    required this.createdAt,
    this.teacherProfile,
  });

  factory TeacherProfileData.fromJson(Map<String, dynamic> j) =>
      TeacherProfileData(
        id: j['id'] as int,
        name: j['name'] as String,
        gmail: j['gmail'] as String,
        phone: j['phone'] as String?,
        role: j['role'] as String,
        country: j['country'] as String?,
        imageUrl: j['image_url'] as String?,
        isVerified: j['is_verified'] as bool,
        isActive: j['is_active'] as bool,
        loginTimes: j['login_times'] as int,
        registrationStep: j['registration_step'] as String,
        createdAt: DateTime.parse(j['created_at'] as String),
        teacherProfile: j['teacher_profile'] != null
            ? TeacherProfileDetail.fromJson(
                j['teacher_profile'] as Map<String, dynamic>)
            : null,
      );

  String get initials {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}

class TeacherProfileDetail {
  final int id;
  final int userId;
  final int experienceYears;
  final CategoryModel? specialization;
  final String teachingType;
  final String paymentType;
  final String? about;
  final DateTime createdAt;

  const TeacherProfileDetail({
    required this.id,
    required this.userId,
    required this.experienceYears,
    this.specialization,
    required this.teachingType,
    required this.paymentType,
    this.about,
    required this.createdAt,
  });

  factory TeacherProfileDetail.fromJson(Map<String, dynamic> j) =>
      TeacherProfileDetail(
        id: j['id'] as int,
        userId: j['user_id'] as int,
        experienceYears: j['experience_years'] as int,
        specialization: CategoryModel.fromJson(
            j['specialization'] as Map<String, dynamic>? ?? {}),
        teachingType: j['teaching_type'] as String,
        paymentType: j['payment_type'] as String,
        about: j['about'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}

class CourseModel {
  final String id, name, imageUrl, type;
  final String? categoryId, categoryName, description;
  final double price, averageRating, totalHours;
  final int studentsCount, sessionsCount;
  final bool isPublished;
  bool isEnrolled;
  bool isFavorite;
  bool isSubscribed;

  // Progress fields — populated by the API for enrolled students.
  // Progress is based on materials only (0.0–100.0).
  double progress;
  int materialsTotal;
  final double expectedHours;
  int materialsCompleted;
  final List<CourseSchedule> schedules;
  final List<CourseCertificate> certificates;
  final List<CourseTool> tools;
  final List<CoursePrerequisite> prerequisites;
  final TeacherProfileData? teacher;

  CourseModel(
      {required this.id,
      required this.name,
      required this.imageUrl,
      required this.price,
      required this.type,
      this.categoryId,
      this.categoryName,
      this.description,
      this.averageRating = 0.0,
      this.studentsCount = 0,
      this.sessionsCount = 0,
      this.totalHours = 0.0,
      this.isFavorite = false,
      this.isSubscribed = false,
      this.progress = 0.0,
      this.materialsTotal = 0,
      this.materialsCompleted = 0,
      this.schedules = const [],
      this.certificates = const [],
      this.tools = const [],
      this.prerequisites = const [],
      required this.isEnrolled,
      this.teacher,
      required this.isPublished,
      required this.expectedHours});

  String get title => name;

  double? get rate => averageRating > 0 ? averageRating : null;

  int get hoursCount => totalHours.round();

  factory CourseModel.fromCategoryModel(CategoryCourseModel cat) => CourseModel(
      id: cat.id,
      name: cat.title,
      categoryId: cat.categoryId,
      imageUrl: cat.imageUrl,
      price: cat.price,
      averageRating: cat.rating,
      type: 'recorded',
      certificates: [],
      tools: [],
      schedules: [],
      prerequisites: [],
      isEnrolled: false,
      teacher: null,
      isPublished: true,
      expectedHours: 0);

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
      expectedHours: (j['expected_hours'] as num?)?.toDouble() ?? 0.0,
      teacher: j['teacher'] != null
          ? TeacherProfileData.fromJson(j['teacher'] as Map<String, dynamic>)
          : null,
      description: j['description'] as String? ?? '',
      type: j['type'] as String? ?? 'recorded',
      isSubscribed: j['is_subscribed'] as bool? ?? false,
      isFavorite: j['is_favorite'] as bool? ?? false,
      progress: (j['progress'] as num?)?.toDouble() ?? 0.0,
      materialsTotal: j['materials_total'] as int? ?? 0,
      materialsCompleted: j['materials_completed'] as int? ?? 0,
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
      isEnrolled: j['is_enrolled'],
      isPublished: j['is_published']);

  TeacherCourse get toTeacherModel => TeacherCourse(
      id: int.parse(id),
      title: title,
      progress: progress,
      imageUrl: imageUrl,
      totalHours: totalHours,
      description: description,
      categoryName: categoryName,
      certificates: certificates,
      schedules: schedules,
      prerequisites: prerequisites,
      studentsCount: studentsCount,
      sessionsCount: sessionsCount,
      tools: tools,
      averageRating: averageRating,
      isPublished: true,
      price: price,
      type: type,
      expectedHours: expectedHours);

  CourseModel copyWith(
          {bool? isFavorite,
          double? progress,
          int? materialsTotal,
          int? materialsCompleted,
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
          teacher: teacher,
          description: description,
          isFavorite: isFavorite ?? this.isFavorite,
          progress: progress ?? this.progress,
          materialsTotal: materialsTotal ?? this.materialsTotal,
          materialsCompleted: materialsCompleted ?? this.materialsCompleted,
          schedules: schedules,
          certificates: certificates,
          tools: tools,
          prerequisites: prerequisites,
          isEnrolled: isEnrolled,
          isPublished: isPublished,
          expectedHours: expectedHours);
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
