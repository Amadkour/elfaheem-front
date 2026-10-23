// lib/core/app_mode.dart
//
// "Organization mode" ↔ "Individual mode" — ONE app-wide answer to "which side of my life am I looking at?".
//
//   Individual mode    the normal student / teacher UI: courses the person takes or teaches outside any organization.
//   Organization mode  the member dashboard of ONE organization the person belongs to (OrgMemberHome).
//
// Rules (point 2):
//   • the switch exists only when AppConfig.orgsEnabled AND the person holds ≥ 1 live, approved membership
//     (or manages an approved organization) — otherwise the mode is always Individual;
//   • the last mode + organization are remembered per user (shared_preferences);
//   • first launch (nothing remembered) follows the server's smart default (`suggested_mode` of
//     GET /api/v1/org/public/me/overview: pending items / where the primary role lives);
//   • a deep link / notification for an organization calls [AppModeController.openOrg] → Organization mode.
//
// The data comes from GET /api/v1/org/public/me/overview (memberships, effective rights per org / department,
// to do + approvals counters). Everything is read with null-safe helpers: a failed call keeps the last answer.
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import 'api_client.dart';

enum AppMode { individual, organization }

class AppModeController extends ChangeNotifier {
  AppModeController._() {
    // the org master switch flips at runtime (theme / platform settings) → show / hide the switch at once
    AppConfig.orgsEnabledNotifier.addListener(notifyListeners);
  }
  static final AppModeController instance = AppModeController._();

  static const String overviewPath = '/api/v1/org/public/me/overview';

  AppMode _mode = AppMode.individual;
  int? _orgId;
  int? _userId;
  bool _remembered = false;          // the person chose a mode before (on this device)
  bool _loading = false;
  bool loaded = false;
  Map<String, dynamic> _overview = const {};

  // ── what the server said ─────────────────────────────────────────────────

  Map<String, dynamic> get overview => _overview;

  /// Every organization of the person (approved or — for its admins — under review).
  List<Map<String, dynamic>> get entries => _list(_overview['items']);

  /// Organizations that can be opened in Organization mode (approved).
  List<Map<String, dynamic>> get liveEntries =>
      entries.where((e) => '${_map(e['organization'])['status'] ?? 'approved'}' == 'approved').toList();

  /// Is there anything to switch to? (app-wide org master switch + at least one live organization)
  bool get available => AppConfig.orgsEnabled && liveEntries.isNotEmpty;

  AppMode get mode => available ? _mode : AppMode.individual;
  bool get isOrg => mode == AppMode.organization;

  /// The organization shown in Organization mode (the remembered one, else the server's default, else the first).
  Map<String, dynamic>? get current {
    final live = liveEntries;
    if (live.isEmpty) return null;
    for (final e in live) {
      if (_id(_map(e['organization'])['id']) == _orgId) return e;
    }
    final def = _id(_overview['default_org_id']);
    for (final e in live) {
      if (_id(_map(e['organization'])['id']) == def) return e;
    }
    return live.first;
  }

  int? get currentOrgId => current == null ? null : _id(_map(current!['organization'])['id']);

  /// Total of what waits in every organization (badge on the switcher while in Individual mode).
  int get pendingTotal => _id(_overview['pending_total']) ?? 0;

  /// Loaded, and no organization gives this person any management right (routing of org-staff → '/org_member').
  bool get managesNothing => loaded && entries.isNotEmpty && entries.every((e) => e['manage'] == null);

  /// What waits in one organization (to do + approvals).
  static int pendingOf(Map<String, dynamic> entry) =>
      (_id(_map(entry['todo'])['total']) ?? 0) + (_id(_map(entry['approvals'])['total']) ?? 0);

  // ── lifecycle ─────────────────────────────────────────────────────────────

  String get _modeKey => 'app_mode.${_userId ?? 0}';
  String get _orgKey => 'app_mode_org.${_userId ?? 0}';

  /// Call with the signed-in user's id (or null on logout). Restores the remembered mode, then refreshes.
  Future<void> bindUser(int? userId) async {
    if (userId == _userId && (loaded || _loading)) return;
    _userId = userId;
    _overview = const {};
    loaded = false;
    _mode = AppMode.individual;
    _orgId = null;
    _remembered = false;
    if (userId == null) {
      notifyListeners();
      return;
    }
    try {
      final p = await SharedPreferences.getInstance();
      final m = p.getString(_modeKey);
      _remembered = m != null;
      _mode = m == 'organization' ? AppMode.organization : AppMode.individual;
      _orgId = p.getInt(_orgKey);
    } catch (_) {}
    notifyListeners();
    await refresh();
  }

  /// Reload the overview (pull-to-refresh, after answering a form, after an approval …).
  Future<void> refresh() async {
    if (_userId == null || _loading) return;
    _loading = true;
    try {
      final r = await ApiClient().get(overviewPath);
      if (r is Map) {
        _overview = Map<String, dynamic>.from(r);
        if (!_remembered) {
          // first launch on this device → the smart default from the server
          _mode = _overview['suggested_mode'] == 'organization' ? AppMode.organization : AppMode.individual;
        }
      }
    } catch (_) {
      // offline / old server (404) / paywall: keep the last answer; with nothing loaded the switch stays hidden
    } finally {
      _loading = false;
      loaded = true;
      notifyListeners();
    }
  }

  /// The person switched. Instant (no network), remembered.
  Future<void> setMode(AppMode m, {int? orgId}) async {
    final changed = m != _mode || (orgId != null && orgId != _orgId);
    _mode = m;
    if (orgId != null) _orgId = orgId;
    _remembered = true;
    if (changed) notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_modeKey, m.name);
      if (_orgId != null) await p.setInt(_orgKey, _orgId!);
    } catch (_) {}
  }

  void toggle() => setMode(isOrg ? AppMode.individual : AppMode.organization);

  /// Deep link / notification for an organization → open it in Organization mode.
  Future<void> openOrg(int orgId) => setMode(AppMode.organization, orgId: orgId);

  /// Logout.
  Future<void> reset() => bindUser(null);

  // ── helpers ───────────────────────────────────────────────────────────────

  static Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  static List<Map<String, dynamic>> _list(dynamic v) =>
      v is List ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];

  static int? _id(dynamic v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('${v ?? ''}'));

  /// Test hook: feed an overview without the network.
  @visibleForTesting
  void debugSet(Map<String, dynamic> overview, {AppMode? mode, int? orgId, bool remembered = true}) {
    _overview = overview;
    loaded = true;
    _remembered = remembered;
    if (mode != null) _mode = mode;
    if (orgId != null) _orgId = orgId;
    notifyListeners();
  }
}
