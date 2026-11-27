/// shared/teacher_models.dart
///
/// Data models used across the teacher feature.
/// ScheduleSession now matches the dashboard_service.py output which is
/// derived from CourseSchedule (not SessionModel.scheduled_at).
library;

import 'package:flutter_education_app/features/home/student/models.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/utils/helpers.dart';
import 'package:flutter_education_app/utils/widget/rating_widget.dart';
import 'package:flutter_education_app/features/courses/course_scope.dart' show CourseOrg;
import 'package:flutter_education_app/features/courses/course_setup.dart';
import 'package:flutter_education_app/features/courses/category/categories_provider.dart';
import 'package:flutter_education_app/features/courses/teacher/component/teacher_stats.dart';

export 'package:flutter_education_app/features/courses/discount_info.dart';

class CourseSchedule {
  final int id;
  final int courseId;
  final String day, startTime, endTime;

  const CourseSchedule({
    required this.id,
    required this.courseId,
    required this.day,
    required this.startTime,
    required this.endTime,
  });

  /// The day's name in the app language (`day` is the server's English key).
  String get dayLabel =>
      (AppConfig.lang == 'ar' ? _dayAr : _dayEn)[day.toLowerCase()] ?? day;

  static const _dayAr = {
    'monday': 'الإثنين',
    'tuesday': 'الثلاثاء',
    'wednesday': 'الأربعاء',
    'thursday': 'الخميس',
    'friday': 'الجمعة',
    'saturday': 'السبت',
    'sunday': 'الأحد',
  };
  static const _dayEn = {
    'monday': 'Monday',
    'tuesday': 'Tuesday',
    'wednesday': 'Wednesday',
    'thursday': 'Thursday',
    'friday': 'Friday',
    'saturday': 'Saturday',
    'sunday': 'Sunday',
  };

  /// Lightweight constructor for pending (not-yet-saved) entries.
  factory CourseSchedule.pending({
    required String day,
    required String startTime,
    required String endTime,
  }) => CourseSchedule(
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
    endTime: j['end_time'] as String? ?? '',
  );
}

// ── CourseCertificate ─────────────────────────────────────────────────────────
class CourseCertificate {
  final int id, courseId;
  final String title;
  final String? description;
  final String? templateUrl;

  const CourseCertificate({
    required this.id,
    required this.courseId,
    required this.title,
    this.description,
    this.templateUrl,
  });

  factory CourseCertificate.fromJson(Map<String, dynamic> j) =>
      CourseCertificate(
        id: j['id'] as int,
        courseId: j['course_id'] as int? ?? 0,
        title: j['title'] as String? ?? '',
        description: j['description'] as String?,
        templateUrl: j['template_url'] as String?,
      );
}

// ── CourseTool ────────────────────────────────────────────────────────────────
class CourseTool {
  final int id, courseId;
  final String name;
  final String? description;

  const CourseTool({
    required this.id,
    required this.courseId,
    required this.name,
    this.description,
  });

  factory CourseTool.fromJson(Map<String, dynamic> j) => CourseTool(
    id: j['id'] as int,
    courseId: j['course_id'] as int? ?? 0,
    name: j['title'] as String? ?? '',
    description: j['description'] as String?,
  );
}

// ── CoursePrerequisite ────────────────────────────────────────────────────────
class CoursePrerequisite {
  final int id, courseId;
  final String title;
  final String? description;

  const CoursePrerequisite({
    required this.id,
    required this.courseId,
    required this.title,
    this.description,
  });

  factory CoursePrerequisite.fromJson(Map<String, dynamic> j) =>
      CoursePrerequisite(
        id: j['id'] as int,
        courseId: j['course_id'] as int? ?? 0,
        title: j['title'] as String? ?? '',
        description: j['description'] as String?,
      );
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
  final String dayLabelStr;

  // ── NEW: live session fields returned by the updated backend ──────────────
  final int? sessionId; // SessionModel.id  – null if not yet created
  final int? onlineSessionId; // OnlineSession.id – null if not yet created
  final String? roomName; // LiveKit room name
  final String? provider; // 'livekit' | 'zoom' | …
  final bool isLive; // OnlineSession.is_active
  final String? joinUrl; // OnlineSession.url  (room join URL)
  final String? hostUrl; // OnlineSession.host_url
  final String? token; // OnlineSession.host_url
  int get startMin {
    final p = startTime.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  int get endMin {
    final p = endTime.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  int get calcDuration => durationMinutes > 0 ? durationMinutes : (endMin - startMin);

  double progressFraction(int liveSecondsLeft) {
    final totalSec = calcDuration * 60;
    if (totalSec <= 0) return 0;
    final elapsed = totalSec - liveSecondsLeft;
    return (elapsed / totalSec).clamp(0.0, 1.0);
  }

  String countdownLabel(int liveSecondsLeft) {
    if (isOngoing) {
      if (liveSecondsLeft <= 0) return 'end-now'.tr;
      final m = liveSecondsLeft ~/ 60;
      final s = liveSecondsLeft % 60;
      return 'تنتهي ${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    if (!isToday) return dayLabelStr;
    final mu = minutesUntilStart ?? 0;
    if (mu <= 0) return 'start-now'.tr;
    if (mu < 60) return 'بعد $muد';
    final h = mu ~/ 60;
    final m = mu % 60;
    return 'بعد $hس${m > 0 ? ' $mد' : ''}';
  }

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
    required this.dayLabelStr,
  });

  factory ScheduleSession.fromJson(Map<String, dynamic> j) {
    // tolerant: a course with only an Arabic name (course_name null) must not break the whole schedule
    final day = '${j['day'] ?? ''}';
    int id(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
    return ScheduleSession(
      scheduleId: id(j['schedule_id']),
      courseId: id(j['course_id']),
      courseName: '${j['course_name'] ?? ''}',
      day: day,
      dayLabelStr: j['day_label'] as String? ?? day,
      startTime: '${j['start_time'] ?? '00:00'}',
      endTime: '${j['end_time'] ?? '00:00'}',
      isToday: j['is_today'] as bool? ?? false,
      isOngoing: j['is_ongoing'] as bool? ?? false,
      minutesUntilStart: j['minutes_until_start'] as int?,
      minutesUntilEnd: j['minutes_until_end'] as int?,
      scheduledDate: j['scheduled_date'] != null
          ? (j['scheduled_date'] as String).toLocalSaTime
          : DateTime.now(),
      durationMinutes: j['duration_minutes'] as int? ?? 0,
      maxStudents: j['max_students'] as int?,

      courseImage: j['course_image'] as String?,
      dayLabel: j['day_label'] as String? ?? _labels[day] ?? day,
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
class TeacherCourse with DiscountInfo {
  final int id, studentsCount, sessionsCount;
  final String imageUrl, type;
  final double totalHours;
  @override
  final double price;
  final int progress;
  final double expectedHours;
  final CategoryModel? category;
  final bool isPublished;

  /// The publish review (docs/redesign/api/governance.md §1): null | pending_review | approved | rejected, and the
  /// reviewer's reason when rejected.
  final String? reviewStatus, reviewReason;
  bool get underReview => reviewStatus == 'pending_review';
  bool get reviewRejected => reviewStatus == 'rejected' && !isPublished;
  final List<CourseSchedule> schedules;
  final List<CourseCertificate> certificates;
  final List<CourseTool> tools;
  final List<CoursePrerequisite> prerequisites;
  final RatingSummary? rateSummary;
  final AppCurrency currency;
  final CourseStatus status;
  final bool isPrivate;
  final String? titleAr, titleEn, descriptionAr, descriptionEn;

  // ── Next courses (ORDERED roadmap) / recommended courses ────────────────
  final List<int> nextCourseIds;

  /// beginner | intermediate | advanced | null, and the topic words (D-120).
  final String? level;
  final List<String> tags;
  final List<int> recommendedCourseIds;

  // ── Rich recommendation cards (for the course-profile page) ────────────────
  final List<CourseSummary> nextCourses;
  final List<CourseSummary> recommendedCourseSummaries;
  final List<CourseSummary> similarCourses;
  @override
  final DateTime? discountEndsAt;
  @override
  final bool? discountActive;
  @override
  final double? finalPrice;
  @override
  final double? discountPercentage;
  final int? discountDays;

  /// Optional shorter plans. [price] is the YEARLY price; null = plan not offered.
  final double? priceMonthly, priceSixMonths;

  /// The raw YEARLY price (what the edit form edits). [price] / [finalPrice] follow
  /// the teacher's default plan, so they must not be used to prefill the yearly field.
  final double? priceYearly;

  /// Plan students see first: 0 yearly · 1 six months · 2 monthly.
  final int defaultPricePlanIndex;

  /// The organization the course belongs to; null = a personal course (or an older server).
  final CourseOrg? org;

  /// Who the course is for and where it is held (targets, subject, delivery mode, area, address; D-1314).
  final CourseSetup setup;

  const TeacherCourse({
    this.org,
    this.setup = const CourseSetup(),
    this.priceYearly,
    this.defaultPricePlanIndex = 0,
    this.priceMonthly,
    this.priceSixMonths,
    this.finalPrice,
    this.discountEndsAt,
    this.discountActive,
    this.discountPercentage,
    this.discountDays,
    required this.id,
    required this.imageUrl,
    required this.totalHours,
    required this.type,
    this.studentsCount = 0,
    this.sessionsCount = 0,
    this.price = 0,
    this.category,
    this.isPublished = false,
    this.reviewStatus,
    this.reviewReason,
    this.schedules = const [],
    this.certificates = const [],
    this.tools = const [],
    this.prerequisites = const [],
    required this.progress,
    required this.expectedHours,
    this.rateSummary,
    this.isPrivate = false,
    this.currency = AppCurrency.egp,
    this.status = CourseStatus.inProgress,
    this.nextCourseIds = const [],
    this.level,
    this.tags = const [],
    this.recommendedCourseIds = const [],
    this.nextCourses = const [],
    this.recommendedCourseSummaries = const [],
    this.similarCourses = const [],
    this.titleAr,
    this.titleEn,
    this.descriptionAr,
    this.descriptionEn,
  });

  factory TeacherCourse.dummy(int courseId) => TeacherCourse(
    id: courseId,
    imageUrl: '',
    price: 0,
    type: 'live',
    isPublished: false,
    expectedHours: 0,
    titleAr: '',
    titleEn: '',
    totalHours: 0,
    progress: 0,
  );

  factory TeacherCourse.fromJson(Map<String, dynamic> j) => TeacherCourse(
    id: j['id'] as int,
    imageUrl: j['image_url'] as String? ?? '',
    studentsCount: (j['students_count'] as num?)?.toInt() ?? 0,
    expectedHours: (j['expected_hours'] as num?)?.toDouble() ?? 0.0,
    isPrivate: j['is_private'] as bool? ?? false,
    sessionsCount: j['sessions_count'] as int? ?? 0,
    totalHours: (j['total_hours'] as num?)?.toDouble() ?? 0,
    discountDays: j['discount_days'] as int?,
    price:
    (j['price'] as num?)?.toDouble() ??
        (j['fees'] as num?)?.toDouble() ??
        0,
    finalPrice: (j['final_price'] as num?)?.toDouble(),
    priceMonthly: (j['price_monthly'] as num?)?.toDouble(),
    priceYearly: (j['price_yearly'] as num?)?.toDouble(),
    defaultPricePlanIndex: (j['default_price_plan_index'] as num?)?.toInt() ?? 0,
    priceSixMonths: (j['price_six_months'] as num?)?.toDouble(),
    discountActive: j['discount_active'] as bool?,
    discountPercentage: (j['discount_percentage'] as num?)?.toDouble(),
    discountEndsAt: j['discount_ends_at'] != null
        ? DateTime.tryParse(j['discount_ends_at'] as String)
        : null,
    progress: ((j['progress'] as num?)?.toDouble().toInt() ?? 0.0).toInt(),
    currency: AppCurrencyX.fromCode(j['currency'] as String?),
    status: CourseStatusX.fromApiValue(j['status'] as String?),
    category: j['category'] != null
        ? CategoryModel.fromJson(j['category'] as Map<String, dynamic>)
        : null,
    isPublished: j['is_published'] as bool? ?? false,
    reviewStatus: j['review_status'] as String?,
    reviewReason: j['review_reason'] as String?,
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
    rateSummary: j.containsKey('rate') && j['rate'] != null
        ? RatingSummary.fromJson(j['rate'] as Map<String, dynamic>)
        : null,
    level: j['level'] as String?,
    tags: [for (final x in (j['tags'] as List? ?? const [])) '$x'],
    nextCourseIds: (j['next_course_ids'] as List? ?? [])
        .map((e) => e as int)
        .toList(),
    recommendedCourseIds: (j['recommended_course_ids'] as List? ?? [])
        .map((e) => e as int)
        .toList(),
    nextCourses: (j['next_courses'] as List? ?? [])
        .map((e) => CourseSummary.fromJson(e as Map<String, dynamic>))
        .toList(),
    recommendedCourseSummaries: (j['recommended_courses'] as List? ?? [])
        .map((e) => CourseSummary.fromJson(e as Map<String, dynamic>))
        .toList(),
    similarCourses: (j['similar_courses'] as List? ?? [])
        .map((e) => CourseSummary.fromJson(e as Map<String, dynamic>))
        .toList(),
    titleAr: j['name_ar'] as String?,
    titleEn: j['name_en'] as String?,
    descriptionAr: j['description_ar'] as String?,
    descriptionEn: j['description_en'] as String?,
    org: CourseOrg.fromJson(j['org']),
    setup: CourseSetup.fromJson(j),
  );

  CourseModel get toCourseModel => CourseModel(
    org: org,
    setup: setup,
    titleAr: titleAr,
    titleEn: titleEn,
    descriptionAr: descriptionAr,
    descriptionEn: descriptionEn,
    isPrivate: isPrivate,
    id: id.toString(),
    imageUrl: imageUrl,
    price: price,
    rateSummary: rateSummary,
    progress: progress,
    type: type,
    isEnrolled: false,
    certificates: certificates,
    tools: tools,
    prerequisites: prerequisites,
    schedules: schedules,
    studentsCount: studentsCount,
    sessionsCount: sessionsCount,
    totalHours: totalHours,
    expectedHours: expectedHours,
    category: category,
    isPublished: isPublished,
    finalPrice: finalPrice,
    discountEndsAt: discountEndsAt,
    discountActive: discountActive,
    discountPercentage: discountPercentage,
    discountDays: discountDays,
  );

  TeacherCourse copyWith({
    bool? isPublished,
    String? reviewStatus,
    String? reviewReason,
    bool clearReview = false,
    String? imageUrl,
    int? discountDays,
    List<CourseSchedule>? schedules,
    List<CourseCertificate>? certificates,
    List<CourseTool>? tools,
    List<CoursePrerequisite>? prerequisites,
    AppCurrency? currency,
    CourseStatus? status,
    List<int>? nextCourseIds,
    List<int>? recommendedCourseIds,
    DateTime? discountEndsAt,
    bool? discountActive,
    double? discountPercentage,
    double? price,
    double? finalPrice,
    double? priceMonthly,
    double? priceSixMonths,
    double? priceYearly,
    int? defaultPricePlanIndex,
  }) => TeacherCourse(
    currency: currency ?? this.currency,
    status: status ?? this.status,
    id: id,
    titleEn: titleEn,
    titleAr: titleAr,
    descriptionEn: descriptionEn,
    descriptionAr: descriptionAr,
    progress: progress,
    imageUrl: imageUrl ?? this.imageUrl,
    totalHours: totalHours,
    type: type,
    discountDays: discountDays ?? this.discountDays,
    expectedHours: expectedHours,
    studentsCount: studentsCount,
    sessionsCount: sessionsCount,
    price: price ?? this.price,
    priceMonthly: priceMonthly ?? this.priceMonthly,
    priceYearly: priceYearly ?? this.priceYearly,
    defaultPricePlanIndex: defaultPricePlanIndex ?? this.defaultPricePlanIndex,
    priceSixMonths: priceSixMonths ?? this.priceSixMonths,
    category: category,
    isPublished: isPublished ?? this.isPublished,
    reviewStatus: clearReview ? null : (reviewStatus ?? this.reviewStatus),
    reviewReason: clearReview ? null : (reviewReason ?? this.reviewReason),
    schedules: schedules ?? this.schedules,
    certificates: certificates ?? this.certificates,
    tools: tools ?? this.tools,
    prerequisites: prerequisites ?? this.prerequisites,
    nextCourseIds: nextCourseIds ?? this.nextCourseIds,
    level: level,
    tags: tags,
    recommendedCourseIds: recommendedCourseIds ?? this.recommendedCourseIds,
    finalPrice: finalPrice ?? this.finalPrice,
    discountEndsAt: discountEndsAt ?? this.discountEndsAt,
    discountActive: discountActive ?? this.discountActive,
    discountPercentage: discountPercentage ?? this.discountPercentage,
    rateSummary: rateSummary,
    nextCourses: nextCourses,
    recommendedCourseSummaries: recommendedCourseSummaries,
    similarCourses: similarCourses,
    org: org,
    setup: setup,
  );
}

// ── TeacherDashboardData ──────────────────────────────────────────────────────
class TeacherDashboardData {
  final TeacherStats stats;
  final List<TeacherCourse> courses;
  final List<ScheduleSession> schedule;

  /// What waits for the teacher (home "pending" cards): attendance_missing · materials_missing · grading ·
  /// enrollment_requests. Empty on an older server.
  final Map<String, int> pending;

  const TeacherDashboardData({
    required this.stats,
    required this.courses,
    required this.schedule,
    this.pending = const {},
  });

  factory TeacherDashboardData.fromJson(Map<String, dynamic> j) {
    return TeacherDashboardData(
      stats: TeacherStats.fromJson(j),
      courses: (j['courses'] as List? ?? [])
          .map((e) => TeacherCourse.fromJson(e as Map<String, dynamic>))
          .toList(),
      schedule:
      (j['schedule'] as List? ?? j['upcoming_sessions'] as List? ?? [])
          .map((e) => ScheduleSession.fromJson(e as Map<String, dynamic>))
          .toList(),
      pending: {
        if (j['pending'] is Map)
          for (final e in (j['pending'] as Map).entries)
            if (e.value is num) '${e.key}': (e.value as num).toInt(),
      },
    );
  }
}