// ─────────────────────────────────────────────────────────────────────────────
// teacher_courses_provider.dart
//
// Owns the full teacher course list: fetching, filtering, and course CRUD
// (create/update sync from the form, publish/unpublish, delete).
//
// PROVIDER SPLIT
// ─────────────────────────────────────────────────────────────────────────
// Split out of the old `TeacherProvider`, which also carried the home
// dashboard's stats, home-grid course preview, and schedule. Those now live
// in `teacher_home_provider.dart`'s `TeacherHomeProvider`. Browsing,
// filtering, publishing, or deleting a course here no longer notifies (or
// risks rebuilding) the home dashboard.
//
// [onCoursesChanged] is an optional hook the owning screen can wire up so a
// mutation here (create/update/publish/unpublish/delete) can tell the
// teacher home dashboard its stats/preview are stale — without this
// provider holding a hard reference to `TeacherHomeProvider`. See
// `TeacherCoursesScreen.initState` for how it's wired.
// ─────────────────────────────────────────────────────────────────────────

import '../../../core/api_client.dart';
import '../../../core/base_provider.dart';
import '../home/teacher_models.dart';

class TeacherCoursesProvider extends BaseProvider {
  final ApiClient _api;

  /// Fired after any mutation (create/update/publish/unpublish/delete) so
  /// an owning screen can refresh other providers (e.g. the teacher home
  /// dashboard) without a hard dependency between the two providers.
  void Function()? onCoursesChanged;

  TeacherCoursesProvider({ApiClient? api, this.onCoursesChanged})
      : _api = api ?? ApiClient();

  // ── Course list state ────────────────────────────────────────────────────

  List<TeacherCourse> _allCourses = [];
  TeacherCourseStatus _activeFilter = TeacherCourseStatus.all;

  /// Page size used by [goToNextPage]/[goToPreviousPage]/[fetchPage]. The
  /// screen's footer paginates in units of this.
  static const int pageSize = 10;

  int _currentPage = 0;
  bool _hasMore = true;

  int get currentPage => _currentPage;

  /// Whether a page after the current one is known to exist — inferred
  /// from the last fetch returning a full page (the endpoint has no
  /// total-count field to read this from directly).
  bool get hasMore => _hasMore;

  bool get hasPreviousPage => _currentPage > 0;

  TeacherCourseStatus get activeFilter => _activeFilter;

  List<TeacherCourse> get allCourses => List.unmodifiable(_allCourses);

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
  // Fetch
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> fetchMyCourses({int skip = 0, int limit = pageSize}) async {
    final result = await run(() => _api.get(
      '/api/v1/my-courses',
      queryParams: {'skip': skip, 'limit': limit},
    ));
    if (result is List) {
      _allCourses = result
          .map((e) => TeacherCourse.fromJson(e as Map<String, dynamic>))
          .toList();
      // A full page came back, so there's likely at least one more.
      // Anything short of that is the last page.
      _hasMore = result.length == limit;
      notifyListeners();
    }
  }

  /// Fetches a specific page (0-based) using [pageSize], and updates
  /// [currentPage] so the footer reflects where we are.
  Future<void> fetchPage(int page) async {
    if (page < 0 || isLoading) return;
    _currentPage = page;
    await fetchMyCourses(skip: page * pageSize, limit: pageSize);
  }

  Future<void> goToNextPage() async {
    if (!_hasMore || isLoading) return;
    await fetchPage(_currentPage + 1);
  }

  Future<void> goToPreviousPage() async {
    if (!hasPreviousPage || isLoading) return;
    await fetchPage(_currentPage - 1);
  }

  Future<TeacherCourse?> fetchCourseById(int courseId) async {
    final result = await run(() => _api.get('/api/v1/courses/$courseId'));
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
    notifyListeners();
    onCoursesChanged?.call();
  }

  /// Replace an updated course in the list.
  void onCourseUpdated(TeacherCourse course) {
    _allCourses =
        _allCourses.map((c) => c.id == course.id ? course : c).toList();
    notifyListeners();
    onCoursesChanged?.call();
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
      onCoursesChanged?.call();
      return true;
    }
    return false;
  }

  Future<bool> unpublishCourse(int courseId) async {
    final result =
    await run(() => _api.post('/api/v1/courses/$courseId/unpublish'));
    if (result != null) {
      _updateLocalPublish(courseId, isPublished: false);
      onCoursesChanged?.call();
      return true;
    }
    return false;
  }

  Future<bool> deleteCourse(int courseId) async {
    await run(() => _api.delete(
      '/api/v1/courses/$courseId',
      queryParams: {'force': true},
    ));
    if (state == ProviderState.success) {
      _allCourses = _allCourses.where((c) => c.id != courseId).toList();
      notifyListeners();
      onCoursesChanged?.call();
      return true;
    }
    return false;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Private helpers
  // ─────────────────────────────────────────────────────────────────────────

  void _updateLocalPublish(int courseId, {required bool isPublished}) {
    _allCourses = _allCourses
        .map((c) =>
    c.id == courseId ? c.copyWith(isPublished: isPublished) : c)
        .toList();
    notifyListeners();
  }
}