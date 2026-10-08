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

import 'dart:async';

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

  /// Pages already fetched for the CURRENT search query, keyed by page
  /// index, so going back to a page you've already seen is instant — no
  /// spinner, no request. Cleared whenever the query changes (a different
  /// search has a different result set) and re-synced after any mutation
  /// (create/update/publish/unpublish/delete), since those can shift which
  /// course falls on which page.
  final Map<int, List<TeacherCourse>> _pageCache = {};

  /// Page size used by [goToNextPage]/[goToPreviousPage]/[fetchPage]. The
  /// screen's footer paginates in units of this.
  static const int pageSize = 10;

  int _currentPage = 0;
  bool _hasMore = true;

  /// Total number of courses matching the current filter/search, as
  /// reported by the server alongside each page — not just how many are
  /// loaded on this page.
  int _totalCount = 0;

  int get currentPage => _currentPage;
  int get totalCount => _totalCount;

  /// Total number of pages at [pageSize], at least 1 so an empty result
  /// still reads as "page 1 of 1" rather than "of 0".
  int get totalPages =>
      _totalCount == 0 ? 1 : (_totalCount / pageSize).ceil();

  /// Whether a page after the current one exists. Uses [_totalCount] once
  /// the server has reported one; falls back to "did the last page come back
  /// full" only before the first fetch completes.
  bool get hasMore =>
      _totalCount > 0 ? (_currentPage + 1) * pageSize < _totalCount : _hasMore;

  bool get hasPreviousPage => _currentPage > 0;

  // ── Search (server-side; debounced so we don't fire on every keystroke) ──

  String _query = '';
  Timer? _searchDebounce;

  String get query => _query;

  /// Re-fetches page 1 with the new query shortly after the user stops
  /// typing, rather than filtering the (partial) loaded page on the client.
  void setQuery(String q) {
    if (_query == q) return;
    _query = q;
    _pageCache.clear(); // a different search has a different result set
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      fetchPage(0, force: true);
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

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

  /// Returns true when the page came back and [_allCourses] was updated —
  /// callers use this to know whether it's safe to cache the result.
  Future<bool> fetchMyCourses({int skip = 0, int limit = pageSize}) async {
    final result = await run(() => _api.get(
      '/api/v1/my-courses',
      queryParams: {
        'skip': skip,
        'limit': limit,
        if (_query.trim().isNotEmpty) 'search': _query.trim(),
      },
    ));
    // New shape: {"items": [...], "total": N}. A bare List is kept working
    // for as long as an older server is still deployed — total then falls
    // back to page-length guessing, same as before this change.
    if (result is Map && result['items'] is List) {
      _allCourses = (result['items'] as List)
          .map((e) => TeacherCourse.fromJson(e as Map<String, dynamic>))
          .toList();
      _totalCount = (result['total'] as num?)?.toInt() ?? _allCourses.length;
      _hasMore = _allCourses.length == limit;
      notifyListeners();
      return true;
    } else if (result is List) {
      _allCourses = result
          .map((e) => TeacherCourse.fromJson(e as Map<String, dynamic>))
          .toList();
      _totalCount = 0; // unknown — legacy server response
      _hasMore = result.length == limit;
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Fetches a specific page (0-based) using [pageSize], and updates
  /// [currentPage] so the footer reflects where we are.
  ///
  /// A page already seen for the current search is served from
  /// [_pageCache] instantly — no spinner, no request — so paging back and
  /// forth (e.g. next → previous) feels immediate. Pass [force]: true to
  /// bypass that and re-fetch anyway (pull-to-refresh).
  Future<void> fetchPage(int page, {bool force = false}) async {
    if (page < 0 || isLoading) return;
    _currentPage = page;

    if (!force) {
      final cached = _pageCache[page];
      if (cached != null) {
        _allCourses = cached;
        notifyListeners();
        return;
      }
    }

    final ok = await fetchMyCourses(skip: page * pageSize, limit: pageSize);
    if (ok) _pageCache[page] = _allCourses;
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
    _syncCacheAfterMutation();
    onCoursesChanged?.call();
  }

  /// Replace an updated course in the list.
  void onCourseUpdated(TeacherCourse course) {
    _allCourses =
        _allCourses.map((c) => c.id == course.id ? course : c).toList();
    notifyListeners();
    _syncCacheAfterMutation();
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
      _syncCacheAfterMutation();
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
    _syncCacheAfterMutation();
  }

  /// A mutation can shift which course falls on which page (a new course
  /// pushes everything else down a slot, a delete pulls everything after it
  /// up one), so cached pages OTHER than the one we're already viewing can
  /// no longer be trusted. Keep just the current page (already updated
  /// in-place above) and let the others be re-fetched on demand.
  void _syncCacheAfterMutation() {
    _pageCache
      ..clear()
      ..[_currentPage] = _allCourses;
  }
}