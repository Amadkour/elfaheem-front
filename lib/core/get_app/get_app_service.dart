// lib/core/get_app/get_app_service.dart — the web build's "Get the app" state: where the page runs, the releases
// manifest, the remembered dismissals and the light analytics. Drawn by GetAppBanner / GetAppSheet / GetAppTile
// (lib/features/get_app/).
//
// Everything offered comes from ONE file, the releases manifest `<site>/releases/releases.json` (schema in
// releases_manifest.dart), published with the files by scripts/release/publish_release.py into the server's
// releases folder (outside the web build): publishing a version never needs a new web build. A missing or broken
// manifest hides everything. The native apps read the same file on launch (VersionCheckService).
//
// Analytics: one `GET <site>/releases/ping/<os>/<event>` per banner view (once per page load), download click and
// install tap; nginx answers 204 and logs only time + path (no IP, no user agent). Kill switches: `get_app.banner`
// (the banner and the iPhone notifications strip), `get_app.entry` (the settings row).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_education_app/core/share/external_link.dart';

import '../../config/app_config.dart';
import 'get_app_probe_stub.dart' if (dart.library.js_interop) 'get_app_probe_web.dart' as probe;
import 'get_app_rules.dart';

export 'get_app_rules.dart';

/// SharedPreferences key: when the banner was last closed (milliseconds since epoch).
const String kGetAppDismissedKey = 'get_app_banner_dismissed_at_v2';

/// SharedPreferences key: when the installed iPhone app's "turn on notifications" strip was last closed.
const String kGetAppPushDismissedKey = 'get_app_push_dismissed_at_v1';

/// Kill-switch keys (services/feature_catalog.py).
const String kGetAppBannerKey = 'get_app.banner';
const String kGetAppEntryKey = 'get_app.entry';

/// The manifest's path at the site root.
const String kReleasesManifestPath = 'releases/releases.json';

/// The manifest URL for the native apps: the API host's root (`https://alfheemacademy.com/api` → `https://alfheemacademy.com/
/// releases/releases.json`).
Uri releasesManifestUriFor(String apiBaseUrl) => Uri.parse(apiBaseUrl).replace(path: '/$kReleasesManifestPath');

/// Fetches and parses the manifest; [ReleasesManifest.empty] on any failure (missing file, the SPA's index.html
/// answered instead of JSON, a timeout). Never throws.
Future<ReleasesManifest> fetchReleasesManifest(Uri url, {http.Client? client}) async {
  try {
    final get = client?.get ?? http.get;
    final res = await get(url, headers: const {'Accept': 'application/json'}).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return ReleasesManifest.empty;
    return parseReleasesManifest(jsonDecode(utf8.decode(res.bodyBytes)), base: url);
  } catch (_) {
    return ReleasesManifest.empty;
  }
}

class GetAppService extends ChangeNotifier {
  GetAppService({
    GetAppEnv Function()? env,
    Future<ReleasesManifest> Function()? loadManifest,
    DateTime Function()? clock,
    void Function(String path)? ping,
    bool Function(String key)? disabled,
    String Function()? notificationPermission,
  })  : _probe = env ?? probe.probeGetAppEnv,
        _loadManifest = loadManifest ?? _fetchSiteManifest,
        _clock = clock ?? DateTime.now,
        _ping = ping ?? _sendPing,
        _disabled = disabled ?? ((k) => AppConfig.disableList.contains(k)),
        _permission = notificationPermission ?? probe.webNotificationPermission;

  static final GetAppService instance = GetAppService();

  final GetAppEnv Function() _probe;
  final Future<ReleasesManifest> Function() _loadManifest;
  final DateTime Function() _clock;
  final void Function(String path) _ping;
  final bool Function(String key) _disabled;
  final String Function() _permission;

  GetAppEnv _env = GetAppEnv.native;
  ReleasesManifest _manifest = ReleasesManifest.empty;
  DateTime? _dismissedAt;
  DateTime? _pushDismissedAt;
  Future<void>? _init;
  final Set<String> _viewed = {};

  GetAppEnv get env => _env;
  ReleasesManifest get manifest => _manifest;
  DateTime? get dismissedAt => _dismissedAt;

  /// What this device is offered (ignores dismissal and kill switches).
  GetAppOffer? get offer => getAppOfferFor(_env, _manifest);

  /// The settings row / sheet (also after the banner was dismissed).
  bool get entryAvailable => !_disabled(kGetAppEntryKey) && getAppEntryAvailable(_env, _manifest);

  /// The banner is shown (the route rules come on top, in the widget).
  bool get bannerEligible =>
      !_disabled(kGetAppBannerKey) &&
      shouldShowGetAppBanner(offer: offer, now: _clock(), dismissedAt: _dismissedAt);

  /// The installed iPhone / iPad web app has never been asked about notifications (iOS asks only after a tap).
  bool get pushPromptEligible {
    if (_disabled(kGetAppBannerKey)) return false;
    if (!_env.isWeb || !_env.standalone) return false;
    if (_env.os != GetAppOs.ios && _env.os != GetAppOs.ipados) return false;
    if (_permission() != 'default') return false;
    return shouldShowGetAppBanner(
      offer: const GetAppOffer(kind: GetAppOfferKind.installIos, os: GetAppOs.ios, release: PlatformRelease(platform: 'ios')),
      now: _clock(),
      dismissedAt: _pushDismissedAt,
      snooze: const Duration(days: 30),
    );
  }

  /// Reads the browser, the dismissals and the manifest once; later calls return the same future. Nothing happens
  /// off the web or inside a wrapper, and a failure leaves everything hidden.
  Future<void> init() => _init ??= _doInit();

  Future<void> _doInit() async {
    try {
      _env = _probe();
    } catch (_) {
      _env = GetAppEnv.native;
    }
    if (!_env.isWeb || _env.embedded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(kGetAppDismissedKey);
      if (ms != null) _dismissedAt = DateTime.fromMillisecondsSinceEpoch(ms);
      final pms = prefs.getInt(kGetAppPushDismissedKey);
      if (pms != null) _pushDismissedAt = DateTime.fromMillisecondsSinceEpoch(pms);
    } catch (_) {}
    if (_env.standalone) {
      notifyListeners(); // the iPhone notifications strip only
      return;
    }
    probe.listenPwaInstallable((v) {
      _env = _env.copyWith(pwaInstallable: v);
      notifyListeners();
    });
    try {
      _manifest = await _loadManifest();
    } catch (_) {
      _manifest = ReleasesManifest.empty;
    }
    notifyListeners();
    if (_env.os != GetAppOs.other && _env.os != GetAppOs.ios && _env.os != GetAppOs.ipados) {
      final arch = await probe.probeArchHint(_env.os);
      if (arch != null) {
        _env = _env.copyWith(archHint: arch);
        notifyListeners();
      }
    }
  }

  /// The banner's close button: hidden for [kGetAppSnooze] on this browser.
  Future<void> dismiss() => _stamp(kGetAppDismissedKey, (t) => _dismissedAt = t);

  /// The notifications strip's close button.
  Future<void> dismissPush() => _stamp(kGetAppPushDismissedKey, (t) => _pushDismissedAt = t);

  Future<void> _stamp(String key, void Function(DateTime) set) async {
    final now = _clock();
    set(now);
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(key, now.millisecondsSinceEpoch);
    } catch (_) {}
  }

  // ── analytics (no personal data: the platform and the event, nothing else) ──────────────────────────────────

  /// Counts a banner view once per page load and platform.
  void trackView(GetAppOs os) {
    if (_viewed.add(os.name)) track(os, 'view');
  }

  /// `view` · `click` (a download) · `install` (an install / Add-to-Home-Screen guide opened).
  void track(GetAppOs os, String event) {
    try {
      _ping('releases/ping/${os.name}/$event');
    } catch (_) {}
  }

  // ── actions ─────────────────────────────────────────────────────────────────────────────────────────────────

  /// Starts the download of [file] in a new tab. False when the browser refused.
  Future<bool> download(GetAppOs os, ReleaseFile file) async {
    track(os, 'click');
    return openExternalLink(file.url, quiet: true, webOnlyWindowName: '_blank');
  }

  /// The browser's own "Install app" prompt (Chrome / Edge): 'accepted', 'dismissed' or 'unavailable'.
  Future<String> installWebApp(GetAppOs os) async {
    track(os, 'install');
    final r = await probe.promptPwaInstall();
    if (r != 'unavailable') {
      _env = _env.copyWith(pwaInstallable: false); // a prompt is good for one use
      notifyListeners();
    }
    return r;
  }

  /// This page's address (the "open in Safari" card copies it).
  String get pageUrl => probe.currentPageUrl();

  /// Asks for notification permission. Call it straight from the tap (no await before it): iOS asks only then.
  Future<String> requestNotifications() => probe.requestWebNotificationPermission();

  static Future<ReleasesManifest> _fetchSiteManifest() async {
    final url = probe.getAppSiteFile(kReleasesManifestPath);
    if (url == null) return ReleasesManifest.empty;
    return fetchReleasesManifest(Uri.parse(url));
  }

  static void _sendPing(String path) {
    final url = probe.getAppSiteFile(path);
    if (url == null) return;
    unawaited(http.get(Uri.parse(url)).timeout(const Duration(seconds: 8)).then((_) {}, onError: (_) {}));
  }

  @visibleForTesting
  void debugSetEnv(GetAppEnv env) {
    _env = env;
    notifyListeners();
  }
}
