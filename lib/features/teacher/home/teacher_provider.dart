// ─────────────────────────────────────────────────────────────────────────────
// teacher_provider.dart
//
// Owns ONLY the teacher dashboard / course-list state.
// All form state (create / update) lives in CourseFormProvider (scoped to
// the form route and auto-disposed on pop).
// ─────────────────────────────────────────────────────────────────────────────

import '../../../core/api_client.dart';
import '../../../core/base_provider.dart';
import '../courses/component/teacher_stats.dart';
import 'teacher_models.dart';

class TeacherProvider extends BaseProvider {
  final ApiClient _api;

  TeacherProvider({ApiClient? api}) : _api = api ?? ApiClient();

  // ── Dashboard state ──────────────────────────────────────────────────────

  TeacherStats _stats = const TeacherStats();
  List<TeacherCourse> _allCourses = [];
  List<ScheduleSession> _schedule = [];
  TeacherCourseStatus _activeFilter = TeacherCourseStatus.all;

  TeacherStats get stats => _stats;

  TeacherCourseStatus get activeFilter => _activeFilter;

  List<TeacherCourse> get allCourses => List.unmodifiable(_allCourses);

  List<ScheduleSession> get schedule => List.unmodifiable(_schedule);

  List<TeacherCourse> get filteredCourses => switch (_activeFilter) {
        TeacherCourseStatus.all => _allCourses,
        TeacherCourseStatus.published =>
          _allCourses.where((c) => c.isPublished).toList(),
        TeacherCourseStatus.draft =>
          _allCourses.where((c) => !c.isPublished).toList(),
      };

  TeacherCourse? courseById(int id) =>
      _allCourses.where((c) => c.id == id).firstOrNull;

  // ─────────────────────────────────────────────────────────────────────────
  // Bootstrap
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> init() => _fetchDashboard();

  Future<void> _fetchDashboard() async {
    final result = await run(() => _api.get('/api/v1/teacher/dashboard'));
    if (result is Map<String, dynamic>) {
      final data = TeacherDashboardData.fromJson(result);
      _stats = data.stats;
      _allCourses = data.courses;
      _schedule = data.schedule;
      notifyListeners();
    }
  }

  Future<void> fetchMyCourses({int skip = 0, int limit = 50}) async {
    final result = await run(() => _api.get(
          '/api/v1/my-courses',
          queryParams: {'skip': skip, 'limit': limit},
        ));
    if (result is List) {
      print("111111111111111111111111111111111111111111");

      _allCourses = result
          .map((e) => TeacherCourse.fromJson(e as Map<String, dynamic>))
          .toList();
      _updateStats();
      notifyListeners();
    }
  }

  Future<TeacherCourse?> fetchCourseById(int courseId) async {
    final result = await run(() => _api.get(
          '/api/v1/courses/$courseId',
        ));
    if (result is Map<String, dynamic>) {
      return TeacherCourse.fromJson(result);
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Called by CourseFormScreen on successful save so the list stays in sync
  // ─────────────────────────────────────────────────────────────────────────

  /// Prepend a newly created course to the list.
  void onCourseCreated(TeacherCourse course) {
    _allCourses = [course, ..._allCourses];
    _updateStats();
    notifyListeners();
  }

  /// Replace an updated course in the list.
  void onCourseUpdated(TeacherCourse course) {
    _allCourses =
        _allCourses.map((c) => c.id == course.id ? course : c).toList();
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Filter
  // ─────────────────────────────────────────────────────────────────────────

  void setFilter(TeacherCourseStatus status) {
    if (_activeFilter == status) return;
    _activeFilter = status;
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Publish / Unpublish / Delete
  // ─────────────────────────────────────────────────────────────────────────

  Future<bool> publishCourse(int courseId) async {
    final result =
        await run(() => _api.post('/api/v1/courses/$courseId/publish'));
    if (result != null) {
      _updateLocalPublish(courseId, isPublished: true);
      return true;
    }
    return false;
  }

  Future<bool> unpublishCourse(int courseId) async {
    final result =
        await run(() => _api.post('/api/v1/courses/$courseId/unpublish'));
    if (result != null) {
      _updateLocalPublish(courseId, isPublished: false);
      return true;
    }
    return false;
  }

  Future<bool> deleteCourse(int courseId) async {
    await run(() => _api.delete('/api/v1/courses/$courseId',queryParams: {'force':true}));
    if (state == ProviderState.success) {
      _allCourses = _allCourses.where((c) => c.id != courseId).toList();
      _updateStats();
      notifyListeners();
      return true;
    }
    return false;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Live-session helpers  (home-screen "start session" button)
  // ─────────────────────────────────────────────────────────────────────────

  Future<int> createSession({
    required int courseId,
    required String name,
    required int durationMinutes,
    String? description,
  }) async {
    final result = await run(() => _api.post(
          '/api/v1/sessions',
          body: {
            'course_id': courseId,
            'name': name,
            'type': 'live',
            'duration_minutes': durationMinutes,
            if (description != null && description.isNotEmpty)
              'description': description,
          },
        ));
    return result['id'] as int;
  }

  Future<String?> startLiveSession(
    int sessionId, {
    bool enableRecording = true,
    int durationHours = 24,
  }) async {
    final result = await run(() => _api.post(
          '/api/v1/live-sessions/start',
          queryParams: {
            'session_id': sessionId,
            'enable_recording': enableRecording,
            'duration_hours': durationHours,
          },
        ));
    if (result is Map<String, dynamic>) {
      return result['meeting_url'] as String? ??
          result['room_url'] as String? ??
          result['url'] as String?;
    }
    return null;
  }

  Future<bool> endLiveSession(int sessionId,
      {bool saveRecording = true}) async {
    final result = await run(() => _api.post(
          '/api/v1/live-sessions/$sessionId/end',
          queryParams: {'save_recording': saveRecording},
        ));
    return result != null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Private helpers
  // ─────────────────────────────────────────────────────────────────────────

  void _updateLocalPublish(int courseId, {required bool isPublished}) {
    _allCourses = _allCourses
        .map((c) => c.id == courseId ? c.copyWith(isPublished: isPublished) : c)
        .toList();
    notifyListeners();
  }

  void _updateStats() {
    _stats = _stats.copyWith(
      totalStudents: _allCourses.fold(0, (s, c) => (s!) + c.studentsCount),
      totalCourses: _allCourses.length,
    );
  }
}
