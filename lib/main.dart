library;

import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/version_check_service.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/auth/forget_screen.dart';
import 'package:flutter_education_app/features/student/dashboard/dashboard_screen.dart';
import 'package:flutter_education_app/features/student/home/home_screen.dart';
import 'package:flutter_education_app/features/student/models.dart';
import 'package:flutter_education_app/utils/remote_config_service.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'package:provider/provider.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'config/app_config.dart';
import 'config/theme/app_theme.dart';
import 'config/storage_service.dart';
import 'config/theme/theme_config_provider.dart';
import 'core/providers.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/register_screen.dart';
import 'features/auth/verified_screen.dart';
import 'features/shared/notification/notification_service.dart';
import 'features/shared/notification/notifications_screen.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'features/student/courses/details/course_detail_screen.dart';
import 'features/teacher/dashboard/teacher_dashboard_screen.dart';
import 'features/shared/profile/profile_provider.dart';
import 'firebase_options.dart';

late StorageService _storage;
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  if (!kIsWeb) {
    runZonedGuarded(() async {
      WidgetsFlutterBinding.ensureInitialized();

      await _initCore();
      await _initCrashlytics();

      _runApp();
    }, _onZoneError);
  } else {
    WidgetsFlutterBinding.ensureInitialized();

    await _initCore();

    _runApp();
  }
}

// ── Shared initialisation (all platforms) ───────────────────────────────────

Future<void> _initCore() async {
  _storage = await StorageService.getInstance();

  await readLanguage();
  timeago.setLocaleMessages('ar', timeago.ArShortMessages());
  timeago.setLocaleMessages('en', timeago.EnShortMessages());

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await RemoteConfigService.instance.init();
  await NotificationService.instance.init();
}

// ── Crashlytics (mobile only) ────────────────────────────────────────────────

Future<void> _initCrashlytics() async {
  // Disable in debug so your dashboard stays clean during development
  await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
    !kDebugMode,
  );

  // Flutter framework errors (widget build failures, etc.)
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
}

void _onZoneError(Object error, StackTrace stack) {
  // Catches errors outside the widget tree (Futures, Streams, isolates)
  FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
}

// ── App entry point ──────────────────────────────────────────────────────────

void _runApp() {
  final api = ApiClient();

  runApp(
    MultiProvider(
      providers: appProviders(storage: _storage, api: api),
      child: const ElFaheemApp(),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// App widget
// ─────────────────────────────────────────────────────────────────────────────

class ElFaheemApp extends StatefulWidget {
  const ElFaheemApp({super.key});

  @override
  State<ElFaheemApp> createState() => _ElFaheemAppState();
}

class _ElFaheemAppState extends State<ElFaheemApp> {
  @override
  void initState() {
    // NOTE: load() must NOT be called synchronously here. ThemeConfigProvider
    // .load() calls notifyListeners() before its first await, and calling
    // that mid-mount (while sibling providers like NotificationsProvider are
    // still building) throws "setState() or markNeedsBuild() called during
    // build". Deferring to the post-frame callback runs it safely once the
    // whole tree has finished its first build.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      context.read<ThemeConfigProvider>().load();

      // ── Version check – blocks launch if a force-update is required ──────────
      await VersionCheckService.instance.checkOnStartup();
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final tc = context.watch<ThemeConfigProvider>();

    // Block on the theme response before rendering the real app so every
    // screen paints with the correct palette from the very first frame.
    if (tc.isLoading) {
      return const _PremiumLoadingScreen();
    }

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
    final appName = RemoteConfigService.instance.appName;

    return ThemeConfigScope(
      // ← wrap here
      provider: tc,
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: appName,
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
        builder: (_, child) => ResponsiveBreakpoints.builder(
          breakpoints: [
            const Breakpoint(start: 0, end: 450, name: MOBILE),
            const Breakpoint(start: 451, end: 800, name: TABLET),
            const Breakpoint(start: 801, end: 1920, name: DESKTOP),
            const Breakpoint(start: 1921, end: double.infinity, name: '4K'),
          ],
          useShortestSide: true,
          child: child!,
        ),
        supportedLocales: context
            .read<LangProvider>()
            .languages
            .map((_) => const Locale('en', ''))
            .toList(),
      ),
    );
  }

  Route<dynamic>? _router(RouteSettings settings) {
    switch (settings.name) {
      case '/login':
        return _fade(const LoginScreen());
      case '/register':
        return _fade(const RegisterScreen());
      case '/otp':
        final args = settings.arguments as List;
        return _fade(
          OtpVerificationScreen(
            email: args[0] as String,
            role: args[1] as String,
          ),
        );
      case '/forgot-password':
        return _fade(const ForgetScreen());
      case '/home':
        return _fade(const _Guard(child: HomeScreen()));
      case '/dashboard':
        return _fade(const _Guard(child: DashboardScreen()));
      case '/teacher_dashboard':
        return _fade(const _Guard(child: TeacherDashboardScreen()));
      case '/course-detail':
        final course = settings.arguments as CourseModel;
        return _fade(_Guard(child: CourseDetailScreen(course: course)));
      case '/notifications':
        return _fade(const _Guard(child: NotificationsScreen()));
      default:
        return _fade(const _NotFoundScreen());
    }
  }

  PageRoute _fade(Widget page) => PageRouteBuilder(
    pageBuilder: (_, _, _) => page,
    transitionsBuilder: (_, anim, _, child) =>
        FadeTransition(opacity: anim, child: child),
    transitionDuration: const Duration(milliseconds: 300),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Premium splash screen — shown while the live theme is being fetched
// ─────────────────────────────────────────────────────────────────────────────

/// Branded splash shown between app launch and the first theme response.
///
/// IMPORTANT: colors here are hard-coded to match `flutter_native_splash`'s
/// config in pubspec.yaml exactly (background #D4FEFD) — not read from
/// AppTheme — so there is zero visible hand-off flash between the OS-level
/// native splash and this Flutter splash, on every platform.
/// If the brand palette ever changes, update both places together.
class _PremiumLoadingScreen extends StatelessWidget {
  const _PremiumLoadingScreen();

  static const _bg = Color(0xFFD4FEFD); // matches flutter_native_splash color

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.light, fontFamily: 'tajawal'),
      home: Scaffold(
        backgroundColor: _bg,
        // AppLoadingIndicator already shows the branded logo (with its own
        // built-in fallback if the asset fails to load), so it replaces the
        // separate Image.asset + CircularProgressIndicator that used to sit
        // here — one branded widget doing both jobs.
        body: const Center(
          child: AppLoadingIndicator(size: 140),
        ),
      ),
    );
  }
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
            Text(
              '404',
              style: TextStyle(
                fontSize: 64,
                fontWeight: FontWeight.w900,
                color: c.textDark,
              ),
            ),
            Text(
              'not_found'.tr,
              style: TextStyle(
                fontFamily: 'tajawal',
                fontSize: 16,
                color: c.textMedium,
              ),
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () => Navigator.of(context).pushReplacementNamed(
                context.read<AuthProvider>().isTeacher
                    ? '/teacher_dashboard'
                    : '/dashboard',
              ),
              child: Text(
                'home'.tr,
                style: TextStyle(
                  fontFamily: 'tajawal',
                  color: Color(0xFF5B8FFF),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}