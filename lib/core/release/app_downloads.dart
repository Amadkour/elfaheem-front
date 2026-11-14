// lib/core/release/app_downloads.dart — the website channel's downloads (D-144, docs/release/APP_RELEASES_CODEMAGIC.md
// "Downloads"): the public list `GET /api/v1/app/downloads`, what this browser is offered first, and the dismissal
// remembered per browser for one version. Drawn by AppDownloadBanner (lib/features/get_app/app_download_banner.dart).
//
//   parseAppDownloads(raw)                 the list, leniently ({items} / {downloads} / a bare list; web and file-less
//                                          entries dropped: the site itself is not a download)
//   appDownloadOfferFor(env, releases)     Android → the universal APK (arm64 / v7a listed under it), Windows / Linux →
//                                          their file, iPhone / iPad → the "Add to Home Screen" steps, anything else →
//                                          "see the downloads"; nothing in the native app, an installed web app, a
//                                          wrapper or an Android in-app browser (it cannot hand an APK to the installer)
//   AppDownloadsService                    loads once, remembers "closed for this version" (a new version shows again),
//                                          kill switch `app.download_banner`; a failed request or an empty list hides it
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_config.dart';
import '../api_client.dart';
import '../get_app/get_app_probe_stub.dart' if (dart.library.js_interop) '../get_app/get_app_probe_web.dart' as probe;
import '../get_app/get_app_rules.dart';

export '../get_app/get_app_rules.dart' show GetAppEnv, GetAppOs;

/// Kill-switch key (services/feature_catalog.py).
const String kDownloadBannerKey = 'app.download_banner';

/// SharedPreferences key: the [AppDownloadOffer.stamp] the banner was closed for.
const String kDownloadBannerDismissedKey = 'app_download_banner_dismissed_v1';

/// The public route.
const String kAppDownloadsPath = '/api/v1/app/downloads';

/// [url] as an absolute link: a path on our API (`/api/v1/app/downloads/android/x.apk`) is read against [apiBase]
/// (`https://nextbrain.site/api`, which carries the proxy's `/api` prefix); anything else is returned as it is.
String resolveDownloadUrl(String url, {required String apiBase}) {
  if (!url.startsWith('/') || url.startsWith('//')) return url;
  final base = apiBase.endsWith('/') ? apiBase.substring(0, apiBase.length - 1) : apiBase;
  return '$base$url';
}

int? _int(Object? v) => v == null ? null : (v is num ? v.toInt() : int.tryParse('$v'));
String _str(Object? v) => v == null ? '' : '$v'.trim();

class AppDownloadFile {
  const AppDownloadFile({required this.name, required this.url, this.size, this.sha256, this.abi, this.kind = '', this.primary = false});

  final String name;

  /// Absolute (a server path is read against the API base).
  final String url;
  final int? size;
  final String? sha256;

  /// `arm64-v8a`, `armeabi-v7a`, `universal`, `x64` …
  final String? abi;

  /// `apk` | `deb` | `tar` | `zip` (from the name when the server sends none).
  final String kind;

  /// The server's pick for the platform (`primary: true`: the universal APK, the .deb).
  final bool primary;

  bool get universal => abi == 'universal' || name.toLowerCase().contains('universal');

  factory AppDownloadFile.fromJson(Map<String, dynamic> j, {required String apiBase}) {
    final name = _str(j['name'] ?? j['file']);
    final lower = name.toLowerCase();
    var kind = _str(j['kind']);
    if (kind.isEmpty) {
      kind = lower.endsWith('.tar.gz') || lower.endsWith('.tgz') ? 'tar' : (lower.contains('.') ? lower.split('.').last : '');
    }
    var abi = _str(j['abi'] ?? j['arch']);
    if (abi.isEmpty) {
      for (final a in const ['arm64-v8a', 'armeabi-v7a', 'universal', 'x86_64', 'x64', 'arm64']) {
        if (lower.contains(a)) {
          abi = a;
          break;
        }
      }
    }
    return AppDownloadFile(
      name: name,
      url: resolveDownloadUrl(_str(j['url'] ?? j['download_url']), apiBase: apiBase),
      size: _int(j['size'] ?? j['bytes']),
      sha256: _str(j['sha256']).isEmpty ? null : _str(j['sha256']),
      abi: abi.isEmpty ? null : abi,
      kind: kind,
      primary: j['primary'] == true,
    );
  }
}

class AppDownloadRelease {
  const AppDownloadRelease({
    required this.platform,
    required this.version,
    this.buildNumber,
    this.notesAr = '',
    this.notesEn = '',
    this.files = const [],
  });

  final String platform;
  final String version;
  final int? buildNumber;
  final String notesAr, notesEn;
  final List<AppDownloadFile> files;

  /// `android:1.4.1+53` — what "closed for this version" remembers.
  String get stamp => '$platform:$version+${buildNumber ?? ''}';

  String notes(String lang) {
    final mine = (lang == 'ar' ? notesAr : notesEn).trim();
    return mine.isNotEmpty ? mine : (lang == 'ar' ? notesEn : notesAr).trim();
  }

  /// The file the banner's button downloads: Android → the universal APK (fits every phone), else the first APK;
  /// Linux → the .deb, then the .tar.gz; Windows → the zip; anything else → the first file.
  AppDownloadFile? get primary {
    if (files.isEmpty) return null;
    AppDownloadFile? first(bool Function(AppDownloadFile f) test) {
      for (final f in files) {
        if (test(f)) return f;
      }
      return null;
    }

    final marked = first((f) => f.primary);
    if (marked != null) return marked;
    return switch (platform) {
      'android' => first((f) => f.kind == 'apk' && f.universal) ?? first((f) => f.kind == 'apk') ?? files.first,
      'linux' => first((f) => f.kind == 'deb') ?? first((f) => f.kind == 'tar' || f.kind == 'gz') ?? files.first,
      'windows' => first((f) => f.kind == 'zip' || f.kind == 'exe' || f.kind == 'msix') ?? files.first,
      _ => files.first,
    };
  }

  /// Every file but [primary] (arm64 / v7a under the universal APK, the .tar.gz under the .deb).
  List<AppDownloadFile> get others => [for (final f in files) if (!identical(f, primary)) f];
}

/// The platforms in the order the sheet lists them.
const List<String> kDownloadPlatformOrder = ['android', 'windows', 'linux', 'macos', 'ios'];

/// `GET /app/downloads` → the releases with at least one file, the web build left out (it IS the site).
List<AppDownloadRelease> parseAppDownloads(Object? raw, {required String apiBase}) {
  final rows = raw is Map ? (raw['items'] ?? raw['downloads'] ?? raw['platforms'] ?? raw['data']) : raw;
  if (rows is! List) return const [];
  final out = <AppDownloadRelease>[];
  for (final r in rows) {
    if (r is! Map) continue;
    final m = Map<String, dynamic>.from(r);
    final platform = _str(m['platform']);
    if (platform.isEmpty || platform == 'web') continue;
    final notes = m['notes'] is Map ? Map<String, dynamic>.from(m['notes'] as Map) : const <String, dynamic>{};
    final files = [
      for (final f in (m['files'] is List ? m['files'] as List : const []))
        if (f is Map) AppDownloadFile.fromJson(Map<String, dynamic>.from(f), apiBase: apiBase),
    ].where((f) => f.name.isNotEmpty && f.url.startsWith('https://')).toList();
    if (files.isEmpty) continue;
    out.add(AppDownloadRelease(
      platform: platform,
      version: _str(m['version']),
      buildNumber: _int(m['build_number'] ?? m['build']),
      notesAr: _str(m['notes_ar'] ?? notes['ar']),
      notesEn: _str(m['notes_en'] ?? notes['en']),
      files: files,
    ));
  }
  out.sort((a, b) {
    int at(String p) => kDownloadPlatformOrder.contains(p) ? kDownloadPlatformOrder.indexOf(p) : 99;
    return at(a.platform).compareTo(at(b.platform));
  });
  return out;
}

enum AppDownloadOfferKind {
  /// One file for this device.
  file,

  /// iPhone / iPad: Share → Add to Home Screen (Apple allows no other install outside the App Store).
  iosWebApp,

  /// A device with no file of its own (a Mac, ChromeOS, …): the list of every download.
  browse,
}

class AppDownloadOffer {
  const AppDownloadOffer({required this.kind, required this.os, required this.stamp, this.release, this.file});

  final AppDownloadOfferKind kind;
  final GetAppOs os;

  /// What closing the banner remembers: this platform's version, or every version for [AppDownloadOfferKind.browse] /
  /// [AppDownloadOfferKind.iosWebApp] — a new version brings the banner back.
  final String stamp;
  final AppDownloadRelease? release;
  final AppDownloadFile? file;
}

String _allStamps(List<AppDownloadRelease> releases) => [for (final r in releases) r.stamp].join('|');

/// What this browser is offered first; null: nothing (no downloads, the native app, an installed web app, a wrapper,
/// an Android in-app browser).
AppDownloadOffer? appDownloadOfferFor(GetAppEnv env, List<AppDownloadRelease> releases) {
  if (!env.isWeb || env.standalone || env.embedded || releases.isEmpty) return null;
  AppDownloadRelease? of(String platform) {
    for (final r in releases) {
      if (r.platform == platform) return r;
    }
    return null;
  }

  AppDownloadOffer browse() => AppDownloadOffer(kind: AppDownloadOfferKind.browse, os: env.os, stamp: _allStamps(releases));
  AppDownloadOffer fileFor(String platform) {
    final r = of(platform);
    final f = r?.primary;
    if (r == null || f == null) return browse();
    return AppDownloadOffer(kind: AppDownloadOfferKind.file, os: env.os, stamp: r.stamp, release: r, file: f);
  }

  switch (env.os) {
    case GetAppOs.android:
      // an app's own browser often cannot hand an APK to the installer: nothing rather than a broken download
      return env.inAppBrowser ? null : fileFor('android');
    case GetAppOs.windows:
      return fileFor('windows');
    case GetAppOs.linux:
      return fileFor('linux');
    case GetAppOs.ios || GetAppOs.ipados:
      return AppDownloadOffer(kind: AppDownloadOfferKind.iosWebApp, os: env.os, stamp: 'ios-web-app|${_allStamps(releases)}');
    case GetAppOs.macos || GetAppOs.other:
      return browse();
  }
}

class AppDownloadsService extends ChangeNotifier {
  AppDownloadsService({
    GetAppEnv Function()? env,
    Future<Object?> Function()? fetch,
    bool Function(String key)? disabled,
    String? apiBase,
  })  : _probe = env ?? probe.probeGetAppEnv,
        _fetch = fetch ?? (() => ApiClient.instance.get(kAppDownloadsPath)),
        _disabled = disabled ?? ((k) => AppConfig.disableList.contains(k)),
        _apiBase = apiBase;

  static final AppDownloadsService instance = AppDownloadsService();

  final GetAppEnv Function() _probe;
  final Future<Object?> Function() _fetch;
  final bool Function(String key) _disabled;
  final String? _apiBase;

  GetAppEnv _env = GetAppEnv.native;
  List<AppDownloadRelease> _releases = const [];
  String? _dismissed;
  bool _started = false;
  bool _loaded = false;

  GetAppEnv get env => _env;
  List<AppDownloadRelease> get releases => _releases;
  bool get loaded => _loaded;

  /// Something is published on the website channel (the D-137 "Get the app" strip steps aside then: one offer).
  bool get hasDownloads => _releases.isNotEmpty;

  AppDownloadOffer? get offer => appDownloadOfferFor(_env, _releases);

  /// The strip shows: an offer, not closed for this version, the kill switch off.
  bool get visible {
    final o = offer;
    return o != null && o.stamp != _dismissed && !_disabled(kDownloadBannerKey);
  }

  /// Reads the browser, the remembered dismissal and the list, once (later calls return at once).
  Future<void> init() async {
    if (_started) return;
    _started = true;
    try {
      _env = _probe();
    } catch (_) {
      _env = GetAppEnv.native;
    }
    if (!_env.isWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _dismissed = prefs.getString(kDownloadBannerDismissedKey);
    } catch (_) {/* private window / blocked storage: shown every visit */}
    await reload();
  }

  /// Fetches the list again (a failure or an empty answer hides the strip).
  Future<void> reload() async {
    try {
      _releases = parseAppDownloads(await _fetch(), apiBase: _apiBase ?? AppConfig.baseUrl);
    } catch (_) {
      _releases = const [];
    }
    _loaded = true;
    notifyListeners();
  }

  /// "Close" — remembered on this browser for this version.
  Future<void> dismiss() async {
    final o = offer;
    if (o == null) return;
    _dismissed = o.stamp;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kDownloadBannerDismissedKey, o.stamp);
    } catch (_) {/* not remembered: it shows again on the next visit */}
  }

  /// Opens [file] (the browser downloads it: the server answers with Content-Disposition: attachment).
  Future<bool> download(AppDownloadFile file) async {
    try {
      return await launchUrl(Uri.parse(file.url), mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
    } catch (_) {
      return false;
    }
  }

  @visibleForTesting
  void debugSet({GetAppEnv? env, List<AppDownloadRelease>? releases, String? dismissed}) {
    _started = true;
    if (env != null) _env = env;
    if (releases != null) _releases = releases;
    _dismissed = dismissed;
    _loaded = true;
    notifyListeners();
  }
}
