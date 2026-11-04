// HelpService (workstream f3): the in-app Help catalogue, fetched ONCE per person + organization context, cached on
// the device with its version, and refreshed only when `GET /api/v1/help/version` says it changed.
//
//   - first ask: no cache -> GET /help/pages?org_id= (role is resolved by the server) and store it;
//   - later asks: a cache is shown at once; the version is checked at most once per app start and again on resume
//     after [recheckAfter] (1 h). `If-None-Match: "help-<n>"` answers 304 = keep; a new number refetches the pages;
//   - offline / any failure: the cached copy stays; a failed check is retried at most once a minute.
//
// The transport is a [HelpRemote] so tests (and the offline case) never need a server.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api_client.dart';
import 'help_models.dart';

/// What the service needs from the server.
abstract class HelpRemote {
  /// The catalogue's version; null when the server answered 304 for [etag] (keep the cache).
  Future<int?> version({String? etag});

  /// `{version, role, pages:[...]}`.
  Future<Map<String, dynamic>> pages({int? orgId});
}

class ApiHelpRemote implements HelpRemote {
  const ApiHelpRemote();

  @override
  Future<int?> version({String? etag}) async {
    try {
      final r = await ApiClient().get('/api/v1/help/version', auth: false, headers: {'If-None-Match': ?etag});
      if (r is Map) return (r['version'] as num?)?.toInt();
      return null;
    } catch (e) {
      final x = ApiException.from(e);
      if (x.statusCode == 304) return null;
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> pages({int? orgId}) async {
    final r = await ApiClient().get('/api/v1/help/pages', queryParams: {'org_id': ?orgId});
    return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
  }
}

class HelpService extends ChangeNotifier with WidgetsBindingObserver {
  HelpService({HelpRemote remote = const ApiHelpRemote(), DateTime Function()? clock})
      : _remote = remote,
        _now = clock ?? DateTime.now;

  static HelpService instance = HelpService();

  /// Tests: replaces the singleton.
  static void debugReplace(HelpService s) => instance = s;

  static const recheckAfter = Duration(hours: 1);
  static const retryAfterFailure = Duration(minutes: 1);
  static const _prefix = 'help.cache.v1.';

  final HelpRemote _remote;
  final DateTime Function() _now;

  String _scope = '';
  int _version = -1;
  String _role = '';
  Map<String, HelpEntry> _pages = const {};
  DateTime? _checkedAt, _failedAt;
  Future<void>? _inFlight;
  bool _observing = false;
  int? _lastOrg;
  String _lastUser = '';

  int get version => _version;
  String get role => _role;
  bool get loaded => _scope.isNotEmpty;
  int get count => _pages.length;

  /// The entry of [pageId] for the current person, or null (no button).
  HelpEntry? entry(String pageId) => _pages[pageId];

  Iterable<String> get pageIds => _pages.keys;

  static String scopeOf(String userKey, int? orgId) => '$userKey:${orgId ?? 0}';

  /// Makes sure the catalogue for ([userKey], [orgId]) is loaded: the cache at once, then (at most once per start and
  /// per [recheckAfter]) the version check. Never throws.
  Future<void> ensure({required String userKey, int? orgId, bool force = false}) {
    _lastUser = userKey;
    _lastOrg = orgId;
    if (!_observing) {
      _observing = true;
      try {
        WidgetsBinding.instance.addObserver(this);
      } catch (_) {/* no binding (a plain Dart test) */}
    }
    final scope = scopeOf(userKey, orgId);
    final running = _inFlight;
    if (running != null && scope == _scope && !force) return running;
    final f = _run(scope, force).whenComplete(() => _inFlight = null);
    return _inFlight = f;
  }

  Future<void> _run(String scope, bool force) async {
    if (scope != _scope) {
      _scope = scope;
      _version = -1;
      _role = '';
      _pages = const {};
      _checkedAt = null;
      _failedAt = null;
      await _loadCache(scope);
      notifyListeners();
    }
    final now = _now();
    if (!force) {
      if (_checkedAt != null && now.difference(_checkedAt!) < recheckAfter) return;
      if (_failedAt != null && now.difference(_failedAt!) < retryAfterFailure) return;
    }
    try {
      final org = _orgOf(scope);
      if (_version < 0) {
        await _fetchPages(scope, org);
      } else {
        final v = await _remote.version(etag: '"help-$_version"');
        if (v != null && v != _version) await _fetchPages(scope, org);
      }
      _checkedAt = _now();
      _failedAt = null;
    } catch (_) {
      _failedAt = _now(); // offline or a server error: keep what is cached
    }
  }

  static int? _orgOf(String scope) {
    final n = int.tryParse(scope.substring(scope.lastIndexOf(':') + 1));
    return n == null || n == 0 ? null : n;
  }

  Future<void> _fetchPages(String scope, int? org) async {
    final r = await _remote.pages(orgId: org);
    if (scope != _scope) return; // the person changed meanwhile
    final list = [for (final p in (r['pages'] as List? ?? const [])) if (p is Map) HelpEntry.fromJson(p)];
    _apply((r['version'] as num?)?.toInt() ?? 0, '${r['role'] ?? ''}', list);
    await _saveCache(scope, r);
  }

  void _apply(int version, String role, List<HelpEntry> list) {
    _version = version;
    _role = role;
    _pages = {for (final e in list) if (e.pageId.isNotEmpty && e.hasContent) e.pageId: e};
    notifyListeners();
  }

  Future<void> _loadCache(String scope) async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString('$_prefix$scope');
      if (raw == null) return;
      final m = jsonDecode(raw);
      if (m is! Map) return;
      _apply((m['version'] as num?)?.toInt() ?? -1, '${m['role'] ?? ''}',
          [for (final e in (m['pages'] as List? ?? const [])) if (e is Map) HelpEntry.fromJson(e)]);
    } catch (_) {/* a damaged cache is just a miss */}
  }

  Future<void> _saveCache(String scope, Map<String, dynamic> body) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('$_prefix$scope', jsonEncode(body));
    } catch (_) {}
  }

  /// Forgets the in-memory copy (sign-out); the device cache stays for the next sign-in.
  void reset() {
    _scope = '';
    _version = -1;
    _role = '';
    _pages = const {};
    _checkedAt = _failedAt = null;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _lastUser.isNotEmpty) {
      unawaited(ensure(userKey: _lastUser, orgId: _lastOrg)); // rechecks only after [recheckAfter]
    }
  }

  // ── The tour: first visit only, remembered per page per person ───────────────

  static String _tourKey(String userKey, String pageId) => 'help.tour.$userKey.$pageId';

  Future<bool> tourSeen(String userKey, String pageId) async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getBool(_tourKey(userKey, pageId)) ?? false;
    } catch (_) {
      return true; // no storage: never nag
    }
  }

  Future<void> markTourSeen(String userKey, String pageId) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_tourKey(userKey, pageId), true);
    } catch (_) {}
  }
}
