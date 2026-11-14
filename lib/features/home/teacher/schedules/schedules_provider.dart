/// schedules/schedules_provider.dart — a course's weekly appointments (the teacher's course studio).
///
/// The student / teacher "My schedule" tab is the one schedule page now (lib/features/shared/calendar/schedule_page.dart,
/// D-085): it reads GET /student|teacher/schedules itself (CalendarStore.weekly).
library;

import 'package:flutter_education_app/features/home/teacher/teacher_models.dart'
    show TeacherCourse, CourseSchedule;

import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/base_provider.dart';

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
