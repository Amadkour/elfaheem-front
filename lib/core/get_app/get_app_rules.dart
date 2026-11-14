// lib/core/get_app/get_app_rules.dart — the pure rules behind the web build's "Get the app" banner, its sheet and its
// settings row (no browser, no Flutter: unit-tested in test/ui/get_app_test.dart).
//
//   detectGetAppOs(userAgent, maxTouchPoints:)   which build fits the browser's device (iPadOS-as-Mac handled)
//   looksLikeInAppWebView(userAgent)             a native wrapper / in-app browser (Facebook, Instagram, WKWebView, …)
//   isIosSafari / isMacSafari(userAgent)         the browsers that install a web app from their own menus
//   archFromClientHints(os, architecture, bitness)  the CPU, when Chromium's client hints say
//   getAppOfferFor(env, manifest)                what the banner offers here: a download, "Add to Home Screen",
//                                                "open in Safari", install the web app — or nothing
//   shouldShowGetAppBanner(...)                  an offer, not dismissed in the last 14 days
//   routeAllowsGetAppBanner(name)                only on the role homes (never login, live room, player, exam)
library;

import 'releases_manifest.dart';

export 'releases_manifest.dart';

/// The device family the build is picked for.
enum GetAppOs { android, ios, ipados, windows, macos, linux, other }

/// How long a dismissed banner stays away.
const Duration kGetAppSnooze = Duration(days: 14);

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
/// [GetAppOs.other]: no build fits them.
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

const List<String> _inAppMarkers = [
  'fban/', 'fbav/', 'fb_iab', 'instagram', 'micromessenger', 'line/', 'snapchat', 'bytedancewebview', 'musical_ly',
  'twitterandroid', 'gsa/', 'whatsapp', 'telegram',
];

/// True for a page shown inside an app rather than a browser: Android WebView ("; wv)"), an Apple WKWebView (WebKit
/// without "Safari/"; Safari and Chrome / Firefox / Edge on iOS all keep it), and the common in-app browsers.
bool looksLikeInAppWebView(String userAgent) {
  final ua = userAgent.toLowerCase();
  if (ua.contains('; wv)') || ua.contains(' wv)')) return true;
  for (final m in _inAppMarkers) {
    if (ua.contains(m)) return true;
  }
  final apple = ua.contains('iphone') || ua.contains('ipad') || ua.contains('ipod') || ua.contains('macintosh');
  return apple && ua.contains('applewebkit') && !ua.contains('safari/');
}

/// An Android WebView ("; wv)"): a native wrapper, where nothing is offered.
bool looksLikeAndroidWebView(String userAgent) {
  final ua = userAgent.toLowerCase();
  return ua.contains('; wv)') || ua.contains(' wv)');
}

const List<String> _otherAppleBrowsers = ['crios/', 'fxios/', 'edgios/', 'opios/', 'opt/', 'yabrowser', 'duckduckgo'];

/// Safari itself on an iPhone / iPad (iPadOS-as-Mac included): the browser whose Share menu has "Add to Home Screen"
/// on every iOS version we support. Chrome / Edge / Firefox on iOS and the in-app browsers are not.
bool isIosSafari(String userAgent, {int maxTouchPoints = 0}) {
  final os = detectGetAppOs(userAgent, maxTouchPoints: maxTouchPoints);
  if (os != GetAppOs.ios && os != GetAppOs.ipados) return false;
  final ua = userAgent.toLowerCase();
  if (!ua.contains('safari/') || looksLikeInAppWebView(userAgent)) return false;
  return !_otherAppleBrowsers.any(ua.contains);
}

/// Safari on a Mac (17+ has File → Add to Dock). Chrome / Edge / Firefox / Opera on a Mac are not.
bool isMacSafari(String userAgent, {int maxTouchPoints = 0}) {
  if (detectGetAppOs(userAgent, maxTouchPoints: maxTouchPoints) != GetAppOs.macos) return false;
  final ua = userAgent.toLowerCase();
  if (!ua.contains('safari/') || !ua.contains('version/')) return false;
  return !['chrome/', 'chromium/', 'edg/', 'firefox/', 'opr/'].any(ua.contains);
}

/// The manifest file arch for Chromium's `userAgentData` high-entropy values (`architecture` "arm" / "x86",
/// `bitness` "64" / "32"); null when unknown. Android Chrome usually reports nothing, and a 32-bit Chrome may run
/// on a 64-bit phone, so Android only trusts an explicit 64-bit arm.
String? archFromClientHints(GetAppOs os, String? architecture, String? bitness) {
  final a = (architecture ?? '').toLowerCase();
  final b = (bitness ?? '').trim();
  if (a.isEmpty) return null;
  switch (os) {
    case GetAppOs.android:
      return a == 'arm' && b == '64' ? 'arm64-v8a' : null;
    case GetAppOs.windows || GetAppOs.macos || GetAppOs.linux:
      if (a == 'arm' && b != '32') return 'arm64';
      if (a == 'x86' && b == '64') return 'x64';
      return null;
    default:
      return null;
  }
}

/// The manifest key for a device (`ipados` reads `ios`), or null.
String? releaseKeyFor(GetAppOs os) => switch (os) {
      GetAppOs.android => 'android',
      GetAppOs.ios || GetAppOs.ipados => 'ios',
      GetAppOs.windows => 'windows',
      GetAppOs.macos => 'macos',
      GetAppOs.linux => 'linux',
      GetAppOs.other => null,
    };

/// What the running app knows about where it runs.
class GetAppEnv {
  const GetAppEnv({
    required this.isWeb,
    this.os = GetAppOs.other,
    this.standalone = false,
    this.embedded = false,
    this.inAppBrowser = false,
    this.iosSafari = false,
    this.macSafari = false,
    this.pwaInstallable = false,
    this.archHint,
  });

  /// The native app (or a test): nothing to offer.
  static const GetAppEnv native = GetAppEnv(isWeb: false);

  final bool isWeb;
  final GetAppOs os;

  /// Installed as a PWA / added to the home screen (display-mode standalone, navigator.standalone).
  final bool standalone;

  /// Inside a native wrapper (Android WebView, a JavaScript bridge): nothing is offered at all.
  final bool embedded;

  /// An app's own browser (Instagram, Facebook, WhatsApp, an iOS WKWebView): on iPhone the banner says "open in Safari".
  final bool inAppBrowser;

  /// Safari on iPhone / iPad (Share → Add to Home Screen).
  final bool iosSafari;

  /// Safari on a Mac (File → Add to Dock).
  final bool macSafari;

  /// The browser offered to install the web app (Chromium's `beforeinstallprompt` arrived and was kept).
  final bool pwaInstallable;

  /// The manifest arch for this device's CPU, when known.
  final String? archHint;

  GetAppEnv copyWith({bool? pwaInstallable, String? archHint}) => GetAppEnv(
        isWeb: isWeb,
        os: os,
        standalone: standalone,
        embedded: embedded,
        inAppBrowser: inAppBrowser,
        iosSafari: iosSafari,
        macSafari: macSafari,
        pwaInstallable: pwaInstallable ?? this.pwaInstallable,
        archHint: archHint ?? this.archHint,
      );
}

/// What can be offered for one platform.
enum GetAppOfferKind {
  /// One file to download (APK, desktop package).
  download,

  /// iPhone / iPad in Safari: Share → Add to Home Screen.
  installIos,

  /// iPhone / iPad in another browser or an app's own browser: open this page in Safari first.
  openInSafari,

  /// A computer: install the web app (the browser's own prompt, or Safari's File → Add to Dock).
  installWeb,
}

class GetAppOffer {
  const GetAppOffer({required this.kind, required this.os, required this.release, this.file});

  final GetAppOfferKind kind;
  final GetAppOs os;
  final PlatformRelease release;

  /// The file to download ([GetAppOfferKind.download] only).
  final ReleaseFile? file;
}

/// What this browser is offered, from the manifest only (nothing hard-coded); null = nothing (the native app, an
/// installed web app, a wrapper, an unknown device, or nothing published for this platform).
GetAppOffer? getAppOfferFor(GetAppEnv env, ReleasesManifest manifest) {
  if (!env.isWeb || env.standalone || env.embedded) return null;
  final key = releaseKeyFor(env.os);
  if (key == null) return null;
  final r = manifest[key];
  if (r == null) return null;
  GetAppOffer? download() {
    final f = r.primaryFile(archHint: env.archHint);
    return f == null ? null : GetAppOffer(kind: GetAppOfferKind.download, os: env.os, release: r, file: f);
  }

  switch (env.os) {
    case GetAppOs.android:
      // an app's own browser often cannot hand an APK to the installer: nothing rather than a broken download
      return env.inAppBrowser ? null : download();
    case GetAppOs.ios || GetAppOs.ipados:
      if (!r.pwaFirst) {
        final d = download();
        if (d != null) return d;
      }
      if (!r.pwa) return null;
      return GetAppOffer(
        kind: env.iosSafari ? GetAppOfferKind.installIos : GetAppOfferKind.openInSafari,
        os: env.os,
        release: r,
      );
    case GetAppOs.windows || GetAppOs.macos || GetAppOs.linux:
      if (env.inAppBrowser) return null;
      final canInstallWeb = r.pwa && (env.pwaInstallable || (env.os == GetAppOs.macos && env.macSafari));
      if (r.pwaFirst && canInstallWeb) return GetAppOffer(kind: GetAppOfferKind.installWeb, os: env.os, release: r);
      // the web app first but this browser cannot install it (Firefox): the file, when there is one
      return download() ??
          (canInstallWeb ? GetAppOffer(kind: GetAppOfferKind.installWeb, os: env.os, release: r) : null);
    case GetAppOs.other:
      return null;
  }
}

/// The settings row: a real browser tab (not the native app, an installed web app or a wrapper) and something
/// published for any platform. It opens the sheet with every platform.
bool getAppEntryAvailable(GetAppEnv env, ReleasesManifest manifest) =>
    env.isWeb && !env.standalone && !env.embedded && !manifest.isEmpty;

/// The banner: an offer for this device, not dismissed in the last [snooze]. A dismissal stamped more than a day in
/// the future (the clock was moved back) is ignored rather than hiding the banner for months.
bool shouldShowGetAppBanner({
  required GetAppOffer? offer,
  required DateTime now,
  DateTime? dismissedAt,
  Duration snooze = kGetAppSnooze,
}) {
  if (offer == null) return false;
  if (dismissedAt == null) return true;
  if (dismissedAt.isAfter(now.add(const Duration(days: 1)))) return true;
  return now.difference(dismissedAt) >= snooze;
}
