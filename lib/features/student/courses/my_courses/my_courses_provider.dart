/// courses/my_courses/my_courses_provider.dart
///
/// The student's enrolled courses, one side at a time (lib/features/shared/course/course_scope.dart):
/// the side follows the app mode (personal account ↔ the open organization) until the student picks another
/// chip; the personal account with no personal course opens on "All" ([smartStudentScope]). The first page's
/// `scopes` counts every side for the chip bar. An older server ignores the scope and answers everything.
library;

import '../../../../core/api_client.dart';
import '../../../../core/app_mode.dart';
import '../../../../core/base_provider.dart';
import '../../../shared/course/course_scope.dart';
import '../../models.dart';

class MyCoursesProvider extends BaseProvider {
  final ApiClient _api;

  /// [mode] defaults to the app's AppModeController; [followMode] false keeps the list on "All" (tests).
  MyCoursesProvider({ApiClient? api, AppModeController? mode, bool followMode = true})
      : _api = api ?? ApiClient(),
        _mode = followMode ? (mode ?? AppModeController.instance) : null {
    final m = _mode;
    if (m != null) {
      _modeScope = _scopeOf(m);
      m.addListener(_onMode);
    }
  }

  final AppModeController? _mode;

  List<CourseModel> _all = [];
  CourseStatus _filter = CourseStatus.all;
  String _query = '';

  // ── Scope (personal account ↔ organizations) ─────────────────────────────

  CourseScope _modeScope = CourseScope.all;
  CourseScope? _picked;                    // the student's own chip, until the mode changes
  CourseScope _loadedScope = CourseScope.all;
  List<CourseScopeCount> _scopes = const [];
  bool _started = false;

  static CourseScope _scopeOf(AppModeController m) => CourseScope.forMode(isOrg: m.isOrg, orgId: m.currentOrgId);

  /// The side shown: the student's pick, else the mode's (or "All" when the personal account is empty).
  CourseScope get scope => smartStudentScope(_modeScope, _scopes, picked: _picked);

  /// The mode's side (Organization mode → that organization).
  CourseScope get modeScope => _modeScope;

  /// Every side counted by the server (first page); empty on an older server.
  List<CourseScopeCount> get scopes => _scopes;

  void selectScope(CourseScope s) {
    if (s == scope) return;
    _picked = s;
    _followScope();
  }

  void _onMode() {
    final m = _scopeOf(_mode!);
    if (m == _modeScope) return;
    _modeScope = m;
    _picked = null; // a new mode starts on its own side
    _followScope();
  }

  /// Loads the shown side when it is not the one on screen (nothing before the tab was ever opened).
  void _followScope() {
    if (!_started || scope == _loadedScope) {
      notifyListeners();
      return;
    }
    fetchMyEnrollments();
  }

  @override
  void dispose() {
    _mode?.removeListener(_onMode);
    super.dispose();
  }

  // ── Pagination ────────────────────────────────────────────────────────────
  int _skip = 0;
  int _total = 0; // server total of enrolled courses (0 = not known yet)
  bool _hasMore = true;
  static const _pageSize = 20;

  /// A page request failed → stop auto-paging (scroll / fill-viewport) until the next refresh,
  /// otherwise a failing endpoint would be hammered in a loop.
  bool _pageFailed = false;

  /// Bumped on every refresh / re-init. A page request that started before that must be dropped when it
  /// answers late, otherwise an old page is appended to the NEW list (duplicated / out-of-order courses).
  int _gen = 0;

  bool get hasMore => _hasMore;

  /// Total enrolled courses on the server — drives the "Showing 40 of 134" card.
  int get total => _total;

  /// True only while fetching another page onto an already-populated list —
  /// distinct from the initial-load spinner, so the UI can show a small
  /// footer loader instead of blanking the whole list.
  bool get isLoadingMore => isLoading && _all.isNotEmpty;

  CourseStatus get activeFilter => _filter;

  List<CourseModel> get allCourses => List.unmodifiable(_all);

  int get allCount => _all.length;

  int get inProgressCount => _all.where(_ip).length;

  int get completedCount => _all.where(_done).length;

  void setQuery(String q) {
    _query = q;
    notifyListeners();
  }

  List<CourseModel> get filteredCourses {
    List<CourseModel> list = switch (_filter) {
      CourseStatus.all => _all,
      CourseStatus.inProgress => _all.where(_ip).toList(),
      CourseStatus.completed => _all.where(_done).toList(),
    };
    if (_query.isEmpty) return List.unmodifiable(list);
    final q = _query.toLowerCase();
    return list
        .where((s) =>
    (s.titleAr?.toLowerCase().contains(q) ?? false) ||
        (s.titleEn?.toLowerCase().contains(q) ?? false) ||
        (s.descriptionAr?.toLowerCase().contains(q) ?? false) ||
        (s.descriptionEn?.toLowerCase().contains(q) ?? false) ||
        (s.teacher?.name.toLowerCase().contains(q) ?? false))
        .toList();
  }

  void setFilter(CourseStatus f) {
    if (_filter == f) return;
    _filter = f;
    notifyListeners();
  }

  Map<String, dynamic> _params(int skip, [int limit = _pageSize]) =>
      {'skip': skip, 'limit': limit, ..._loadedScope.query};

  /// Fetches the first page fresh (used on first open and on a side change). Blanks the list while loading.
  Future<void> fetchMyEnrollments() async {
    _started = true;
    _gen++;
    _loadedScope = scope;
    _skip = 0;
    _total = 0;
    _hasMore = true;
    _pageFailed = false;
    _all = [];
    notifyListeners();
    await _loadPage();
  }

  /// Pull-to-refresh: reloads page 1 and replaces the list WITHOUT blanking it first,
  /// so the RefreshIndicator / scroll view stay alive.
  Future<void> refresh() async {
    _started = true;
    final gen = ++_gen;
    _pageFailed = false;
    final r = await run(() => _api.get('/api/v1/my-enrolled-courses', queryParams: _params(0)));
    if (gen != _gen) return; // another refresh / re-init started meanwhile
    if (r is Map && r['items'] is List) {
      _apply(r, replace: true);
    } else {
      notifyListeners();
    }
  }

  /// Fetches the next page and appends it. No-ops while a fetch is already
  /// in flight, once the server has told us there's nothing more, or after a failure.
  Future<void> loadMore() async {
    if (!_hasMore || isLoading || _pageFailed || _pageGen == _gen) return;
    await _loadPage();
  }

  /// The generation whose page request is in flight (-1 = none). `isLoading` alone is not enough: a dropped
  /// request of an older generation sets the state back to success while the new page is still loading, and
  /// the fill-the-viewport pager (wide screens) then asked for the same page again → every course twice (H4).
  int _pageGen = -1;

  Future<void> _loadPage() async {
    final gen = _gen;
    _pageGen = gen;
    final r = await run(() => _api.get('/api/v1/my-enrolled-courses', queryParams: _params(_skip)));
    if (_pageGen == gen) _pageGen = -1;
    if (gen != _gen) return; // a refresh started while this page was loading
    if (r is Map && r['items'] is List) {
      _apply(r, replace: false);
    } else {
      _pageFailed = true;
      notifyListeners();
    }
  }

  /// Applies a server page: replaces the list (refresh) or appends to it (next page).
  void _apply(Map r, {required bool replace}) {
    final page =
    (r['items'] as List).map((e) => CourseModel.fromJson(e)).toList();
    if (replace) {
      _all = page;
    } else {
      final seen = {for (final c in _all) c.id};
      _all = [..._all, ...page.where((c) => seen.add(c.id))]; // never the same course twice
    }
    _skip = _all.length;
    final hasTotal = r['total'] is num;
    if (hasTotal) _total = (r['total'] as num).toInt();
    // Trust the server total (the old `page.length == 20` test kept a spinner forever when the
    // last page happened to be exactly full, and when the list was seeded from the home screen).
    _hasMore = page.isNotEmpty &&
        (hasTotal ? _all.length < _total : page.length >= _pageSize);
    _takeScopes(r);
  }

  /// Reads `scopes` (first pages carry it) and follows the side they make the default — e.g. the personal
  /// account turns out to be empty while organizations hold courses → "All".
  void _takeScopes(Map r) {
    if (r['scopes'] is List) _scopes = parseCourseScopes(r);
    if (_scopes.isNotEmpty && serverScoped(r) && scope != _loadedScope) {
      fetchMyEnrollments();
      return;
    }
    notifyListeners();
  }

  /// N8: "In progress" is every enrolled course not completed yet, a 0 % one included, so All = In progress +
  /// Completed (a course at 0 % sat in neither filter).
  static bool _ip(CourseModel c) => c.progress < 100;

  static bool _done(CourseModel c) => c.progress >= 100;

  /// Called with the home screen's already-fetched courses (every enrolment, any side) for an instant first
  /// paint. They stand for page 1 only while the side shown is "All"; another side loads its own page 1
  /// (refreshed in place when it is already on screen).
  Future<void> init(List<CourseModel> homeCourses) async {
    if (!scope.isAll) {
      if (_started && _loadedScope == scope && _all.isNotEmpty) {
        await refresh();
      } else {
        await fetchMyEnrollments();
      }
      return;
    }
    if (homeCourses.isEmpty) {
      await fetchMyEnrollments();
    } else {
      _started = true;
      _gen++;
      _loadedScope = CourseScope.all;
      _pageFailed = false;
      _all = List.of(homeCourses); // own copy: the home list is replaced / mutated independently
      _skip = homeCourses.length;
      _total = 0;
      _hasMore = true;
      notifyListeners();
      _syncTotal(_gen); // learn the server total (and the sides) without blocking the first paint
    }
  }

  /// One-row request just to read `total` and `scopes` (the home list we were seeded with carries neither).
  Future<void> _syncTotal(int gen) async {
    try {
      final r = await _api.get('/api/v1/my-enrolled-courses', queryParams: _params(0, 1));
      if (gen != _gen) return;
      if (r is Map && r['total'] is num) {
        _total = (r['total'] as num).toInt();
        _hasMore = _all.length < _total;
        if (r['scopes'] is List) _scopes = parseCourseScopes(r);
        notifyListeners();
      }
    } catch (_) {
      // non-critical: the card just stays hidden and scrolling still loads pages
    }
  }
}
