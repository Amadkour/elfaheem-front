// lib/features/messaging/notification/web_notification_web.dart
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
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:web/web.dart' as web;

import 'package:flutter_education_app/utils/widget/app_navigator.dart';

void showWebNotification(String? title, String? body) {
  showBrowserNotification(title, body, const <String, dynamic>{});
}

/// Shows a foreground push as a browser `Notification` (a tap focuses this tab and opens the push's target
/// through [AppNavigator.openFromPush] with [data]). Returns true when the notification is on screen, so the
/// caller can skip its in-app toast; false when permission is denied / not yet granted (it is requested then,
/// and the popup shown once granted) or the browser refused (Android Chrome only allows notifications from a
/// service worker, the constructor throws there) — the caller keeps its toast in those cases.
bool showBrowserNotification(String? title, String? body, Map<String, dynamic> data) {
  final notifTitle = (title == null || title.isEmpty) ? 'NextBrain' : title;
  final notifBody = body ?? '';
  final payload = Map<String, dynamic>.from(data);

  final permission = web.Notification.permission;

  if (permission == 'granted') {
    return _display(notifTitle, notifBody, payload);
  } else if (permission != 'denied') {
    // Not yet asked (or 'default') — ask now, then show if granted.
    web.Notification.requestPermission().toDart.then((result) {
      if (result.toDart == 'granted') {
        _display(notifTitle, notifBody, payload);
      } else {
        debugPrint('[FCM][web] Notification permission not granted '
            '(${result.toDart}) — skipping popup, message was still logged '
            'above.');
      }
    });
  } else {
    debugPrint('[FCM][web] Notification permission denied by user — '
        'skipping popup, message was still logged above.');
  }
  return false;
}

bool _display(String title, String body, Map<String, dynamic> data) {
  try {
    final options = web.NotificationOptions(body: body, icon: '/icons/Icon-192.png');
    final tag = '${data['id'] ?? data['target_id'] ?? ''}';
    if (tag.isNotEmpty) options.tag = '${data['type'] ?? data['module'] ?? 'push'}-$tag'; // collapses a repeat
    final n = web.Notification(title, options);
    n.onclick = ((web.Event _) {
      try {
        web.window.focus();
        n.close();
      } catch (_) {}
      AppNavigator.openFromPush(data);
    }).toJS;
    return true;
  } catch (e) {
    debugPrint('[FCM][web] Failed to display browser notification: $e');
    return false;
  }
}

/// A push that reached web/firebase-messaging-sw.js while this tab was hidden (FCM's onMessage fires only in
/// the focused tab) arrives here as `{source: "fcm", data: {...}}`; [onData] gets the push's data map.
void listenServiceWorkerMessages(void Function(Map<String, dynamic> data) onData) {
  try {
    final container = web.window.navigator.serviceWorker;
    container.addEventListener(
      'message',
      ((web.MessageEvent event) {
        try {
          final raw = event.data?.dartify();
          if (raw is! Map || '${raw['source']}' != 'fcm') return;
          final data = raw['data'];
          if (data is! Map) return;
          onData({for (final e in data.entries) '${e.key}': e.value});
        } catch (e) {
          debugPrint('[FCM][web] service worker message ignored: $e');
        }
      }).toJS,
    );
  } catch (e) {
    debugPrint('[FCM][web] service worker messages unavailable: $e');
  }
}
