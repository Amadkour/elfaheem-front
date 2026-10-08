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
  bool _hasMore = true;
  static const _pageSize = 20;

  /// Bumped on every refresh / re-init. A page request that started before that must be dropped when it
  /// answers late, otherwise an old page is appended to the NEW list (duplicated / out-of-order courses).
  int _gen = 0;

  bool get hasMore => _hasMore;

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
    List<CourseModel> list= switch (_filter) {
      CourseStatus.all => _all,
      CourseStatus.inProgress => _all.where(_ip).toList(),
      CourseStatus.completed => _all.where(_done).toList(),
    };
    if (_query.isEmpty) return List.unmodifiable(list);
    final q = _query.toLowerCase();
    return list
        .where((s) =>
    (s.titleAr?.toLowerCase().contains(q) ?? false) ||
        (s.titleEn?.toLowerCase().contains(q) ?? false) || // was titleAr twice → English titles were never searchable
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

  /// Fetches the first page fresh (used on pull-to-refresh / first open).
  Future<void> fetchMyEnrollments() async {
    _gen++;
    _skip = 0;
    _hasMore = true;
    _all = [];
    notifyListeners();
    await _loadPage();
  }

  /// Fetches the next page and appends it. No-ops while a fetch is already
  /// in flight or once the server has told us there's nothing more.
  Future<void> loadMore() async {
    if (!_hasMore || isLoading) return;
    await _loadPage();
  }

  Future<void> _loadPage() async {
    final gen = _gen;
    final r = await run(() => _api.get('/api/v1/my-enrolled-courses',
        queryParams: {'skip': _skip, 'limit': _pageSize}));
    if (gen != _gen) return; // a refresh started while this page was loading
    if (r is Map && r['items'] is List) {
      final page = (r['items'] as List)
          .map((e) => CourseModel.fromJson(e))
          .toList();
      _all = [..._all, ...page];
      _skip += page.length;
      _hasMore = page.length == _pageSize;
      notifyListeners();
    }
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
      _all = List.of(homeCourses); // own copy: the home list is replaced / mutated independently
      _skip = homeCourses.length;
      _hasMore = true;
      notifyListeners();
    }
  }
}