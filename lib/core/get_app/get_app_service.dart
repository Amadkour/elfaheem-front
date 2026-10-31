// lib/core/get_app/get_app_service.dart — the web build's "Get the app" state: where the page runs, the store /
// installer links, and the remembered dismissal. Drawn by GetAppBanner / GetAppTile (lib/design/get_app_banner.dart).
//
// The links live in ONE file next to index.html, `web/app_links.json` (published as `<site>/app_links.json`), one
// entry per platform: android · ios (iPhone and iPad) · windows · macos · linux. Editing it on the hosting changes
// them without a new build; an empty entry hides the banner on that platform. The native app never reads it.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'get_app_probe_stub.dart' if (dart.library.js_interop) 'get_app_probe_web.dart' as probe;
import 'get_app_rules.dart';

export 'get_app_rules.dart';

/// SharedPreferences key: when the banner was last closed (milliseconds since epoch).
const String kGetAppDismissedKey = 'get_app_banner_dismissed_at_v1';

class GetAppService extends ChangeNotifier {
  GetAppService({
    GetAppEnv Function()? env,
    Future<Object?> Function()? loadLinks,
    DateTime Function()? clock,
  })  : _probe = env ?? probe.probeGetAppEnv,
        _loadLinks = loadLinks ?? _fetchSiteLinks,
        _clock = clock ?? DateTime.now;

  static final GetAppService instance = GetAppService();

  final GetAppEnv Function() _probe;
  final Future<Object?> Function() _loadLinks;
  final DateTime Function() _clock;

  GetAppEnv _env = GetAppEnv.native;
  GetAppLinks _links = GetAppLinks.none;
  DateTime? _dismissedAt;
  Future<void>? _init;

  GetAppEnv get env => _env;
  GetAppLinks get links => _links;
  DateTime? get dismissedAt => _dismissedAt;

  /// The store / installer link for this device, or null.
  String? get link => entryAvailable ? _links.linkFor(_env.os) : null;

  /// The settings row is shown (also after the banner was dismissed).
  bool get entryAvailable => getAppEntryAvailable(_env, _links);

  /// The banner is shown (the route rules come on top, in the widget).
  bool get bannerEligible =>
      shouldShowGetAppBanner(env: _env, links: _links, now: _clock(), dismissedAt: _dismissedAt);

  /// Reads the browser, the dismissal and the links once; later calls return the same future. Nothing happens off
  /// the web or inside an installed / embedded app, and a failure leaves everything hidden.
  Future<void> init() => _init ??= _doInit();

  Future<void> _doInit() async {
    try {
      _env = _probe();
    } catch (_) {
      _env = GetAppEnv.native;
    }
    if (!_env.isWeb || _env.standalone || _env.embedded || _env.os == GetAppOs.other) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(kGetAppDismissedKey);
      if (ms != null) _dismissedAt = DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {}
    try {
      _links = parseGetAppLinks(await _loadLinks());
    } catch (_) {
      _links = GetAppLinks.none;
    }
    notifyListeners();
  }

  /// The banner's close button: hidden for [kGetAppSnooze] on this browser.
  Future<void> dismiss() async {
    final now = _clock();
    _dismissedAt = now;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(kGetAppDismissedKey, now.millisecondsSinceEpoch);
    } catch (_) {}
  }

  /// Opens the store / installer in a new tab. False when there is no link or the browser refused.
  Future<bool> open() async {
    final url = link;
    if (url == null) return false;
    try {
      return await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
    } catch (_) {
      return false;
    }
  }

  /// `<site>/app_links.json`, or null when it is missing / unreadable.
  static Future<Object?> _fetchSiteLinks() async {
    final url = probe.getAppSiteFile('app_links.json');
    if (url == null) return null;
    final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return null;
    // the hosting answers index.html for a missing file (SPA rewrite): that is not JSON → no links
    return jsonDecode(utf8.decode(res.bodyBytes));
  }
}
