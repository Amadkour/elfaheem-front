// Web: reads the browser (user agent, touch points, display mode, native bridges, the install prompt kept by
// web/index.html's `nbPwa` script) for the "Get the app" banner. The decisions are the pure functions in
// get_app_rules.dart.
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
    embedded: looksLikeAndroidWebView(ua) || _nativeBridge(),
    inAppBrowser: looksLikeInAppWebView(ua),
    iosSafari: isIosSafari(ua, maxTouchPoints: touch),
    macSafari: isMacSafari(ua, maxTouchPoints: touch),
    pwaInstallable: _pwaDeferred(),
  );
}

/// The absolute URL of a file published at the site root (`/releases/…`). The web app itself lives under its
/// `<base href>` (`/app/`, D-165), so the path is resolved from the origin's root, not from the base.
String? getAppSiteFile(String path) {
  try {
    return Uri.parse(web.document.baseURI).resolve('/${path.startsWith('/') ? path.substring(1) : path}').toString();
  } catch (_) {
    return null;
  }
}

JSObject? _nbPwa() {
  try {
    final v = (web.window as JSObject).getProperty<JSAny?>('nbPwa'.toJS);
    return v != null && v.isA<JSObject>() ? v as JSObject : null;
  } catch (_) {
    return null;
  }
}

bool _pwaDeferred() {
  final p = _nbPwa();
  if (p == null) return false;
  try {
    final d = p.getProperty<JSAny?>('deferred'.toJS);
    return d != null && !d.isUndefinedOrNull;
  } catch (_) {
    return false;
  }
}

void listenPwaInstallable(void Function(bool installable) onChange) {
  try {
    web.window.addEventListener('nb-pwa-installable', ((web.Event _) => onChange(true)).toJS);
    web.window.addEventListener('nb-pwa-installed', ((web.Event _) => onChange(false)).toJS);
  } catch (_) {}
}

Future<String> promptPwaInstall() async {
  try {
    final fn = (web.window as JSObject).getProperty<JSAny?>('nbPwaPrompt'.toJS);
    if (fn == null || !fn.isA<JSFunction>()) return 'unavailable';
    final r = (fn as JSFunction).callAsFunction();
    if (r == null || !r.isA<JSPromise>()) return 'unavailable';
    final out = await (r as JSPromise<JSAny?>).toDart;
    return out != null && out.isA<JSString>() ? (out as JSString).toDart : 'unavailable';
  } catch (_) {
    return 'unavailable';
  }
}

Future<String?> probeArchHint(GetAppOs os) async {
  try {
    final data = web.window.navigator.getProperty<JSAny?>('userAgentData'.toJS);
    if (data == null || !data.isA<JSObject>()) return null;
    final hints = ['architecture'.toJS, 'bitness'.toJS].toJS;
    final p = (data as JSObject).callMethod<JSPromise<JSObject>>('getHighEntropyValues'.toJS, hints);
    final v = await p.toDart.timeout(const Duration(seconds: 2));
    String? s(String k) {
      final x = v.getProperty<JSAny?>(k.toJS);
      return x != null && x.isA<JSString>() ? (x as JSString).toDart : null;
    }

    return archFromClientHints(os, s('architecture'), s('bitness'));
  } catch (_) {
    return null;
  }
}

String currentPageUrl() {
  try {
    return web.window.location.href;
  } catch (_) {
    return '';
  }
}

String webNotificationPermission() {
  try {
    if (!(web.window as JSObject).has('Notification')) return 'unsupported';
    return web.Notification.permission;
  } catch (_) {
    return 'unsupported';
  }
}

Future<String> requestWebNotificationPermission() async {
  try {
    if (!(web.window as JSObject).has('Notification')) return 'unsupported';
    // called synchronously from the tap, so Safari still sees the user gesture
    final r = await web.Notification.requestPermission().toDart;
    return r.toDart;
  } catch (_) {
    return 'unsupported';
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
