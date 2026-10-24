// Web half of `url_strategy.dart`.
//
// The app uses the PATH url strategy: `https://nextbrain.site/live/<token>` and `/c/12?ref=5` are real paths
// (Firebase Hosting rewrites `**` to /index.html, `web/index.html` keeps `<base href="$FLUTTER_BASE_HREF">`).
// Older links still carry the route in the hash (`/#/live/x`): main.dart reads it (legacyHashRoute) and calls
// [replaceBrowserUrl] so the address bar shows the clean path without a reload.
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:web/web.dart' as web;

void configureUrlStrategy() => usePathUrlStrategy();

/// `history.replaceState` to [url] — no navigation, no reload.
void replaceBrowserUrl(String url) {
  try {
    web.window.history.replaceState(null, '', url);
  } catch (_) {}
}
