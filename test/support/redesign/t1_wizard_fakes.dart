// Redesign group T1, the course wizard: demo data from docs/redesign/CAST.md (أ. ماجد الشهري, his maths group) on top of
// FakeApi, for the layout tests and the review renders of lib/features/courses/teacher/course_form_screen.dart.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/courses/category/categories_provider.dart';
import 'package:flutter_education_app/features/courses/teacher/course_form_screen.dart';
import 'package:flutter_education_app/features/courses/teacher/teacher_courses_provider.dart';
import 'package:flutter_education_app/features/home/teacher/teacher_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fake_api.dart';

/// The course the teacher edits: yearly 450 (default), six months 260, monthly 85, 15 % off for ten days, private with
/// a code, 36 hours, secondary grade 3, three weekly slots.
Map<String, dynamic> t1WizardCourseJson() => {
      'id': 41,
      'name_ar': 'الرياضيات ٣ ثانوي، مجموعة أ',
      'name_en': 'Math Grade 12, Group A',
      'description_ar': 'مراجعة شاملة لمنهج الصف الثالث الثانوي مع حل نماذج الاختبارات.',
      'description_en': 'A full review of the Grade 12 curriculum with past-paper practice.',
      'type': 'live',
      'fees': 450.0,
      'price': 450.0,
      'price_yearly': 450.0,
      'price_six_months': 260.0,
      'price_monthly': 85.0,
      'currency': 'SAR',
      'default_price_plan_index': 0,
      'discount_percentage': 15.0,
      'discount_days': 10,
      'is_private': true,
      'is_published': false,
      'expected_hours': 36.0,
      'delivery_mode': 'both',
      'country_code': 'SA',
      'subject': {'id': 3, 'name_ar': 'الرياضيات', 'name_en': 'Mathematics'},
      'area': {'id': 6, 'name_ar': 'مدينة نصر', 'name_en': 'Nasr City', 'parent': {'id': 5, 'name_ar': 'القاهرة', 'name_en': 'Cairo', 'parent': null}},
      'address': 'Al-Yasmin district',
      'targets': [
        {'stage_id': 2, 'stage_ar': 'الثانوية', 'stage_en': 'Secondary', 'grade_id': 23, 'grade_ar': 'الصف الثالث', 'grade_en': 'Grade 3'},
      ],
      'schedules': [
        {'id': 1, 'course_id': 41, 'day': 'sunday', 'start_time': '19:30', 'end_time': '20:20'},
        {'id': 2, 'course_id': 41, 'day': 'tuesday', 'start_time': '19:30', 'end_time': '20:20'},
        {'id': 3, 'course_id': 41, 'day': 'thursday', 'start_time': '16:00', 'end_time': '16:50'},
      ],
    };

TeacherCourse t1WizardCourse() => TeacherCourse.fromJson(t1WizardCourseJson());

/// The routes the form reads on opening (categories, the teacher's other courses, the edu catalog, the course).
FakeApi t1WizardApi({Map<String, FakeHandler>? extra}) {
  final catJson = jsonDecode(File('test/fixtures/payloads/edu_catalog_eg.json').readAsStringSync());
  return FakeApi({
    'GET /api/v1/categories': (_) => [
          {'id': 1, 'name_ar': 'الرياضيات', 'name_en': 'Maths'},
          {'id': 2, 'name_ar': 'الفيزياء', 'name_en': 'Physics'},
        ],
    'GET /api/v1/edu/countries': (_) => [
          {'code': 'EG', 'name_ar': 'مصر', 'name_en': 'Egypt'}
        ],
    'GET /api/v1/edu/catalog': (_) => catJson,
    'GET /api/v1/edu/areas': (_) => [
          {'id': 5, 'key': 'cairo', 'name_ar': 'القاهرة', 'name_en': 'Cairo', 'level': 1}
        ],
    'GET /api/v1/my-courses': (_) => {
          'items': [
            {'id': 42, 'name_ar': 'الرياضيات ٣ ثانوي، مجموعة ب', 'name_en': 'Math Grade 12, Group B'},
            {'id': 43, 'name_ar': 'تحصيلي رياضيات', 'name_en': 'Tahsili maths'},
          ],
          'total': 2,
        },
    'GET /api/v1/courses/41': (_) => t1WizardCourseJson(),
    'GET /api/v1/courses/41/access-code': (_) => {'access_code': '748291'},
    ...?extra,
  }, latency: Duration.zero);
}

/// Installs [api] for the current test.
Future<void> t1WizardSetUp(FakeApi api) async {
  SharedPreferences.setMockInitialValues({});
  mockRequestPlugins();
  api.install();
  addTearDown(api.uninstall);
}

/// The form (create when [course] is null) with the providers it reads.
Widget t1WizardForm({TeacherCourse? course}) => MultiProvider(
      providers: [
        ChangeNotifierProvider<TeacherCoursesProvider>(create: (_) => TeacherCoursesProvider()),
        ChangeNotifierProvider<CategoriesProvider>(create: (_) => CategoriesProvider(api: ApiClient())),
      ],
      child: CourseFormScreen(course: course),
    );

/// Wraps [child] in the theme scope for the review renders.
Widget t1WizardThemed(Widget child) {
  final theme = ThemeConfigProvider(api: ApiClient());
  return ThemeConfigScope(provider: theme, child: child);
}
