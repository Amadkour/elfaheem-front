import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_education_app/core/offline/app_connectivity.dart';
import 'package:flutter_education_app/core/offline/downloads_availability.dart';
import 'package:flutter_education_app/core/offline/offline_video_service.dart';
import 'package:flutter_education_app/features/shared/downloads/downloads_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/version_check_service.dart';
import 'package:flutter_education_app/core/app_locale.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/auth/forget_screen.dart';
import 'package:flutter_education_app/features/student/dashboard/dashboard_screen.dart';
import 'package:flutter_education_app/features/student/home/home_screen.dart';
import 'package:flutter_education_app/features/student/models.dart';
import 'package:flutter_education_app/utils/widget/url_strategy.dart';
import 'package:flutter_education_app/utils/helpers.dart';
import 'package:flutter_education_app/utils/remote_config_service.dart';
import 'package:flutter_education_app/utils/top_route_observer.dart';
import 'package:flutter_education_app/design/app_hscroll.dart' show AppScrollBehavior;
import 'package:flutter_education_app/design/boot_splash.dart';
import 'package:flutter_education_app/utils/widget/app_navigator.dart';
import 'package:flutter_education_app/utils/widget/app_network_image.dart';
import 'package:flutter_education_app/core/offline/offline_strings.dart';
import 'package:flutter_education_app/utils/widget/deep_link_service.dart';
import 'package:flutter_education_app/core/app_time.dart' show AppTime;
import 'package:flutter_education_app/utils/web_base_path.dart';
import 'package:flutter_education_app/utils/web_entry_route.dart';
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
import 'features/org/org_application_screen.dart';
import 'features/onboarding/explore_entry_page.dart';
import 'features/onboarding/guest_search_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/onboarding/onboarding_store.dart';
import 'features/onboarding/start_route.dart';
import 'features/auth/verified_screen.dart';
import 'features/shared/attendance/attendance_offline_sync.dart';
import 'features/shared/attendance/attendance_push.dart';
import 'features/shared/attendance/attendance_store.dart';
import 'features/shared/attendance/attendance_teacher_banner.dart';
import 'features/shared/guest/guest_live_api.dart' show guestLiveTokenFromRoute, legacyHashRoute;
import 'features/shared/guest/guest_live_page.dart';
import 'features/shared/certificates_issue/cert_issue_logic.dart' show certVerifyTokenFromRoute;
import 'features/shared/certificates_issue/cert_verify_page.dart';
import 'design/export/export_studio_api.dart' show exportLinkTokenFromRoute;
import 'features/shared/exports/export_link_open_page.dart';
import 'features/shared/exports/export_links_page.dart';
import 'features/shared/exports/export_log_page.dart';
import 'features/shared/exports/export_schedules_page.dart';
import 'features/shared/exports/exports_center_page.dart';
import 'features/shared/guest/guest_state.dart';
import 'features/shared/rag/app_assistant.dart' show AppAssistantHost;
import 'features/admin/models/model_download_bar.dart' show ModelDownloadsHost;
import 'core/release/web_release_watch.dart' show WebReleaseBanner;
import 'features/shared/get_app/app_download_banner.dart' show AppDownloadBanner;
import 'features/shared/live/live_room_host.dart' show LiveRoomHost, LiveRoomLayer;
import 'features/shared/get_app/get_app_banner.dart' show GetAppBanner;
import 'features/shared/session/video/vod_listen_layer.dart' show VodListenLayer;
import 'design/app_keyboard.dart' show AppKeyboardSupport;
import 'features/shared/notification/admin_message_dialogs.dart';
import 'features/shared/notification/notification_service.dart';
import 'features/shared/inbox/inbox_page.dart' show InboxPage, inboxRouteTab;
import 'features/shared/course_profile/course_profile_hub.dart' show CoursePageLoader;
import 'features/shared/calendar/calendar_screen.dart';
import 'features/shared/profile/change_password_widget.dart';
import 'features/shared/profile/update_account_widget.dart';
import 'features/shared/subscription/subscription_screen.dart';
import 'features/student/courses/details/course_detail_screen.dart';
import 'features/org/org_dashboard_screen.dart';
import 'features/org/org_member_dashboard.dart' show OrgMemberDashboardScreen;
import 'features/org/orgs_unavailable_gate.dart';
import 'features/student/courses/details/course_link_loader.dart';
import 'features/shared/public_profile/public_profile_page.dart' show PublicProfileScreen;
import 'features/teacher/dashboard/teacher_dashboard_screen.dart';
import 'features/admin/admin_dashboard_screen.dart';
import 'features/parent/parent_dashboard_screen.dart';
import 'features/shared/profile/profile_provider.dart';
import 'firebase_options.dart';
import 'core/display/display_settings.dart';
import 'core/display/display_sync.dart';
import 'design/app_display.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';

late StorageService _storage;
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Web: the route an old hash link (`/#/live/x`, `/#/dashboard`) pointed at, read once at start-up. With the
/// path URL strategy a plain path is the platform's default route by itself; this covers the links that are
/// still out there (shared guest links, bookmarks). Null on mobile and for clean URLs.
String? _legacyHashRoute;

/// Web: the route the browser URL asked for (`/notifications`, `/profile`, a share link), read in main() BEFORE the
/// boot splash's Navigator resets the engine's default route to `/` (M20); consumed by the real app's first
/// Navigator (utils/web_entry_route.dart). Null on mobile and for `/`.
String? _webEntry;

// ─────────────────────────────────────────────────────────────────────────────
// Entry point
// ─────────────────────────────────────────────────────────────────────────────

Future<void> main() async {
  configureUrlStrategy(); // web: usePathUrlStrategy(), mobile: no-op
  if (kIsWeb) {
    // Old `/#/route` links: keep them working and show the clean path in the address bar (no reload).
    final base = Uri.base;
    _legacyHashRoute = legacyHashRoute(base);
    if (_legacyHashRoute != null) {
      // under the app's <base href> (/app/, D-150): /app/#/payment/callback → /app/payment/callback
      replaceBrowserUrl(base.removeFragment().resolve('$webBasePath${_legacyHashRoute!.substring(1)}').toString());
    }
    _webEntry = _legacyHashRoute ?? webEntryRouteFromUri(base);
  }

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
  LiveRoomHost.installBackHandler(); // before runApp: the live room answers the back button before WidgetsApp
  if (SplashState.instance.steps > 0) SplashState.instance.reset(); // retry after a fatal start
  SplashState.instance.expected = kIsWeb ? 7 : 10;
  AppTime.useLatinDigits(); // ONE digit system (0-9) in Arabic too, before any date is formatted (M24)
  // Decode the splash artwork first (bounded): the native splash stays up meanwhile, so Flutter's first
  // frame already shows the logo exactly where the native one was — no blank flash.
  unawaited(SplashTheme.load()); // the user's dark-mode choice, usually read before the first frame
  await SplashArt.preload().timeout(const Duration(milliseconds: 800), onTimeout: () {});
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
    SplashState.instance.setStage(1);
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
  OnboardingStore.load(_storage);
  await ApiClient().primeSession(); // load the token store so MyAuthProvider.isAuthenticated is answered synchronously
  // Display & reading (fonts per language, text size, zoom, contrast, reduce motion …): early, so the splash
  // already honours reduce motion and the first real frame has the chosen fonts (D-072)
  await _safe('display', DisplaySettings.instance.load, seconds: 4);
  // The splash greets the returning user by name and paces its bar by this device's usual boot time.
  SplashState.instance.setUser(ApiClient().hasSession ? _storage.savedUser : null);
  await _safe('pacing', SplashPacing.load, seconds: 2);
  // The app's identity (name, tagline, version): cached → instant, refreshed in the background.
  await _safe('identity', _initIdentity, seconds: 3);

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
  SplashState.instance.setOffline(!AppConnectivity.instance.isOnline);

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

Future<void> _initIdentity() async {
  final id = AppIdentity.instance;
  void push() {
    SplashState.instance
      ..setIdentity(tagline: id.tagline, version: id.installedVersion)
      ..setFooter(text: id.splashFooter, logoBytes: id.splashLogoBytes, logoUrl: id.splashLogoUrl ?? '');
  }
  id.addListener(push); // the background refresh may land while the splash is still up
  await id.init();
  push();
}

/// Runs an init step with a timeout; failures are logged, never fatal.
Future<T?> _safe<T>(
    String name,
    Future<T> Function() fn, {
      int seconds = 6,
    }) async {
  SplashState.instance.beginStep(name); // splash status only
  try {
    return await fn().timeout(Duration(seconds: seconds));
  } catch (e) {
    debugPrint('[init:$name] $e');
    return null;
  } finally {
    SplashState.instance.stepDone(name); // splash progress only
  }
}

// ── Crashlytics (mobile only) ────────────────────────────────────────────────

Future<void> _initCrashlytics() async {
  // Firebase failed or timed out → skip instead of throwing.
  if (Firebase.apps.isEmpty) return;
  // Firebase now starts on Windows too (D-145), but Crashlytics has no Windows / Linux plugin.
  if (defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.linux) return;

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

      await _refreshMe();
      // Display & reading follows the account: pull at every sign-in, push every change (display_sync.dart)
      if (!mounted) return;
      final auth = context.read<MyAuthProvider>();
      DisplaySync.instance.bind(auth,
          signedIn: () => auth.isAuthenticated, skip: () => GuestState.active || ViewAsState.active);
    });
  }

  /// `GET /auth/me` once per start (S14): the cached user may be stale (role changed, flags). A changed role
  /// moves the person to that role's home. Skipped offline (an offline start keeps the cache), signed out,
  /// and in view-as (the reply would be the viewed user).
  Future<void> _refreshMe() async {
    if (!mounted) return;
    final auth = context.read<MyAuthProvider>();
    if (!auth.isAuthenticated || !AppConnectivity.instance.isOnline || ViewAsState.active) return;
    final before = auth.currentUser?.role;
    await _safe('me', auth.getMe, seconds: 8);
    if (!mounted || !auth.isAuthenticated) return;
    final after = auth.currentUser?.role;
    if (after != null && after != before) {
      navigatorKey.currentState?.pushNamedAndRemoveUntil(auth.homeRoute, (_) => false);
    }
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
    // Web uses the PATH url strategy, but the boot splash's own Navigator resets the engine's default route to `/`
    // before this app starts: the URL (`/notifications`, `/c/12?ref=5`, an old `/#/live/x`) was read in main()
    // and is honoured here when the person may open it (resolveWebEntry: share links always, sign-in pages when
    // signed out, argument-free pages over the home when signed in; another role's dashboard → the own home).
    final entry = resolveWebEntry(_webEntry,
        signedIn: auth.isAuthenticated,
        home: auth.homeRoute,
        isLink: (r) =>
            guestLiveTokenFromRoute(r) != null || certVerifyTokenFromRoute(r) != null || exportLinkTokenFromRoute(r) != null ||
            DeepLinkService.parse(r) != null || DeepLinkService.parseProfile(r) != null ||
            ExploreRequest.matches(r) || isInstitutionRoute(r) || registerRoleFromRoute(r) != null);
    final String initialRoute = entry?.route ??
        (!auth.isAuthenticated
        ? (decideSignedOutStart(
                isAuthenticated: false, isWeb: kIsWeb, onboardingSeen: OnboardingStore.seen, hasEntryLink: false) ??
            '/login')
        : (offlineStudentStart
        ? '/dashboard'
        : (offlineStart ? '/downloads' : auth.homeRoute)));

    final isDark = context.watch<ProfileProvider>().darkMode;
    // the framework's locale follows the app language (core/app_locale.dart): rebuild the MaterialApp on a switch
    context.watch<LangProvider>();
    // ONE app name everywhere: the name the super admin set on the dashboard ("About us" → AppIdentity,
    // cached for offline/first frame); remote config is only the fallback before the very first fetch.
    final appName = AppIdentity.instance.name.isNotEmpty
        ? AppIdentity.instance.name
        : RemoteConfigService.instance.appName;

    // The splash dissolves over the first app frame instead of being cut away.
    return SplashHandOff(child: AnnotatedRegion<SystemUiOverlayStyle>(
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
          scrollBehavior: const AppScrollBehavior(), // mouse / trackpad can drag every scrollable (web, desktop)
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
            // `/profile` by URL: the home, on its account tab (N10) — the dashboard reads the request when it mounts.
            final tab = auth.isAuthenticated ? webEntryTab(_webEntry) : null;
            if (tab != null) AppNavigator.requestedTab.value = tab;
            _webEntry = null; // one start only: a later Navigator (sign-out / sign-in) opens the usual way
            if (entry != null && entry.overHome && name == entry.route) {
              return [_router(RouteSettings(name: auth.homeRoute))!, _router(RouteSettings(name: name))!];
            }
            return [_router(RouteSettings(name: name))!];
          },
          // Arabic or English as the person picked (core/app_locale.dart): the root semantics node reads Arabic
          // rows right to left, and Material's own labels / pickers speak the app language.
          locale: appLocale,
          supportedLocales: appSupportedLocales,
          localizationsDelegates: appLocalizationsDelegates,
          // ViewAsBanner shows the "View only: <name> · Back to admin" bar above EVERY screen while a
          // super-admin is in view-as mode (it renders nothing otherwise).
          // GuestBanner is the same idea for a guest ("Browsing as guest · Login").
          // ONE direction for everything the Navigator shows — pages AND overlays (dialogs, bottom sheets, menus,
          // date pickers). A Directionality inside a page never reaches overlays, which is why some of them were
          // laid out in the wrong direction.
          // AppDisplayScope (outermost): the person's text size, zoom, bold, contrast, motion and fonts for
          // everything below — pages, overlays, the assistant and the live room (design/app_display.dart, D-072)
          builder: (_, child) => AppDisplayScope(
            child: Directionality(
            textDirection: Helpers.pageDirection,
            // web / desktop keyboards: Enter walks a form and submits it, Ctrl+Enter from a multi-line field, Esc,
            // Ctrl+K / "/" to the search box — for every text field (design/app_keyboard.dart)
            child: AppKeyboardSupport(
            // listen-only (D-104): a lecture playing as sound is a bar at the very top; the whole app (assistant,
            // banners, pages, the live room) is laid out below it (session/video/vod_listen_layer.dart)
            child: VodListenLayer(
            navigatorKey: navigatorKey,
            // the super admin's floating model-download bar (D-152): above every page, so it stays while moving around
            // the app; a tap opens AI Models (admin/models/model_download_bar.dart)
            child: ModelDownloadsHost(
            navigatorKey: navigatorKey,
            // the floating app assistant: a bubble above every signed-in screen (rag/app_assistant.dart)
            child: AppAssistantHost(
            navigatorKey: navigatorKey,
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
                    // the live room above the Navigator: full-screen, or a box while moving around the app
                    // web: "Get the app" strip above the role homes; above it the website downloads strip on every page,
                    // sign-in included (D-144); on top "A new version is live — Reload" (D-143), which keeps the top spot
                    child: LiveRoomLayer(child: WebReleaseBanner(child: AppDownloadBanner(child: GetAppBanner(child: child!)))),
                  ),
                ),
              ),
            ),
          ))))))),
        ),
      ),
    ));
  }

  Route<dynamic>? _router(RouteSettings settings) {
    // /live/<token> — a live session's public guest link (web deep link, app link, QR). No account needed:
    // it resolves before login and in guest mode, on purpose outside _Guard.
    final guestToken = guestLiveTokenFromRoute(settings.name);
    if (guestToken != null) {
      return _fade(GuestLivePage(token: guestToken), settings);
    }
    // /verify/<token> — a certificate's public verification page (the link / QR printed on it). No account needed,
    // outside _Guard: the page calls only the public verify route with auth: false.
    final verifyToken = certVerifyTokenFromRoute(settings.name);
    if (verifyToken != null) {
      return _fade(CertVerifyPage(token: verifyToken), settings);
    }
    // /e/<token> — an Export Studio share link (D-134): sign-in required, the page downloads the file
    final exportToken = exportLinkTokenFromRoute(settings.name);
    if (exportToken != null) {
      if (!context.read<MyAuthProvider>().isAuthenticated) {
        ExportLinkPending.set(exportToken); // opened right after login (_Guard)
        return _fade(const LoginScreen(), const RouteSettings(name: '/login'));
      }
      return _fade(_Guard(child: ExportLinkOpenPage(token: exportToken)), settings);
    }
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
    // /@ahmed — a profile link (D-074): the same flow as a course link (signed out → login, then the profile)
    final profile = DeepLinkService.parseProfile(settings.name);
    if (profile != null) {
      if (!context.read<MyAuthProvider>().isAuthenticated) {
        DeepLinkService.instance.setPendingProfile(profile);
        return _fade(const LoginScreen(), const RouteSettings(name: '/login'));
      }
      return _fade(_Guard(child: PublicProfileScreen(username: profile.username)), settings);
    }
    // the inbox page — the inbox and the notifications on one page with tabs: '/inbox' (?tab= / an InboxTab
    // argument) on its tab, the old '/notifications' on the Notifications tab
    // the landing website's links (also reachable by URL while signed out): the explorer, an institution applying, a
    // registration with a role preselected
    if (ExploreRequest.matches(settings.name)) {
      return _fade(ExploreEntryPage(request: ExploreRequest.parse(settings.name)), const RouteSettings(name: '/explore'));
    }
    if (isInstitutionRoute(settings.name)) {
      return _fade(const OrgApplicationScreen(), const RouteSettings(name: '/start/institution'));
    }
    final regRole = registerRoleFromRoute(settings.name);
    if (regRole != null) {
      return _fade(RegisterScreen(initialRole: regRole), const RouteSettings(name: '/register'));
    }
    final inboxTab = inboxRouteTab(settings.name, settings.arguments);
    if (inboxTab != null) return _fade(_Guard(child: InboxPage(initial: inboxTab)), settings);
    switch (settings.name) {
      case '/login':
        return _fade(const LoginScreen(), settings);
      case '/register':
        return _fade(const RegisterScreen(), settings);
      case '/onboarding':
        return _fade(const OnboardingScreen(), settings);
      case '/guest-search':
        return _fade(const GuestSearchScreen(), settings);
      case '/explore':
        return _fade(ExploreEntryPage(request: ExploreRequest.parse(settings.name)), settings);
      case '/start/institution':
        return _fade(const OrgApplicationScreen(), settings);
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
      case '/org_member': // the student's organization page (Organization mode as a page); arguments: org id (deep link)
        return _fade(_Guard(child: OrgsGate(child: OrgMemberDashboardScreen(orgId: settings.arguments is int ? settings.arguments as int : null))), settings);
      case '/org_dashboard': // ONE dashboard for every non-student org role (D-103); a student sees OrgStaffOnlyPage
        return _fade(const _Guard(child: OrgsGate(child: OrgDashboardScreen())), settings);
      case '/parent_dashboard':
        return _fade(const _Guard(child: ParentDashboardScreen()), settings);
      case '/subscription':
        return _fade(const _Guard(child: SubscriptionScreen()), settings);
      case '/profile': // the role's account tab (N10); the edit-account form is '/edit-account'
        return _fade(const _Guard(child: _RedirectHome(tab: 'profile')), settings);
      case '/edit-account':
        return _fade(const _Guard(child: EditAccountScreen()), settings);
      case '/change-password':
        return _fade(const _Guard(child: ChangePasswordScreen()), settings);
      case '/downloads':
        // offline downloads are device files: no such page on the web (a typed / old link goes home)
        if (!kDownloadsAvailable) return _fade(const _Guard(child: _RedirectHome()), settings);
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
      case '/course-profile': // arguments: course id (int) — one profile page for every role
        final cid = settings.arguments;
        if (cid is! int) return _fade(const _Guard(child: _RedirectHome()), settings);
        return _fade(_Guard(child: CoursePageLoader(courseId: cid)), settings); // the one course page (D-111)
      case '/exports': // the Export Studio hub; arguments: true → admins (shows the export log)
        return _fade(_Guard(child: ExportsCenterPage(admin: settings.arguments == true)), settings);
      case '/exports/log': // arguments: an organization id (int) or null
        return _fade(_Guard(child: ExportLogPage(orgId: settings.arguments is int ? settings.arguments as int : null)), settings);
      case '/exports/schedules':
        return _fade(const _Guard(child: ExportSchedulesPage()), settings);
      case '/exports/links':
        return _fade(const _Guard(child: ExportLinksPage()), settings);
      case '/calendar': // arguments: a meeting id (int, notification tap) or {org_id?, dept_id?, meeting_id?}
        final a = settings.arguments;
        final m = a is Map ? a : const {};
        return _fade(
            _Guard(
                child: CalendarScreen(
                    orgId: m['org_id'] as int?,
                    deptId: m['dept_id'] as int?,
                    openMeetingId: a is int ? a : m['meeting_id'] as int?)),
            settings);
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
                            style: TextStyle(
                              fontFamily: AppFonts.family,
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
                                          style: TextStyle(
                                            fontFamily: AppFonts.family,
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
                                  style: TextStyle(
                                    fontFamily: AppFonts.family,
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
    pageBuilder: (_, _, _) => const BootSplash(),
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.light, fontFamily: AppFonts.family),
      onGenerateRoute: _splashRoute,
      onGenerateInitialRoutes: (_) => [
        _splashRoute(const RouteSettings(name: '/')),
      ],
    );
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
      ExportLinkPending.consume(Navigator.of(context)); // an export share link, likewise
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
  const _RedirectHome({this.tab});

  /// The dashboard tab to show ('profile' for the `/profile` route, N10): back to the home under this page, or
  /// the home in its place, which then switches to the tab.
  final String? tab;

  @override
  State<_RedirectHome> createState() => _RedirectHomeState();
}

class _RedirectHomeState extends State<_RedirectHome> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final nav = Navigator.of(context);
      if (widget.tab != null) {
        AppNavigator.requestedTab.value = null; // re-fire even if the same tab is requested twice
        AppNavigator.requestedTab.value = widget.tab;
        if (nav.canPop()) {
          nav.pop();
          return;
        }
      }
      nav.pushReplacementNamed(context.read<MyAuthProvider>().homeRoute);
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
                fontFamily: AppFonts.family,
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
                style: TextStyle(
                  fontFamily: AppFonts.family,
                  color: context.colors.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
