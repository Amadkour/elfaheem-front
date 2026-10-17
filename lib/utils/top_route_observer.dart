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
    // The Downloads page WE opened because the phone went offline.
    if (_awaitingAutoRoute && route.settings.name == '/downloads') {
      _autoRoute = route;
      _awaitingAutoRoute = false;
    }
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
  }

  @override
  void didReplace({
    Route<dynamic>? newRoute,
    Route<dynamic>? oldRoute,
  }) {
    previousRoute = oldRoute;
    currentRoute = newRoute;
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
  //  offline  → from ANY screen go to the Downloads page (downloaded videos + the Attendance
  //             tab with the courses stored on this phone)
  //  online   → close that page again and land on whatever screen the user came from
  //
  // Only the page WE opened is ever closed automatically; a user who went to Downloads
  // on their own is never moved.

  /// Screens where an automatic jump makes no sense.
  static const _neverInterrupt = {'/login', '/register', '/splash', '/downloads'};

  bool _bound = false;
  bool _awaitingAutoRoute = false; // pushed, didPush not seen yet
  Route<dynamic>? _autoRoute; // the Downloads route we opened
  bool _leaveWhenTop = false; // back online, but something is open above Downloads

  /// True while the app has no usable connection (see [AppConnectivity]).
  bool get isOffline => !AppConnectivity.instance.isOnline;

  /// Call once at start-up (main.dart), after [AppConnectivity.init].
  void bindConnectivity() {
    if (_bound) return;
    _bound = true;
    AppConnectivity.instance.online.addListener(_onConnectivityChanged);
  }

  void _onConnectivityChanged() {
    if (isOffline) {
      _switchToOffline();
    } else {
      _switchToOnline();
    }
    // Providers / screens that want to reload themselves can listen for this.
    LiveEvents.instance.emit(
      LiveEvents.connectivity,
      {'online': '${!isOffline}'},
    );
  }

  /// Online -> offline.
  void _switchToOffline() {
    final nav = navigator;
    if (nav == null || kIsWeb) return;
    _leaveWhenTop = false;
    if (_autoRoute != null || _awaitingAutoRoute) return; // already there
    final name = currentRouteName;
    if (name != null && _neverInterrupt.contains(name)) return;
    final hasOffline = OfflineVideoService.instance.downloadedIds.value.isNotEmpty ||
        AttendanceStore.instance.hasCachedCourses;
    if (!hasOffline) return;
    _awaitingAutoRoute = true;
    nav.pushNamed('/downloads');
  }

  /// Offline -> online.
  void _switchToOnline() {
    // 1) Whatever was stored while offline is settled now (idempotent re-send of attendance
    //    requests, refresh of the cached attendance windows).
    AttendanceOfflineSync.instance.onReconnect();

    // 2) Close the Downloads page only if WE opened it.
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
}

final topRouteObserver = TopRouteObserver();
