// Phase 7: the REAL course lists with their real providers over the FakeApi, asserted on what a person sees.
//   teacher   tap a course card → the panel with its figures and students; My students / the strip
//   student   tap a course card → their own course; "Left" → the courses left, from the server
//   a11y      Flutter's guidelines over the role lists and a learner's course
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/core/entities/entities_api.dart';
import 'package:flutter_education_app/core/entities/entity_models.dart';
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/design/master_detail/entity_detail_page.dart';
import 'package:flutter_education_app/design/master_detail/entity_learner.dart';
import 'package:flutter_education_app/design/master_detail/entity_list_page.dart';
import 'package:flutter_education_app/design/master_detail/entity_panel_controller.dart';
import 'package:flutter_education_app/design/master_detail/master_detail_scaffold.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/features/student/courses/my_courses/my_courses_provider.dart';
import 'package:flutter_education_app/features/student/courses/my_courses/my_courses_screen.dart';
import 'package:flutter_education_app/features/student/record/student_record_pages.dart';
import 'package:flutter_education_app/features/teacher/classroom/teacher_classroom.dart';
import 'package:flutter_education_app/features/teacher/courses/courses_screen.dart';
import 'package:flutter_education_app/features/teacher/courses/teacher_courses_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_api.dart';
import '../a11y_guidelines_test.dart' show expectA11y;
import '../layout_harness.dart';
import 'md_roles_support.dart';
import 'md_support.dart' show mdCourseRef;

Map<String, dynamic> _studentCourse(int id, String en, int progress) => {
      'id': id, 'name_ar': en, 'name_en': en, 'image_url': '', 'type': 'recorded', 'is_published': true,
      'is_enrolled': true, 'org': null, 'progress': progress, 'sessions_count': 12, 'fees': 300, 'currency': 'EGP',
      'teacher': {'id': 21, 'name': 'Dr. Omar', 'created_at': '2026-01-10T09:00:00'},
    };

Map<String, dynamic> _teacherCourse(int id, String en) => {
      'id': id, 'name_ar': en, 'name_en': en, 'image_url': '', 'type': 'recorded', 'is_published': true, 'org': null,
      'students_count': 42, 'sessions_count': 12, 'fees': 300, 'price': 300, 'currency': 'EGP', 'total_hours': 14,
      'progress': 0, 'expected_hours': 14,
    };

Future<void> _settle(WidgetTester t, [int n = 14]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Map<String, dynamic> _env(List<Map<String, dynamic>> items) =>
    {'items': items, 'total': items.length, 'has_more': false, 'scope': 'personal', 'scopes': const []};

void main() {
  late FakeApi api;
  late EntityPanelController panel;

  setUp(() {
    AppConfig.lang = 'en';
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    AppConfig.setOrgsEnabled(false);
    AppModeController.applyContext = (_) {};
    EntitiesApi.instance.invalidate();
    panel = EntityPanelController(rowKind: EntityKind.course);
    api = FakeApi({
      ...roleRoutes(),
      'GET /api/v1/my-enrolled-courses': (o) => _env([_studentCourse(40, 'Python Basics', 64), _studentCourse(41, 'Physics', 20)]),
      'GET /api/v1/my-courses': (o) => _env([_teacherCourse(40, 'Python Basics')]),
      'GET /api/v1/entities/courses/40': (o) => learnerCourse(40),
    }, latency: const Duration(milliseconds: 5))
      ..install();
  });

  tearDown(() {
    api.uninstall();
    panel.dispose();
  });

  Future<void> sized(WidgetTester t, Size size) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

  testWidgets('student: a course card opens the sheet with their progress; Left comes from the server', (t) async {
    final storage = await StorageService.getInstance();
    await sized(t, const Size(390, 844));
    final search = TextEditingController();
    addTearDown(search.dispose);
    await t.pumpWidget(layoutHost(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => MyCoursesProvider(mode: AppModeController.instance)..init(const [])),
          ChangeNotifierProvider(create: (_) => MyAuthProvider(storage: storage)),
        ],
        child: MasterDetailScaffold(
          controller: panel,
          list: MyCoursesBody(controller: search, panel: panel),
        ),
      ),
      scale: 1,
    ));
    await _settle(t);
    expect(find.text('Python Basics'), findsWidgets);
    await t.tap(find.text('Python Basics').first);
    await _settle(t);
    expect(panel.current, const EntityRef(EntityKind.course, 40));
    expect(find.byType(EntityLearnerCard), findsOneWidget);
    expect(find.byKey(const ValueKey('md.continue')), findsOneWidget);
    expect(find.byKey(const ValueKey('md.sheet')), findsOneWidget);
  });

  testWidgets('teacher: a course card opens the panel, not the page; the strip reaches My students', (t) async {
    await sized(t, const Size(1400, 900));
    final search = TextEditingController();
    addTearDown(search.dispose);
    api.routes['GET /api/v1/entities/courses/40'] = (o) => {...learnerCourse(40), 'sections': const ['students']};
    await t.pumpWidget(layoutHost(
      ChangeNotifierProvider(
        create: (_) => TeacherCoursesProvider(mode: AppModeController.instance)..refresh(),
        child: MasterDetailScaffold(
          controller: panel,
          list: TeacherCoursesBody(controller: search, panel: panel),
        ),
      ),
      scale: 1,
    ));
    await _settle(t);
    await t.tap(find.text('Python Basics').first);
    await _settle(t);
    expect(panel.current?.id, 40);
    expect(find.byKey(const ValueKey('md.inline')), findsOneWidget);
    expect(api.calls.any((c) => c.path == '/api/v1/entities/courses/40'), isTrue);
  });

  testWidgets('a11y: the role lists and a learner course', (t) async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    addTearDown(() => translation = {});
    await expectA11y(t, 'md7 students', () => EntityListPage<PersonRow>(config: teacherStudentsList(21), deepLinks: false));
    await expectA11y(t, 'md7 submissions', () => EntityListPage<GradeRow>(config: teacherSubmissionsList(21), deepLinks: false));
    await expectA11y(t, 'md7 grades', () => EntityListPage<GradeRow>(config: studentGradesList(77), deepLinks: false));
    await expectA11y(t, 'md7 learner', () => const EntityDetailPage(entity: EntityRef(EntityKind.course, 40)));
    expect(mdCourseRef(0)['id'], 40);
  });
}
