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
//
// INFINITE SCROLL
// ─────────────────────────────────────────────────────────────────────────
// The list is cumulative (same model as the admin lists): [refresh] loads the
// first page and REPLACES the list, [loadMore] APPENDS the next page. The
// screen shows "Showing {loadedCount} of {totalCount}" with a progress bar
// (PagedCountCard) and calls [loadMore] when the scroll nears the end.
//
// SCOPE
// ─────────────────────────────────────────────────────────────────────────
// The list follows the app mode by itself (AppModeController): the personal
// account shows only courses outside any organization, Organization mode
// only that organization's ([setScope], `scope` / `org_id` on the request,
// lib/features/courses/course_scope.dart) — so every reader (courses
// tab, analytics hub) sees the same side. The first page's `scopes`
// counts every side for the banner. An older server ignores the scope and
// answers everything; the list then shows what it got.
// ─────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/core/base_provider.dart';
import 'package:flutter_education_app/features/courses/course_scope.dart';
import 'package:flutter_education_app/features/home/teacher/teacher_models.dart';

class TeacherCoursesProvider extends BaseProvider {
  final ApiClient _api;

  /// Fired after any mutation (create/update/publish/unpublish/delete) so
  /// an owning screen can refresh other providers (e.g. the teacher home
  /// dashboard) without a hard dependency between the two providers.
  void Function()? onCoursesChanged;

  /// [mode] defaults to the app's AppModeController; tests pass their own (or none via [followMode] false).
  TeacherCoursesProvider({ApiClient? api, this.onCoursesChanged, AppModeController? mode, bool followMode = true})
      : _api = api ?? ApiClient(),
        _mode = followMode ? (mode ?? AppModeController.instance) : null {
    final m = _mode;
    if (m != null) {
      _scope = _modeScope(m);
      m.addListener(_onMode);
    }
  }

  final AppModeController? _mode;

  static CourseScope _modeScope(AppModeController m) =>
      CourseScope.forMode(isOrg: m.isOrg, orgId: m.currentOrgId);

  void _onMode() => setScope(_modeScope(_mode!));

  // ── Course list state ────────────────────────────────────────────────────

  List<TeacherCourse> _allCourses = [];
  TeacherCourseStatus _activeFilter = TeacherCourseStatus.all;

  /// How many courses each request asks for (first page and every append).
  static const int pageSize = 12;

  /// Only used before the server has reported a total (legacy list response):
  /// "did the last page come back full".
  bool _hasMore = true;

  /// Total number of courses matching the current search, as reported by the
  /// server alongside each page — not just how many are loaded so far.
  int _totalCount = 0;

  bool _loadingMore = false;

  /// The last [loadMore] failed (or returned nothing new). Automatic loading
  /// pauses until the user scrolls again — prevents hammering a broken server.
  bool _loadMoreFailed = false;

  /// Bumped by every [refresh]; a response that belongs to an older value is
  /// dropped (e.g. an append that was in flight when the search text changed).
  int _generation = 0;

  int get totalCount => _totalCount;

  // ── Scope (personal account ↔ one organization) ─────────────────────────

  CourseScope _scope = CourseScope.all;
  List<CourseScopeCount> _scopes = const [];
  bool _scopeApplied = false;

  CourseScope get scope => _scope;

  /// Every side counted by the server (first page); empty on an older server.
  List<CourseScopeCount> get scopes => _scopes;

  /// The server filtered the list by [scope] (false on an older server: everything is listed).
  bool get scopeApplied => _scopeApplied;

  /// Courses on the other sides than [scope] (the banner's "+n in your organizations").
  int get elsewhereCount => _scopes.isEmpty || _scope.isAll
      ? 0
      : (countFor(_scopes, CourseScope.all) - countFor(_scopes, _scope)).clamp(0, 1 << 30);

  /// Shows [s] from now on; a change empties the list (the old side's courses never flash) and loads it again —
  /// only when a list was loaded before: a provider nobody has opened yet makes no request (app start budgets).
  void setScope(CourseScope s) {
    if (s == _scope) return;
    _scope = s;
    final wasLoaded = _loadedOnce;
    _generation++; // a page of the old side still in flight is dropped
    _allCourses = [];
    _totalCount = 0;
    _hasMore = true;
    _scopes = const [];
    _scopeApplied = false;
    if (wasLoaded) {
      refresh();
    } else {
      notifyListeners();
    }
  }

  bool _loadedOnce = false;

  /// A first load was asked for (the Courses tab, Analytics, …). Before it, an empty list means "not loaded yet".
  bool get loadedOnce => _loadedOnce;

  /// Loads the first page once, for whichever screen opens first (the tabs are lazy: Analytics may be visited
  /// before Courses). Nothing happens when a load already ran or is running.
  Future<void> ensureLoaded() async {
    if (_loadedOnce || isLoading) return;
    await refresh();
  }

  /// Courses loaded so far (for the progress card).
  int get loadedCount => _allCourses.length;

  bool get loadingMore => _loadingMore;
  bool get loadMoreFailed => _loadMoreFailed;

  /// Whether more courses exist on the server than are loaded. Uses
  /// [_totalCount] once the server has reported one; falls back to "did the
  /// last page come back full" for a legacy list-only response.
  bool get hasMore =>
      _totalCount > 0 ? _allCourses.length < _totalCount : _hasMore;

  // ── Search (server-side; debounced so we don't fire on every keystroke) ──

  String _query = '';
  Timer? _searchDebounce;

  String get query => _query;

  /// Re-fetches the first page with the new query shortly after the user
  /// stops typing, rather than filtering the (partial) loaded list.
  void setQuery(String q) {
    if (_query == q) return;
    _query = q;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), refresh);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _mode?.removeListener(_onMode);
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

  Map<String, dynamic> _params(int skip) => {
    'skip': skip,
    'limit': pageSize,
    if (_query.trim().isNotEmpty) 'search': _query.trim(),
    ..._scope.query,
  };

  /// New shape: {"items": [...], "total": N}. A bare List is kept working for
  /// as long as an older server is still deployed (total is then unknown).
  /// Returns null when the response is not one of the two shapes.
  ({List<TeacherCourse> items, int? total})? _parse(dynamic result) {
    if (result is Map && result['items'] is List) {
      return (
      items: (result['items'] as List)
          .map((e) => TeacherCourse.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: (result['total'] as num?)?.toInt(),
      );
    }
    if (result is List) {
      return (
      items: result
          .map((e) => TeacherCourse.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: null,
      );
    }
    return null;
  }

  /// Loads the first page and replaces the list (initial load, pull-to-refresh,
  /// and every search change).
  Future<void> refresh() async {
    final gen = ++_generation;
    _loadMoreFailed = false;
    _loadedOnce = true;
    final result = await run(() => _api.get(
      '/api/v1/my-courses',
      queryParams: _params(0),
    ));
    if (gen != _generation) return; // a newer refresh superseded this one
    final page = _parse(result);
    if (page == null) return; // error state already set by run()
    _allCourses = page.items;
    _totalCount = page.total ?? 0; // 0 = unknown (legacy server response)
    _scopes = parseCourseScopes(result);
    _scopeApplied = serverScoped(result);
    _hasMore = serverHasMore(result) ?? page.items.length == pageSize;
    notifyListeners();
  }

  /// Appends the next page. Safe to call as often as the scroll fires: it does
  /// nothing while a load is running, when everything is loaded, or after a
  /// failure (until [retry] is true — i.e. the user scrolled again).
  Future<void> loadMore({bool retry = false}) async {
    if (_loadingMore || isLoading || !hasMore) return;
    if (_loadMoreFailed && !retry) return;

    final gen = _generation;
    _loadingMore = true;
    _loadMoreFailed = false;
    notifyListeners();
    try {
      final result = await _api.get(
        '/api/v1/my-courses',
        queryParams: _params(_allCourses.length),
      );
      if (gen != _generation) return; // list was reset while we were loading
      final page = _parse(result);
      if (page == null) {
        _loadMoreFailed = true;
        return;
      }
      final seen = _allCourses.map((c) => c.id).toSet();
      final fresh = page.items.where((c) => seen.add(c.id)).toList();
      _allCourses = [..._allCourses, ...fresh];
      if (page.total != null) _totalCount = page.total!;
      _hasMore = serverHasMore(result) ?? page.items.length == pageSize;
      // Nothing new although the server says more exist → stop auto-loading.
      if (fresh.isEmpty) _loadMoreFailed = true;
    } catch (_) {
      _loadMoreFailed = true;
    } finally {
      _loadingMore = false;
      notifyListeners();
    }
  }

  /// Kept for callers written against the old page-based API: page 0 reloads
  /// the list, any other page appends the next one.
  Future<void> fetchPage(int page, {bool force = false}) =>
      page == 0 ? refresh() : loadMore(retry: true);

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

  /// Prepend a newly created course to the list — unless the list shows another side (a course created here is
  /// a personal one: it does not belong in an organization's list).
  void onCourseCreated(TeacherCourse course) {
    if (_scope.matches(course.org)) {
      _allCourses = [course, ..._allCourses];
      _bumpTotal(1);
      notifyListeners();
    }
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
  // Filter (client-side on the loaded courses — the screen keeps loading
  // pages in the background while a filter is active so it sees them all)
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
      _bumpTotal(-1);
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

  /// Keeps the server-reported total in step with local create/delete so the
  /// progress card and [hasMore] stay correct without a refetch. The list is
  /// offset-based (skip = loaded count), so a prepend/removal here matches the
  /// server's own shift and the next page still lines up.
  void _bumpTotal(int delta) {
    if (_totalCount > 0 || (delta > 0 && _allCourses.length == 1)) {
      _totalCount = (_totalCount + delta).clamp(0, 1 << 30);
    }
  }
}