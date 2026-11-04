// HelpService (workstream f3): the in-app Help catalogue. A page's Info button costs NO request (the owner's rule:
// homes stay cheap):
//
//   - visibility comes from the index bundled in the app, `assets/help/help_index.json` ((page_id, role) pairs that
//     have an entry, generated from the backend's help seed by tool/gen_help_index.dart); a catalogue cached on the
//     device from an earlier tap overrides it (exact for this person's role);
//   - the catalogue is fetched only when the person taps an Info button ([ensure]): no cache -> GET /help/pages?org_id=
//     (the role is resolved by the server); a cache -> `GET /help/version` with `If-None-Match: "help-<n>"` (304 =
//     keep, a new number refetches the pages), at most once per app start and again after [recheckAfter] (1 h);
//   - nothing at start-up, on resume or on a timer; offline / any failure: the cached copy stays, a failed check is
//     retried at most once a minute.
//
// The transport is a [HelpRemote] so tests (and the offline case) never need a server.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
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

class HelpService extends ChangeNotifier {
  HelpService({HelpRemote remote = const ApiHelpRemote(), DateTime Function()? clock, Future<String> Function()? indexLoader})
      : _remote = remote,
        _now = clock ?? DateTime.now,
        _indexLoader = indexLoader ?? (() => rootBundle.loadString(indexAsset));

  static HelpService instance = HelpService();

  /// Tests: replaces the singleton.
  static void debugReplace(HelpService s) => instance = s;

  static const recheckAfter = Duration(hours: 1);
  static const retryAfterFailure = Duration(minutes: 1);
  static const _prefix = 'help.cache.v1.';
  static const indexAsset = 'assets/help/help_index.json';

  final HelpRemote _remote;
  final DateTime Function() _now;
  final Future<String> Function() _indexLoader;

  String _scope = '';
  int _version = -1;
  String _role = '';
  Map<String, HelpEntry> _pages = const {};
  DateTime? _checkedAt, _failedAt;
  Future<void>? _inFlight;
  Map<String, Set<String>>? _index; // page_id -> roles that have an entry
  String _helpRole = ''; // the person's resolved help role ([helpRoleOf]); '' = unknown
  Future<void>? _indexLoading;

  int get version => _version;
  String get role => _role;
  bool get loaded => _scope.isNotEmpty;
  int get count => _pages.length;

  /// The entry of [pageId] from the catalogue cached on the device, or null (not cached yet: the tour waits).
  HelpEntry? entry(String pageId) => _pages[pageId];

  Iterable<String> get pageIds => _pages.keys;

  /// Without a cached catalogue the bundled index decides, for the person's help role and its fallback chain (the
  /// server's rules, [helpRoleOf] / [helpFallback]); an unknown role (no [loadLocal] yet) shows nothing.
  bool has(String pageId) {
    if (_version >= 0) return _pages.containsKey(pageId);
    final roles = _index?[pageId];
    if (roles == null || _helpRole.isEmpty) return false;
    return helpFallback(_helpRole).any(roles.contains);
  }

  /// The help role of a person, as the server's `resolve_role` computes it: a platform admin is always
  /// `super_admin`; inside an organization an `org_admin` member is `org_admin` and any other member `org_member`;
  /// else the platform role (`org-admin` -> org_admin, `org-staff` -> org_member, teacher / parent / student).
  static String helpRoleOf(String? platformRole, {bool inOrg = false, bool orgAdmin = false}) {
    final base = switch (platformRole) {
      'admin' || 'super-admin' || 'super_admin' || 'developer' => 'super_admin',
      'teacher' => 'teacher',
      'parent' => 'parent',
      'org-admin' || 'org_admin' => 'org_admin',
      'org-staff' || 'org_staff' => 'org_member',
      _ => 'student',
    };
    if (base == 'super_admin' || !inOrg) return base;
    return orgAdmin ? 'org_admin' : 'org_member';
  }

  /// The server's fallback chains (`_FALLBACK` in services/help_service.py).
  static List<String> helpFallback(String role) => switch (role) {
        'super_admin' => const ['super_admin', 'org_admin'],
        'org_admin' => const ['org_admin', 'org_member', 'student'],
        'org_member' => const ['org_member', 'student'],
        'teacher' => const ['teacher', 'student'],
        'parent' => const ['parent', 'student'],
        'student' => const ['student'],
        _ => [role, 'student'],
      };

  static String scopeOf(String userKey, int? orgId) => '$userKey:${orgId ?? 0}';

  /// Reads the bundled index (a local asset, no request). Never throws.
  Future<void> loadIndex() => _indexLoading ??= () async {
        try {
          final m = jsonDecode(await _indexLoader());
          final list = m is Map ? (m['pages'] as List? ?? const []) : const [];
          final idx = <String, Set<String>>{};
          for (final p in list) {
            if (p is List && p.length >= 2) idx.putIfAbsent('${p[0]}', () => {}).add('${p[1]}');
          }
          _index = idx;
        } catch (_) {
          _index = <String, Set<String>>{};
        }
        notifyListeners();
      }();

  /// Local only, no request: the bundled index plus this person's cached catalogue (saved by an earlier tap).
  Future<void> loadLocal({required String userKey, int? orgId, required String helpRole}) async {
    unawaited(loadIndex());
    final roleChanged = helpRole != _helpRole;
    _helpRole = helpRole;
    final scope = scopeOf(userKey, orgId);
    if (scope == _scope && roleChanged) notifyListeners();
    if (scope == _scope) return;
    _resetTo(scope);
    await _loadCache(scope);
    notifyListeners();
  }

  void _resetTo(String scope) {
    _scope = scope;
    _version = -1;
    _role = '';
    _pages = const {};
    _checkedAt = null;
    _failedAt = null;
  }

  /// The tap path: makes sure the catalogue for ([userKey], [orgId]) is loaded: the cache at once, then (at most once
  /// per start and per [recheckAfter]) the version check, or the first fetch when nothing is cached. Never throws.
  Future<void> ensure({required String userKey, int? orgId, bool force = false}) {
    final scope = scopeOf(userKey, orgId);
    final running = _inFlight;
    if (running != null && scope == _scope && !force) return running;
    final f = _run(scope, force).whenComplete(() => _inFlight = null);
    return _inFlight = f;
  }

  Future<void> _run(String scope, bool force) async {
    if (scope != _scope) {
      _resetTo(scope);
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
