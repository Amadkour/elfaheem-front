library;

import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/version_check_service.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/auth/forget_screen.dart';
import 'package:flutter_education_app/features/student/dashboard/dashboard_screen.dart';
import 'package:flutter_education_app/features/student/home/home_screen.dart';
import 'package:flutter_education_app/features/student/models.dart';
import 'package:flutter_education_app/utils/remote_config_service.dart';
import 'package:flutter_education_app/utils/top_route_observer.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'package:flutter_education_app/utils/widget/app_network_image.dart';
import 'package:flutter_education_app/utils/widget/deep_link_service.dart';
import 'package:flutter_education_app/utils/widget/view_as_state.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:provider/provider.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'config/app_config.dart';
import 'config/theme/app_theme.dart';
import 'config/storage_service.dart';
import 'config/theme/theme_config_provider.dart';
import 'core/providers.dart';
import 'features/admin/admin_view_as_page.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/register_screen.dart';
import 'features/auth/verified_screen.dart';
import 'features/shared/notification/admin_message_dialogs.dart';
import 'features/shared/notification/notification_service.dart';
import 'features/shared/notification/notifications_screen.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'features/shared/subscription/subscription_screen.dart';
import 'features/student/courses/details/course_detail_screen.dart';
import 'features/student/courses/details/course_link_loader.dart';
import 'features/teacher/dashboard/teacher_dashboard_screen.dart';
import 'features/admin/admin_dashboard_screen.dart';
import 'features/shared/profile/profile_provider.dart';
import 'firebase_options.dart';

late StorageService _storage;
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  usePathUrlStrategy();
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

  await _safe('firebase', () =>
      Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform));
  await _safe('remoteConfig', () => RemoteConfigService.instance.init());

  // Safari (non-PWA) has no push support, so on web don't block startup on it.
  if (kIsWeb) {
    _safe('notifications', () => NotificationService.instance.init());
  } else {
    await _safe('notifications', () => NotificationService.instance.init());
  }
}

/// Runs an init step with a timeout; failures are logged, never fatal.
Future<T?> _safe<T>(String name, Future<T> Function() fn,
    {int seconds = 6}) async {
  try {
    return await fn().timeout(Duration(seconds: seconds));
  } catch (e) {
    debugPrint('[init:$name] $e');
    return null;
  }
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

class _ElFaheemAppState extends State<ElFaheemApp> with WidgetsBindingObserver{
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    ViewAsBanner.onExit = () {
      // /auth/me returned the VIEWED user while view-as was on → put the admin's own profile back first,
      // otherwise the admin dashboard answers "admins only".
      context.read<AuthProvider>().restoreOwnUser();
      navigatorKey.currentState
          ?.pushNamedAndRemoveUntil('/admin_dashboard', (r) => false);
    };

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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed &&
        context.read<AuthProvider>().isAuthenticated &&
        !ViewAsState.active) {   // never pop the VIEWED user's admin dialogs while an admin is looking around
      AdminMessageDialogs.checkPending();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tc = context.watch<ThemeConfigProvider>();

    // Block on the theme response before rendering the real app so every
    // screen paints with the correct palette from the very first frame.
    if (tc.isLoading) {
      return ThemeConfigScope(
        provider: tc,
        child: const _PremiumLoadingScreen(),
      );
    }

    final auth = context.read<AuthProvider>();
    final String initialRoute = auth.isAuthenticated
        ? auth.homeRoute
        : '/login';

    final isDark = context.watch<ProfileProvider>().darkMode;
    final appName = RemoteConfigService.instance.appName;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Light icons (time/battery/signal) in the status bar, on every
      // screen — set once here instead of per-screen, since individual
      // AppBars/Scaffolds would otherwise need to remember to set this
      // themselves and could drift back to dark icons over time.
      value: const SystemUiOverlayStyle(
        statusBarIconBrightness: Brightness.light, // Android
        statusBarBrightness: Brightness.dark, // iOS (inverted meaning)
        statusBarColor: Colors.transparent,
      ),
      child: ThemeConfigScope(
        // ← wrap here
        provider: tc,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          navigatorObservers: [topRouteObserver],
          title: appName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.themeData,
          darkTheme: AppTheme.darkThemeData,
          themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
          initialRoute: initialRoute,
          onGenerateRoute: _router,
          onGenerateInitialRoutes: (name) => [
            _router(RouteSettings(name: name))!,
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          // ViewAsBanner shows the "View only: <name> · Back to admin" bar above EVERY screen while a
          // super-admin is in view-as mode (it renders nothing otherwise).
          builder: (_, child) => ViewAsBanner(
            child: ResponsiveBreakpoints.builder(
              breakpoints: [
                const Breakpoint(start: 0, end: 450, name: MOBILE),
                const Breakpoint(start: 451, end: 800, name: TABLET),
                const Breakpoint(start: 801, end: 1920, name: DESKTOP),
                const Breakpoint(start: 1921, end: double.infinity, name: '4K'),
              ],
              useShortestSide: true,
              child: child!,
            ),
          ),
          supportedLocales: context
              .read<LangProvider>()
              .languages
              .map((_) => const Locale('en', ''))
              .toList(),
        ),
      ),
    );
  }

  Route<dynamic>? _router(RouteSettings settings) {
    final link = DeepLinkService.parse(settings.name);              // /c/12?ref=5
    if (link != null) {
      if (!context.read<AuthProvider>().isAuthenticated) {          // open it right after login
        DeepLinkService.instance.setPending(link);
        return _fade(const LoginScreen(), const RouteSettings(name: '/login'));
      }
      return _fade(_Guard(child: CourseLinkLoader(courseId: link.courseId, ref: link.ref)), settings);
    }
    switch (settings.name) {
      case '/login':
        return _fade(const LoginScreen(), settings);
      case '/register':
        return _fade(const RegisterScreen(), settings);
      case '/otp':
        final args = settings.arguments;
        if (args is! List || args.length < 2) {
          return _fade(const LoginScreen(), const RouteSettings(name: '/login'));
        }
        return _fade(
          OtpVerificationScreen(
            email: args[0] as String,
            role: args[1] as String,
          ),
          settings,
        );
      case '/forgot-password':
        return _fade(const ForgetScreen(), settings);
      case '/home':
        return _fade(const _Guard(child: HomeScreen()), settings);
      case '/dashboard':
        return _fade(const _Guard(child: DashboardScreen()), settings);
      case '/teacher_dashboard':
        return _fade(const _Guard(child: TeacherDashboardScreen()), settings);
      case '/admin_dashboard':
        return _fade(const _Guard(child: AdminDashboardScreen()), settings);
      case '/subscription':
        return _fade(const _Guard(child: SubscriptionScreen()), settings);
      case '/course-detail':
        final course = settings.arguments;
        if (course is! CourseModel) {
          // opened by URL / page refresh → there is no CourseModel to show
          return _fade(const _Guard(child: _RedirectHome()), settings);
        }
        return _fade(
          _Guard(child: CourseDetailScreen(course: course)),
          settings,
        );
      case '/notifications':
        return _fade(const _Guard(child: NotificationsScreen()), settings);
      default:
        debugPrint(
          'Unknown route: ${settings.name} args=${settings.arguments}',
        );
        return _fade(_NotFoundScreen(routeName: settings.name), settings);
    }
  }
}

PageRoute _fade(Widget page, RouteSettings settings) => PageRouteBuilder(
  settings: settings, // ← this is the missing piece
  pageBuilder: (_, _, _) => page,
  transitionsBuilder: (_, anim, _, child) =>
      FadeTransition(opacity: anim, child: child),
  transitionDuration: const Duration(milliseconds: 300),
);
// ─────────────────────────────────────────────────────────────────────────────
// Premium splash screen — shown while the live theme is being fetched
// ─────────────────────────────────────────────────────────────────────────────

class _PremiumLoadingScreen extends StatelessWidget {
  const _PremiumLoadingScreen();


  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.light, fontFamily: 'tajawal'),
      home: const _SplashBody(),
    );
  }
}

/// Built below the MaterialApp (and the ThemeConfigScope above it), so
/// context.colors can resolve here.
class _SplashBody extends StatelessWidget {
  const _SplashBody();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      // AppLoadingIndicator shows the branded logo with its own fallback.
      body: const Center(child: AppLoadingIndicator(size: 140)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Auth guard
// ─────────────────────────────────────────────────────────────────────────────

class _Guard extends StatefulWidget {
  final Widget child;
  const _Guard({required this.child});
  @override State<_Guard> createState() => _GuardState();
}
class _GuardState extends State<_Guard> {
  @override void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!context.read<AuthProvider>().isAuthenticated) {
        Navigator.of(context).pushReplacementNamed('/login');
        return;
      }
      DeepLinkService.instance.consumePending();     // link opened while logged out
      if (!ViewAsState.active) {
        AdminMessageDialogs.checkPending();          // dialogs sent by admins
      }
      // a push tapped while the app was closed / logged out → open its target now
      NotificationService.instance.consumePendingPush();
    });
  }
  @override Widget build(BuildContext context) =>
      context.read<AuthProvider>().isAuthenticated ? widget.child : const SizedBox.shrink();
}

/// Sends the user to their own home screen (used when a route has no usable arguments).
class _RedirectHome extends StatefulWidget {
  const _RedirectHome();
  @override
  State<_RedirectHome> createState() => _RedirectHomeState();
}

class _RedirectHomeState extends State<_RedirectHome> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context)
          .pushReplacementNamed(context.read<AuthProvider>().homeRoute);
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

// ─────────────────────────────────────────────────────────────────────────────
// 404
// ─────────────────────────────────────────────────────────────────────────────

class _NotFoundScreen extends StatelessWidget {
  const _NotFoundScreen({this.routeName});

  /// Shown only in debug builds, to spot which route is missing.
  final String? routeName;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppNetworkImage(
              url: 'assets/images/logo.png',
              height: 100,
              width: 100,
            ),
            Text(
              'not_found'.tr,
              style: TextStyle(
                fontFamily: 'tajawal',
                fontSize: 16,
                color: c.textMedium,
              ),
            ),
            if (kDebugMode && routeName != null)
              Text(
                routeName!,
                style: TextStyle(fontSize: 12, color: c.textLight),
              ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () => Navigator.of(
                context,
              ).pushReplacementNamed(context.read<AuthProvider>().homeRoute),
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