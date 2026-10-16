import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_education_app/core/offline/app_connectivity.dart';
import 'package:flutter_education_app/core/offline/offline_video_service.dart';
import 'package:flutter_education_app/features/student/models.dart';
import 'package:flutter_education_app/utils/live_events.dart';

import '../features/shared/attendance/attendance_offline_sync.dart';

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
  }

  @override
  void didPop(
      Route<dynamic> route,
      Route<dynamic>? previousRoute,
      ) {
    this.previousRoute = route;
    currentRoute = previousRoute;
  }

  @override
  void didRemove(
      Route<dynamic> route,
      Route<dynamic>? previousRoute,
      ) {
    this.previousRoute = previousRoute;
    currentRoute = previousRoute;
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

  /// Screens that are only landing pages: going offline there means "nothing useful to do",
  /// so the user is taken to the Downloads page. Every OTHER screen is left alone — above all
  /// '/course-detail', where a student may be checking in through a classmate while offline.
  static const _landingRoutes = {'/home', '/dashboard'};

  bool _bound = false;
  bool _openedDownloadsAutomatically = false;

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
    final hasDownloads = OfflineVideoService.instance.downloadedIds.value.isNotEmpty;
    if (hasDownloads && _landingRoutes.contains(currentRouteName)) {
      _openedDownloadsAutomatically = true;
      nav.pushNamed('/downloads');
    }
  }

  /// Offline -> online.
  void _switchToOnline() {
    // 1) Whatever was stored while offline is settled now (idempotent re-send of attendance
    //    requests, refresh of the cached attendance windows).
    AttendanceOfflineSync.instance.onReconnect();

    // 2) Leave the Downloads page only if WE opened it (never yank a user who went there).
    if (_openedDownloadsAutomatically && currentRouteName == '/downloads') {
      navigator?.maybePop();
    }
    _openedDownloadsAutomatically = false;
  }
}

final topRouteObserver = TopRouteObserver();