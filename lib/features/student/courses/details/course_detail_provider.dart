/// courses/details/course_detail_provider.dart
import '../../../../core/api_client.dart';
import '../../../../core/base_provider.dart';
import '../../models.dart';

class CourseDetailProvider extends BaseProvider {
  final ApiClient _api;

  CourseDetailProvider({ApiClient? api}) : _api = api ?? ApiClient();

  late CourseModel course;
  CourseDetailTab _activeTab = CourseDetailTab.lessons;
  bool _isEnrolled = false;
  bool _isEnrolling = false;

  CourseDetailTab get activeTab => _activeTab;

  bool get isEnrolled => _isEnrolled;

  bool get isEnrolling => _isEnrolling;

  void init(CourseModel course) async{
    this.course = course;
    await fetchSessions(course.id);
  }

  Future<void> fetchFull(String courseId) async {
    final r =
        await run(() => _api.get('/api/v1/courses/$courseId', auth: true));
    if (r is Map<String, dynamic>) {
      course = CourseModel.fromJson(r);
      notifyListeners();
    }
  }

  bool isLoadingSession = false;

  Future<void> fetchSessions(String courseId) async {
    isLoadingSession = true;
    notifyListeners();
    final result =
        await run(() => _api.get('/api/v1/courses/$courseId/sessions'));
    if (result is List) {
      course.sessions = result
          .map((e) => SessionModel.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.order.compareTo(b.order));
      isLoadingSession = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => fetchFull(course.id);

  void setTab(CourseDetailTab tab) {
    if (_activeTab == tab) return;
    _activeTab = tab;
    notifyListeners();
  }

  Future<void> toggleFavorite() async {
    final was = course.isFavorite;
    course = course.copyWith(isFavorite: !was);
    notifyListeners();
    final r = was
        ? await run(() => _api.delete('/api/v1/courses/${course.id}/favorite'))
        : await run(() => _api.post('/api/v1/courses/${course.id}/favorite'));
    if (r == null && hasError) {
      course = course.copyWith(isFavorite: was);
      notifyListeners();
    }
  }

  Future<void> enroll() async {
    if (_isEnrolled || _isEnrolling) return;
    _isEnrolling = true;
    notifyListeners();
    final r = await run(() => _api.post('/api/v1/courses/${course.id}/enroll'));
    _isEnrolling = false;
    if (r != null) _isEnrolled = true;
    notifyListeners();
  }
}
