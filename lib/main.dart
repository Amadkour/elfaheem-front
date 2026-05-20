library;

import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';   // ← NEW
import 'package:flutter/foundation.dart';                           // ← NEW (kDebugMode)
import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/auth/forget_screen.dart';
import 'package:flutter_education_app/features/student/dashboard/dashboard_screen.dart';
import 'package:flutter_education_app/features/student/home/home_screen.dart';
import 'package:flutter_education_app/features/student/models.dart';
import 'package:flutter_education_app/utils/remote_config_service.dart';
import 'package:provider/provider.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'config/app_config.dart';
import 'config/app_theme.dart';
import 'config/storage_service.dart';
import 'core/providers.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/register_screen.dart';
import 'features/auth/verified_screen.dart';
import 'features/notification/notification_service.dart';
import 'features/notification/notifications_screen.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'features/student/courses/details/course_detail_screen.dart';
import 'features/student/courses/list/courses_list_screen.dart';
import 'features/teacher/dashboard/teacher_dashboard_screen.dart';
import 'features/shared/profile/profile_provider.dart';

late StorageService _storage;
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Wrap the entire app in [runZonedGuarded] so any uncaught async error
/// is forwarded to Crashlytics automatically.
Future<void> main() async {
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    _storage = await StorageService.getInstance();
    ApiClient api = ApiClient();

    await readLanguage();
    timeago.setLocaleMessages('ar', timeago.ArShortMessages());
    timeago.setLocaleMessages('en', timeago.EnShortMessages());

    // ── Firebase ────────────────────────────────────────────────────────────
    await Firebase.initializeApp();

    // ── Crashlytics ─────────────────────────────────────────────────────────
    // In debug mode, Crashlytics is disabled to avoid polluting your dashboard.
    // Enable it in production (release / profile builds).
    await FirebaseCrashlytics.instance
        .setCrashlyticsCollectionEnabled(!kDebugMode);

    // Forward Flutter framework errors to Crashlytics
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

    // ── Remote Config ────────────────────────────────────────────────────────
    await RemoteConfigService.instance.init();

    // ── FCM / Local Notifications ────────────────────────────────────────────
    await NotificationService.instance.init();

    runApp(
      MultiProvider(
        providers: appProviders(storage: _storage, api: api),
        child: const ElFaheemApp(),
      ),
    );
  },
      // Catches errors OUTSIDE the Flutter widget tree (e.g. in Futures, Streams)
          (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      });
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

    final isDark = context.watch<ProfileProvider>().darkMode;

    // ── App name from Remote Config ──────────────────────────────────────────
    // RemoteConfigService.instance.appName returns "ElFaheem" by default,
    // or whatever value is set in Firebase Console → Remote Config.
    final appName = RemoteConfigService.instance.appName;

    return MaterialApp(
      key: navigatorKey,
      title: appName,                 // ← was hardcoded 'ElFaheem'
      debugShowCheckedModeBanner: false,
      theme: AppTheme.themeData,
      darkTheme: AppTheme.darkThemeData,
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      initialRoute: initialRoute,
      onGenerateRoute: _router,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (a, child) {
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
      case '/login':             return _fade(const LoginScreen());
      case '/register':          return _fade(const RegisterScreen());
      case '/otp':
        final args = settings.arguments as List;
        return _fade(OtpVerificationScreen(
          email: args[0] as String, role: args[1] as String,
        ));
      case '/forgot-password':   return _fade(const ForgetScreen());
      case '/home':              return _fade(const _Guard(child: HomeScreen()));
      case '/dashboard':         return _fade(const _Guard(child: DashboardScreen()));
      case '/teacher_dashboard': return _fade(const _Guard(child: TeacherDashboardScreen()));
      case '/courses':           return _fade(const _Guard(child: CoursesListScreen()));
      case '/course-detail':
        final course = settings.arguments as CourseModel;
        return _fade(_Guard(child: CourseDetailScreen(course: course)));
      case '/notifications':     return _fade(const _Guard(child: NotificationsScreen()));
      default:                   return _fade(const _NotFoundScreen());
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
    final c = context.colors;
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