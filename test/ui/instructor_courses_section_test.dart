// The "Courses" block of the teacher profile (lib/features/profile/instructor_courses_section.dart):
//   • InstructorCoursesController on the wire — GET /api/v1/courses with teacher_id + scope=personal, a first page of
//     6 then 12, paged on `has_more`, never the same course twice, an organization / private / draft course an older
//     server still lists is left out, a failure keeps the listed courses and Retry asks the same page again;
//   • InstructorCoursesSection — every state (loading, empty, error, cards, show more, loading more, an error under
//     the cards) without overflow at 320×640 and 1400×900, ar / en, text ×1.3 (layout harness), "Show more" /
//     Retry / a card tap reach their callbacks.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_buttons.dart' show AppButton;
import 'package:flutter_education_app/features/auth/teacher_document_provider.dart';
import 'package:flutter_education_app/features/profile/course_instractor_profile.dart';
import 'package:flutter_education_app/features/profile/instructor_courses_section.dart';
import 'package:flutter_education_app/features/home/student/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import 'layout_harness.dart';

Map<String, dynamic> course(int id, {Map<String, dynamic>? org, bool private = false, bool published = true}) => {
      'id': id,
      'name_en': 'A rather long course title number $id that wraps over two lines',
      'name_ar': 'عنوان كورس طويل بعض الشيء رقم $id يلتف على سطرين',
      'image_url': '',
      'type': id.isEven ? 'live' : 'recorded',
      'is_published': published,
      'is_private': private,
      'is_enrolled': false,
      'price': id * 10,
      'final_price': id * 10,
      'sessions_count': id,
      'org': ?org,
    };

/// A server holding [total] personal courses of teacher 42 (ids total…1, newest first), paged by skip / limit.
Object? Function(dynamic) teacherCourses(int total, {Map<int, Map<String, dynamic>> extra = const {}}) => (o) {
      final q = o.queryParameters as Map<String, dynamic>;
      final skip = int.parse('${q['skip'] ?? 0}');
      final limit = int.parse('${q['limit'] ?? 20}');
      final ids = [for (var i = total - skip; i >= 1 && i > total - skip - limit; i--) i];
      return {
        'items': [for (final id in ids) extra[id] ?? course(id)],
        'total': total,
        'has_more': skip + ids.length < total,
        'scope': q['scope'] ?? 'personal',
      };
    };

List<CourseModel> models(int n) => [for (var i = 1; i <= n; i++) CourseModel.fromJson(course(i))];

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    AppConfig.lang = 'en';
  });

  group('InstructorCoursesController', () {
    Future<(FakeApi, InstructorCoursesController)> open(Object? Function(dynamic) route) async {
      final fake = FakeApi({'GET /api/v1/courses': route}, latency: Duration.zero);
      fake.install();
      addTearDown(fake.uninstall);
      final c = InstructorCoursesController(teacherId: 42);
      addTearDown(c.dispose);
      return (fake, c);
    }

    test('asks for the teacher\'s personal courses, 6 first then 12, until has_more is false', () async {
      final (fake, c) = await open(teacherCourses(20));
      expect(c.loading, isTrue); // not asked yet = the skeleton
      await c.load();
      expect(fake.calls.single.query, {'skip': '0', 'limit': '6', 'teacher_id': '42', 'scope': 'personal'});
      expect(c.courses.length, 6);
      expect(c.hasMore, isTrue);
      expect(c.total, 20);
      await c.loadMore();
      expect(fake.calls.last.query['skip'], '6');
      expect(fake.calls.last.query['limit'], '12');
      expect(c.courses.length, 18);
      await c.loadMore();
      expect(c.courses.length, 20);
      expect(c.hasMore, isFalse);
      await c.loadMore(); // the end: no request
      expect(fake.calls.length, 3);
      expect(c.courses.map((x) => x.id).toSet().length, 20);
    });

    test('rapid "Show more" taps send one page request', () async {
      final (fake, c) = await open(teacherCourses(40));
      await c.load();
      await Future.wait([c.loadMore(), c.loadMore(), c.loadMore()]);
      expect(fake.calls.length, 2);
      expect(c.courses.length, 18);
    });

    test('a page that repeats a listed course never lists it twice', () async {
      var n = 0;
      final (_, c) = await open((o) {
        n++;
        // page 2 starts with the last course of page 1 (a course was published meanwhile: offsets shifted)
        final ids = n == 1 ? [9, 8, 7, 6, 5, 4] : [4, 3, 2, 1];
        return {'items': [for (final id in ids) course(id)], 'total': 10, 'has_more': n == 1};
      });
      await c.load();
      await c.loadMore();
      expect(c.courses.map((x) => x.id).toList(), ['9', '8', '7', '6', '5', '4', '3', '2', '1']);
      expect(c.hasMore, isFalse);
    });

    test('an organization, private or draft course an older server lists is left out', () async {
      final (_, c) = await open(teacherCourses(6, extra: {
        6: course(6, org: {'id': 3, 'name_en': 'Uni'}),
        5: course(5, private: true),
        4: course(4, published: false),
      }));
      await c.load();
      expect(c.courses.map((x) => x.id).toList(), ['3', '2', '1']);
      expect(c.total, 3);
    });

    test('an empty list is the empty state, not an error', () async {
      final (_, c) = await open((_) => {'items': [], 'total': 0, 'has_more': false});
      await c.load();
      expect(c.loading, isFalse);
      expect(c.courses, isEmpty);
      expect(c.error, isNull);
      expect(c.total, 0);
    });

    test('a failed page keeps the listed courses; Retry asks the same page again', () async {
      var fail = false;
      final ok = teacherCourses(20);
      final (fake, c) = await open((o) => fail ? const FakeResponse(500, {'detail': 'boom'}) : ok(o));
      await c.load();
      fail = true;
      await c.loadMore();
      expect(c.error, isNotNull);
      expect(c.courses.length, 6);
      fail = false;
      await c.retry();
      expect(c.error, isNull);
      expect(fake.calls.last.query['skip'], '6');
      expect(c.courses.length, 18);
    });

    test('a failed first page: error, then Retry loads page 1', () async {
      var fail = true;
      final ok = teacherCourses(3);
      final (_, c) = await open((o) => fail ? const FakeResponse(500, {'detail': 'boom'}) : ok(o));
      await c.load();
      expect(c.error, isNotNull);
      expect(c.loading, isFalse);
      fail = false;
      await c.retry();
      expect(c.error, isNull);
      expect(c.courses.length, 3);
    });
  });

  group('InstructorCoursesSection', () {
    Widget host(Widget section) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
          child: section,
        );

    InstructorCoursesSection section({
      List<CourseModel> courses = const [],
      bool loading = false,
      bool loadingMore = false,
      bool hasMore = false,
      String? error,
      int? total,
      VoidCallback? onRetry,
      VoidCallback? onLoadMore,
      void Function(CourseModel)? onOpen,
    }) =>
        InstructorCoursesSection(
          courses: courses,
          total: total ?? courses.length,
          loading: loading,
          loadingMore: loadingMore,
          hasMore: hasMore,
          error: error,
          onRetry: onRetry ?? () {},
          onLoadMore: onLoadMore ?? () {},
          onOpen: onOpen ?? (_) {},
        );

    final cases = <String, InstructorCoursesSection Function()>{
      'loading': () => section(loading: true),
      'empty': () => section(),
      'error': () => section(error: 'Could not load the courses, please check the connection and try again'),
      'cards + show more': () => section(courses: models(6), hasMore: true, total: 1234),
      'cards, loading more': () => section(courses: models(6), hasMore: true, loadingMore: true, total: 30),
      'cards + error': () => section(courses: models(3), hasMore: true, error: 'Failed to load data', total: 9),
      'one card': () => section(courses: models(1)),
    };
    for (final e in cases.entries) {
      testWidgets('no layout error: ${e.key}', (tester) async {
        await expectNoLayoutErrors(tester, () => host(e.value()));
      });
    }

    testWidgets('Show more, Retry and a card tap reach their callbacks', (tester) async {
      var more = 0, retry = 0;
      CourseModel? opened;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 2400);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(layoutHost(host(section(
        courses: models(2),
        hasMore: true,
        onLoadMore: () => more++,
        onOpen: (c) => opened = c,
      )), scale: 1));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byType(AppButton)); // "Show more courses" is the kit's secondary button
      expect(more, 1);
      await tester.tap(find.byKey(const ValueKey('instructor-course-2')));
      expect(opened?.id, '2');

      await tester.pumpWidget(layoutHost(host(section(error: 'Failed', onRetry: () => retry++)), scale: 1));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byType(AppButton)); // Retry is the error state's ghost AppButton
      expect(retry, 1);
    });
  });

  group('InstructorProfileScreen', () {
    testWidgets('the profile lists the teacher\'s courses in both layouts without a layout error', (tester) async {
      final fake = FakeApi({'GET /api/v1/courses': teacherCourses(9)}, latency: Duration.zero);
      fake.install();
      addTearDown(fake.uninstall);
      final teacher = TeacherProfileData(
        id: 42,
        name: 'Dr. Omar Hassan with a fairly long display name',
        gmail: '',
        role: 'teacher',
        isVerified: true,
        isActive: true,
        loginTimes: 0,
        registrationStep: 'complete',
        createdAt: DateTime(2024, 3, 1),
      );
      await expectNoLayoutErrors(
        tester,
        () => ChangeNotifierProvider(
          create: (_) => TeacherDocumentProvider(),
          child: InstructorProfileScreen(teacher: teacher, studentView: false),
        ),
        scaffold: false,
        frames: 8,
      );
      expect(fake.calls.where((c) => c.path == '/api/v1/courses'), isNotEmpty);
      expect(fake.calls.where((c) => c.path == '/api/v1/courses').every((c) => c.query['teacher_id'] == '42' && c.query['scope'] == 'personal'), isTrue);
    });
  });
}
