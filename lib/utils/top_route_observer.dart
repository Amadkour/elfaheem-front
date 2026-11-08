import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_education_app/core/attention/attention_service.dart';
import 'package:flutter_education_app/core/offline/app_connectivity.dart';
import 'package:flutter_education_app/features/shared/chat/chat_store.dart' show ChatHub;
import 'package:flutter_education_app/core/offline/offline_video_service.dart';
import 'package:flutter_education_app/features/student/models.dart';
import 'package:flutter_education_app/utils/live_events.dart';

import '../features/shared/attendance/attendance_offline_sync.dart';
import '../features/shared/attendance/attendance_store.dart';
import 'package:flutter_education_app/features/shared/exam_engine/offline/offline_exam_service.dart';
import 'package:flutter_education_app/features/org/advising/adv_draft_store.dart' show AdvDraftStore;
import 'package:flutter_education_app/features/auth/username_confirm.dart';
import 'package:flutter_education_app/design/app_shell_nav.dart' show AppShellNav;

class TopRouteObserver extends NavigatorObserver {
  /// The root navigator's top route.
  Route<dynamic>? _rootRoute;
  Route<dynamic>? previousRoute;

  /// The root navigator's top route (a role shell's route while its tab pages are on screen).
  Route<dynamic>? get rootRoute => _rootRoute;

  /// The route the person sees: the root navigator's top, or — inside a role shell — the top page of the visible
  /// tab (each tab has its own navigator, D-081). A tab on its root page reports the shell's route.
  Route<dynamic>? get currentRoute => AppShellNav.effectiveTop(_rootRoute);
  set currentRoute(Route<dynamic>? r) => _rootRoute = r;

  /// A push / pop inside a shell tab's navigator ([initial]: the tab's own first page, built on its first visit).
  void didChangeNested(Route<dynamic> route, {required bool pushed, bool initial = false}) {
    _refreshShortcut();
    if (initial) return; // a tab opening is not a navigation: no extra attention refresh (request budgets)
    AttentionService.instance.onRouteChanged();
  }

  /// The visible tab changed, and with it the route the person sees.
  void didSwitchTab() => _refreshShortcut();

  @override
  void didPush(
      Route<dynamic> route,
      Route<dynamic>? previousRoute,
      ) {
    this.previousRoute = previousRoute;
    currentRoute = route;
    // The Downloads page WE opened because the app started offline.
    if (_awaitingAutoRoute && route.settings.name == '/downloads') {
      _autoRoute = route;
      _awaitingAutoRoute = false;
    }
    _refreshShortcut();
    AttentionService.instance.onRouteChanged();   // badges: a new screen / back from one
    if (route.settings.name != '/login') ChatHub.instance.start();   // chat events, delivered acks (idempotent, D-330)
    // a role home is on screen: ask once about an auto-filled @username (D-071 v2)
    UsernameConfirmPrompt.instance.onRoute(route, () => currentRouteName);
  }

  @override
  void didPop(
      Route<dynamic> route,
      Route<dynamic>? previousRoute,
      ) {
    this.previousRoute = route;
    currentRoute = previousRoute;
    if (identical(route, _autoRoute)) _autoRoute = null;
    AppShellNav.forgetRoute(route);
    _leaveIfReady();
    _refreshShortcut();
    AttentionService.instance.onRouteChanged();
  }

  @override
  void didRemove(
      Route<dynamic> route,
      Route<dynamic>? previousRoute,
      ) {
    this.previousRoute = previousRoute;
    currentRoute = previousRoute;
    if (identical(route, _autoRoute)) _autoRoute = null;
    AppShellNav.forgetRoute(route);
    _leaveIfReady();
    _refreshShortcut();
  }

  @override
  void didReplace({
    Route<dynamic>? newRoute,
    Route<dynamic>? oldRoute,
  }) {
    previousRoute = oldRoute;
    currentRoute = newRoute;
    _refreshShortcut();
  }

  bool get isCourseDetailActive =>
      currentRoute?.settings.name == '/course-detail';

  String? get activeCourseId {
    final args = currentRoute?.settings.arguments;

    if (args is CourseModel) {
      return args.id;
    }

    return null;
  }

  // Previous route name
  String? get previousRouteName =>
      previousRoute?.settings.name;

  // Current route name
  String? get currentRouteName =>
      currentRoute?.settings.name;

  // ───────────────────────────────────────────────────────────────────────────
  // Offline / online switching
  // ───────────────────────────────────────────────────────────────────────────
  //
  //  app STARTS offline  → main.dart opens the Downloads page by itself
  //                        (student: Dashboard on its last tab → Downloads on top).
  //                        It calls [expectAutoDownloads] so that page counts as
  //                        "opened by the app".
  //  app GOES offline    → nothing navigates. A small "Open downloads" button
  //                        ([shortcutVisible], drawn by OfflineShortcutOverlay)
  //                        lets the user jump there with one tap.
  //  back ONLINE         → the Downloads page the APP opened is closed again;
  //                        a page the user opened himself is never closed.

  /// Screens where the shortcut button makes no sense.
  static const _neverInterrupt = {'/login', '/register', '/splash', '/downloads', '/attendance-live'};

  bool _bound = false;
  bool _awaitingAutoRoute = false; // set by expectAutoDownloads, didPush not seen yet
  Route<dynamic>? _autoRoute; // the Downloads route the app opened (offline start)
  bool _leaveWhenTop = false; // back online, but something is open above Downloads

  /// True while the app has no usable connection (see [AppConnectivity]).
  bool get isOffline => !AppConnectivity.instance.isOnline;

  /// Call right before the offline start-up stack (… → /downloads) is built.
  void expectAutoDownloads() => _awaitingAutoRoute = true;

  /// Call once at start-up (main.dart), after [AppConnectivity.init].
  void bindConnectivity() {
    if (_bound) return;
    _bound = true;
    AppConnectivity.instance.online.addListener(_onConnectivityChanged);
    // A video was downloaded / deleted → the button may need to appear / go away.
    OfflineVideoService.instance.downloadedIds.addListener(_refreshShortcut);
  }

  void _onConnectivityChanged() {
    // A new connection change: show the button again even if it was dismissed.
    _shortcutDismissed = false;
    if (isOffline) {
      _switchToOffline();
    } else {
      _switchToOnline();
    }
    _refreshShortcut();
    // Providers / screens that want to reload themselves can listen for this.
    LiveEvents.instance.emit(
      LiveEvents.connectivity,
      {'online': '${!isOffline}'},
    );
  }

  /// Online -> offline. No automatic navigation any more: only the shortcut
  /// button is shown (see [shortcutVisible]).
  void _switchToOffline() {
    _leaveWhenTop = false;
  }

  /// Offline -> online.
  void _switchToOnline() {
    // 1) Whatever was stored while offline is settled now (idempotent re-send of attendance
    //    requests, refresh of the cached attendance windows).
    AttendanceOfflineSync.instance.onReconnect();
    OfflineExamSync.instance.onReconnect();          // finished offline exam sittings + answers carried for classmates
    AdvDraftStore.instance.onReconnect();            // advising notes written offline (idempotent by client_id)

    // 2) Close the Downloads page only if the APP opened it.
    _awaitingAutoRoute = false;
    if (_autoRoute == null) return;
    _leaveWhenTop = true;
    _leaveIfReady();
  }

  /// Pops the auto-opened Downloads page once it is the top route (so a video player or a
  /// check-in sheet opened on top of it is never torn down in the middle of what the user does).
  void _leaveIfReady() {
    if (!_leaveWhenTop) return;
    final r = _autoRoute;
    if (r == null) {
      _leaveWhenTop = false;
      return;
    }
    if (identical(currentRoute, r)) {
      _leaveWhenTop = false;
      // after the current navigation frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (identical(currentRoute, r)) navigator?.pop();
      });
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // "Open downloads" shortcut button
  // ───────────────────────────────────────────────────────────────────────────

  /// Drives OfflineShortcutOverlay.
  final ValueNotifier<bool> shortcutVisible = ValueNotifier<bool>(false);

  /// The route on top, updated after each navigation (deferred like [shortcutVisible]); the floating app
  /// assistant listens to it.
  final ValueNotifier<Route<dynamic>?> topRoute = ValueNotifier<Route<dynamic>?>(null);

  bool _shortcutDismissed = false;
  bool _refreshQueued = false;

  /// Re-evaluates [shortcutVisible]. Deferred to a microtask: navigator callbacks can fire in
  /// the middle of a build, where notifying listeners would throw.
  void _refreshShortcut() {
    if (_refreshQueued) return;
    _refreshQueued = true;
    scheduleMicrotask(() {
      _refreshQueued = false;
      topRoute.value = currentRoute;
      final v = _computeShortcut();
      if (shortcutVisible.value != v) shortcutVisible.value = v;
    });
  }

  bool _computeShortcut() {
    if (kIsWeb || _shortcutDismissed || !isOffline) return false;
    final r = currentRoute;
    // only real pages (not dialogs / bottom sheets)
    if (r == null || r is! PageRoute) return false;
    final name = r.settings.name;
    if (name != null && _neverInterrupt.contains(name)) return false;
    return OfflineVideoService.instance.downloadedIds.value.isNotEmpty ||
        AttendanceStore.instance.hasCachedCourses;
  }

  /// The button was tapped. This is a page the USER chose, so it is not closed
  /// automatically when the connection returns.
  void openDownloads() {
    final nav = navigator;
    if (nav == null) return;
    shortcutVisible.value = false;
    nav.pushNamed('/downloads');
  }

  /// The small "x": hide the button until the next connection change.
  void dismissShortcut() {
    _shortcutDismissed = true;
    shortcutVisible.value = false;
  }
}

final topRouteObserver = TopRouteObserver();