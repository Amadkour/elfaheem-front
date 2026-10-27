/// schedules/schedules_provider.dart
library;

import 'package:flutter_education_app/features/teacher/home/teacher_models.dart'
    show TeacherCourse, CourseSchedule, ScheduleSession;

import '../../../config/app_config.dart';
import '../../../core/api_client.dart';
import '../../../core/base_provider.dart';
import '../../shared/calendar/calendar_api.dart';
import '../../shared/calendar/calendar_models.dart';

// ─────────────────────────────────────────────
//  Day constants
// ─────────────────────────────────────────────

const kDayOrder = [
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
  'sunday',
];
const kDayLabels = {
  'monday': 'الاثنين',
  'tuesday': 'الثلاثاء',
  'wednesday': 'الأربعاء',
  'thursday': 'الخميس',
  'friday': 'الجمعة',
  'saturday': 'السبت',
  'sunday': 'الأحد',
};
const kDayShort = {
  'monday': 'إث',
  'tuesday': 'ثل',
  'wednesday': 'أر',
  'thursday': 'خم',
  'friday': 'جم',
  'saturday': 'سب',
  'sunday': 'أح',
};

String slotDayLabel(String d) => kDayLabels[d] ?? d;

String slotDayShort(String d) => kDayLabels[d] ?? d.substring(0, 2);

int slotDayOrder(String d) => kDayOrder.indexOf(d);

// ─────────────────────────────────────────────
//  CourseScheduleGroup
// ─────────────────────────────────────────────

class CourseScheduleGroup {
  final int courseId;
  final String courseName;
  final String? courseImage;
  final List<ScheduleSession> schedules;

  const CourseScheduleGroup({
    required this.courseId,
    required this.courseName,
    required this.schedules,
    this.courseImage,
  });

  factory CourseScheduleGroup.fromJson(Map<String, dynamic> j) =>
      CourseScheduleGroup(
        courseId: j['course_id'] is num ? (j['course_id'] as num).toInt() : 0,
        courseName: '${j['course_name'] ?? ''}',
        courseImage: j['course_image'] as String?,
        schedules: (j['schedules'] as List? ?? [])
            .whereType<Map>()
            .map((e) => ScheduleSession.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

// ─────────────────────────────────────────────
//  ScheduleResponse
// ─────────────────────────────────────────────

class ScheduleResponse {
  final String todayDay;
  final String todayLabel;
  final List<ScheduleSession> todaySlots;
  final ScheduleSession? nextSlot;
  final List<CourseScheduleGroup> allCourses;

  const ScheduleResponse({
    required this.todayDay,
    required this.todayLabel,
    required this.todaySlots,
    required this.allCourses,
    this.nextSlot,
  });

  factory ScheduleResponse.fromJson(Map<String, dynamic> j) =>
      ScheduleResponse(
        todayDay: j['today_day'] as String? ?? '',
        todayLabel: j['today_label'] as String? ?? '',
        todaySlots: (j['today_slots'] as List? ?? [])
            .whereType<Map>()
            .map((e) => ScheduleSession.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        nextSlot: j['next_slot'] is Map
            ? ScheduleSession.fromJson(Map<String, dynamic>.from(j['next_slot'] as Map))
            : null,
        allCourses: (j['all_courses'] as List? ?? [])
            .whereType<Map>()
            .map((e) => CourseScheduleGroup.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );

  List<String> get activeDays {
    final s = <String>{};
    for (final g in allCourses)
      for (final sl in g.schedules) {
        s.add(sl.day);
      }
    return s.toList()
      ..sort((a, b) => slotDayOrder(a).compareTo(slotDayOrder(b)));
  }

  List<ScheduleSession> slotsForDay(String day) {
    final r = <ScheduleSession>[];
    for (final g in allCourses) {
      r.addAll(g.schedules.where((s) => s.day == day));
    }
    r.sort((a, b) => a.startMin.compareTo(b.startMin));
    return r;
  }
}

/// Hard limit of one schedule load: past it the tab shows an error with retry, never an endless spinner.
const Duration kScheduleTimeout = Duration(seconds: 20);

/// GET + parse. Any failure (timeout, unreadable body) ends as an exception, so [BaseProvider.run] reaches the
/// error state — before, a parse error left `data` null and the tab on its loading screen forever.
Future<ScheduleResponse> loadScheduleResponse(ApiClient api, String path) async =>
    parseScheduleResponse(await api.get(path).timeout(kScheduleTimeout));

/// The user's meetings over the next [days] days (GET /me/calendar, meetings only, declined ones dropped). Never
/// throws: a failure here must not fail the schedule tab, it just shows no meetings.
Future<List<CalEvent>> loadUpcomingMeetings({CalendarApi api = const RemoteCalendarApi(), int days = 7}) async {
  try {
    final now = DateTime.now().toUtc();
    final r = await api.feed(now.toIso8601String(), now.add(Duration(days: days)).toIso8601String());
    return CalEvent.listFrom(r).where((e) => e.source == 'meeting' && e.end.isAfter(now) && e.myStatus != 'declined').toList()
      ..sort((a, b) => a.start.compareTo(b.start));
  } catch (_) {
    return const [];
  }
}

ScheduleResponse parseScheduleResponse(dynamic body) {
  try {
    return ScheduleResponse.fromJson(Map<String, dynamic>.from(body as Map));
  } catch (_) {
    throw ApiException(statusCode: 0, message: 'schedule_load_failed'.tr);
  }
}

// ─────────────────────────────────────────────
//  Student Schedules Provider  (manual refresh only)
// ─────────────────────────────────────────────

class StudentSchedulesProvider extends BaseProvider {
  final ApiClient _api;

  StudentSchedulesProvider({ApiClient? api}) : _api = api ?? ApiClient();

  ScheduleResponse? _data;
  DateTime? _lastFetched;

  ScheduleResponse? get data => _data;

  ScheduleSession? get nextSlot => _data?.nextSlot;

  List<ScheduleSession> get todaySlots => _data?.todaySlots ?? [];

  List<CourseScheduleGroup> get allCourses => _data?.allCourses ?? [];

  String get todayDay => _data?.todayDay ?? '';

  DateTime? get lastFetched => _lastFetched;

  /// Call once on first load.
  Future<void> fetchOnce() async {
    if (_data != null) return; // already have data — user will manually refresh
    await fetch();
  }

  List<CalEvent> _meetings = const [];

  /// The next 7 days' meetings — loaded beside the schedule, never failing it.
  List<CalEvent> get meetings => _meetings;

  Future<void> fetch() async {
    final meetings = loadUpcomingMeetings();
    final r = await run(() => loadScheduleResponse(_api, '/api/v1/student/schedules'));
    if (r != null) {
      _data = r;
      _lastFetched = DateTime.now();
      notifyListeners();
    }
    _meetings = await meetings;
    notifyListeners();
  }
}

// ─────────────────────────────────────────────
//  Teacher Schedule Overview Provider  (manual refresh only)
// ─────────────────────────────────────────────

class TeacherScheduleOverviewProvider extends BaseProvider {
  final ApiClient _api;

  TeacherScheduleOverviewProvider({ApiClient? api}) : _api = api ?? ApiClient();

  ScheduleResponse? _data;
  DateTime? _lastFetched;

  ScheduleResponse? get data => _data;

  ScheduleSession? get nextSlot => _data?.nextSlot;

  List<ScheduleSession> get todaySlots => _data?.todaySlots ?? [];

  List<CourseScheduleGroup> get allCourses => _data?.allCourses ?? [];

  String get todayDay => _data?.todayDay ?? '';

  DateTime? get lastFetched => _lastFetched;

  /// Call once on first load.
  Future<void> fetchOnce() async {
    if (_data != null) return;
    await fetch();
  }

  List<CalEvent> _meetings = const [];

  /// The next 7 days' meetings — loaded beside the schedule, never failing it.
  List<CalEvent> get meetings => _meetings;

  Future<void> fetch() async {
    final meetings = loadUpcomingMeetings();
    final r = await run(() => loadScheduleResponse(_api, '/api/v1/teacher/schedules'));
    if (r != null) {
      _data = r;
      _lastFetched = DateTime.now();
      notifyListeners();
    }
    _meetings = await meetings;
    notifyListeners();
  }
}

// ─────────────────────────────────────────────
//  Teacher Course-specific Provider
// ─────────────────────────────────────────────

class TeacherSchedulesProvider extends BaseProvider {
  final ApiClient _api;

  TeacherSchedulesProvider({ApiClient? api}) : _api = api ?? ApiClient();

  List<CourseSchedule> _schedules = [];
  int? _courseId;

  List<CourseSchedule> get schedules => List.unmodifiable(_schedules);

  Future<void> fetchSchedules(TeacherCourse course) async {
    _courseId = course.id;
    if (course.schedules.isNotEmpty) {
      _schedules = List.from(course.schedules);
      notifyListeners();
    }
    final r =
    await run(() => _api.get('/api/v1/courses/${course.id}/schedules'));
    if (r is List) {
      _schedules = r
          .map((e) => CourseSchedule.fromJson(e as Map<String, dynamic>))
          .toList();
      notifyListeners();
    }
  }

  void initCourse(int courseId) {
    _courseId = courseId;
  }

  Future<CourseSchedule?> addSchedule({
    required String day,
    required String startTime,
    required String endTime,
  }) async {
    if (_courseId == null) return null;
    final r = await run(() =>
        _api.post(
          '/api/v1/courses/$_courseId/schedules',
          body: {'day': day, 'start_time': startTime, 'end_time': endTime},
        ));
    if (r is Map<String, dynamic>) {
      final s = CourseSchedule.fromJson(r);
      _schedules = [..._schedules, s];
      notifyListeners();
      return s;
    }
    return null;
  }

  Future<bool> removeSchedule(int scheduleId) async {
    await run(() => _api.delete('/api/v1/schedules/$scheduleId'));
    if (state == ProviderState.success) {
      _schedules = _schedules.where((s) => s.id != scheduleId).toList();
      notifyListeners();
      return true;
    }
    return false;
  }
}
