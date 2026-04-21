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
  String _q = '';

  CourseStatus get activeFilter => _filter;
  List<CourseModel> get allCourses => List.unmodifiable(_all);
  int get allCount        => _all.length;
  int get inProgressCount => _all.where(_ip).length;
  int get completedCount  => _all.where(_done).length;

  List<CourseModel> get filteredCourses {
    final list = switch(_filter){
      CourseStatus.all        => _all,
      CourseStatus.inProgress => _all.where(_ip).toList(),
      CourseStatus.completed  => _all.where(_done).toList(),
    };
    if(_q.isEmpty)return list;
    final q=_q.toLowerCase();
    return list.where((c)=>c.name.toLowerCase().contains(q)||
        (c.teacherName?.toLowerCase().contains(q)??false)).toList();
  }

  Future<void> fetchMyEnrollments() async {
    final r=await run(()=>_api.get('/api/v1/my-enrollments'));
    if(r is List){
      _all=r.map((e){
        final j=e as Map<String,dynamic>;
        final cj=j['course']as Map<String,dynamic>? ??j;
        final c=CourseModel.fromJson(cj);
        final p=(j['progress']as num?)?.toDouble()??c.progress;
        return c.copyWith(progress:p);
      }).toList();
      notifyListeners();
    }
  }

  void setFilter(CourseStatus f){if(_filter==f)return;_filter=f;notifyListeners();}
  void updateSearch(String q){_q=q;notifyListeners();}
  static bool _ip(CourseModel c)=>c.progress>0&&c.progress<1.0;
  static bool _done(CourseModel c)=>c.progress>=1.0;
}
