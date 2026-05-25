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

  CourseStatus get activeFilter => _filter;

  List<CourseModel> get allCourses => List.unmodifiable(_all);

  int get allCount => _all.length;

  int get inProgressCount => _all.where(_ip).length;

  int get completedCount => _all.where(_done).length;

  void setQuery(String q) {
    _query = q;
    notifyListeners();
  }

  String _query = '';

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
            s.name.toLowerCase().contains(q) ||
            (s.description?.toLowerCase().contains(q) ?? false) ||
            (s.teacher?.name.toLowerCase().contains(q) ?? false))
        .toList();

  }

  void setFilter(CourseStatus f) {
    if (_filter == f) return;
    _filter = f;
    notifyListeners();
  }

  Future<void> fetchMyEnrollments() async {
    final r = await run(() => _api.get('/api/v1/my-enrolled-courses'));
    if (r is List) {
      _all = r.map((e) {
        return CourseModel.fromJson(e);
      }).toList();
      notifyListeners();
    }
  }
  static bool _ip(CourseModel c) => c.progress > 0 && c.progress < 100;

  static bool _done(CourseModel c) => c.progress >= 100;

  Future<void> init(List<CourseModel> homeCourses) async {
    if (homeCourses.isEmpty) {
      await fetchMyEnrollments();
    } else {
      _all = homeCourses;
    }
    notifyListeners();
  }
}
