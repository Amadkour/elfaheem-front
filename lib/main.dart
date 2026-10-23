import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
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
import 'features/org/org_dashboard_screen.dart';
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
  // Decode the splash artwork first (bounded): the native splash stays up meanwhile, so Flutter's first
  // frame already shows the logo exactly where the native one was — no blank flash.
  await _SplashArt.preload().timeout(const Duration(milliseconds: 800), onTimeout: () {});
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
    _BootProgress.stage = 1;
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
  } finally {
    _BootProgress.steps++; // splash progress only
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
      return const _PremiumLoadingScreen(); // the splash needs no theme: same frame either way
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
    // ONE app name everywhere: the name the super admin set on the dashboard ("About us" → AppIdentity,
    // cached for offline/first frame); remote config is only the fallback before the very first fetch.
    final appName = AppIdentity.instance.name.isNotEmpty
        ? AppIdentity.instance.name
        : RemoteConfigService.instance.appName;

    // The splash dissolves over the first app frame instead of being cut away.
    return _SplashHandOff(child: AnnotatedRegion<SystemUiOverlayStyle>(
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
          // ONE direction for everything the Navigator shows — pages AND overlays (dialogs, bottom sheets, menus,
          // date pickers). A Directionality inside a page never reaches overlays, which is why some of them were
          // laid out in the wrong direction.
          builder: (_, child) => Directionality(
            textDirection: Helpers.pageDirection,
            child: GuestBanner(
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
          )),
          supportedLocales: context
              .read<LangProvider>()
              .languages
              .map((_) => const Locale('en', ''))
              .toList(),
        ),
      ),
    ));
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
      case '/org_dashboard':
        return _fade(const _Guard(child: OrgDashboardScreen()), settings);
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

/// Boot progress shown by the splash. Visual only: it never influences how the init steps run.
abstract final class _BootProgress {
  /// Finished [_safe] init steps.
  static int steps = 0;

  /// 0 core init · 1 app mounted (live theme loading) · 2 ready → hand-off.
  static int stage = 0;

  // language, firebase, remoteConfig, notifications, connectivity (+ offlineVideos, attendanceCourses, crashlytics).
  static int get _expected => kIsWeb ? 5 : 8;

  static double get target => switch (stage) {
        0 => 0.06 + 0.62 * (steps / _expected).clamp(0.0, 1.0),
        1 => 0.82,
        _ => 1.0,
      };
}

/// The native splash artwork, decoded BEFORE the first Flutter frame so that frame already shows the logo
/// (no blank flash between the native splash and Flutter's).
abstract final class _SplashArt {
  static const asset = 'assets/images/splash.png';

  /// flutter_native_splash treats the source image as 4x (Android xxxhdpi, iOS @3x = ¾, web light-4x):
  /// assets/images/splash.png is 1040×1000 px → 260×250 logical px, centred on the whole window on every
  /// platform (android_gravity / ios_content_mode: center, fullscreen, web `.center`).
  static const Size size = Size(260, 250);

  static ui.Image? image;

  static Future<void> preload() async {
    try {
      final views = WidgetsBinding.instance.platformDispatcher.views;
      final dpr = views.isEmpty ? 3.0 : views.first.devicePixelRatio;
      final data = await rootBundle.load(asset);
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
        targetWidth: (size.width * dpr).round().clamp(1, 1040),
      );
      image = (await codec.getNextFrame()).image;
    } catch (e) {
      debugPrint('[splash] preload: $e');
    }
  }

  static Widget widget(Size s) {
    final img = image;
    if (img != null) {
      return RawImage(image: img, width: s.width, height: s.height, fit: BoxFit.fill, filterQuality: FilterQuality.medium);
    }
    return Image.asset(asset, width: s.width, height: s.height, fit: BoxFit.fill, gaplessPlayback: true);
  }
}

/// THE splash, shared by the instant boot screen, the live-theme loading screen and the hand-off overlay.
///
/// Frame 1 is pixel-identical to the native splash (same artwork, 260×250 logical px, centred, #FBF7EC /
/// #0F7B5F). Every value is derived from one shared clock, so re-mounting between those three screens never
/// restarts or jumps the animation:
///  * 0–0.35 s  perfectly still (the native frame);
///  * then      a soft breathing scale + glow behind the mark, and a light shimmer sweeping across it;
///  * > 1.5 s   (slow start only) a calm progress bar + message fade in below the logo;
///  * [exit]    the mark zooms gently and fades while the canvas dissolves into the first app screen.
/// Reduced motion (MediaQuery.disableAnimations): no breathing / shimmer / zoom — only fades.
class _SplashBody extends StatefulWidget {
  const _SplashBody({this.exit});

  /// Hand-off progress 0 → 1 (null while still loading).
  final Animation<double>? exit;

  @override
  State<_SplashBody> createState() => _SplashBodyState();
}

class _SplashBodyState extends State<_SplashBody> with SingleTickerProviderStateMixin {
  static const _cream = Color(0xFFFBF7EC);
  static const _emerald = Color(0xFF0F7B5F);
  static const _still = 0.35, _indicatorAt = 1.5;

  static final Stopwatch _clock = Stopwatch();
  static double _shown = 0, _lastT = 0, _lastTarget = -1, _targetAt = 0;

  static const _msgAr = ['نجهّز لك كل شيء…', 'لحظات ونكون معك', 'نحضّر تجربتك…'];
  static const _msgEn = ['Getting everything ready…', 'Just a moment…', 'Preparing your experience…'];

  late final AnimationController _tick = AnimationController(vsync: this, duration: const Duration(seconds: 1))
    ..repeat();

  @override
  void initState() {
    super.initState();
    if (!_clock.isRunning) _clock.start();
  }

  @override
  void dispose() {
    _tick.dispose();
    super.dispose();
  }

  double get _t => _clock.elapsedMicroseconds / 1e6;

  /// Eases the bar toward the boot stage, creeping slowly inside a long step so it never looks frozen.
  static void _advance(double t) {
    final dt = (t - _lastT).clamp(0.0, 0.25);
    _lastT = t;
    final target = _BootProgress.target;
    if (target != _lastTarget) {
      _lastTarget = target;
      _targetAt = t;
    }
    final creep = target >= 1 ? 0.0 : 0.09 * (1 - math.exp(-(t - _targetAt) / 5));
    final goal = math.min(0.97, target + creep);
    final next = _shown + (goal - _shown) * (1 - math.exp(-dt * (target >= 1 ? 9 : 2.6)));
    _shown = target >= 1 ? math.max(_shown, next) : math.max(_shown, math.min(next, goal));
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.maybeOf(context);
    final reduce = mq?.disableAnimations ?? false;
    final dark = (mq?.platformBrightness ?? ui.PlatformDispatcher.instance.platformBrightness) == Brightness.dark;
    final bg = dark ? _emerald : _cream;
    final accent = dark ? _cream : _emerald;
    final en = AppConfig.lang == 'en';
    final msgs = en ? _msgEn : _msgAr;
    final exit = widget.exit;

    return Directionality(
      textDirection: en ? TextDirection.ltr : TextDirection.rtl,
      child: DefaultTextStyle(
        style: const TextStyle(decoration: TextDecoration.none),
        child: Semantics(
          label: en ? 'Loading' : 'جارٍ التحميل',
          child: LayoutBuilder(builder: (context, box) {
            final w = box.maxWidth.isFinite ? box.maxWidth : _SplashArt.size.width + 32;
            final h = box.maxHeight.isFinite ? box.maxHeight : _SplashArt.size.height + 32;
            // Native size on every real screen; only a window smaller than the artwork scales it down.
            final fit = math
                .min(1.0, math.min((w - 32) / _SplashArt.size.width, (h - 32) / _SplashArt.size.height))
                .clamp(0.2, 1.0);
            final art = _SplashArt.size * fit;
            final logo = RepaintBoundary(child: _SplashArt.widget(art));
            // The visible mark spans ~32–68 % of the artwork's height: sit the indicator just below it.
            final indicatorTop = (h / 2 + art.height * 0.18 + 40).clamp(0.0, math.max(0.0, h - 56)).toDouble();
            final barW = math.min(150.0, math.max(0.0, w - 32));

            return AnimatedBuilder(
              animation: exit == null ? _tick : Listenable.merge([_tick, exit]),
              builder: (context, _) {
                final t = _t;
                _advance(t);
                final x = exit?.value ?? 0.0;

                final ramp = reduce ? 0.0 : Curves.easeInOut.transform(((t - _still) / 0.8).clamp(0.0, 1.0));
                final breath = 0.5 - 0.5 * math.cos(2 * math.pi * math.max(0.0, t - _still) / 2.8);
                final scale = 1 + 0.028 * ramp * breath + (reduce ? 0.0 : 0.12 * Curves.easeOutCubic.transform(x));
                final cyc = (t - 0.8) % 3.4;
                final sweep = (!reduce && t > 0.8 && cyc < 1.2 && x == 0)
                    ? Curves.easeInOutSine.transform(cyc / 1.2)
                    : -1.0;
                final glowA = (dark ? 0.16 : 0.11) * ramp * (0.55 + 0.45 * breath) * (1 - x);
                final bgA = 1 - Curves.easeInOut.transform(x);
                final logoA = 1 - Curves.easeInCubic.transform(x);
                final appear = reduce ? (t > _indicatorAt ? 1.0 : 0.0) : ((t - _indicatorAt) / 0.5).clamp(0.0, 1.0);
                final indA = appear * (1 - (x * 2.2).clamp(0.0, 1.0));
                final msgIndex = (math.max(0.0, t - _indicatorAt) / 2.6).floor() % msgs.length;
                final glow = art.width * 1.45;

                return Stack(fit: StackFit.expand, children: [
                  ColoredBox(color: bg.withValues(alpha: bgA)),
                  Center(
                    child: IgnorePointer(
                      child: Container(
                        width: glow,
                        height: glow,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(colors: [
                            accent.withValues(alpha: glowA),
                            accent.withValues(alpha: 0),
                          ]),
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: Opacity(
                      opacity: logoA,
                      child: Transform.scale(
                        scale: scale,
                        child: ShaderMask(
                          blendMode: BlendMode.srcATop,
                          shaderCallback: (r) {
                            const clear = Color(0x00FFFFFF);
                            if (sweep < 0) return const LinearGradient(colors: [clear, clear]).createShader(r);
                            final c = -0.35 + 1.7 * sweep;
                            return LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [clear, Colors.white.withValues(alpha: dark ? 0.32 : 0.48), clear],
                              stops: [(c - 0.14).clamp(0.0, 1.0), c.clamp(0.0, 1.0), (c + 0.14).clamp(0.0, 1.0)],
                            ).createShader(r);
                          },
                          child: logo,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    top: indicatorTop,
                    child: Visibility(
                      visible: indA > 0,
                      child: Opacity(
                        opacity: indA,
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: SizedBox(
                              width: barW,
                              height: 3,
                              child: ColoredBox(
                                color: accent.withValues(alpha: 0.16),
                                child: Align(
                                  alignment: AlignmentDirectional.centerStart,
                                  child: FractionallySizedBox(
                                    widthFactor: _shown.clamp(0.0, 1.0),
                                    heightFactor: 1,
                                    child: ColoredBox(color: accent.withValues(alpha: 0.85)),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          AnimatedSwitcher(
                            duration: reduce ? Duration.zero : const Duration(milliseconds: 450),
                            child: Text(
                              msgs[msgIndex],
                              key: ValueKey(msgIndex),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'tajawal',
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.none,
                                color: dark ? _cream.withValues(alpha: 0.85) : const Color(0xFF4D6A61),
                              ),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ]);
              },
            );
          }),
        ),
      ),
    );
  }
}

/// Lays the splash over the first real app frame and dissolves it (scale + fade), so the app appears out of
/// the splash instead of replacing it in one cut. Plays once per launch.
class _SplashHandOff extends StatefulWidget {
  const _SplashHandOff({required this.child});
  final Widget child;

  @override
  State<_SplashHandOff> createState() => _SplashHandOffState();
}

class _SplashHandOffState extends State<_SplashHandOff> with SingleTickerProviderStateMixin {
  static bool _done = false;

  late final AnimationController _out =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 620));

  @override
  void initState() {
    super.initState();
    if (_done) return;
    _BootProgress.stage = 2;
    // Let the app paint its first frame underneath, then dissolve the splash.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
        _out.duration = const Duration(milliseconds: 220);
      }
      _out.forward().whenComplete(() {
        _done = true;
        if (mounted) setState(() {});
      });
    });
  }

  @override
  void dispose() {
    _done = true;
    _out.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The app stays the FIRST child at all times, so removing the overlay never re-mounts it.
    return Stack(fit: StackFit.expand, textDirection: TextDirection.ltr, children: [
      widget.child,
      if (!_done) Positioned.fill(child: IgnorePointer(child: _SplashBody(exit: _out))),
    ]);
  }
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
