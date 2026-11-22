import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/edu/edu_catalog.dart';
import 'package:flutter_education_app/features/courses/course_setup.dart';
import 'package:flutter_education_app/features/courses/course_setup_views.dart';
import 'package:flutter_education_app/features/courses/category/categories_provider.dart';
import 'package:flutter_education_app/features/courses/teacher/course_form_provider.dart';
import 'package:flutter_education_app/features/courses/teacher/course_form_screen.dart';
import 'package:flutter_education_app/features/courses/teacher/teacher_courses_provider.dart';
import 'package:flutter_education_app/features/home/teacher/teacher_models.dart';
import 'package:flutter_education_app/features/sessions/teacher/components/teacher_course_parts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import 'layout_harness.dart';

/// The real course form (create or edit) over a fake backend.
Future<void> _pumpForm(WidgetTester tester, {TeacherCourse? course}) async {
  tester.view.physicalSize = const Size(1400, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final theme = ThemeConfigProvider(api: ApiClient());
  await tester.pumpWidget(ThemeConfigScope(
    provider: theme,
    child: MaterialApp(
      theme: theme.materialTheme(dark: false),
      home: Scaffold(
        body: MultiProvider(providers: [
          ChangeNotifierProvider<TeacherCoursesProvider>(create: (_) => TeacherCoursesProvider()),
          ChangeNotifierProvider<CategoriesProvider>(create: (_) => CategoriesProvider()),
        ], child: CourseFormScreen(course: course)),
      ),
    ),
  ));
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  final json = jsonDecode(File('test/fixtures/payloads/course_setup.json').readAsStringSync()) as Map<String, dynamic>;
  final cat = EduCountryCatalog.fromJson(
      jsonDecode(File('test/fixtures/payloads/edu_catalog_eg.json').readAsStringSync()) as Map<String, dynamic>);
  const cairo = EduArea(id: 5, key: 'cairo', nameAr: 'القاهرة', nameEn: 'Cairo', hasChildren: true);
  const nasr = EduArea(id: 6, key: 'nasr', nameAr: 'مدينة نصر', nameEn: 'Nasr City', level: 2);
  Future<List<EduArea>> load(int? p) async => p == null ? [cairo] : [nasr];

  setUp(() => AppConfig.lang = 'en');

  test('the course response parses into the setup', () {
    final s = CourseSetup.fromJson(json);
    expect(s.deliveryMode, 'both');
    expect(s.countryCode, 'EG');
    expect(s.subject?.id, 3);
    expect(s.area?.id, 6);
    expect(s.area?.parent?.name, 'Cairo');
    expect(s.address, '12 Tahrir St');
    expect(s.targets.map((t) => t.label).toList(), ['Secondary - Grade 2', 'Primary']);
    expect(s.targets.map((t) => t.gradeId).toList(), [22, null]);
    expect(s.isEmpty, isFalse);
    expect(TeacherCourse.fromJson(json).setup.targets.length, 2);
  });

  test('an older course answer is an empty setup, an online course has no address', () {
    final s = CourseSetup.fromJson({'id': 1});
    expect(s.isEmpty, isTrue);
    expect(s.deliveryMode, 'online');
    expect(CourseSetup.fromJson({'delivery_mode': 'bogus'}).deliveryMode, 'online');
  });

  test('program kind (D-1343): parsed, sent with the setup, reset on create', () {
    expect(CourseSetup.fromJson(json).programKind, 'course');
    expect(CourseSetup.fromJson({'program_kind': 'quran'}).programKind, 'quran');
    expect(CourseSetup.fromJson({'program_kind': 'bogus'}).programKind, 'course');
    final p = CourseFormProvider();
    expect(p.setupBodyForTest()['program_kind'], 'course');
    p.setProgramKind('quran');
    expect(p.setupBodyForTest()['program_kind'], 'quran');
    expect(p.setupBodyForTest(update: true)['program_kind'], 'quran');
    expect(p.programKindLocked, isFalse);
  });

  testWidgets('program kind field: open and locked, no layout error', (tester) async {
    await expectNoLayoutErrors(tester, () => CourseProgramKindField(value: 'quran', onChanged: (_) {}));
    await expectNoLayoutErrors(tester, () => CourseProgramKindField(value: 'course', locked: true, onChanged: (_) {}));
  });

  test('the bilingual text of course_area_required', () {
    AppConfig.lang = 'ar';
    expect(courseAreaRequiredText(), contains('المنطقة'));
    AppConfig.lang = 'en';
    expect(courseAreaRequiredText(), contains('area'));
  });

  testWidgets('form section: online, in person with the area and address, and no catalog', (tester) async {
    final address = TextEditingController();
    Widget section({String mode = 'both', List<CourseTarget> targets = const [], EduCountryCatalog? c}) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: CourseSetupSection(
            stages: c?.stages ?? const [],
            subjects: c?.subjects ?? const [],
            targets: targets,
            onToggleTarget: (_) {},
            subjectId: c?.subjects.isEmpty ?? true ? null : c!.subjects.first.id,
            onSubject: (_) {},
            deliveryMode: mode,
            onDeliveryMode: (_) {},
            loadAreas: load,
            onArea: (_, _) {},
            area1: cairo,
            area2: nasr,
            address: address,
          ),
        );
    await expectNoLayoutErrors(tester, () => section(c: cat, targets: CourseSetup.fromJson(json).targets));
    await expectNoLayoutErrors(tester, () => section(mode: 'online', c: cat));
    await expectNoLayoutErrors(tester, () => section(mode: 'in_person'));
  });

  testWidgets('form section: a stage opens its grades and a grade toggles', (tester) async {
    CourseTarget? got;
    await tester.pumpWidget(layoutHost(SingleChildScrollView(
      child: CourseSetupSection(
        stages: cat.stages,
        subjects: cat.subjects,
        targets: const [],
        onToggleTarget: (t) => got = t,
        subjectId: null,
        onSubject: (_) {},
        deliveryMode: 'online',
        onDeliveryMode: (_) {},
        loadAreas: load,
        onArea: (_, _) {},
        address: TextEditingController(),
      ),
    )));
    await tester.pump();
    await tester.tap(find.text('Primary'));
    await tester.pump();
    await tester.tap(find.text('Whole stage'));
    expect(got?.stageId, cat.stages.firstWhere((s) => s.nameEn == 'Primary').id);
    expect(got?.gradeId, isNull);
  });

  testWidgets('profile block: full, online only, and empty', (tester) async {
    await expectNoLayoutErrors(tester, () => CourseWhoWhereBlock(setup: CourseSetup.fromJson(json)));
    await expectNoLayoutErrors(
        tester,
        () => CourseWhoWhereBlock(
            setup: CourseSetup.fromJson({
          'delivery_mode': 'online',
          'targets': [
            {'stage_id': 1, 'stage_ar': 'الابتدائية', 'stage_en': 'Primary'}
          ],
        })));
    await tester.pumpWidget(layoutHost(const CourseWhoWhereBlock(setup: CourseSetup())));
    expect(find.byType(Text), findsNothing);
  });

  group('the real form over a fake backend', () {
    late FakeApi api;
    var detailFails = true;
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      mockRequestPlugins();
      detailFails = true;
      final catJson = jsonDecode(File('test/fixtures/payloads/edu_catalog_eg.json').readAsStringSync());
      api = FakeApi({
        'GET /api/v1/edu/countries': (_) => [
              {'code': 'EG', 'name_ar': 'مصر', 'name_en': 'Egypt'}
            ],
        'GET /api/v1/edu/catalog': (_) => catJson,
        'GET /api/v1/edu/areas': (_) => [
              {'id': 5, 'key': 'cairo', 'name_ar': 'القاهرة', 'name_en': 'Cairo', 'level': 1}
            ],
        'GET /api/v1/my-courses': (_) => {'items': [], 'total': 0},
        'GET /api/v1/courses/7': (_) => detailFails ? const FakeResponse(500, {'detail': 'boom'}) : json,
      }, latency: const Duration(milliseconds: 5))
        ..install();
    });
    tearDown(() => api.uninstall());

    testWidgets('create: a stage chip opens its grades', (tester) async {
      await _pumpForm(tester);
      await tester.ensureVisible(find.text('Primary'));
      await tester.tap(find.text('Primary'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Whole stage'), findsOneWidget);
    });

    testWidgets('edit: a failed detail call shows Retry instead of the section; Retry loads it', (tester) async {
      await _pumpForm(tester, course: TeacherCourse.fromJson(json));
      expect(find.byType(CourseSetupLoadError), findsOneWidget);
      expect(find.byType(CourseSetupSection), findsNothing);
      detailFails = false;
      await tester.ensureVisible(find.text('Retry'));
      await tester.tap(find.text('Retry'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(CourseSetupLoadError), findsNothing);
      expect(find.byType(CourseSetupSection), findsOneWidget);
      expect(find.widgetWithText(TextField, '12 Tahrir St'), findsOneWidget);
    });
  });

  testWidgets('load error line: no layout error', (tester) async {
    await expectNoLayoutErrors(tester, () => CourseSetupLoadError(onRetry: () {}));
  });

  testWidgets("the teacher's Details tab shows who / where with the address", (tester) async {
    await tester.pumpWidget(layoutHost(SingleChildScrollView(child: TeacherCourseDetails(course: TeacherCourse.fromJson(json)))));
    await tester.pump();
    expect(find.byType(CourseWhoWhereBlock), findsOneWidget);
    expect(find.text('12 Tahrir St'), findsOneWidget);
  });
}
