// ─────────────────────────────────────────────────────────────────────────────
// teacher_home_provider.dart
//
// Owns ONLY the teacher home / dashboard state: stats, the small course
// preview shown on the home grid, and the upcoming schedule.
//
// PROVIDER SPLIT
// ─────────────────────────────────────────────────────────────────────────
// Previously all of this lived in one `TeacherProvider` together with the
// full course list, filtering, and course CRUD (publish/unpublish/delete),
// which meant any course-management mutation notified — and could
// potentially rebuild — the home dashboard too.
//
// This provider now owns only what the home screen needs. Full course
// management (list, filter, CRUD) lives in `teacher_courses_provider.dart`'s
// `TeacherCoursesProvider`. Both are registered as separate, independent
// providers at the app root (see core/providers.dart) — exactly like the
// old single `TeacherProvider` was — so either screen can read the one it
// needs without a hard dependency on the other.
//
// `refreshSilently()` is unchanged from before: it does the exact same
// dashboard fetch as `init()` but skips the loading state entirely, so a
// background refresh (e.g. `queue_work_items.dart`'s per-second schedule
// ticker, once a session crosses its start time) updates data in place
// without flashing a full-screen loading state on whatever the teacher is
// currently looking at.
// ─────────────────────────────────────────────────────────────────────────

import '../../../core/api_client.dart';
import '../../../core/base_provider.dart';
import '../courses/component/teacher_stats.dart';
import 'teacher_models.dart';

class TeacherHomeProvider extends BaseProvider {
  final ApiClient _api;

  TeacherHomeProvider({ApiClient? api}) : _api = api ?? ApiClient();

  // ── Dashboard state ──────────────────────────────────────────────────────

  TeacherStats _stats = const TeacherStats();
  List<TeacherCourse> _homeCourses = [];
  List<ScheduleSession> _schedule = [];

  TeacherStats get stats => _stats;

  /// Course preview for the home grid only — the full, filterable course
  /// list lives in [TeacherCoursesProvider]. The screen additionally clamps
  /// this to 8 items for the 2-column grid.
  List<TeacherCourse> get homeCourses => List.unmodifiable(_homeCourses);

  List<ScheduleSession> get schedule => List.unmodifiable(_schedule);

  Map<String, int> _pending = const {};

  /// attendance_missing · materials_missing · grading · enrollment_requests (GET /teacher/dashboard `pending`).
  Map<String, int> get pending => _pending;

  // ─────────────────────────────────────────────────────────────────────────
  // Bootstrap
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> init() => _fetchDashboard();

  /// Same fetch as [init], but never puts the provider into
  /// [ProviderState.loading]. Use this for background/automatic refreshes
  /// where flashing a full-screen loading state would be jarring and isn't
  /// tied to any user action.
  Future<void> refreshSilently() => _fetchDashboard(silent: true);

  Future<void> _fetchDashboard({bool silent = false}) async {
    final result = await run(
          () => _api.get('/api/v1/teacher/dashboard'),
      makLoading: !silent,
    );
    if (result is Map<String, dynamic>) {
      final data = TeacherDashboardData.fromJson(result);
      _stats = data.stats;
      _homeCourses = data.courses;
      _schedule = data.schedule;
      _pending = data.pending;
      notifyListeners();
    }
  }
}