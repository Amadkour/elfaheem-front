import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_education_app/core/offline/app_connectivity.dart';
import 'package:flutter_education_app/core/offline/offline_video_service.dart';
import 'package:flutter_education_app/features/student/models.dart';
import 'package:flutter_education_app/utils/live_events.dart';

import '../features/shared/attendance/attendance_offline_sync.dart';
import '../features/shared/attendance/attendance_store.dart';

class TopRouteObserver extends NavigatorObserver {
  Route<dynamic>? currentRoute;
  Route<dynamic>? previousRoute;

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
  }

  @override
  void didPop(
      Route<dynamic> route,
      Route<dynamic>? previousRoute,
      ) {
    this.previousRoute = route;
    currentRoute = previousRoute;
    if (identical(route, _autoRoute)) _autoRoute = null;
    _leaveIfReady();
    _refreshShortcut();
  }

  @override
  void didRemove(
      Route<dynamic> route,
      Route<dynamic>? previousRoute,
      ) {
    this.previousRoute = previousRoute;
    currentRoute = previousRoute;
    if (identical(route, _autoRoute)) _autoRoute = null;
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

  bool _shortcutDismissed = false;
  bool _refreshQueued = false;

  /// Re-evaluates [shortcutVisible]. Deferred to a microtask: navigator callbacks can fire in
  /// the middle of a build, where notifying listeners would throw.
  void _refreshShortcut() {
    if (_refreshQueued) return;
    _refreshQueued = true;
    scheduleMicrotask(() {
      _refreshQueued = false;
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