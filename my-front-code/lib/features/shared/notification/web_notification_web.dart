// lib/features/shared/notification/web_notification_web.dart
//
// Real web implementation — only compiled into web builds (see the
// conditional import in notification_service.dart).
//
// WHY THIS FILE EXISTS:
//   FCM's onMessage (foreground) does NOT show a system notification by
//   itself on any platform, web included — the app is expected to display
//   it. On mobile we use flutter_local_notifications; that package has no
//   web support, so on web we call the browser's native Notification API
//   directly instead.
//
// NOTE ON APIs USED:
//   dart:html and dart:js_util are removed on recent Dart SDKs (this
//   project targets Dart >=3.10.0). This file uses their replacements:
//   package:web (typed DOM bindings) + dart:js_interop (JS interop
//   primitives). Requires `web: ^1.1.0` in pubspec.yaml.

import 'dart:js_interop';
import 'package:web/web.dart' as web;

void showWebNotification(String? title, String? body) {
  final notifTitle = (title == null || title.isEmpty) ? 'ElFaheem' : title;
  final notifBody = body ?? '';

  final permission = web.Notification.permission;

  if (permission == 'granted') {
    _display(notifTitle, notifBody);
  } else if (permission != 'denied') {
    // Not yet asked (or 'default') — ask now, then show if granted.
    web.Notification.requestPermission().toDart.then((result) {
      if (result.toDart == 'granted') {
        _display(notifTitle, notifBody);
      } else {
        print('[FCM][web] Notification permission not granted '
            '(${result.toDart}) — skipping popup, message was still logged '
            'above.');
      }
    });
  } else {
    print('[FCM][web] Notification permission denied by user — '
        'skipping popup, message was still logged above.');
  }
}

void _display(String title, String body) {
  try {
    web.Notification(
      title,
      web.NotificationOptions(body: body, icon: '/icons/Icon-192.png'),
    );
  } catch (e) {
    print('[FCM][web] Failed to display browser notification: $e');
  }
}