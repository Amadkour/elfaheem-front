import 'dart:async';
import 'dart:math' as math;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_education_app/core/offline/app_connectivity.dart';
import 'package:flutter_education_app/core/offline/offline_video_service.dart';
import 'package:flutter_education_app/features/shared/downloads/downloads_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/version_check_service.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/auth/forget_screen.dart';
import 'package:flutter_education_app/features/student/dashboard/dashboard_screen.dart';
import 'package:flutter_education_app/features/student/home/home_screen.dart';
import 'package:flutter_education_app/features/student/models.dart';
import 'package:flutter_education_app/url_strategy_stub.dart';
import 'package:flutter_education_app/utils/helpers.dart';
import 'package:flutter_education_app/utils/remote_config_service.dart';
import 'package:flutter_education_app/utils/top_route_observer.dart';
import 'package:flutter_education_app/utils/widget/app_navigator.dart';
import 'package:flutter_education_app/utils/widget/app_network_image.dart';
import 'package:flutter_education_app/core/offline/offline_strings.dart';
import 'package:flutter_education_app/utils/widget/deep_link_service.dart';
import 'package:flutter_education_app/utils/widget/view_as_state.dart';
import 'package:provider/provider.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'config/app_config.dart';
import 'config/storage_service.dart';
import 'config/theme/theme_config_provider.dart';
import 'core/app_identity.dart';
import 'core/providers.dart';
import 'features/admin/admin_view_as_page.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/register_screen.dart';
import 'features/auth/verified_screen.dart';
import 'features/shared/attendance/attendance_offline_sync.dart';
import 'features/shared/attendance/attendance_push.dart';
import 'features/shared/attendance/attendance_store.dart';
import 'features/shared/attendance/attendance_teacher_banner.dart';
import 'features/shared/guest/guest_state.dart';
import 'features/shared/notification/admin_message_dialogs.dart';
import 'features/shared/notification/notification_service.dart';
import 'features/shared/notification/notifications_screen.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'features/shared/profile/change_password_widget.dart';
import 'features/shared/profile/update_account_widget.dart';
import 'features/shared/subscription/subscription_screen.dart';
import 'features/student/courses/details/course_detail_screen.dart';
import 'features/student/courses/details/course_link_loader.dart';
import 'features/teacher/dashboard/teacher_dashboard_screen.dart';
import 'features/admin/admin_dashboard_screen.dart';
import 'features/parent/parent_dashboard_screen.dart';
import 'features/shared/profile/profile_provider.dart';
import 'firebase_options.dart';

late StorageService _storage;
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// ─────────────────────────────────────────────────────────────────────────────
// Entry point
// ─────────────────────────────────────────────────────────────────────────────

Future<void> main() async {
  configureUrlStrategy(); // web: usePathUrlStrategy(), mobile: no-op

  if (kIsWeb) {
    WidgetsFlutterBinding.ensureInitialized();
    await _bootstrap();
  } else {
    // ensureInitialized and runApp must run in the SAME zone.
    runZonedGuarded(() async {
      WidgetsFlutterBinding.ensureInitialized();
      await _bootstrap();
    }, _onZoneError);
  }
}

/// Paints the premium splash immediately (no white screen), runs the startup
/// work, then ALWAYS starts the real app. The error screen ([_FatalApp]) is
/// shown only when startup fails.
Future<void> _bootstrap() async {
  runApp(const _BootApp());

  try {
    await _initCore();
  } catch (e, s) {
    debugPrint('[bootstrap:core] $e\n$s');
    runApp(_FatalApp(error: '$e'));
    return;
  }

  if (!kIsWeb) {
    await _safe('crashlytics', _initCrashlytics, seconds: 8);
  }

  try {
    _runApp();
  } catch (e, s) {
    debugPrint('[bootstrap:runApp] $e\n$s');
    runApp(_FatalApp(error: '$e'));
  }
}

// ── Shared initialisation (all platforms) ───────────────────────────────────

Future<void> _initCore() async {
  // Essential: the app cannot run without storage.
  _storage = await StorageService.getInstance();

  await _safe('language', () => readLanguage(), seconds: 8);
  timeago.setLocaleMessages('ar', timeago.ArShortMessages());
  timeago.setLocaleMessages('en', timeago.EnShortMessages());

  await _safe(
    'firebase',
        () =>
        Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform),
    seconds: 10,
  );
  await _safe(
    'remoteConfig',
        () => RemoteConfigService.instance.init(),
    seconds: 8,
  );

  // Never block startup on notifications (permission dialog / FCM token can be slow).
  _safe(
    'notifications',
        () => NotificationService.instance.init(),
    seconds: 30,
  );

  // One online/offline answer for the whole app; the route observer switches screens with it.
  await _safe(
    'connectivity',
        () => AppConnectivity.instance.init(),
    seconds: 5,
  );
  try {
    topRouteObserver.bindConnectivity();
  } catch (e) {
    debugPrint('[init:bindConnectivity] $e');
  }

  // Offline (encrypted) videos: purge expired copies and load the list, so the
  // start route can be chosen synchronously.
  if (!kIsWeb) {
    await _safe(
      'offlineVideos',
          () => OfflineVideoService.instance.init(),
      seconds: 8,
    );
    // Subscribed courses saved for the offline Attendance tab.
    await _safe(
      'attendanceCourses',
          () => AttendanceStore.instance.preload(),
      seconds: 8,
    );
  }
}

/// Runs an init step with a timeout; failures are logged, never fatal.
Future<T?> _safe<T>(
    String name,
    Future<T> Function() fn, {
      int seconds = 6,
    }) async {
  try {
    return await fn().timeout(Duration(seconds: seconds));
  } catch (e) {
    debugPrint('[init:$name] $e');
    return null;
  }
}

// ── Crashlytics (mobile only) ────────────────────────────────────────────────

Future<void> _initCrashlytics() async {
  // Firebase failed or timed out → skip instead of throwing.
  if (Firebase.apps.isEmpty) return;

  // Disable in debug so your dashboard stays clean during development
  await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
    !kDebugMode,
  );

  // Flutter framework errors (widget build failures, etc.)
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
}

void _onZoneError(Object error, StackTrace stack) {
  debugPrint('Zone error: $error\n$stack');
  try {
    if (Firebase.apps.isNotEmpty) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    }
  } catch (_) {}
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
// Boot screen (shown instantly while startup work runs) + fatal error screen
// ─────────────────────────────────────────────────────────────────────────────

/// Shown INSTANTLY while the startup work runs: the same premium splash that is
/// shown while the live theme loads (so the two hand over seamlessly).
///
/// It needs a ThemeConfigProvider for `context.colors`; this one is never loaded,
/// so it paints with the default palette. If it cannot be created before the
/// core services are ready, a plain spinner is used as the very first frame.
class _BootApp extends StatefulWidget {
  const _BootApp();

  @override
  State<_BootApp> createState() => _BootAppState();
}

class _BootAppState extends State<_BootApp> {
  ThemeConfigProvider? _theme;

  @override
  void initState() {
    super.initState();
    try {
      _theme = ThemeConfigProvider(api: ApiClient());
    } catch (e) {
      debugPrint('[boot] splash theme unavailable: $e');
    }
  }

  @override
  void dispose() {
    _theme?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = _theme;
    if (theme == null) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    return ThemeConfigScope(provider: theme, child: const _PremiumLoadingScreen());
  }
}

class _FatalApp extends StatelessWidget {
  const _FatalApp({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 48, color: Colors.redAccent),
                    const SizedBox(height: 12),
                    const Text(
                      'Startup error',
                      style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      error,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () => _bootstrap(),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// App widget
// ─────────────────────────────────────────────────────────────────────────────

class ElFaheemApp extends StatefulWidget {
  const ElFaheemApp({super.key});

  @override
  State<ElFaheemApp> createState() => _ElFaheemAppState();
}

class _ElFaheemAppState extends State<ElFaheemApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    AttendancePush.instance.bind(navigatorKey);
    ViewAsBanner.onExit = () {
      // /auth/me returned the VIEWED user while view-as was on → put the admin's own profile back first,
      // otherwise the admin dashboard answers "admins only".
      context.read<MyAuthProvider>().restoreOwnUser();
      navigatorKey.currentState?.pushNamedAndRemoveUntil(
        '/admin_dashboard',
            (r) => false,
      );
    };

    // NOTE: load() must NOT be called synchronously here. ThemeConfigProvider
    // .load() calls notifyListeners() before its first await, and calling
    // that mid-mount (while sibling providers like NotificationsProvider are
    // still building) throws "setState() or markNeedsBuild() called during
    // build". Deferring to the post-frame callback runs it safely once the
    // whole tree has finished its first build.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      context.read<ThemeConfigProvider>().load();

      // When the network link returns, AppConnectivity asks the server before it says "online".
      AppConnectivity.instance.serverProbe = () async {
        final t = context.read<ThemeConfigProvider>();
        await t.reload();
        return !t.serverUnreachable;
      };

      // ── Version check – blocks launch if a force-update is required ──────────
      try {
        await VersionCheckService.instance.checkOnStartup();
      } catch (e) {
        debugPrint('[versionCheck] $e');
      }
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
        context.read<MyAuthProvider>().isAuthenticated &&
        !ViewAsState.active) {
      // never pop the VIEWED user's admin dialogs while an admin is looking around
      AdminMessageDialogs.checkPending();
    }
  }

  bool? _lastServerOk;

  @override
  Widget build(BuildContext context) {
    final tc = context.watch<ThemeConfigProvider>();

    // Feed the server-reachability signal to AppConnectivity (after this frame: its listeners
    // rebuild widgets, which is not allowed in the middle of a build).
    final serverOk = !tc.serverUnreachable;
    if (_lastServerOk != serverOk) {
      _lastServerOk = serverOk;
      WidgetsBinding.instance.addPostFrameCallback(
            (_) => AppConnectivity.instance.reportServerReachable(serverOk),
      );
    }

    // Block on the theme response before rendering the real app so every
    // screen paints with the correct palette from the very first frame.
    if (tc.isLoading) {
      return ThemeConfigScope(
        provider: tc,
        child: const _PremiumLoadingScreen(),
      );
    }

    final auth = context.read<MyAuthProvider>();
    // Offline at start-up + the user has downloaded videos → open the
    // Downloads page so they can keep watching. (If there are no downloads,
    // behave exactly as before.)
    final bool offlineStart =
        !kIsWeb &&
            auth.isAuthenticated &&
            tc.serverUnreachable &&
            (OfflineVideoService.instance.downloadedIds.value.isNotEmpty ||
                AttendanceStore.instance.hasCachedCourses);
    // Refresh the saved course list for the offline Attendance tab (no-op offline).
    if (auth.isAuthenticated && !tc.serverUnreachable) {
      WidgetsBinding.instance.addPostFrameCallback(
            (_) => AttendanceOfflineSync.instance.warmCourses(),
      );
    }
    // Student + offline start-up: Dashboard (on its LAST tab) first, Downloads on top of it.
    final bool offlineStudentStart = offlineStart && auth.isStudent;
    final String initialRoute = !auth.isAuthenticated
        ? '/login'
        : (offlineStudentStart
        ? '/dashboard'
        : (offlineStart ? '/downloads' : auth.homeRoute));

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
        provider: tc,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          navigatorObservers: [topRouteObserver],
          title: appName,
          debugShowCheckedModeBanner: false,
          theme: tc.materialTheme(dark: false),
          darkTheme: tc.materialTheme(dark: true),
          themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
          initialRoute: initialRoute,
          onGenerateRoute: _router,
          onGenerateInitialRoutes: (name) {
            if (offlineStudentStart) {
              // The dashboard reads this when it mounts and jumps to its last tab (profile).
              AppNavigator.requestedTab.value = 'last';
              // The Downloads page below is opened by the app → closed again when back online.
              topRouteObserver.expectAutoDownloads();
              return [
                _router(const RouteSettings(name: '/dashboard'))!,
                _router(const RouteSettings(name: '/downloads'))!,
              ];
            }
            return [_router(RouteSettings(name: name))!];
          },
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          // ViewAsBanner shows the "View only: <name> · Back to admin" bar above EVERY screen while a
          // super-admin is in view-as mode (it renders nothing otherwise).
          // GuestBanner is the same idea for a guest ("Browsing as guest · Login").
          builder: (_, child) => GuestBanner(
            child: ViewAsBanner(
              child: AttendanceTeacherBanner(
                navigatorKey: navigatorKey,
                child: _OfflineThemeBanner(
                  child: ResponsiveBreakpoints.builder(
                    breakpoints: [
                      const Breakpoint(start: 0, end: 450, name: MOBILE),
                      const Breakpoint(start: 451, end: 800, name: TABLET),
                      const Breakpoint(start: 801, end: 1920, name: DESKTOP),
                      const Breakpoint(
                        start: 1921,
                        end: double.infinity,
                        name: '4K',
                      ),
                    ],
                    useShortestSide: true,
                    child: child!,
                  ),
                ),
              ),
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
    final link = DeepLinkService.parse(settings.name); // /c/12?ref=5
    if (link != null) {
      if (!context.read<MyAuthProvider>().isAuthenticated) {
        // open it right after login
        DeepLinkService.instance.setPending(link);
        return _fade(const LoginScreen(), const RouteSettings(name: '/login'));
      }
      return _fade(
        _Guard(
          child: CourseLinkLoader(courseId: link.courseId, ref: link.ref),
        ),
        settings,
      );
    }
    switch (settings.name) {
      case '/login':
        return _fade(const LoginScreen(), settings);
      case '/register':
        return _fade(const RegisterScreen(), settings);
      case '/otp':
        final args = settings.arguments;
        if (args is! List || args.length < 2) {
          return _fade(
            const LoginScreen(),
            const RouteSettings(name: '/login'),
          );
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
        return _fade(
          const _Guard(guestOk: true, child: HomeScreen()),
          settings,
        );
      case '/dashboard':
        return _fade(
          const _Guard(guestOk: true, child: DashboardScreen()),
          settings,
        );
      case '/teacher_dashboard':
        return _fade(const _Guard(child: TeacherDashboardScreen()), settings);
      case '/admin_dashboard':
        return _fade(const _Guard(child: AdminDashboardScreen()), settings);
      case '/parent_dashboard':
        return _fade(const _Guard(child: ParentDashboardScreen()), settings);
      case '/subscription':
        return _fade(const _Guard(child: SubscriptionScreen()), settings);
      case '/profile':
        return _fade(const _Guard(child: EditAccountScreen()), settings);
      case '/change-password':
        return _fade(const _Guard(child: ChangePasswordScreen()), settings);
      case '/downloads':
        return _fade(const _Guard(child: DownloadsScreen()), settings);
      case '/course-detail':
        final course = settings.arguments;
        if (course is! CourseModel) {
          // opened by URL / page refresh → there is no CourseModel to show
          return _fade(const _Guard(child: _RedirectHome()), settings);
        }
        return _fade(
          _Guard(guestOk: true, child: CourseDetailScreen(course: course)),
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
  settings: settings,
  pageBuilder: (_, _, _) => page,
  transitionsBuilder: (_, anim, _, child) =>
      FadeTransition(opacity: anim, child: child),
  transitionDuration: const Duration(milliseconds: 300),
);

// ─────────────────────────────────────────────────────────────────────────────
// "No internet" header — shown above every screen while the theme could not be
// fetched from the server. The app keeps running on the cached / default theme.
// ─────────────────────────────────────────────────────────────────────────────

class _OfflineThemeBanner extends StatelessWidget {
  const _OfflineThemeBanner({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: topRouteObserver.shortcutVisible,
    builder: (context, shortcut, _) => _content(context, shortcut),
  );

  Widget _content(BuildContext context, bool shortcut) {
    final tc = context.watch<ThemeConfigProvider>();
    // The header also shows while the phone is offline but the theme call has not failed yet,
    // because it hosts the "Open downloads" button.
    final show = tc.serverUnreachable || shortcut;
    final c = context.colors;

    // The child keeps the same slot (index 1, wrapped in the same widgets)
    // whether the banner is visible or not — otherwise toggling the banner
    // would rebuild the Navigator below and lose the current screen.
    return Column(
      children: [
        show
            ? Directionality(
          textDirection: Helpers.pageDirection,
          child: Material(
            color: c.danger,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.wifi_off_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'no_network_banner'.tr,
                            style: const TextStyle(
                              fontFamily: 'tajawal',
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    // Bottom of the header: one tap to the Downloads page (offline only).
                    if (shortcut)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 2),
                        child: Row(
                          children: [

                            Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: Material(
                                color: Colors.white.withValues(alpha: 0.18),
                                shape: StadiumBorder(
                                  side: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.55),
                                  ),
                                ),
                                child: InkWell(
                                  customBorder: const StadiumBorder(),
                                  onTap: topRouteObserver.openDownloads,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 5,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.download_for_offline_rounded,
                                          size: 16,
                                          color: Colors.white,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          offlineT('dl_open_downloads'),
                                          style: const TextStyle(
                                            fontFamily: 'tajawal',
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Spacer(),
                            if (tc.isRetrying)
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            else
                              TextButton.icon(
                                onPressed: () =>
                                    context.read<ThemeConfigProvider>().reload(),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  visualDensity: VisualDensity.compact,
                                ),
                                icon: const Icon(Icons.refresh_rounded, size: 18),
                                label: Text(
                                  'retry'.tr,
                                  style: const TextStyle(
                                    fontFamily: 'tajawal',
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        )
            : const SizedBox.shrink(),
        Expanded(
          // The banner already covers the status bar, so the screens below
          // must not add their own top inset a second time.
          child: MediaQuery.removePadding(
            context: context,
            removeTop: show,
            child: child,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Premium splash screen — shown while the live theme is being fetched
// ─────────────────────────────────────────────────────────────────────────────

class _PremiumLoadingScreen extends StatelessWidget {
  const _PremiumLoadingScreen();

  // On web / deep links the platform's initial route (e.g. "/login") is passed
  // to THIS MaterialApp first. It must resolve every route name to the splash,
  // otherwise Flutter logs "Could not navigate to initial route".
  Route<dynamic> _splashRoute(RouteSettings _) => PageRouteBuilder(
    settings: const RouteSettings(name: '/'),
    pageBuilder: (_, _, _) => const _SplashBody(),
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.light, fontFamily: 'tajawal'),
      onGenerateRoute: _splashRoute,
      onGenerateInitialRoutes: (_) => [
        _splashRoute(const RouteSettings(name: '/')),
      ],
    );
  }
}

/// Built below the MaterialApp (and the ThemeConfigScope above it), so
/// context.colors can resolve here.
///
/// Branded from the dashboard's "About us" data (AppIdentity: cached from the last launch,
/// so it is already right on the first frame; before the very first fetch it falls back to
/// the bundled logo + the remote-config name).
class _SplashBody extends StatefulWidget {
  const _SplashBody();

  @override
  State<_SplashBody> createState() => _SplashBodyState();
}

class _SplashBodyState extends State<_SplashBody>
    with TickerProviderStateMixin {
  // Shared by the instant boot splash and the theme-loading splash, so the hand-over between
  // them neither replays the intro nor makes the logo jump.
  static bool _introPlayed = false;
  static final Stopwatch _clock = Stopwatch()..start();
  static final List<double> _phShared = (() {
    final r = math.Random();
    return List<double>.generate(8, (_) => r.nextDouble() * math.pi * 2);
  })();

  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
    value: _introPlayed ? 1.0 : 0.0,
  );

  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  )..repeat(reverse: true);

  // Continuous clock for the organic random logo drift (never loops/snaps).
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 86400),
  )..forward();

  // Random phases per launch: the logo wanders differently every time.
  late final List<double> _ph = _phShared;

  late final Animation<double> _greetA = _step(0.00, 0.35);
  late final Animation<double> _logoA = _step(0.10, 0.60, Curves.easeOutBack);
  late final Animation<double> _nameA = _step(0.35, 0.75);
  late final Animation<double> _tagA = _step(0.50, 0.90);
  late final Animation<double> _footA = _step(0.65, 1.00);
  late final Animation<double> _float = CurvedAnimation(
    parent: _loop,
    curve: Curves.easeInOut,
  );

  Animation<double> _step(
      double s,
      double e, [
        Curve curve = Curves.easeOutCubic,
      ]) => CurvedAnimation(
    parent: _enter,
    curve: Interval(s, e, curve: curve),
  );

  static const _messages = [
    'نجهّز لك كل شيء…',
    'لحظات ونكون معك',
    'نحضّر تجربتك بكل حب',
    'شكراً لصبرك 💛',
  ];
  int _msgIndex = 0;
  Timer? _msgTimer;

  @override
  void initState() {
    super.initState();
    if (!_introPlayed) {
      _enter.forward().whenComplete(() => _introPlayed = true);
    }
    _msgTimer = Timer.periodic(const Duration(milliseconds: 2200), (_) {
      if (!mounted) return;
      setState(() => _msgIndex = (_msgIndex + 1) % _messages.length);
    });
  }

  @override
  void dispose() {
    _msgTimer?.cancel();
    _enter.dispose();
    _loop.dispose();
    _drift.dispose();
    super.dispose();
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 5) return 'ليلة هادئة 🌙';
    if (h < 12) return 'صباح الخير ☀️';
    if (h < 17) return 'طاب يومك 🌤️';
    if (h < 21) return 'مساء الخير 🌇';
    return 'مساء النور 🌙';
  }

  double get _t => _clock.elapsedMicroseconds / 1000000.0;

  Widget _reveal(Animation<double> a, Widget child, {double dy = 0.18}) {
    return FadeTransition(
      opacity: a,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset(0, dy),
          end: Offset.zero,
        ).animate(a),
        child: child,
      ),
    );
  }

  Widget _glow(double size, Color color) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final id = AppIdentity.instance;

    return ListenableBuilder(
      listenable: id,
      builder: (context, _) {
        final name = id.name.isNotEmpty ? id.name : _safeAppName();
        final tagline = id.tagline;
        final version = id.versionLabel;

        final logoImage = AppNetworkImage(
          url: id.logoUrl ?? 'assets/images/logo.png',
          width: 92,
          height: 92,
          fit: BoxFit.contain,
        );

        return Directionality(
          textDirection: pageDirection,
          child: Scaffold(
            backgroundColor: c.background,
            body: Container(
              width: double.infinity,
              height: double.infinity,
              // Flat theme background colour (adapts to light / dark).
              color: c.background,
              child: Stack(
                children: [
                  // ══ Premium background (all layers derive from the theme) ══

                  // 1) Gentle top/bottom primary wash over the flat background.
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            c.primary.withValues(alpha: c.isDark ? 0.12 : 0.08),
                            Colors.transparent,
                            c.primary.withValues(alpha: c.isDark ? 0.14 : 0.09),
                          ],
                          stops: const [0.0, 0.5, 1.0],
                        ),
                      ),
                    ),
                  ),

                  // 2) Fine dot grid that fades out toward the centre.
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _DotGridPainter(
                          color: c.primary.withValues(
                            alpha: c.isDark ? 0.22 : 0.16,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // 3) Drifting primary glows.
                  AnimatedBuilder(
                    animation: _drift,
                    builder: (_, _) {
                      final t = _t;
                      return Stack(
                        children: [
                          PositionedDirectional(
                            top: -120 + 26 * math.sin(t * 0.30 + _ph[0]),
                            end: -110 + 20 * math.sin(t * 0.23 + _ph[1]),
                            child: _glow(
                              380,
                              c.primary.withValues(
                                alpha: c.isDark ? 0.24 : 0.16,
                              ),
                            ),
                          ),
                          PositionedDirectional(
                            bottom: -140 + 24 * math.sin(t * 0.27 + _ph[2]),
                            start: -100 + 18 * math.sin(t * 0.21 + _ph[3]),
                            child: _glow(
                              360,
                              c.primaryLight.withValues(
                                alpha: c.isDark ? 0.20 : 0.22,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),

                  // 4) Breathing spotlight + concentric rings behind the logo.
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: _float,
                        builder: (_, _) {
                          final p = _float.value;
                          Widget ring(double size, double alpha) => Container(
                            width: size,
                            height: size,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: c.primary.withValues(alpha: alpha),
                                width: 1,
                              ),
                            ),
                          );
                          return Center(
                            child: Transform.scale(
                              scale: 1 + 0.05 * p,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  _glow(
                                    460,
                                    c.primary.withValues(
                                      alpha: c.isDark ? 0.26 : 0.17,
                                    ),
                                  ),
                                  ring(280, c.isDark ? 0.20 : 0.14),
                                  ring(400, c.isDark ? 0.14 : 0.09),
                                  ring(540, c.isDark ? 0.09 : 0.05),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                  // 5) Soft vignette for depth.
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: Alignment.center,
                            radius: 1.15,
                            colors: [
                              Colors.transparent,
                              (c.isDark ? Colors.black : c.primaryDark)
                                  .withValues(alpha: c.isDark ? 0.35 : 0.10),
                            ],
                            stops: const [0.6, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ),

                  SafeArea(
                    child: Column(
                      children: [
                        // ── Top half: greeting ──
                        Expanded(
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 20),
                              child: _reveal(
                                _greetA,
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: c.primaryTint,
                                    borderRadius: BorderRadius.circular(30),
                                    border: Border.all(
                                      color: c.primary.withValues(alpha: 0.18),
                                    ),
                                  ),
                                  child: Text(
                                    _greeting,
                                    style: TextStyle(
                                      fontFamily: 'tajawal',
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                      color: c.primary,
                                    ),
                                  ),
                                ),
                                dy: -0.4,
                              ),
                            ),
                          ),
                        ),

                        // ── Logo: exactly centred (both halves are Expanded) ──
                        ScaleTransition(
                          scale: Tween<double>(
                            begin: 0.8,
                            end: 1,
                          ).animate(_logoA),
                          child: FadeTransition(
                            opacity: CurvedAnimation(
                              parent: _enter,
                              curve: const Interval(0.1, 0.45),
                            ),
                            child: AnimatedBuilder(
                              animation: Listenable.merge([_drift, _float]),
                              child: logoImage,
                              builder: (_, image) {
                                final t = _t;
                                final dx =
                                    12 * math.sin(t * 0.90 + _ph[0]) +
                                        6 * math.sin(t * 1.70 + _ph[1]);
                                final dy =
                                    14 * math.sin(t * 1.10 + _ph[2]) +
                                        6 * math.sin(t * 2.10 + _ph[3]);
                                final tilt =
                                    0.05 * math.sin(t * 0.80 + _ph[4]) +
                                        0.02 * math.sin(t * 1.90 + _ph[5]);
                                final breathe =
                                    1 + 0.025 * math.sin(t * 1.30 + _ph[6]);
                                final p = _float.value;

                                return Transform.translate(
                                  offset: Offset(dx, dy),
                                  child: Transform.rotate(
                                    angle: tilt,
                                    child: Transform.scale(
                                      scale: breathe,
                                      child: SizedBox(
                                        width: 200,
                                        height: 200,
                                        child: Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            // pulsing halo in primary
                                            Container(
                                              width: 150 + 46 * p,
                                              height: 150 + 46 * p,
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                BorderRadius.circular(
                                                  46 + 10 * p,
                                                ),
                                                border: Border.all(
                                                  color: c.primary.withValues(
                                                    alpha: 0.30 * (1 - p),
                                                  ),
                                                  width: 1.6,
                                                ),
                                              ),
                                            ),
                                            Container(
                                              width: 136,
                                              height: 136,
                                              padding: const EdgeInsets.all(20),
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius:
                                                BorderRadius.circular(40),
                                                border: Border.all(
                                                  color: c.primaryLight
                                                      .withValues(alpha: 0.55),
                                                  width: 3,
                                                ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: c.primary.withValues(
                                                      alpha: 0.28,
                                                    ),
                                                    blurRadius: 36,
                                                    offset: Offset(
                                                      -dx * 0.5,
                                                      16 - dy * 0.4,
                                                    ),
                                                  ),
                                                  BoxShadow(
                                                    color: c.primaryLight
                                                        .withValues(
                                                      alpha: 0.30,
                                                    ),
                                                    blurRadius: 60,
                                                    spreadRadius: 2,
                                                  ),
                                                ],
                                              ),
                                              child: image,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),

                        // ── Bottom half: name, tagline, then footer ──
                        Expanded(
                          child: Column(
                            children: [
                              const SizedBox(height: 6),
                              _reveal(
                                _nameA,
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 32,
                                  ),
                                  child: Text(
                                    name,
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: 'tajawal',
                                      fontSize: 30,
                                      fontWeight: FontWeight.w800,
                                      color: c.textDark,
                                      height: 1.2,
                                    ),
                                  ),
                                ),
                              ),
                              if (tagline.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                _reveal(
                                  _tagA,
                                  Column(
                                    children: [
                                      Container(
                                        width: 36,
                                        height: 3,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [c.primary, c.primaryLight],
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            3,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 40,
                                        ),
                                        child: Text(
                                          tagline,
                                          textAlign: TextAlign.center,
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontFamily: 'tajawal',
                                            fontSize: 15.5,
                                            height: 1.6,
                                            color: c.textMedium,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const Spacer(),
                              _reveal(
                                _footA,
                                Column(
                                  children: [
                                    AnimatedSwitcher(
                                      duration: const Duration(
                                        milliseconds: 450,
                                      ),
                                      transitionBuilder: (child, anim) =>
                                          FadeTransition(
                                            opacity: anim,
                                            child: SlideTransition(
                                              position: Tween<Offset>(
                                                begin: const Offset(0, 0.4),
                                                end: Offset.zero,
                                              ).animate(anim),
                                              child: child,
                                            ),
                                          ),
                                      child: Text(
                                        _messages[_msgIndex],
                                        key: ValueKey(_msgIndex),
                                        style: TextStyle(
                                          fontFamily: 'tajawal',
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: c.textMedium,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: SizedBox(
                                        width: 120,
                                        height: 4,
                                        child: LinearProgressIndicator(
                                          minHeight: 4,
                                          backgroundColor: c.primary.withValues(
                                            alpha: 0.15,
                                          ),
                                          valueColor:
                                          AlwaysStoppedAnimation<Color>(
                                            c.primary,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    if (version.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: c.primaryTint,
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        child: Text(
                                          'v$version',
                                          style: TextStyle(
                                            fontFamily: 'tajawal',
                                            fontSize: 11.5,
                                            letterSpacing: 0.6,
                                            color: c.textLight,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                dy: 0.3,
                              ),
                              const SizedBox(height: 22),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Fine dot grid; dots fade out near the centre so the logo stays the focus.
class _DotGridPainter extends CustomPainter {
  final Color color;

  const _DotGridPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 26.0;
    final center = Offset(size.width / 2, size.height / 2);
    final maxDist = math.sqrt(center.dx * center.dx + center.dy * center.dy);
    final paint = Paint();
    for (double y = gap / 2; y < size.height; y += gap) {
      for (double x = gap / 2; x < size.width; x += gap) {
        final d =
            (Offset(x, y) - center).distance / maxDist; // 0 centre → 1 corner
        final fade = ((d - 0.25) / 0.75).clamp(0.0, 1.0);
        if (fade <= 0) continue;
        paint.color = color.withValues(alpha: color.a * fade);
        canvas.drawCircle(Offset(x, y), 1.1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGridPainter old) => old.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
// Route guard
// ─────────────────────────────────────────────────────────────────────────────

class _Guard extends StatefulWidget {
  final Widget child;

  /// Student catalogue screens a GUEST may open (read-only). Everything else still needs a login.
  final bool guestOk;

  const _Guard({required this.child, this.guestOk = false});

  @override
  State<_Guard> createState() => _GuardState();
}

class _GuardState extends State<_Guard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.guestOk && GuestState.active) {
        return; // guest: no pending links / admin dialogs / pushes
      }
      if (!context.read<MyAuthProvider>().isAuthenticated) {
        Navigator.of(context).pushReplacementNamed('/login');
        return;
      }
      DeepLinkService.instance.consumePending(); // link opened while logged out
      if (!ViewAsState.active) {
        AdminMessageDialogs.checkPending(); // dialogs sent by admins
      }
      // a push tapped while the app was closed / logged out → open its target now
      NotificationService.instance.consumePendingPush();
    });
  }

  @override
  Widget build(BuildContext context) =>
      (context.read<MyAuthProvider>().isAuthenticated ||
          (widget.guestOk && GuestState.active))
          ? widget.child
          : const SizedBox.shrink();
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
      Navigator.of(
        context,
      ).pushReplacementNamed(context.read<MyAuthProvider>().homeRoute);
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
              ).pushReplacementNamed(context.read<MyAuthProvider>().homeRoute),
              child: Text(
                'home'.tr,
                style: const TextStyle(
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
/// RemoteConfigService may not be initialised yet while the boot splash is showing.
String _safeAppName() {
  try {
    return RemoteConfigService.instance.appName;
  } catch (_) {
    return '';
  }
}