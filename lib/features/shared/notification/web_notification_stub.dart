// lib/features/shared/notification/web_notification_stub.dart
//
// No-op stub used on mobile/desktop builds. The real implementation
// (web_notification_web.dart) is swapped in only for web builds via the
// conditional import in notification_service.dart. This file exists purely
// so the import resolves and compiles on every platform.

void showWebNotification(String? title, String? body) {
  // Intentionally empty — mobile/desktop use flutter_local_notifications
  // instead (see NotificationService._onForegroundMessage).
}

/// Web only: pushes relayed by the service worker (see web_notification_web.dart).
void listenServiceWorkerMessages(void Function(Map<String, dynamic> data) onData) {
  // Intentionally empty — there is no service worker outside the browser.
}
