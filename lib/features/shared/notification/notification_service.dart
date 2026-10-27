// lib/features/notification/notification_service.dart
import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/utils/helpers.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;

import '../../../config/theme/theme_config_provider.dart';
import '../../../core/api_client.dart';
import '../../../core/live/live_events_client.dart';
import '../../../main.dart';
import '../../../utils/live_events.dart';
import '../../../utils/top_route_observer.dart';
import '../live/live_room.dart' show LiveLobbyEvents;
import 'package:provider/provider.dart';
import 'dart:convert';
import '../../../utils/widget/app_navigator.dart';
import 'admin_message_dialogs.dart';
// Attendance live nudges (silent pushes). Adjust the path if your attendance folder differs.
import '../attendance/attendance_push.dart';

// TODO: adjust this path if CourseDetailProvider actually lives elsewhere.
import 'package:flutter_education_app/features/student/courses/details/course_detail_provider.dart';

import 'web_notification_stub.dart'
    if (dart.library.js_interop) 'web_notification_web.dart';

// ── Background handler — MUST be top-level function ──────────────────────────
// Only registered on mobile (see init()), but must stay top-level.
//
// NOTE: this handler NEVER fires on web. Web background messages (tab not
// focused / closed) are handled entirely by web/firebase-messaging-sw.js —
// that's a separate JS file, not this Dart code — and that's where you'll
// see the console.log for background messages on web (check the browser
// DevTools console while the service worker is active / in the "Application"
// tab's Service Workers section, since a backgrounded tab's own console may
// be throttled).
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  // print(
  //   '[FCM][background] id=${message.messageId} '
  //   'title=${message.notification?.title} '
  //   'body=${message.notification?.body} '
  //   'data=${message.data}',
  // );
}

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
  FlutterLocalNotificationsPlugin();
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;

  ApiClient? _api;

  /// A tapped push that could not be opened yet (app just started: no Navigator yet, or the user is
  /// not logged in). `main.dart`'s `_Guard` calls [consumePendingPush] once the first screen is up.
  Map<String, dynamic>? _pendingPush;

  // ── Android channel ───────────────────────────────────────────────────────
  static const _channel = AndroidNotificationChannel(
    'elfaheem_main',
    'ElFaheem Notifications',
    description: 'Course updates, payments, and reminders',
    importance: Importance.max,
  );

  /// A push with `action: generate` (a term without a timetable, back: schedule_auto) gets one more button that
  /// runs the one-tap generation without opening the app first (Android action · iOS category).
  static const generateActionId = 'org_timetable_generate';
  static const generateCategoryId = 'org_timetable';

  static NotificationDetails _withGenerateAction() => NotificationDetails(
        android: AndroidNotificationDetails(
          'elfaheem_main',
          'ElFaheem Notifications',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          actions: [AndroidNotificationAction(generateActionId, AppConfig.lang == 'ar' ? 'ولّد الجدول الآن' : 'Generate now', showsUserInterface: true)],
        ),
        iOS: const DarwinNotificationDetails(presentAlert: true, presentBadge: true, presentSound: true, categoryIdentifier: generateCategoryId),
      );

  static const _notifDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'elfaheem_main',
      'ElFaheem Notifications',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    ),
  );

  // ── Init — call once in main() ────────────────────────────────────────────
  //
  // NOTE: a previous version of this file guarded against Flutter Web
  // hot-restart re-registering FCM listeners, using a flag stored on
  // `window`. That guard was REMOVED — it lives on `window`, which only
  // resets on a genuine full page reload, not on every `flutter run`. If the
  // same browser tab is reused across separate dev-server sessions (common,
  // since DWDS often reattaches to an already-open tab), the flag from the
  // first successful run stayed `true` forever, silently skipping
  // initialization on every later run — i.e. notifications stop firing
  // entirely until the tab is hard-refreshed. That failure mode is worse
  // than the problem it solved.
  //
  // Practical guidance instead: if you're stress-testing push notifications
  // during development and doing many Flutter Web hot restarts in the same
  // tab, do one full page refresh (Ctrl/Cmd+Shift+R) before triggering a
  // test push, to avoid any stacked listeners from that session. Real end
  // users only ever get one page load per session, so this never affects
  // them.
  Future<void> init() async {
    tz.initializeTimeZones();

    // BUG 1 FIX: onBackgroundMessage is NOT supported on web — throws
    // UnimplementedError and crashes init() entirely on web.
    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
    }

    // Local notifications plugin does NOT support web — skip it entirely
    if (!kIsWeb) {
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      final iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
        notificationCategories: [
          DarwinNotificationCategory(generateCategoryId, actions: [
            DarwinNotificationAction.plain(generateActionId, AppConfig.lang == 'ar' ? 'ولّد الجدول الآن' : 'Generate now', options: {DarwinNotificationActionOption.foreground}),
          ]),
        ],
      );
      await _plugin.initialize(
        settings: InitializationSettings(
          android: androidSettings,
          iOS: iosSettings,
        ),
        onDidReceiveNotificationResponse: _onTap,
      );

      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
      >();
      await androidPlugin?.requestNotificationsPermission();
      await androidPlugin?.createNotificationChannel(_channel);
    }

    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    print('[FCM] Permission status: ${settings.authorizationStatus}');

    // onMessage fires on all platforms — handler is web-safe (see below)
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    // Web: a push the service worker got while this tab was hidden is relayed as a window message.
    if (kIsWeb) listenServiceWorkerMessages(_onServiceWorkerData);

    // onMessageOpenedApp fires on mobile only; safe to register on web
    // (it simply never fires), but harmless.
    FirebaseMessaging.onMessageOpenedApp.listen(_onNotificationTap);

    final initial = await _fcm.getInitialMessage();
    if (initial != null) _onNotificationTap(initial);

    _fcm.onTokenRefresh.listen((newToken) {
      if (_api != null) _registerTokenWithBackend(_api!, newToken);
    });
  }

  // ── Called right after the user logs in ──────────────────────────────────
  Future<void> registerWithBackend(ApiClient api) async {
    try {
      _api = api;
      String? token;

      if (kIsWeb) {
        token = await _fcm.getToken(
          vapidKey:
          'BLpXoCZIPMtfWfU9Ftnl8NzJgx4wHo-ZY16GCZ01ZD5fvs12c8KcMpAYPQ30-0kWdTrZku8dVxc3Gxl0smubJJ0',
        );
      } else {
        token = await _fcm.getToken();
      }

      print('[FCM] Token: $token');

      if (token != null) {
        await _registerTokenWithBackend(api, token);
      }
    } catch (e) {
      print('[FCM] registerWithBackend error: $e');
    }
  }

  // ── Called on logout ─────────────────────────────────────────────────────
  Future<void> unregisterFromBackend(ApiClient api) async {
    final token = await _fcm.getToken();
    if (token == null) return;
    try {
      await api.dio.delete(
        '/api/v1/notifications/token',
        data: {'token': token, 'device_type': _deviceType()},
      );
      print('[FCM] Token unregistered from backend.');
    } catch (e) {
      print('[FCM] unregisterFromBackend failed: $e');
    } finally {
      _api = null;
    }
  }

  // ── Internal: POST token to backend ──────────────────────────────────────
  Future<void> _registerTokenWithBackend(ApiClient api, String token) async {
    try {
      await api.post(
        '/api/v1/notifications/token',
        body: {'token': token, 'device_type': _deviceType()},
      );
      print('[FCM] Token registered with backend ✓');
    } catch (e) {
      print('[FCM] registerTokenWithBackend failed: $e');
    }
  }

  // ── Foreground message handler ────────────────────────────────────────────
  // Fires on EVERY platform (including web) whenever a push arrives while
  // the app/tab is open and focused.
  Future<void> _onForegroundMessage(RemoteMessage message) async {
    // Always log first, on every platform, regardless of whether a
    // "notification" payload is present — this makes data-only messages
    // visible too.
    print(
      '[FCM][foreground] id=${message.messageId} '
          'title=${message.notification?.title} '
          'body=${message.notification?.body} '
          'data=${message.data}',
    );

    final data = Map<String, dynamic>.from(message.data);
    if (_handleSilent(data, visible: message.notification != null)) return;
    final liveType = data['type'] as String?;
    // The visible "new complaint / new transfer" notification also nudges the lists, then is
    // shown normally below.
    final nudged = LiveEvents.fromNotificationType(liveType);
    if (nudged != null) {
      LiveEvents.instance.emit(nudged, Map<String, dynamic>.from(data));
    }
    if (data['type'] == 'session_started' || data['type'] == 'session_ended') {
      _refreshCourseDetailIfActive(data['course_id'] as String?);
    }
    // Admin broadcast shown as a dialog: show it now instead of waiting for the next app start.
    if (data['type'] == 'admin_message' &&
        (data['display'] == 'dialog' || data['display'] == 'dialog_action')) {
      AdminMessageDialogs.checkPending();
      return; // the dialog IS the alert — do not also raise a system notification / toast for it
    }

    final notification = message.notification;
    if (notification == null) return;

    if (kIsWeb) {
      // BUG 3 FIX (web): flutter_local_notifications doesn't support web,
      // and the browser does NOT auto-display foreground pushes (only
      // background ones, via the service worker) — so we must trigger the
      // browser's native Notification popup ourselves here.
      // showWebNotification(notification.title, notification.body);

      // Keep the in-app toast too, as a fallback for browsers where the
      // user hasn't granted Notification permission.
      final title = notification.title;
      final body = notification.body ?? '';
      Helpers.showMessage(
        title != null && title.isNotEmpty && body.isNotEmpty
            ? '$title\n$body'
            : (body.isNotEmpty ? body : (title ?? '')),
      );
      return;
    }
    await _plugin.show(
      id: message.hashCode,
      title: notification.title,
      body: notification.body,
      notificationDetails: message.data['action'] == 'generate' ? _withGenerateAction() : _notifDetails,
      payload: jsonEncode(
        message.data,
      ), // lets a tap on the local notification open the right screen
    );
  }

  /// The silent (data-only) pushes, handled and never shown: the admin's disable list / theme, attendance
  /// nudges, a lobby join request, and the real-time events (Track D: `event` + `event_id` + fields, the same
  /// frames the SSE stream carries — LiveEventsClient drops a duplicate, LiveEvents delivers the rest). True when
  /// [data] was one of them; a push that also carries a visible notification ([visible]) is handled AND shown.
  bool _handleSilent(Map<String, dynamic> data, {bool visible = false}) {
    final type = data['type'] as String?;
    // Silent push: the admin changed the disable list → reload it, show nothing.
    if (type == 'disable_list_updated') {
      print('[FCM] disable_list_updated received → refreshing');
      _refreshDisableList();
      return true;
    }
    // Silent push: attendance opened / closed (student button) or a web session asks this phone
    // for the classroom location (teacher). Shows nothing.
    if (type == 'attendance_opened' ||
        type == 'attendance_closed' ||
        type == 'attendance_location_request') {
      AttendancePush.instance.handle(data);
      return true;
    }
    // Silent push: the admin changed the theme -> re-fetch it, repaint live, show nothing.
    if (type == 'theme_updated') {
      final target = data['platform'] as String?;
      if (target == null || target == _deviceType()) {
        print('[FCM] theme_updated received -> refreshing theme');
        _refreshTheme();
      }
      return true;
    }
    // Silent push: someone asks to join a live room the user hosts → the room's lobby refreshes at once
    // (live-rooms-spec §4). Shows nothing; the visible `live_lobby` notification is a separate push.
    if (type == LiveLobbyEvents.pushType) {
      LiveLobbyEvents.notify(data);
      return true;
    }
    // Real-time event (attention_changed, job_updated, lobby_updated, *_updated, …): same dedupe and bus as
    // the SSE stream, so a screen gets it once whichever channel was faster.
    final event = data['event'] as String?;
    if (event != null && event.isNotEmpty) {
      debugPrint('[FCM] event $event received -> live bus');
      LiveEventsClient.instance.ingest(event, data['event_id']?.toString(), data);
      return !visible;
    }
    // Older server: a complaint / manual transfer / payment / payout changed, sent as `type` → every open list
    // (and the dashboard badges) reloads by itself. Shows nothing.
    if (type != null && LiveEvents.silentTypes.contains(type)) {
      print('[FCM] $type received -> live refresh');
      LiveEventsClient.instance.ingest(type, data['event_id']?.toString(), data);
      return true;
    }
    return false;
  }

  /// web/firebase-messaging-sw.js relays a push it received while this tab was hidden (no onMessage then).
  void _onServiceWorkerData(Map<String, dynamic> data) {
    debugPrint('[FCM][sw] data=$data');
    _handleSilent(data);
  }

  // ── Live session push → refresh CourseDetailScreen if it's on screen ───────
  // A start_session/end_session push should update the session list live
  // instead of requiring the user to leave and re-enter CourseDetailScreen.
  // Only refreshes if that screen is actually the one currently on top of
  // the nav stack (via topRouteObserver, since navigatorKey.currentContext
  // alone can't tell us the active route — see top_route_observer.dart),
  // and if the push includes a course_id, only for that specific course.
  void _refreshCourseDetailIfActive(String? courseId) {
    if (!topRouteObserver.isCourseDetailActive) return;

    final activeCourseId = topRouteObserver.activeCourseId;
    if (courseId != null && activeCourseId != courseId) return;

    final context = navigatorKey.currentContext;
    if (context == null || activeCourseId == null) return;

    // NOTE: this assumes CourseDetailProvider is registered high enough to
    // be visible from navigatorKey's context (e.g. in the app-wide
    // MultiProvider in core/providers.dart). If it's instead created
    // locally inside CourseDetailScreen's own build method, this call will
    // throw a ProviderNotFoundException — in that case CourseDetailScreen
    // needs to expose its provider some other way (e.g. a static reference
    // set in initState/cleared in dispose).
    try {
      Provider.of<CourseDetailProvider>(
        context,
        listen: false,
      ).fetchSessions(activeCourseId);
    } catch (e) {
      // (the old fallback called the very same lookup again and re-threw)
      debugPrint(
        '[FCM] CourseDetailProvider not reachable from navigatorKey context: $e',
      );
    }
  }

  // ── Tap handlers ──────────────────────────────────────────────────────────
  // Push tap (app in background / terminated): open the course / module the push points to.
  void _onNotificationTap(RemoteMessage message) =>
      _openOrQueue(Map<String, dynamic>.from(message.data));

  /// Opens the push target now if the app can show it, otherwise remembers it for [consumePendingPush].
  /// (`getInitialMessage()` is read in main() BEFORE runApp — there is no Navigator and no logged-in
  /// user at that moment, so opening immediately silently lost every "tap while app was closed".)
  void _openOrQueue(Map<String, dynamic> data) {
    final ctx = navigatorKey.currentContext;
    final ready =
        ctx != null && ctx.mounted && ctx.read<MyAuthProvider>().isAuthenticated;
    if (!ready) {
      _pendingPush = data;
      return;
    }
    AppNavigator.openFromPush(data);
  }

  void consumePendingPush() {
    final data = _pendingPush;
    if (data == null) return;
    final ctx = navigatorKey.currentContext;
    if (ctx == null ||
        !ctx.mounted ||
        !ctx.read<MyAuthProvider>().isAuthenticated) {
      return;
    }
    _pendingPush = null;
    AppNavigator.openFromPush(data);
  }

  // Tap on the local notification we displayed for a foreground push.
  void _onTap(NotificationResponse response) {
    try {
      final p = response.payload;
      if (p != null && p.isNotEmpty) {
        final data = Map<String, dynamic>.from(jsonDecode(p) as Map);
        if (response.actionId == generateActionId) {
          // the button on the notification: generate now, then open the Timetable section (text = why it could not)
          AppNavigator.generateTermFromPush(data).then((text) {
            if (text != null && text.isNotEmpty) Helpers.showMessage(text);
          });
          return;
        }
        _openOrQueue(data);
        return;
      }
    } catch (_) {}
    navigatorKey.currentState?.pushNamed('/notifications');
  }

  // ── Manual local notification (in-app use) ───────────────────────────────
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {
    if (kIsWeb) {
      // showWebNotification(title, body);
      return;
    }
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: _notifDetails,
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<String?> getToken() => _fcm.getToken();

  Future<void> cancel(int id) async {
    if (kIsWeb) return;
    await _plugin.cancel(id: id);
  }

  Future<void> cancelAll() async {
    if (kIsWeb) return;
    await _plugin.cancelAll();
  }

  // BUG 2 FIX: dart:io Platform throws on web. Check kIsWeb first so
  // Platform.isAndroid / Platform.isIOS are never evaluated on web.
  String _deviceType() {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'unknown';
  }

  // Re-fetches the theme palette. Silent: no toast, no splash, no banner on failure.
  void _refreshTheme() {
    final ctx = navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    try {
      Provider.of<ThemeConfigProvider>(ctx, listen: false).silentRefresh();
    } catch (e) {
      print('[FCM] refreshTheme failed: $e');
    }
  }

  // Reloads the disable list from the server. Silent: no toast, no local notification.
  Future<void> _refreshDisableList() async {
    try {
      final platform = _deviceType(); // android | ios | web
      if (platform == 'unknown') return;
      final r = await ApiClient().get('/api/v1/disable-items/$platform');
      final items = ((r is Map ? r['items'] : null) as List? ?? const [])
          .map((e) => '$e')
          .toList();
      print('[FCM] disable list from server ($platform): $items');
      final changed = AppConfig.setDisableList(items);
      print('[FCM] disable list changed=$changed');
    } catch (e) {
      print('[FCM] refreshDisableList failed: $e');
    }
  }
}