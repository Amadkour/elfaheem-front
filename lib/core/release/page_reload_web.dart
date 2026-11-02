// Web: reloads the page, so the tab picks up the newly published build (core/release/web_release_watch.dart).
import 'package:web/web.dart' as web;

/// Reloads the browser page.
void reloadPage() {
  try {
    web.window.location.reload();
  } catch (_) {}
}
