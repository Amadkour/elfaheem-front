// The student home's filtered strip (D-1326): the dashboard call carries the remembered filters and the bar starts
// from the server's `applied_filters`; a bar change asks GET /courses (limit 12) and shows the server's total, the
// enrolled courses left out, without reloading the dashboard.
import 'dart:convert';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/courses/category/model.dart';
import 'package:flutter_education_app/features/courses/course_filters.dart';
import 'package:flutter_education_app/features/guest/guest_state.dart';
import 'package:flutter_education_app/features/home/student/home_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';

Map<String, dynamic> _course(int id) => {'id': id, 'name_ar': 'كورس $id', 'name_en': 'Course $id', 'fees': 100, 'type': 'live', 'is_enrolled': false, 'is_published': true};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeApi api;

  setUp(() {
    AppConfig.lang = 'en';
    SharedPreferences.setMockInitialValues({
      'course_filters_guest': jsonEncode({'country': 'EG', 'stage_id': 3}),
    });
    mockRequestPlugins();
    GuestState.instance.start();
    api = FakeApi({
      'GET /api/v1/teacher/student-dashboard': (_) => {
            'enrolled_courses': [
              [_course(1)],
              1
            ],
            'other_courses': [_course(2), _course(3)],
            'other_courses_total': 9,
            'categories': [],
            'best_teachers': {'items': []},
            'applied_filters': {'country': 'EG', 'stage_id': 3},
          },
      'GET /api/v1/courses': (_) => {
            'items': [for (final i in [1, 4, 5, 6, 7, 8, 9, 10]) _course(i)],
            'total': 20,
            'has_more': true,
          },
    }, latency: const Duration(milliseconds: 1))
      ..install();
  });

  tearDown(() {
    api.uninstall();
    GuestState.instance.stop();
  });

  test('the dashboard call carries the remembered filters; the bar starts from applied_filters', () async {
    final p = HomeProvider(api: ApiClient());
    await p.fetchStudentDashboard();
    final call = api.calls.single;
    expect(call.path, '/api/v1/teacher/student-dashboard');
    expect(call.query['stage_id'], anyOf(3, '3'));
    expect(call.query.containsKey('level'), isFalse, reason: 'a guest never sends level=profile');
    expect(p.homeFilters.toQuery(), {'country': 'EG', 'stage_id': 3});
    expect(p.otherCoursesTotal, 9);
    expect(p.otherCourses, hasLength(2));
    p.dispose();
  });

  test('a bar change asks GET /courses and shows its total, the enrolled course left out', () async {
    final p = HomeProvider(api: ApiClient());
    await p.fetchStudentDashboard();
    api.reset();
    await p.applyHomeFilters(const CourseFilters(country: 'EG', stageId: 3, gradeId: 10));
    final call = api.calls.single;
    expect(call.path, '/api/v1/courses');
    expect(call.query['limit'], anyOf(12, '12'));
    expect(call.query['grade_id'], anyOf(10, '10'));
    expect([for (final c in p.otherCourses) c.id], ['4', '5', '6', '7', '8', '9']);
    expect(p.otherCoursesTotal, 19, reason: 'the server total minus the enrolled course on that page');
    expect(p.homeFilters.gradeId, 10);
    expect(p.filtering, isFalse);
    p.dispose();
  });

  test('courses.filters off: nothing of the bar is sent', () async {
    final before = AppConfig.disableList;
    AppConfig.disableList = [kCourseFiltersKey];
    addTearDown(() => AppConfig.disableList = before);
    final p = HomeProvider(api: ApiClient());
    await p.fetchStudentDashboard();
    expect(api.calls.single.query.containsKey('stage_id'), isFalse);
    p.dispose();
  });

  test('the explorer card reads CourseResponse: title by language, the real type and teacher', () {
    // decoded as the network gives it (nested maps are Map<String, dynamic>)
    final j = jsonDecode(jsonEncode({
      ..._course(16),
      'name_ar': 'كيمياء',
      'name_en': '',
      'teacher': {'id': 3, 'name': 'Mona', 'created_at': '2026-11-01T10:00:00'},
    })) as Map<String, dynamic>;
    final m = CategoryCourseModel.fromJson(j);
    expect(m.title, 'كيمياء', reason: 'no English title: the Arabic one');
    AppConfig.lang = 'ar';
    expect(CategoryCourseModel.fromJson(j).title, 'كيمياء');
    final c = m.toCourseModel;
    expect(c.type, 'live');
    expect(c.titleAr, 'كيمياء');
    expect(m.instructorName, 'Mona');
  });
}
