/// features/student/models.dart  —  Student data models v3.2.0
library;

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/category/categories_provider.dart';

import '../../../utils/helpers.dart';
import '../../../utils/widget/rating_widget.dart';
import '../category/model.dart';
import '../shared/course/discount_info.dart';
import '../teacher/home/teacher_models.dart';

export '../shared/course/discount_info.dart';

enum CourseStatus { all, inProgress, completed }

extension CourseStatusX on CourseStatus {
  /// Server-side value ("in_progress" / "completed"). `all` is UI-only
  /// (used for filter tabs) and never sent to/from the API.
  String? get apiValue => switch (this) {
    CourseStatus.inProgress => 'in_progress',
    CourseStatus.completed => 'completed',
    CourseStatus.all => null,
  };

  String get labelKey => switch (this) {
    CourseStatus.inProgress => 'course_status_in_progress',
    CourseStatus.completed => 'course_status_completed',
    CourseStatus.all => 'filter_all',
  };

  String get label => labelKey.tr;

  static CourseStatus fromApiValue(String? v) => switch (v) {
    'completed' => CourseStatus.completed,
    _ => CourseStatus.inProgress,
  };
}

/// Currencies a teacher can price a course in. Shown as a translated,
/// highlighted horizontal chip list in the course form, and used to label
/// the price everywhere (teacher + student sides).
enum AppCurrency { sar, egp, usd }

extension AppCurrencyX on AppCurrency {
  /// Raw code sent to / received from the API.
  String get code => switch (this) {
    AppCurrency.sar => 'SAR',
    AppCurrency.egp => 'EGP',
    AppCurrency.usd => 'USD',
  };

  /// Short symbol appended to prices (e.g. "150 ر.س", "150 ج.م", "$150").
  String get symbol => switch (this) {
    AppCurrency.sar => 'ر.س',
    AppCurrency.egp => 'ج.م',
    AppCurrency.usd => '\$',
  };

  /// Translation key for the full currency name shown in the selector chip.
  /// Add these keys to your ar.json / en.json:
  ///   currency_sar: "ريال سعودي" / "Saudi Riyal"
  ///   currency_egp: "جنيه مصري" / "Egyptian Pound"
  ///   currency_usd: "دولار أمريكي" / "US Dollar"
  String get labelKey => switch (this) {
    AppCurrency.sar => 'currency_sar',
    AppCurrency.egp => 'currency_egp',
    AppCurrency.usd => 'currency_usd',
  };

  String get label => labelKey.tr;

  /// Formats a price with this currency's symbol, e.g. "150 ج.م" or "free".
  String format(double price) => price == 0
      ? 'free'.tr
      : '${price.toStringAsFixed(price.truncateToDouble() == price ? 0 : 2)} $symbol';

  static AppCurrency fromCode(String? code) => AppCurrency.values.firstWhere(
        (c) => c.code == (code ?? 'EGP').toUpperCase(),
    orElse: () => AppCurrency.egp,
  );
}

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
  final int progress;
  final RatingSummary? rateSummary;

  SessionModel({
    required this.id,
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
    required this.progress,
    this.rateSummary,
  });

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
    rateSummary: j.containsKey('rate') && j['rate'] != null
        ? RatingSummary.fromJson(j['rate'] as Map<String, dynamic>)
        : null,
    scheduledAt: j['scheduled_at'] != null
        ? (j['scheduled_at'] as String).toLocalSaTime
        : null,
    createdAt: j['created_at'] != null
        ? (j['created_at'] as String).toLocalSaTime
        : DateTime.now(),
    recordingUrl: j['recording_url'] as String? ?? '',
    recordingStatus: j['recording_status'] as String? ?? '',
    totalMaterial: j['total_materials'] as int? ?? 0,
    completeMaterial: j['complete_materials'] as int? ?? 0,
    progress: ((j['progress'] as double?) ?? 0.0).toInt(),
    isCompleted: j['completeness'] as bool,
  );

  TeacherSessionItem get toTeacher => TeacherSessionItem(
    id: id,
    courseId: courseId,
    name: name,
    rateSummary: rateSummary,
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
    progress: progress,
    rateSummary: rateSummary,
  );
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
  final int progress;
  final RatingSummary? rateSummary;

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
    this.rateSummary,
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
          ? (j['scheduled_at'] as String).toLocalSaTime
          : null,
      createdAt: j['created_at'] != null
          ? (j['created_at'] as String).toLocalSaTime
          : DateTime.now(),
      durationMinutes: j['duration_minutes'] as int? ?? 0,
      order: j['order'] as int? ?? 0,
      isLiveActive: j['is_live_active'] as bool? ?? false,
      roomUrl: j['room_url'] as String?,
      recordingUrl: j['recording_url'] as String?,
      recordingStatus: j['recording_status'] as String?,
      totalMaterial: j['total_materials'] as int? ?? 0,
      completeMaterial: j['complete_materials'] as int? ?? 0,
      progress: j.containsKey('progress')
          ? double.parse((j['progress'].toString()) as String? ?? '0.0').toInt()
          : 0,
      rateSummary: j.containsKey('rate') && j['rate'] != null
          ? RatingSummary.fromJson(j['rate'] as Map<String, dynamic>)
          : null,
    );
  }

  TeacherSessionItem copyWith({
    String? name,
    String? description,
    DateTime? scheduledAt,
    DateTime? createdAt,
    int? durationMinutes,
    int? order,
    bool? isLiveActive,
    String? roomUrl,
    String? recordingUrl,
    String? recordingStatus,
    int? totalMaterial,
    int? completeMaterial,
  }) => TeacherSessionItem(
    id: id,
    courseId: courseId,
    name: name ?? this.name,
    description: description ?? this.description,
    type: type,
    rateSummary: rateSummary,
    scheduledAt: scheduledAt ?? this.scheduledAt,
    durationMinutes: durationMinutes ?? this.durationMinutes,
    order: order ?? this.order,
    isLiveActive: isLiveActive ?? this.isLiveActive,
    roomUrl: roomUrl ?? this.roomUrl,
    recordingUrl: recordingUrl ?? this.recordingUrl,
    recordingStatus: recordingStatus ?? this.recordingStatus,
    createdAt: createdAt ?? this.createdAt,
    totalMaterial: totalMaterial ?? this.totalMaterial,
    completeMaterial: completeMaterial ?? this.completeMaterial,
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
        createdAt: (j['created_at'] as String).toLocalSaTime,
        teacherProfile: j['teacher_profile'] != null
            ? TeacherProfileDetail.fromJson(
          j['teacher_profile'] as Map<String, dynamic>,
        )
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
          j['specialization'] as Map<String, dynamic>? ?? {},
        ),
        teachingType: j['teaching_type'] as String,
        paymentType: j['payment_type'] as String,
        about: j['about'] as String?,
        createdAt: (j['created_at'] as String).toLocalSaTime,
      );
}

/// Lightweight course card used for "next course", "recommended courses",
/// and "similar courses" — everything a small preview card needs, without
/// pulling in the full CourseModel (schedules/certificates/etc).
class CourseSummary with DiscountInfo {
  final int id;
  final String name;
  final String imageUrl;
  @override
  final double price;
  @override
  final double finalPrice;
  final AppCurrency currency;
  final double averageRating;
  @override
  final DateTime? discountEndsAt;
  @override
  final bool? discountActive;
  @override
  final double? discountPercentage;

  const CourseSummary({
    required this.id,
    required this.name,
    this.imageUrl = '',
    this.price = 0,
    this.currency = AppCurrency.egp,
    this.averageRating = 0,
    required this.finalPrice,
    this.discountEndsAt,
    this.discountActive,
    this.discountPercentage,
  });

  factory CourseSummary.fromJson(Map<String, dynamic> j) => CourseSummary(
    id: j['id'] as int,
    name: j['name'] as String? ?? '',
    imageUrl: j['image_url'] as String? ?? '',
    price: (j['fees'] as num?)?.toDouble() ?? 0,
    currency: AppCurrencyX.fromCode(j['currency'] as String?),
    averageRating: (j['average_rating'] as num?)?.toDouble() ?? 0,
    discountEndsAt: j['discount_ends_at'] != null
        ? DateTime.tryParse(j['discount_ends_at'] as String)
        : null,
    discountActive: j['discount_active'] as bool? ?? false,
    discountPercentage: (j['discount_percentage'] as num?)?.toDouble() ?? 0.0,
    finalPrice: (j['final_price'] as num?)?.toDouble() ?? 0.0,
  );
}

class CourseModel with DiscountInfo {
  final String id, name, imageUrl, type;
  final String? description;
  final CategoryModel? category;
  @override
  final double price;
  final double totalHours;
  final AppCurrency currency;
  final CourseStatus status;
  final int studentsCount, sessionsCount;
  final bool isPublished;
  bool isEnrolled;
  bool isFavorite;
  bool isSubscribed;
  @override
  final DateTime? discountEndsAt;
  @override
  final bool? discountActive;
  @override
  final double? discountPercentage;

  // Progress fields — populated by the API for enrolled students.
  // Progress is based on materials only (0.0–100.0).
  int progress;
  int materialsTotal;
  final double expectedHours;
  @override
  final double? finalPrice;
  int materialsCompleted;
  final List<CourseSchedule> schedules;
  final List<CourseCertificate> certificates;
  final List<CourseTool> tools;
  final List<CoursePrerequisite> prerequisites;
  final TeacherProfileData? teacher;
  final RatingSummary? rateSummary;
  final List<CourseSummary> nextCourses;
  final List<CourseSummary> recommendedCourses;
  final List<CourseSummary> similarCourses;
  final List<CourseSummary> recentCompletedCourses;
  final int? discountDays;

  CourseModel({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.price,
    required this.type,
    this.currency = AppCurrency.egp,
    this.status = CourseStatus.inProgress,
    this.category,
    this.description,
    this.studentsCount = 0,
    this.sessionsCount = 0,
    this.totalHours = 0.0,
    this.isFavorite = false,
    this.isSubscribed = false,
    this.progress = 0,
    this.materialsTotal = 0,
    this.materialsCompleted = 0,
    this.schedules = const [],
    this.certificates = const [],
    this.tools = const [],
    this.prerequisites = const [],
    required this.isEnrolled,
    this.teacher,
    required this.isPublished,
    required this.expectedHours,
    this.rateSummary,
    this.nextCourses = const [],
    this.recommendedCourses = const [],
    this.similarCourses = const [],
    this.recentCompletedCourses = const [],
    this.finalPrice,
    this.discountEndsAt,
    this.discountActive,
    this.discountPercentage, this.discountDays,
  });

  String get title => name;

  int get hoursCount => totalHours.round();

  factory CourseModel.fromCategoryModel(CategoryCourseModel cat) => CourseModel(
    id: cat.id,
    name: cat.title,
    category: CategoryModel(
      id: cat.id,
      nameEn: cat.title,
      nameAr: cat.title,
      imageUrl: cat.imageUrl,
      description: '',
    ),
    imageUrl: cat.imageUrl,
    price: cat.price,
    type: 'recorded',
    currency: AppCurrency.egp,
    status: CourseStatus.inProgress,
    certificates: [],
    tools: [],
    schedules: [],
    prerequisites: [],
    isEnrolled: false,
    teacher: null,
    isPublished: true,
    expectedHours: 0,
    finalPrice: cat.finalPrice,
    discountEndsAt: cat.discountEndsAt,
    discountActive: cat.discountActive,
    discountPercentage: cat.discountPercentage,
  );

  factory CourseModel.fromJson(Map<String, dynamic> j) => CourseModel(
    id: j['id'].toString(),
    name: j['name'] as String? ?? '',
    imageUrl: j['image_url'] as String? ?? '',
    category: j['category'] != null
        ? CategoryModel.fromJson(j['category'] as Map<String, dynamic>)
        : null,
    price: (j['fees'] as num?)?.toDouble() ?? 0.0,
    currency: AppCurrencyX.fromCode(j['currency'] as String?),
    status: CourseStatusX.fromApiValue(j['status'] as String?),
    studentsCount:
    (j['students_count'] as int? ?? j['enrollment_count'] as int? ?? 0)+700,
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
    progress: ((j['progress'] as num?)?.toDouble() ?? 0.0).toInt(),
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
    isPublished: j['is_published'],
    rateSummary: j.containsKey('rate') && j['rate'] != null
        ? RatingSummary.fromJson(j['rate'] as Map<String, dynamic>)
        : null,
    nextCourses: (j['next_courses'] as List? ?? [])
        .map((e) => CourseSummary.fromJson(e as Map<String, dynamic>))
        .toList(),
    recommendedCourses: (j['recommended_courses'] as List? ?? [])
        .map((e) => CourseSummary.fromJson(e as Map<String, dynamic>))
        .toList(),
    similarCourses: (j['similar_courses'] as List? ?? [])
        .map((e) => CourseSummary.fromJson(e as Map<String, dynamic>))
        .toList(),
    recentCompletedCourses: (j['recent_completed_courses'] as List? ?? [])
        .map((e) => CourseSummary.fromJson(e as Map<String, dynamic>))
        .toList(),
    discountEndsAt: j['discount_ends_at'] != null
        ? DateTime.tryParse(j['discount_ends_at'] as String)
        : null,
    discountActive: j['discount_active'] as bool? ?? false,
    discountPercentage: (j['discount_percentage'] as num?)?.toDouble() ?? 0.0,
    finalPrice: (j['final_price'] as num?)?.toDouble() ?? 0.0,
    discountDays: (j['discount_days'] as num?)?.toInt(),
  );

  /// Builds a minimal-but-valid CourseModel from a lightweight summary card
  /// (next/recommended/similar course), so tapping one can navigate straight
  /// into CourseDetailScreen — which then hydrates the rest via `refresh()`,
  /// the same sparse-then-hydrate pattern as `fromCategoryModel`.
  factory CourseModel.fromSummary(CourseSummary s) => CourseModel(
    id: s.id.toString(),
    name: s.name,
    imageUrl: s.imageUrl,
    price: s.price,
    currency: s.currency,
    type: 'recorded',
    isEnrolled: false,
    isPublished: true,
    expectedHours: 0,
    finalPrice: s.finalPrice,
    discountEndsAt: s.discountEndsAt,
    discountActive: s.discountActive,
    discountPercentage: s.discountPercentage,
  );

  TeacherCourse get toTeacherModel => TeacherCourse(
    id: int.parse(id),
    title: title,
    rateSummary: rateSummary,
    progress: progress,
    imageUrl: imageUrl,
    totalHours: totalHours,
    description: description,
    category: category,
    certificates: certificates,
    schedules: schedules,
    prerequisites: prerequisites,
    studentsCount: studentsCount,
    sessionsCount: sessionsCount,
    tools: tools,
    isPublished: true,
    price: price,
    currency: currency,
    status: status,
    type: type,
    nextCourses: nextCourses,
    recommendedCourseIds: recommendedCourses.map((e) => e.id).toList(),
    similarCourses: similarCourses,
    expectedHours: expectedHours,
  );

  CourseModel copyWith({
    bool? isFavorite,
    int? progress,
    int? materialsTotal,
    int? materialsCompleted,
    List<SessionModel>? sessions,
    CategoryModel? category,
    int? studentsCount,
  }) => CourseModel(
    id: id,
    name: name,
    imageUrl: imageUrl,
    price: price,
    type: type,
    currency: currency,
    status: status,
    category: category ?? this.category,
    rateSummary: rateSummary,
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
    nextCourses: nextCourses,
    recommendedCourses: recommendedCourses,
    similarCourses: similarCourses,
    recentCompletedCourses: recentCompletedCourses,
    expectedHours: expectedHours,
    finalPrice: finalPrice,
    discountEndsAt: discountEndsAt,
    discountActive: discountActive,
    discountPercentage: discountPercentage,
    discountDays: discountDays,
  );
}

class AttendanceRecord {
  final int sessionId;
  final bool isCheckedIn;
  final String? checkInAt, checkOutAt;

  const AttendanceRecord({
    required this.sessionId,
    required this.isCheckedIn,
    this.checkInAt,
    this.checkOutAt,
  });

  factory AttendanceRecord.fromJson(Map<String, dynamic> j) => AttendanceRecord(
    sessionId: j['session_id'] as int? ?? 0,
    isCheckedIn: j['check_in_date'] != null,
    checkInAt: j['check_in_date'] as String? ?? '',
    checkOutAt: j['check_out_date'] as String? ?? '',
  );
}