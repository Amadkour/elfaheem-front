import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/analytics/student/exam/student_exam_provider.dart';
import 'package:flutter_education_app/features/student/attendance/attendance_provider.dart';
import 'package:flutter_education_app/features/student/courses/details/course_detail_provider.dart';
import 'package:flutter_education_app/features/shared/exams_provider.dart';
import 'package:provider/provider.dart';

import '../config/storage_service.dart' show StorageService;
import '../features/auth/auth_provider.dart';
import '../features/category/categories_provider.dart';
import '../features/material/materials_provider.dart';
import '../features/module/modules_provider.dart';
import '../features/notification/notifications_provider.dart';
import '../features/shared/attendance_provider.dart';
import '../features/shared/profile/profile_provider.dart';
import '../features/student/courses/list/courses_provider.dart';
import '../features/student/courses/my_courses/my_courses_provider.dart';
import '../features/student/home/home_provider.dart';
import '../features/rating/ratings_provider.dart';
import 'package:nested/nested.dart';
import '../features/student/reward/rewards_provider.dart';
import '../features/student/sessions/sessions_provider.dart';
import '../features/teacher/home/teacher_provider.dart';
import '../features/teacher/schedules/schedules_provider.dart';
import '../features/teacher/sessions/sessions_provider.dart';

List<SingleChildWidget> appProviders(
        {required StorageService storage, required ApiClient api}) =>
    [
// Storage — shared singleton
      Provider<StorageService>.value(value: storage),
      Provider<StorageService>.value(value: storage),

// Auth — receives the shared storage instance so it can restore
// the user from disk in its constructor without an async gap.
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => AuthProvider(storage: storage),
      ),

// Language (keep however your app initialises this)
      ChangeNotifierProvider<LangProvider>(
          create: (_) => LangProvider(storage: storage)),

// ── Auth (root — all others may read auth state via context.read) ────────

      // ── Domain providers (all share the ApiClient singleton) ─────────────────
      ChangeNotifierProvider<CategoriesProvider>(
        create: (_) => CategoriesProvider(),
      ),
      // ── Domain providers (all share the ApiClient singleton) ─────────────────
      ChangeNotifierProvider<TeacherSchedulesProvider>(
        create: (_) => TeacherSchedulesProvider(),
      ),
      // ── Domain providers (all share the ApiClient singleton) ─────────────────
      ChangeNotifierProvider<TeacherSessionsProvider>(
        create: (_) => TeacherSessionsProvider(),
      ),
      ChangeNotifierProvider<MyCoursesProvider>(
        create: (_) => MyCoursesProvider(),
      ),
      ChangeNotifierProvider<StudentExamProvider>(
        create: (_) => StudentExamProvider(),
      ),
      ChangeNotifierProvider<CourseDetailProvider>(
        create: (_) => CourseDetailProvider(),
      ),
      ChangeNotifierProvider<TeacherProvider>(
        create: (_) => TeacherProvider(),
      ),
      ChangeNotifierProvider<ProfileProvider>(
        create: (_) => ProfileProvider(storage: storage, api: api),
      ),
      ChangeNotifierProvider<CoursesProvider>(
        create: (_) => CoursesProvider(),
      ),
      ChangeNotifierProvider<RewardsProvider>(
        create: (_) => RewardsProvider(),
      ),
      ChangeNotifierProvider<HomeProvider>(
        create: (_) => HomeProvider(),
      ),
      ChangeNotifierProvider<ModulesProvider>(
        create: (_) => ModulesProvider(),
      ),
      ChangeNotifierProvider<MaterialsProvider>(
        create: (_) => MaterialsProvider(),
      ),
      ChangeNotifierProvider<StudentSessionsProvider>(
        create: (_) => StudentSessionsProvider(),
      ),
      ChangeNotifierProvider<ExamsProvider>(
        create: (_) => ExamsProvider(),
      ),
      ChangeNotifierProvider<AttendanceProvider>(
        create: (_) => AttendanceProvider(),
      ),
      ChangeNotifierProvider<RatingsProvider>(
        create: (_) => RatingsProvider(),
      ),
      ChangeNotifierProvider<StudentAttendanceProvider>(
        create: (_) => StudentAttendanceProvider(),
      ),
      ChangeNotifierProvider<NotificationsProvider>(
        create: (_) => NotificationsProvider(),
      ),
    ];
