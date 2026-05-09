import '../../../../core/api_client.dart';
import '../../../../core/base_provider.dart';
import '../../models.dart';

class CoursesProvider extends BaseProvider {
  final ApiClient _api;

  CoursesProvider({ApiClient? api}) : _api = api ?? ApiClient();

  List<CourseModel> _courses = [];
  int _skip = 0;
  bool _hasMore = true;
  static const _pageSize = 20;

  List<CourseModel> get courses => List.unmodifiable(_courses);
  List<CourseModel> get explorHomecourses => List.unmodifiable(_courses.where((e)=>!e.isEnrolled));
  List<CourseModel> get myCourses => List.unmodifiable(_courses.where((e)=>e.isEnrolled));

  bool get hasMore => _hasMore;

  Future<void> fetchCourses(
      {String? categoryId, int? teacherId, String? search}) async {
    _skip = 0;
    _hasMore = true;
    _courses.clear();
    await _loadPage(
        categoryId: categoryId, teacherId: teacherId, search: search);
    notifyListeners();
  }

  Future<void> loadMore(
      {String? categoryId, int? teacherId, String? search}) async {
    if (!_hasMore || isLoading) return;
    await _loadPage(
        categoryId: categoryId, teacherId: teacherId, search: search);
  }

  Future<void> _loadPage(
      {String? categoryId, int? teacherId, String? search}) async {
    final r = await run(() => _api.get('/api/v1/courses',
        queryParams: {
          'skip': _skip,
          'limit': _pageSize,
          if (categoryId != null) 'category_id': categoryId,
          if (teacherId != null) 'teacher_id': teacherId,
          if (search != null) 'search': search
        },
        auth: true));
    if (r is Map && r['items'] is List) {
      final page = (r['items'] as List)
          .map((e) => CourseModel.fromJson(e as Map<String, dynamic>))
          .toList();
      _courses = [..._courses, ...page];
      _skip += page.length;
      _hasMore = page.length == _pageSize;
      notifyListeners();
    }
  }

  Future<void> toggleFavorite(String courseId) async {
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
