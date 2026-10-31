// Web: translation.json keeps the same URL on every build, so a browser may answer it from its HTTP cache (the
// server sends no Cache-Control for /assets/) while main.dart.js is new — every key added since then is shown raw.
// `cache: 'no-cache'` makes the browser revalidate it (a 304 when unchanged, so it costs one round trip).
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:web/web.dart' as web;

/// The text of translation.json fetched past the browser cache; null = use the bundled asset.
Future<String?> fetchFreshTranslations() async {
  try {
    final url = ui_web.assetManager.getAssetUrl('assets/translation.json');
    final res = await web.window.fetch(url.toJS, web.RequestInit(cache: 'no-cache')).toDart;
    if (!res.ok) return null;
    return (await res.text().toDart).toDart;
  } catch (_) {
    return null;
  }
}
