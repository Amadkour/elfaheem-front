/// courses/list/courses_provider.dart
///
/// The course CATALOGUE (GET /api/v1/courses): "Explore other courses" and the home's search box, page by page
/// (AppInfiniteScroll in HomeCourseList asks for the next one).
///
/// Paging rules (the "only the first 6 courses" bug, test/ui/course_list_paging_test.dart):
///   • the filter of page 1 (category / teacher / search / page size) is kept for every next page — a next page
///     never mixes another filter in;
///   • one page request at a time; a page that answers after a reset (new search, other side) is dropped;
///   • a course already listed is never added twice (offset pages shift when a course is published meanwhile);
///   • more pages = the server total says so (`items.length < total`), else "the last page came back full".
///
/// Side (personal account ↔ organization): every request sends `scope` from AppModeController — Individual mode
/// `scope=personal`, Organization mode `scope=org&org_id=…` (course_scope.dart). A mode / organization switch empties
/// the list and loads page 1 of the new side (only once the catalogue was opened: no request at app start).
library;

import 'package:flutter_education_app/utils/widget/view_as_state.dart';
import '../../../../core/api_client.dart';
import '../../../../core/app_mode.dart';
import '../../../../core/base_provider.dart';
import '../../../shared/course/course_scope.dart';
import '../../models.dart';

class CoursesProvider extends BaseProvider {
  final ApiClient _api;

  /// [mode] defaults to the app's AppModeController; [followMode] false stays on the personal account (tests).
  CoursesProvider({ApiClient? api, AppModeController? mode, bool followMode = true})
      : _api = api ?? ApiClient(),
        _mode = followMode ? (mode ?? AppModeController.instance) : null {
    final m = _mode;
    if (m != null) {
      _scope = _scopeOf(m);
      m.addListener(_onMode);
    }
  }

  final AppModeController? _mode;

  static const pageSize = 20;

  List<CourseModel> _courses = [];

  /// Server rows consumed so far (the next page's `skip`). Not `_courses.length`: a page that only repeats known
  /// courses (rows shifted on the server) still moves the offset on — the same page is never asked twice in a loop.
  int _skip = 0;
  int _total = 0;
  bool _hasMore = true;
  bool _pageFailed = false;
  bool _started = false;

  /// Bumped by every reset: an answer of an older generation is dropped.
  int _gen = 0;

  /// The generation whose page is in flight (-1 = none) — one page request at a time.
  int _pageGen = -1;

  // the filter of the list on screen (page 1's), reused by every next page
  String? _categoryId;
  int? _teacherId;
  String? _search;
  int _limit = pageSize;

  /// Never "all" here: GET /courses answers 422 to it (no mode to follow → the personal account, the server's default).
  CourseScope _scope = CourseScope.personal;

  static CourseScope _scopeOf(AppModeController m) => CourseScope.forMode(isOrg: m.isOrg, orgId: m.currentOrgId);

  /// The side listed (Individual mode → personal, Organization mode → that organization).
  CourseScope get scope => _scope;

  void _onMode() {
    final s = _scopeOf(_mode!);
    if (s == _scope) return;
    _scope = s;
    if (!_started) return; // never opened: nothing to reload
    fetchCourses(categoryId: _categoryId, teacherId: _teacherId, search: _search, pageSize: _limit);
  }

  @override
  void dispose() {
    _mode?.removeListener(_onMode);
    super.dispose();
  }

  List<CourseModel> get courses => List.unmodifiable(_courses);
  List<CourseModel> get explorHomecourses => List.unmodifiable(_courses.where((e) => !e.isEnrolled));
  List<CourseModel> get myCourses => List.unmodifiable(_courses.where((e) => e.isEnrolled));

  bool get hasMore => _hasMore;

  /// The last page request failed: only scrolling again retries it ([loadMore] with `retry`).
  bool get pageFailed => _pageFailed;

  /// Server total for the current filter (GET /courses → `total`) — drives the "Showing 40 of 134" card.
  int get total => _total;

  /// True only while fetching another page onto an already-populated list —
  /// distinct from the initial-load spinner, so the UI can show a small
  /// footer loader instead of blanking the whole list.
  bool get isLoadingMore => isLoading && _courses.isNotEmpty;

  /// Page 1 of a (new) filter: empties the list and loads it again.
  Future<void> fetchCourses({String? categoryId, int? teacherId, String? search, int? pageSize}) async {
    _started = true;
    _gen++;
    _categoryId = categoryId;
    _teacherId = teacherId;
    _search = (search ?? '').trim().isEmpty ? null : search!.trim();
    _limit = pageSize ?? CoursesProvider.pageSize;
    _skip = 0;
    _total = 0;
    _hasMore = true;
    _pageFailed = false;
    _courses = [];
    notifyListeners();
    await _loadPage();
  }

  /// The next page of the list on screen. The filter arguments are kept for older callers and ignored: a next page
  /// always uses page 1's filter. No-op before page 1, while a page is in flight, once everything is loaded, or after
  /// a failure (until [retry]: the person scrolled again).
  Future<void> loadMore({String? categoryId, int? teacherId, String? search, int? pageSize, bool retry = false}) async {
    if (!_started || !_hasMore || _pageGen == _gen) return;
    if (_pageFailed && !retry) return;
    _pageFailed = false;
    await _loadPage();
  }

  Map<String, dynamic> get _query => {
        'skip': _skip,
        'limit': _limit,
        'category_id': ?_categoryId,
        'teacher_id': ?_teacherId,
        'search': ?_search,
        ..._scope.query,
      };

  Future<void> _loadPage() async {
    final gen = _gen;
    _pageGen = gen;
    final r = await run(() => _api.get('/api/v1/courses', queryParams: _query, auth: true));
    if (_pageGen == gen) _pageGen = -1;
    if (gen != _gen) return; // a new filter / side started meanwhile
    if (r is! Map || r['items'] is! List) {
      _pageFailed = true;
      notifyListeners();
      return;
    }
    final page = (r['items'] as List).whereType<Map<String, dynamic>>().map(CourseModel.fromJson).toList();
    _skip += page.length;
    final seen = {for (final c in _courses) c.id};
    _courses = [..._courses, ...page.where((c) => seen.add(c.id))]; // never the same course twice
    final total = r['total'];
    // trust the server total; without one, a full page means "maybe more" (compared with the size ASKED for)
    _total = total is num ? total.toInt() : _courses.length;
    _hasMore = page.isNotEmpty && (serverHasMore(r) ?? (total is num ? _skip < _total : page.length >= _limit));
    notifyListeners();
  }

  Future<void> toggleFavorite(String courseId) async {
    if (ViewAsState.active) return;
    final idx = _courses.indexWhere((c) => c.id == courseId);
    if (idx == -1) return;
    final cur = _courses[idx];
    final nv = !cur.isFavorite;
    _courses[idx].isFavorite = nv;
    notifyListeners();
    try {
      if (nv) {
        await _api.post('/api/v1/courses/$courseId/favorite');
      } else {
        await _api.delete('/api/v1/courses/$courseId/favorite');
      }
    } catch (_) {
      _courses[idx].isFavorite = !nv;
      notifyListeners();
    }
  }
}
