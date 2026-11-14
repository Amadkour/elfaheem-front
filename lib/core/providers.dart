import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/student/analysis/student_analytics_provider.dart';
import 'package:flutter_education_app/features/student/attendance/attendance_provider.dart';
import 'package:flutter_education_app/features/courses/student/details/course_detail_provider.dart';
import 'package:flutter_education_app/features/courses/teacher/teacher_courses_provider.dart';
import 'package:provider/provider.dart';
import '../features/org/org_providers.dart';
import '../config/storage_service.dart' show StorageService;
import '../config/theme/theme_config_provider.dart';
import '../features/auth/auth_provider.dart';
import '../features/auth/teacher_document_provider.dart';
import '../features/shared/attendance/relay_host_provider.dart';
import 'package:flutter_education_app/features/courses/category/categories_provider.dart';
import '../features/shared/notification/notifications_provider.dart';
import '../features/shared/profile/about/about_terms_provider.dart';
import '../features/shared/profile/profile_provider.dart';
import 'package:flutter_education_app/features/exams/legacy/student/student_exam_provider.dart';
import 'package:flutter_education_app/features/courses/student/list/courses_provider.dart';
import 'package:flutter_education_app/features/courses/student/my_courses/my_courses_provider.dart';
import '../features/student/home/home_provider.dart';
import 'package:nested/nested.dart';
import '../features/student/reward/rewards_provider.dart';
import '../features/teacher/home/teacher_home_provider.dart';
import '../features/admin/enrollment_request/teacher_transfers_provider.dart';
import '../features/teacher/profile/switch_device_requests/teacher_device_requests_provider.dart';
import '../features/teacher/schedules/schedules_provider.dart';
import 'package:flutter_education_app/features/sessions/teacher/students/course_student_provider.dart';

List<SingleChildWidget> appProviders({
  required StorageService storage,
  required ApiClient api,
}) => [
  // Storage — shared singleton
  Provider<StorageService>.value(value: storage),
  // Organizations: which organizations I manage + the selected one (org-admin dashboard)
  ChangeNotifierProvider<OrgSession>(create: (_) => OrgSession()),
  ChangeNotifierProvider<TeacherTransfersProvider>(
    create: (_) => TeacherTransfersProvider(),
  ),
  ChangeNotifierProvider<TeacherDeviceRequestsProvider>(
    create: (_) => TeacherDeviceRequestsProvider(),
  ),
  // Auth — receives the shared storage instance so it can restore
  // the user from disk in its constructor without an async gap.
  ChangeNotifierProvider<MyAuthProvider>(
    create: (_) => MyAuthProvider(storage: storage),
  ),

  // Language (keep however your app initialises this)
  ChangeNotifierProvider<LangProvider>(
    create: (_) => LangProvider(storage: storage),
  ),

  // ── Auth (root — all others may read auth state via context.read) ────────

  // ── Domain providers (all share the ApiClient singleton) ─────────────────
  ChangeNotifierProvider<CategoriesProvider>(
    create: (_) => CategoriesProvider(),
  ),
  ChangeNotifierProvider<TeacherSchedulesProvider>(
    create: (_) => TeacherSchedulesProvider(),
  ),
  ChangeNotifierProvider<AboutTermsProvider>(
    create: (_) => AboutTermsProvider(),
  ),

  ChangeNotifierProvider<TeacherDocumentProvider>(
    create: (_) => TeacherDocumentProvider(),
  ),

  ChangeNotifierProvider<StudentAnalyticsProvider>(
    create: (_) => StudentAnalyticsProvider(),
  ),
  ChangeNotifierProvider<MyCoursesProvider>(create: (_) => MyCoursesProvider()),
  ChangeNotifierProvider<ThemeConfigProvider>(
    create: (_) => ThemeConfigProvider(api: api),
  ),
  ChangeNotifierProvider<StudentExamProvider>(
    create: (_) => StudentExamProvider(),
  ),
  ChangeNotifierProvider<CourseDetailProvider>(
    create: (_) => CourseDetailProvider(),
  ),
  ChangeNotifierProvider<TeacherCoursesProvider>(create: (_) => TeacherCoursesProvider()),
  ChangeNotifierProvider<ProfileProvider>(
    create: (_) => ProfileProvider(storage: storage, api: api),
  ),
  ChangeNotifierProvider<TeacherHomeProvider>(create: (_) => TeacherHomeProvider()),
  ChangeNotifierProvider<CoursesProvider>(create: (_) => CoursesProvider()),
  ChangeNotifierProvider<RewardsProvider>(create: (_) => RewardsProvider()),
  ChangeNotifierProvider<HomeProvider>(create: (_) => HomeProvider()),
  ChangeNotifierProvider<EnrolledStudentsProvider>(
    create: (_) => EnrolledStudentsProvider(api: api),
  ),
  ChangeNotifierProvider<StudentAttendanceProvider>(
    create: (_) => StudentAttendanceProvider(),
  ),
  // Online students who agree to relay offline classmates' attendance (opt-in, Android).
  ChangeNotifierProvider<RelayHostProvider>(create: (_) => RelayHostProvider()..init()),
  ChangeNotifierProvider<NotificationsProvider>(
    create: (_) => NotificationsProvider(),
  ),
];