/// courses/my_courses/my_courses_provider.dart
library;

import '../../../../core/api_client.dart';
import '../../../../core/base_provider.dart';
import '../../models.dart';

class MyCoursesProvider extends BaseProvider {
  final ApiClient _api;

  MyCoursesProvider({ApiClient? api}) : _api = api ?? ApiClient();

  List<CourseModel> _all = [];
  CourseStatus _filter = CourseStatus.all;
  String _query = '';

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

  /// Fetches the first page fresh (used on first open). Blanks the list while loading.
  Future<void> fetchMyEnrollments() async {
    _gen++;
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
    final gen = ++_gen;
    _pageFailed = false;
    final r = await run(() => _api.get('/api/v1/my-enrolled-courses',
        queryParams: {'skip': 0, 'limit': _pageSize}));
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
    if (!_hasMore || isLoading || _pageFailed) return;
    await _loadPage();
  }

  Future<void> _loadPage() async {
    final gen = _gen;
    final r = await run(() => _api.get('/api/v1/my-enrolled-courses',
        queryParams: {'skip': _skip, 'limit': _pageSize}));
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
    _all = replace ? page : [..._all, ...page];
    _skip = _all.length;
    final hasTotal = r['total'] is num;
    if (hasTotal) _total = (r['total'] as num).toInt();
    // Trust the server total (the old `page.length == 20` test kept a spinner forever when the
    // last page happened to be exactly full, and when the list was seeded from the home screen).
    _hasMore = page.isNotEmpty &&
        (hasTotal ? _all.length < _total : page.length >= _pageSize);
    notifyListeners();
  }

  static bool _ip(CourseModel c) => c.progress > 0 && c.progress < 100;

  static bool _done(CourseModel c) => c.progress >= 100;

  /// Called with the home screen's already-fetched courses (if any) for an
  /// instant first paint. If those were provided, we treat them as page 1
  /// and let [loadMore] fetch page 2 onward from the server; otherwise we
  /// fetch page 1 ourselves.
  Future<void> init(List<CourseModel> homeCourses) async {
    if (homeCourses.isEmpty) {
      await fetchMyEnrollments();
    } else {
      _gen++;
      _pageFailed = false;
      _all = List.of(homeCourses); // own copy: the home list is replaced / mutated independently
      _skip = homeCourses.length;
      _total = 0;
      _hasMore = true;
      notifyListeners();
      _syncTotal(_gen); // learn the server total without blocking the first paint
    }
  }

  /// One-row request just to read `total` (the home list we were seeded with doesn't carry it).
  Future<void> _syncTotal(int gen) async {
    try {
      final r = await _api.get('/api/v1/my-enrolled-courses',
          queryParams: {'skip': 0, 'limit': 1});
      if (gen != _gen) return;
      if (r is Map && r['total'] is num) {
        _total = (r['total'] as num).toInt();
        _hasMore = _all.length < _total;
        notifyListeners();
      }
    } catch (_) {
      // non-critical: the card just stays hidden and scrolling still loads pages
    }
  }
}