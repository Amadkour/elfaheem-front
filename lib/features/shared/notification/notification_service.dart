// lib/features/notification/notification_service.dart
import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_education_app/utils/helpers.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;

import '../../../core/api_client.dart';
import '../../../main.dart';
import '../../../utils/top_route_observer.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import '../../../utils/widget/app_navigator.dart';
import 'admin_message_dialogs.dart';

// TODO: adjust this path if CourseDetailProvider actually lives elsewhere.
import 'package:flutter_education_app/features/student/courses/details/course_detail_provider.dart';

// import 'web_notification_stub.dart'
// if (dart.library.js_interop) 'web_notification_web.dart';

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
  print(
    '[FCM][background] id=${message.messageId} '
    'title=${message.notification?.title} '
    'body=${message.notification?.body} '
    'data=${message.data}',
  );
}

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;

  ApiClient? _api;

  // ── Android channel ───────────────────────────────────────────────────────
  static const _channel = AndroidNotificationChannel(
    'elfaheem_main',
    'ElFaheem Notifications',
    description: 'Course updates, payments, and reminders',
    importance: Importance.max,
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
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      await _plugin.initialize(
        settings: const InitializationSettings(
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

    final data = message.data;
    print(data);
    if (data['type'] == 'session_started' || data['type'] == 'session_ended') {
      _refreshCourseDetailIfActive(data['course_id'] as String?);
    }
    // Admin broadcast shown as a dialog: show it now instead of waiting for the next app start.
    if (data['type'] == 'admin_message' &&
        (data['display'] == 'dialog' || data['display'] == 'dialog_action')) {
      AdminMessageDialogs.checkPending();
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
      Helpers.showMessage(notification.body ?? '');
      return;
    }
    await _plugin.show(
      id: message.hashCode,
      title: notification.title,
      body: notification.body,
      notificationDetails: _notifDetails,
      payload: jsonEncode(message.data), // lets a tap on the local notification open the right screen
    );
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
    } on Exception catch (e) {
      context.read<CourseDetailProvider>().fetchSessions(activeCourseId);
    }
  }

  // ── Tap handlers ──────────────────────────────────────────────────────────
  // Push tap (app in background / terminated): open the course / module the push points to.
  void _onNotificationTap(RemoteMessage message) {
    AppNavigator.openFromPush(Map<String, dynamic>.from(message.data));
  }

  // Tap on the local notification we displayed for a foreground push.
  void _onTap(NotificationResponse response) {
    try {
      final p = response.payload;
      if (p != null && p.isNotEmpty) {
        AppNavigator.openFromPush(Map<String, dynamic>.from(jsonDecode(p) as Map));
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
}
