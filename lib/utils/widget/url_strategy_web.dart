// Web half of `url_strategy.dart`.
//
// The app uses the PATH url strategy: `https://alfheemacademy.com/live/<token>` and `/c/12?ref=5` are real paths
// (Firebase Hosting rewrites `**` to /index.html, `web/index.html` keeps `<base href="$FLUTTER_BASE_HREF">`).
// Older links still carry the route in the hash (`/#/live/x`): main.dart reads it (legacyHashRoute) and calls
// [replaceBrowserUrl] so the address bar shows the clean path without a reload.
import 'dart:async';
import 'dart:ui_web' as ui_web;

import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:web/web.dart' as web;

void configureUrlStrategy() => usePathUrlStrategy();

/// `history.replaceState` to [url] — no navigation, no reload.
void replaceBrowserUrl(String url) {
  try {
    web.window.history.replaceState(null, '', url);
  } catch (_) {}
}

/// `history.go(delta)` through the engine's url strategy: true once the browser has moved (its popstate), false
/// after [timeout] when there was nowhere to go (no popstate comes then). The engine's history sees the popstate as
/// usual (lib/core/routing/web_history.dart).
Future<bool> browserGo(int delta, {Duration timeout = const Duration(milliseconds: 700)}) async {
  final strategy = ui_web.urlStrategy;
  if (strategy == null || delta == 0) return false;
  try {
    var moved = true;
    await strategy.go(delta).timeout(timeout, onTimeout: () => moved = false);
    return moved;
  } catch (_) {
    return false;
  }
}

/// A full reload of the page (a part of the app that is gone from the server after a deploy: the new build loads).
void reloadPage() {
  try {
    web.window.location.reload();
  } catch (_) {}
}
