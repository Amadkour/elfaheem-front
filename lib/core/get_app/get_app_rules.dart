// lib/core/get_app/get_app_rules.dart — the pure rules behind the web build's "Get the app" banner and its
// settings row (no browser, no Flutter: unit-tested in test/ui/get_app_test.dart).
//
//   detectGetAppOs(userAgent, maxTouchPoints:)   which store / installer fits the browser's device
//   looksLikeInAppWebView(userAgent)             a native wrapper / in-app browser (Facebook, Instagram, WKWebView, …)
//   parseGetAppLinks(json)                       web/app_links.json → one https link per platform (others dropped)
//   shouldShowGetAppBanner(...)                  web only, not installed / embedded, a link exists, not dismissed
//   routeAllowsGetAppBanner(name)                only on the role homes (never login, live room, player, exam)
library;

/// The device family the store link is picked for.
enum GetAppOs { android, ios, ipados, windows, macos, linux, other }

/// How long a dismissed banner stays away.
const Duration kGetAppSnooze = Duration(days: 21);

/// The pages the banner may sit above: the role homes. Everything else (sign-in, the video player, an exam
/// sitting, pages pushed inside a tab, dialogs) has another route name or none.
const Set<String> kGetAppBannerRoutes = {
  '/home',
  '/dashboard',
  '/teacher_dashboard',
  '/admin_dashboard',
  '/parent_dashboard',
  '/org_dashboard',
  '/org_member',
};

bool routeAllowsGetAppBanner(String? routeName) =>
    routeName != null && kGetAppBannerRoutes.contains(routeName);

final RegExp _chromeOs = RegExp(r'\bcros\b');

/// The device behind a browser [userAgent]. iPadOS 13+ Safari asks for desktop pages and reports a Mac, so a
/// "Macintosh" with more than one touch point ([maxTouchPoints], `navigator.maxTouchPoints`) is an iPad. Android is
/// checked before Linux (every Android UA says "Linux; Android"). TVs, consoles, ChromeOS and feature phones are
/// [GetAppOs.other]: no link fits them.
GetAppOs detectGetAppOs(String userAgent, {int maxTouchPoints = 0}) {
  final ua = userAgent.toLowerCase();
  if (ua.trim().isEmpty) return GetAppOs.other;
  const notAComputer = [
    'windows phone', 'iemobile', 'xbox', 'playstation', 'nintendo', 'smart-tv', 'smarttv', 'tizen', 'web0s',
    'webos', 'kaios', 'crkey', 'aft', // aft = Fire TV sticks ("AFTMM")
  ];
  for (final m in notAComputer) {
    if (m == 'aft' ? RegExp(r'\baft[a-z]').hasMatch(ua) : ua.contains(m)) return GetAppOs.other;
  }
  if (ua.contains('android')) return GetAppOs.android;
  if (ua.contains('ipad')) return GetAppOs.ipados;
  if (ua.contains('iphone') || ua.contains('ipod')) return GetAppOs.ios;
  if (_chromeOs.hasMatch(ua)) return GetAppOs.other;
  if (ua.contains('macintosh') || ua.contains('mac os x')) {
    return maxTouchPoints > 1 ? GetAppOs.ipados : GetAppOs.macos;
  }
  if (ua.contains('windows')) return GetAppOs.windows;
  if (ua.contains('linux') || ua.contains('x11')) return GetAppOs.linux;
  return GetAppOs.other;
}

/// True for a page shown inside a native app rather than a browser: Android WebView ("; wv)"), an Apple WKWebView
/// (WebKit without "Safari/"; Safari and Chrome / Firefox / Edge on iOS all keep it), and the common in-app browsers.
bool looksLikeInAppWebView(String userAgent) {
  final ua = userAgent.toLowerCase();
  if (ua.contains('; wv)') || ua.contains(' wv)')) return true;
  const inApp = ['fban/', 'fbav/', 'fb_iab', 'instagram', 'micromessenger', 'line/', 'snapchat', 'bytedancewebview',
    'musical_ly', 'twitterandroid', 'gsa/'];
  for (final m in inApp) {
    if (ua.contains(m)) return true;
  }
  final apple = ua.contains('iphone') || ua.contains('ipad') || ua.contains('ipod') || ua.contains('macintosh');
  return apple && ua.contains('applewebkit') && !ua.contains('safari/');
}

/// The config keys, one per platform (iPadOS uses the App Store link of `ios`).
const Map<GetAppOs, String> kGetAppLinkKeys = {
  GetAppOs.android: 'android',
  GetAppOs.ios: 'ios',
  GetAppOs.windows: 'windows',
  GetAppOs.macos: 'macos',
  GetAppOs.linux: 'linux',
};

/// One store / installer link per platform; a platform without a link has none (never a guess).
class GetAppLinks {
  const GetAppLinks(this.byOs);

  static const GetAppLinks none = GetAppLinks({});

  final Map<GetAppOs, String> byOs;

  String? linkFor(GetAppOs os) => switch (os) {
        GetAppOs.ipados => byOs[GetAppOs.ios],
        GetAppOs.other => null,
        _ => byOs[os],
      };

  bool get isEmpty => byOs.isEmpty;
}

/// Reads `{"android": "https://…", "ios": "", …}`. Only absolute https URLs with a host are kept; an empty value,
/// another scheme, a non-string or an unknown key is ignored, and anything that is not a map gives [GetAppLinks.none].
GetAppLinks parseGetAppLinks(Object? json) {
  if (json is! Map) return GetAppLinks.none;
  final out = <GetAppOs, String>{};
  kGetAppLinkKeys.forEach((os, key) {
    final v = json[key];
    if (v is! String) return;
    final s = v.trim();
    final uri = Uri.tryParse(s);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return;
    out[os] = s;
  });
  return GetAppLinks(out);
}

/// What the running app knows about where it runs.
class GetAppEnv {
  const GetAppEnv({
    required this.isWeb,
    this.os = GetAppOs.other,
    this.standalone = false,
    this.embedded = false,
  });

  /// The native app (or a test): nothing to offer.
  static const GetAppEnv native = GetAppEnv(isWeb: false);

  final bool isWeb;
  final GetAppOs os;

  /// Installed as a PWA / added to the home screen (display-mode standalone, navigator.standalone).
  final bool standalone;

  /// Inside a native wrapper / in-app browser.
  final bool embedded;
}

/// The settings row: web, in a real browser tab, and a link for this device.
bool getAppEntryAvailable(GetAppEnv env, GetAppLinks links) =>
    env.isWeb && !env.standalone && !env.embedded && links.linkFor(env.os) != null;

/// The banner: everything the row needs, and not dismissed in the last [snooze]. A dismissal stamped more than a
/// day in the future (the clock was moved back) is ignored rather than hiding the banner for months.
bool shouldShowGetAppBanner({
  required GetAppEnv env,
  required GetAppLinks links,
  required DateTime now,
  DateTime? dismissedAt,
  Duration snooze = kGetAppSnooze,
}) {
  if (!getAppEntryAvailable(env, links)) return false;
  if (dismissedAt == null) return true;
  if (dismissedAt.isAfter(now.add(const Duration(days: 1)))) return true;
  return now.difference(dismissedAt) >= snooze;
}
