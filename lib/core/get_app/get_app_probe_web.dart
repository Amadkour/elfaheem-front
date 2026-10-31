// Web: reads the browser (user agent, touch points, display mode, native bridges) for the "Get the app" banner.
// The decisions themselves are the pure functions in get_app_rules.dart.
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'get_app_rules.dart';

/// The browser this page runs in.
GetAppEnv probeGetAppEnv() {
  var ua = '';
  var touch = 0;
  try {
    ua = web.window.navigator.userAgent;
    touch = web.window.navigator.maxTouchPoints;
  } catch (_) {}
  return GetAppEnv(
    isWeb: true,
    os: detectGetAppOs(ua, maxTouchPoints: touch),
    standalone: _standalone(),
    embedded: looksLikeInAppWebView(ua) || _nativeBridge(),
  );
}

/// The absolute URL of a file published next to index.html (honours `<base href>`).
String? getAppSiteFile(String name) {
  try {
    return Uri.parse(web.document.baseURI).resolve(name).toString();
  } catch (_) {
    return null;
  }
}

/// Installed to the home screen / as a desktop app (PWA), on Chrome, Edge, Firefox and iOS Safari.
bool _standalone() {
  try {
    for (final mode in const ['standalone', 'minimal-ui', 'window-controls-overlay']) {
      if (web.window.matchMedia('(display-mode: $mode)').matches) return true;
    }
  } catch (_) {}
  try {
    final v = web.window.navigator.getProperty<JSAny?>('standalone'.toJS);
    if (v != null && v.isA<JSBoolean>() && (v as JSBoolean).toDart) return true;
  } catch (_) {}
  return false;
}

/// The JavaScript bridges native wrappers inject (flutter_inappwebview, React Native).
bool _nativeBridge() {
  try {
    final w = web.window as JSObject;
    return w.has('flutter_inappwebview') || w.has('ReactNativeWebView');
  } catch (_) {
    return false;
  }
}
