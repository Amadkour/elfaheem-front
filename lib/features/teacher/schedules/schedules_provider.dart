/// schedules/schedules_provider.dart
library;
import 'package:flutter_education_app/features/teacher/home/teacher_models.dart' show TeacherCourse, CourseSchedule;

import '../../../core/api_client.dart';
import '../../../core/base_provider.dart';

// ─────────────────────────────────────────────
//  Day constants
// ─────────────────────────────────────────────

const kDayOrder = [
  'monday','tuesday','wednesday','thursday','friday','saturday','sunday',
];
const kDayLabels = {
  'monday':    'الاثنين', 'tuesday':   'الثلاثاء',
  'wednesday': 'الأربعاء','thursday':  'الخميس',
  'friday':    'الجمعة',  'saturday':  'السبت',   'sunday': 'الأحد',
};
const kDayShort = {
  'monday': 'إث', 'tuesday': 'ثل', 'wednesday': 'أر',
  'thursday': 'خم','friday': 'جم', 'saturday': 'سب', 'sunday': 'أح',
};

String slotDayLabel(String d) => kDayLabels[d] ?? d;
String slotDayShort(String d) => kDayLabels[d] ?? d.substring(0, 2);
int    slotDayOrder(String d) => kDayOrder.indexOf(d);

// ─────────────────────────────────────────────
//  ScheduleSlot model
// ─────────────────────────────────────────────

class ScheduleSlot {
  final int    scheduleId;
  final int    courseId;
  final String courseName;
  final String? courseImage;
  final String day;
  final String dayLabelStr;
  final String startTime;
  final String endTime;
  final bool   isToday;
  final bool   isOngoing;
  final int?   minutesUntilStart;
  final int?   minutesUntilEnd;
  final String? scheduledDate;
  final int?    durationMinutes;
  final int?    maxStudents;

  const ScheduleSlot({
    required this.scheduleId, required this.courseId,
    required this.courseName, required this.day,
    required this.dayLabelStr, required this.startTime,
    required this.endTime, required this.isToday, required this.isOngoing,
    this.courseImage, this.minutesUntilStart, this.minutesUntilEnd,
    this.scheduledDate, this.durationMinutes, this.maxStudents,
  });

  factory ScheduleSlot.fromJson(Map<String, dynamic> j) => ScheduleSlot(
    scheduleId:        j['schedule_id']        as int,
    courseId:          j['course_id']           as int,
    courseName:        j['course_name']         as String,
    courseImage:       j['course_image']        as String?,
    day:               j['day']                 as String,
    dayLabelStr:       j['day_label']           as String? ?? j['day'] as String,
    startTime:         j['start_time']          as String,
    endTime:           j['end_time']            as String,
    isToday:           j['is_today']            as bool? ?? false,
    isOngoing:         j['is_ongoing']          as bool? ?? false,
    minutesUntilStart: j['minutes_until_start'] as int?,
    minutesUntilEnd:   j['minutes_until_end']   as int?,
    scheduledDate:     j['scheduled_date']      as String?,
    durationMinutes:   j['duration_minutes']    as int?,
    maxStudents:       j['max_students']        as int?,
  );

  int get startMin {
    final p = startTime.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }
  int get endMin {
    final p = endTime.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }
  int get calcDuration => durationMinutes ?? (endMin - startMin);

  double progressFraction(int liveSecondsLeft) {
    final totalSec = calcDuration * 60;
    if (totalSec <= 0) return 0;
    final elapsed = totalSec - liveSecondsLeft;
    return (elapsed / totalSec).clamp(0.0, 1.0);
  }

  String countdownLabel(int liveSecondsLeft) {
    if (isOngoing) {
      if (liveSecondsLeft <= 0) return 'انتهت للتو';
      final m = liveSecondsLeft ~/ 60;
      final s = liveSecondsLeft % 60;
      return 'تنتهي ${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}';
    }
    if (!isToday) return dayLabelStr;
    final mu = minutesUntilStart ?? 0;
    if (mu <= 0) return 'بدأت للتو';
    if (mu < 60) return 'بعد $muد';
    final h = mu ~/ 60; final m = mu % 60;
    return 'بعد $hس${m > 0 ? ' $mد' : ''}';
  }
}

// ─────────────────────────────────────────────
//  CourseScheduleGroup
// ─────────────────────────────────────────────

class CourseScheduleGroup {
  final int    courseId;
  final String courseName;
  final String? courseImage;
  final List<ScheduleSlot> schedules;

  const CourseScheduleGroup({
    required this.courseId, required this.courseName,
    required this.schedules, this.courseImage,
  });

  factory CourseScheduleGroup.fromJson(Map<String, dynamic> j) =>
      CourseScheduleGroup(
        courseId:    j['course_id']   as int,
        courseName:  j['course_name'] as String,
        courseImage: j['course_image'] as String?,
        schedules:   (j['schedules'] as List? ?? [])
            .map((e) => ScheduleSlot.fromJson(e as Map<String,dynamic>))
            .toList(),
      );
}

// ─────────────────────────────────────────────
//  ScheduleResponse
// ─────────────────────────────────────────────

class ScheduleResponse {
  final String todayDay;
  final String todayLabel;
  final List<ScheduleSlot> todaySlots;
  final ScheduleSlot? nextSlot;
  final List<CourseScheduleGroup> allCourses;

  const ScheduleResponse({
    required this.todayDay, required this.todayLabel,
    required this.todaySlots, required this.allCourses, this.nextSlot,
  });

  factory ScheduleResponse.fromJson(Map<String, dynamic> j) => ScheduleResponse(
    todayDay:   j['today_day']   as String? ??'',
    todayLabel: j['today_label'] as String? ??'',
    todaySlots: (j['today_slots'] as List? ?? [])
        .map((e) => ScheduleSlot.fromJson(e as Map<String,dynamic>)).toList(),
    nextSlot: j['next_slot'] != null
        ? ScheduleSlot.fromJson(j['next_slot'] as Map<String,dynamic>) : null,
    allCourses: (j['all_courses'] as List? ?? [])
        .map((e) => CourseScheduleGroup.fromJson(e as Map<String,dynamic>)).toList(),
  );

  List<String> get activeDays {
    final s = <String>{};
    for (final g in allCourses) for (final sl in g.schedules) {
      s.add(sl.day);
    }
    return s.toList()..sort((a,b) => slotDayOrder(a).compareTo(slotDayOrder(b)));
  }

  List<ScheduleSlot> slotsForDay(String day) {
    final r = <ScheduleSlot>[];
    for (final g in allCourses) {
      r.addAll(g.schedules.where((s) => s.day == day));
    }
    r.sort((a, b) => a.startMin.compareTo(b.startMin));
    return r;
  }
}

// ─────────────────────────────────────────────
//  Student Schedules Provider  (manual refresh only)
// ─────────────────────────────────────────────

class StudentSchedulesProvider extends BaseProvider {
  final ApiClient _api;
  StudentSchedulesProvider({ApiClient? api}) : _api = api ?? ApiClient();

  ScheduleResponse? _data;
  DateTime?         _lastFetched;

  ScheduleResponse?         get data         => _data;
  ScheduleSlot?             get nextSlot      => _data?.nextSlot;
  List<ScheduleSlot>        get todaySlots    => _data?.todaySlots ?? [];
  List<CourseScheduleGroup> get allCourses    => _data?.allCourses ?? [];
  String                    get todayDay      => _data?.todayDay ?? '';
  DateTime?                 get lastFetched   => _lastFetched;

  /// Call once on first load.
  Future<void> fetchOnce() async {
    if (_data != null) return; // already have data — user will manually refresh
    await fetch();
  }

  Future<void> fetch() async {
    final r = await run(() => _api.get('/api/v1/student/schedules'));
    if (r is Map<String, dynamic>) {
      _data         = ScheduleResponse.fromJson(r);
      _lastFetched  = DateTime.now();
      notifyListeners();
    }
  }
}

// ─────────────────────────────────────────────
//  Teacher Schedule Overview Provider  (manual refresh only)
// ─────────────────────────────────────────────

class TeacherScheduleOverviewProvider extends BaseProvider {
  final ApiClient _api;
  TeacherScheduleOverviewProvider({ApiClient? api}) : _api = api ?? ApiClient();

  ScheduleResponse? _data;
  DateTime?         _lastFetched;

  ScheduleResponse?         get data         => _data;
  ScheduleSlot?             get nextSlot      => _data?.nextSlot;
  List<ScheduleSlot>        get todaySlots    => _data?.todaySlots ?? [];
  List<CourseScheduleGroup> get allCourses    => _data?.allCourses ?? [];
  String                    get todayDay      => _data?.todayDay ?? '';
  DateTime?                 get lastFetched   => _lastFetched;

  /// Call once on first load.
  Future<void> fetchOnce() async {
    if (_data != null) return;
    await fetch();
  }

  Future<void> fetch() async {
    final r = await run(() => _api.get('/api/v1/teacher/schedules'));
    if (r is Map<String, dynamic>) {
      _data         = ScheduleResponse.fromJson(r);
      _lastFetched  = DateTime.now();
      notifyListeners();
    }
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
    final r = await run(() => _api.get('/api/v1/courses/${course.id}/schedules'));
    if (r is List) {
      _schedules = r.map((e) => CourseSchedule.fromJson(e as Map<String,dynamic>)).toList();
      notifyListeners();
    }
  }

  Future<CourseSchedule?> addSchedule({
    required String day, required String startTime, required String endTime,
  }) async {
    if (_courseId == null) return null;
    final r = await run(() => _api.post(
      '/api/v1/courses/$_courseId/schedules',
      body: {'day': day, 'start_time': startTime, 'end_time': endTime},
    ));
    if (r is Map<String,dynamic>) {
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