// lib/features/notification/notification_service.dart
import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_education_app/utils/helpers.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../../../core/api_client.dart';
import '../../../main.dart';

// ── Background handler — MUST be top-level function ──────────────────────────
// Only registered on mobile (see init()), but must stay top-level.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  print('Background message: ${message.messageId}');
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
  Future<void> init() async {
    tz.initializeTimeZones();

    // BUG 1 FIX: onBackgroundMessage is NOT supported on web — throws
    // UnimplementedError and crashes init() entirely on web.
    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
    }

    // Local notifications plugin does NOT support web — skip it entirely
    if (!kIsWeb) {
      const androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      await _plugin.initialize(
        const InitializationSettings(
            android: androidSettings, iOS: iosSettings),
        onDidReceiveNotificationResponse: _onTap,
      );

      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
      await androidPlugin?.createNotificationChannel(_channel);
    }

    await _fcm.requestPermission(alert: true, badge: true, sound: true);

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
        data: {
          'token': token,
          'device_type': _deviceType(),
        },
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
        body: {
          'token': token,
          'device_type': _deviceType(),
        },
      );
      print('[FCM] Token registered with backend ✓');
    } catch (e) {
      print('[FCM] registerTokenWithBackend failed: $e');
    }
  }

  // ── Foreground message handler ────────────────────────────────────────────
  // BUG 3 FIX: _plugin.show() is not supported on web. onMessage fires on
  // web too, so without this guard it crashes every time a push arrives.
  Future<void> _onForegroundMessage(RemoteMessage message) async {
    print('[FCM] Foreground message on web:');
    final notification = message.notification;
    if (notification == null) return;

    if (kIsWeb) {
      // Browser shows the notification natively via the service worker.
      // Nothing to do here. Optionally show an in-app banner instead.
      print('[FCM] Foreground message on web: ${notification.title}');
      Helpers.showMessage(notification.body??'');
      return;
    }

    await _plugin.show(
      message.hashCode,
      notification.title,
      notification.body,
      _notifDetails,
    );
  }

  // ── Tap handlers ──────────────────────────────────────────────────────────
  // BUG 4 FIX: navigation was commented out — uncommented now that
  // navigatorKey is wired correctly in main.dart (navigatorKey: not key:).
  void _onNotificationTap(RemoteMessage message) {
    navigatorKey.currentState?.pushNamed('/notifications');
  }

  void _onTap(NotificationResponse response) {
    navigatorKey.currentState?.pushNamed('/notifications');
  }

  // ── Manual local notification (in-app use) ───────────────────────────────
  // BUG 3 FIX (cont.): guard all _plugin calls with !kIsWeb.
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {
    if (kIsWeb) return;
    await _plugin.show(id, title, body, _notifDetails);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<String?> getToken() => _fcm.getToken();

  Future<void> cancel(int id) async {
    if (kIsWeb) return;
    await _plugin.cancel(id);
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