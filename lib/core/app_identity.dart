// lib/core/app_identity.dart
//
// The app's identity as the admin set it on the dashboard ("About us" → name, tagline,
// mission, logo, stats) plus the installed / newest app version.
//
// It is needed BEFORE anyone signs in (splash screen, login side panel), so:
//   • it comes from the public, light endpoint  GET /api/v1/app-content/identity
//     (both languages in one answer → switching language needs no new request),
//   • it is cached in SharedPreferences → the next launch paints it instantly, offline too,
//   • `init()` only reads the cache and starts a background refresh — it never blocks start-up.
//
// Usage
//   await AppIdentity.instance.init();                       // once, in main()
//   ListenableBuilder(listenable: AppIdentity.instance, builder: (_, _) => Text(AppIdentity.instance.name))
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kCacheKey = 'app_identity_v1';

String _s(dynamic v) => v == null ? '' : '$v'.trim();

/// Language pick with fallback to the other language.
String _pick(String ar, String en) {
  final first = AppConfig.lang == 'en' ? en : ar;
  return first.isNotEmpty ? first : (AppConfig.lang == 'en' ? ar : en);
}

class IdentityStat {
  const IdentityStat({
    required this.valueAr,
    required this.valueEn,
    required this.labelAr,
    required this.labelEn,
  });

  final String valueAr, valueEn, labelAr, labelEn;

  String get value => _pick(valueAr, valueEn);

  String get label => _pick(labelAr, labelEn);

  factory IdentityStat.fromJson(Map<String, dynamic> j) => IdentityStat(
    valueAr: _s(j['value_ar']),
    valueEn: _s(j['value_en']),
    labelAr: _s(j['label_ar']),
    labelEn: _s(j['label_en']),
  );
}

class LatestVersion {
  const LatestVersion({
    required this.version,
    this.forceUpdate = false,
    this.recommendUpdate = false,
    this.notesAr = '',
    this.notesEn = '',
  });

  final String version;
  final bool forceUpdate, recommendUpdate;
  final String notesAr, notesEn;

  String get notes => _pick(notesAr, notesEn);

  factory LatestVersion.fromJson(Map<String, dynamic> j) => LatestVersion(
    version: _s(j['version']),
    forceUpdate: j['force_update'] == true,
    recommendUpdate: j['recommend_update'] == true,
    notesAr: _s(j['release_notes_ar']),
    notesEn: _s(j['release_notes_en']),
  );
}

class AppIdentity extends ChangeNotifier {
  AppIdentity._();

  static final AppIdentity instance = AppIdentity._();

  String _nameAr = '', _nameEn = '';
  String _taglineAr = '', _taglineEn = '';
  String _missionAr = '', _missionEn = '';
  String? logoUrl;
  List<IdentityStat> stats = const [];
  LatestVersion? latest;

  /// Installed app: "2.1.0" and build number "34" (empty until [init] ran / unsupported platform).
  String installedVersion = '';
  String installedBuild = '';

  bool _refreshing = false;

  // ── resolved texts (current app language) ────────────────────────────────
  String get name => _pick(_nameAr, _nameEn);

  String get tagline => _pick(_taglineAr, _taglineEn);

  String get mission => _pick(_missionAr, _missionEn);

  bool get hasInfo => name.isNotEmpty;

  /// "2.1.0 (34)"
  String get versionLabel => installedVersion.isEmpty
      ? ''
      : (installedBuild.isEmpty ? installedVersion : '$installedVersion ($installedBuild)');

  /// The admin published a newer version than the one installed.
  bool get updateAvailable =>
      latest != null && installedVersion.isNotEmpty && compareVersions(latest!.version, installedVersion) > 0;

  // ── lifecycle ────────────────────────────────────────────────────────────

  /// Reads the cache + the installed version (fast, offline) and starts a background refresh.
  Future<void> init() async {
    try {
      final info = await PackageInfo.fromPlatform();
      installedVersion = info.version;
      installedBuild = info.buildNumber;
    } catch (e) {
      debugPrint('[AppIdentity] package info: $e');
    }
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_kCacheKey);
      if (raw != null) _apply(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[AppIdentity] cache read: $e');
    }
    notifyListeners();
    unawaited(refresh());
  }

  /// Fetches the newest identity. Silent on failure — the cached one stays.
  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final r = await ApiClient()
          .get('/api/v1/app-content/identity', queryParams: {'platform': _platform})
          .timeout(const Duration(seconds: 15));
      if (r is Map) {
        final json = Map<String, dynamic>.from(r);
        _apply(json);
        notifyListeners();
        (await SharedPreferences.getInstance()).setString(_kCacheKey, jsonEncode(json));
      }
    } catch (e) {
      debugPrint('[AppIdentity] refresh: $e');
    }
    _refreshing = false;
  }

  void _apply(Map<String, dynamic> j) {
    final i = j['info'];
    if (i is Map) {
      _nameAr = _s(i['name_ar']);
      _nameEn = _s(i['name_en']);
      _taglineAr = _s(i['tagline_ar']);
      _taglineEn = _s(i['tagline_en']);
      _missionAr = _s(i['mission_ar']);
      _missionEn = _s(i['mission_en']);
      final logo = _s(i['logo_url']);
      logoUrl = logo.isEmpty ? null : logo;
    }
    stats = [
      for (final e in (j['stats'] as List? ?? const []))
        if (e is Map) IdentityStat.fromJson(Map<String, dynamic>.from(e)),
    ];
    final v = j['latest_version'];
    latest = v is Map ? LatestVersion.fromJson(Map<String, dynamic>.from(v)) : null;
  }

  static String get _platform {
    if (kIsWeb) return 'web';
    return defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : (defaultTargetPlatform == TargetPlatform.android ? 'android' : 'web');
  }

  /// 1 if a > b, -1 if a < b, 0 if equal ("2.10.0" > "2.9.3").
  static int compareVersions(String a, String b) {
    List<int> parts(String v) =>
        v.split(RegExp(r'[.+-]')).map((e) => int.tryParse(e.replaceAll(RegExp(r'\D'), '')) ?? 0).toList();
    final x = parts(a), y = parts(b);
    for (var i = 0; i < (x.length > y.length ? x.length : y.length); i++) {
      final p = i < x.length ? x[i] : 0, q = i < y.length ? y[i] : 0;
      if (p != q) return p > q ? 1 : -1;
    }
    return 0;
  }
}
