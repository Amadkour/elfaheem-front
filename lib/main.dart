/// ─────────────────────────────────────────────────────────────────────────────
/// main.dart
/// Only change from before: MaterialApp now reads ProfileProvider.darkMode
/// and passes the correct ThemeMode — that's the ENTIRE dark-mode wiring.
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
import 'features/shared/profile/profile_provider.dart';

late StorageService _storage;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _storage = await StorageService.getInstance();
  await readLanguage();

  runApp(
    MultiProvider(
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

    final String initialRoute;
    if (!auth.isAuthenticated) {
      initialRoute = '/login';
    } else if (auth.isTeacher) {
      initialRoute = '/teacher_dashboard';
    } else {
      initialRoute = '/dashboard';
    }

    // ── Dark-mode wiring ─────────────────────────────────────────────────────
    // context.watch rebuilds MaterialApp whenever darkMode flips.
    // That's all — no other file needs to change for the theme to switch.
    final isDark = context.watch<ProfileProvider>().darkMode;

    return MaterialApp(
      title: 'ElFaheem',
      debugShowCheckedModeBanner: false,

      // Light theme
      theme: AppTheme.themeData,
      // Dark theme
      darkTheme: AppTheme.darkThemeData,
      // Controlled by ProfileProvider — not by the OS
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,

      initialRoute: initialRoute,
      onGenerateRoute: _router,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (a, child) {
        ApiClient().context = a;
        return ResponsiveBreakpoints.builder(
          breakpoints: [
            const Breakpoint(start: 0,    end: 450,            name: MOBILE),
            const Breakpoint(start: 451,  end: 800,            name: TABLET),
            const Breakpoint(start: 801,  end: 1920,           name: DESKTOP),
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
      case '/login':            return _fade(const LoginScreen());
      case '/register':         return _fade(const RegisterScreen());
      case '/otp':
        final args  = settings.arguments as List;
        return _fade(OtpVerificationScreen(
          email: args[0] as String, role: args[1] as String,
        ));
      case '/forgot-password':  return _fade(const ForgetScreen());
      case '/home':             return _fade(const _Guard(child: HomeScreen()));
      case '/dashboard':        return _fade(const _Guard(child: DashboardScreen()));
      case '/teacher_dashboard':return _fade(const _Guard(child: TeacherDashboardScreen()));
      case '/courses':          return _fade(const _Guard(child: CoursesListScreen()));
      case '/course-detail':
        final course = settings.arguments as CourseModel;
        return _fade(_Guard(child: CourseDetailScreen(course: course)));
      case '/my-enrollments':   return _fade(const _Guard(child: EnrollmentScreen()));
      case '/notifications':    return _fade(const _Guard(child: NotificationsScreen()));
      default:                  return _fade(const _NotFoundScreen());
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
    final c = context.colors;   // ← uses AppColorsX extension
    return Scaffold(
      backgroundColor: c.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('404', style: TextStyle(
              fontSize: 64, fontWeight: FontWeight.w900, color: c.textDark,
            )),
            Text('الصفحة غير موجودة', style: TextStyle(
              fontFamily: 'Tajawal', fontSize: 16, color: c.textMedium,
            )),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () => Navigator.of(context).pushReplacementNamed(
                context.read<AuthProvider>().isTeacher
                    ? '/teacher_dashboard'
                    : '/dashboard',
              ),
              child: const Text('الرئيسية', style: TextStyle(
                fontFamily: 'Tajawal', color: Color(0xFF5B8FFF),
              )),
            ),
          ],
        ),
      ),
    );
  }
}