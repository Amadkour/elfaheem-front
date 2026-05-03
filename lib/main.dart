/// ─────────────────────────────────────────────────────────────────────────────
/// main.dart
/// App entry point.
///
/// What changed vs the previous version:
///   • StorageService is instantiated once in main() and injected into
///     AuthProvider via the providers list — so both share the same instance.
///   • isAuth is derived from StorageService.isAuthenticated() (same instance).
///   • initialRoute now uses authProvider.isAuthenticated (sync getter on
///     StorageService) rather than a Future, so there is no frame where
///     the user is treated as logged-out while the Future resolves.
/// ─────────────────────────────────────────────────────────────────────────────
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/auth/forget_screen.dart';
import 'package:flutter_education_app/features/student/dashboard/dashboard_screen.dart';
import 'package:flutter_education_app/features/enrollment/enrollment_screen.dart';
import 'package:flutter_education_app/features/student/home/home_screen.dart';
import 'package:flutter_education_app/features/student/models.dart';
import 'package:provider/provider.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'config/app_config.dart';
import 'config/app_theme.dart';
import 'config/storage_service.dart';
import 'core/providers.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/register_screen.dart';
import 'features/auth/verified_screen.dart';
import 'features/notification/notifications_screen.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'features/student/courses/details/course_detail_screen.dart';
import 'features/student/courses/list/courses_list_screen.dart';
import 'features/teacher/dashboard/teacher_dashboard_screen.dart';

// Populated synchronously in main() — safe to read in build()
late StorageService _storage;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise storage ONCE here so the same instance is shared everywhere.
  _storage = await StorageService.getInstance();

  await readLanguage();

  runApp(
    MultiProvider(
      // Pass the storage instance into the providers so AuthProvider
      // can restore the user from disk in its constructor.
      providers: appProviders(storage: _storage),
      child: const ElFaheemApp(),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// App widget
// ─────────────────────────────────────────────────────────────────────────────

class ElFaheemApp extends StatelessWidget {
  const ElFaheemApp({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    // Decide the first screen synchronously — storage is already loaded.
    final String initialRoute;
    if (!auth.isAuthenticated) {
      initialRoute = '/login';
    } else if (auth.isTeacher) {
      initialRoute = '/teacher_dashboard';
    } else {
      initialRoute = '/dashboard';
    }

    return MaterialApp(
      title: 'ElFaheem',
      debugShowCheckedModeBanner: false,
      theme:AppTheme.themeData,
      initialRoute: initialRoute,
      onGenerateRoute: _router,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (a, child) {
        ApiClient().context=a;

        return ResponsiveBreakpoints.builder(
        breakpoints: [
          const Breakpoint(start: 0, end: 450, name: MOBILE),
          const Breakpoint(start: 451, end: 800, name: TABLET),
          const Breakpoint(start: 801, end: 1920, name: DESKTOP),
          const Breakpoint(start: 1921, end: double.infinity, name: '4K'),
        ],
        useShortestSide: true,
        child: child!,
      );
      },
      supportedLocales: context
          .read<LangProvider>()
          .languages
          .map((_) => const Locale('en', ''))
          .toList(),
    );
  }

  Route<dynamic>? _router(RouteSettings settings) {
    switch (settings.name) {
      // ── Auth ───────────────────────────────────────────────────────────────
      case '/login':
        return _fade(const LoginScreen());
      case '/register':
        return _fade(const RegisterScreen());
      case '/otp':
        final args = settings.arguments as List;
        final gmail = args[0] as String;
        final role = args[1] as String;
        return _fade(OtpVerificationScreen(email: gmail, role: role));
      case '/forgot-password':
        return _fade(const ForgetScreen());

      // ── Main ───────────────────────────────────────────────────────────────
      case '/home':
        return _fade(const _Guard(child: HomeScreen()));
      case '/dashboard':
        return _fade(const _Guard(child: DashboardScreen()));
      case '/teacher_dashboard':
        return _fade(const _Guard(child: TeacherDashboardScreen()));

      // ── Courses ────────────────────────────────────────────────────────────
      case '/courses':
        return _fade(const _Guard(child: CoursesListScreen()));
      case '/course-detail':
        CourseModel course = settings.arguments as CourseModel;
        return _fade(_Guard(
            child: CourseDetailScreen(
          course: course,
        )));

      // ── Other ──────────────────────────────────────────────────────────────
      case '/my-enrollments':
        return _fade(const _Guard(child: EnrollmentScreen()));
      case '/notifications':
        return _fade(const _Guard(child: NotificationsScreen()));

      default:
        return _fade(const _NotFoundScreen());
    }
  }

  PageRoute _fade(Widget page) => PageRouteBuilder(
        pageBuilder: (_, __, ___) => page,
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 300),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Auth guard
// ─────────────────────────────────────────────────────────────────────────────

/// Redirects to /login if the user is not authenticated.
/// Uses the synchronous StorageService.isAuthenticated() so no async flash.
class _Guard extends StatelessWidget {
  final Widget child;

  const _Guard({required this.child});

  @override
  Widget build(BuildContext context) {
    if (!context.read<AuthProvider>().isAuthenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushReplacementNamed('/login');
      });
      return const SizedBox.shrink();
    }
    return child;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 404
// ─────────────────────────────────────────────────────────────────────────────

class _NotFoundScreen extends StatelessWidget {
  const _NotFoundScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('404',
                style: TextStyle(fontSize: 64, fontWeight: FontWeight.w900)),
            const Text('الصفحة غير موجودة',
                style: TextStyle(fontFamily: 'Tajawal', fontSize: 16)),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pushReplacementNamed(context.read<AuthProvider>().isTeacher?'/teacher_dashboard':'/dashboard'),
              child: const Text('الرئيسية',
                  style:
                      TextStyle(fontFamily: 'Tajawal', color: Color(0xFF5B8FFF))),
            ),
          ],
        ),
      ),
    );
  }
}
