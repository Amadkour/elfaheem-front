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
import '../design/app_notice.dart' show showAppNotice;
import '../features/org/org_platform_context.dart';
import '../features/org/org_ui.dart' show orgNameOf;
import 'api_client.dart';

enum AppMode { individual, organization }

/// [AppModeController.resolveOrgId]: the organization to show, and whether the remembered one was gone.
class OrgChoice {
  const OrgChoice(this.orgId, this.fellBack);
  final int? orgId;
  final bool fellBack;
}

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

  /// The last refresh of the overview failed (offline / server error): the LAST KNOWN list is kept, and the screens
  /// that show it offer Retry instead of looking like "no organizations".
  bool refreshFailed = false;

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
    final id = resolveOrgId(
      remembered: _orgId,
      liveIds: [for (final e in live) _id(_map(e['organization'])['id']) ?? -1],
      defaultId: _id(_overview['default_org_id']),
    ).orgId;
    return live.firstWhere((e) => _id(_map(e['organization'])['id']) == id, orElse: () => live.first);
  }

  /// Which organization is shown, pure: the remembered one while it is still listed, else the server's default,
  /// else the first. [OrgChoice.fellBack] = the remembered one is GONE (removed / suspended / deleted), so whoever
  /// shows the fallback must say so ([orgGoneText]) and never swap silently.
  static OrgChoice resolveOrgId({required int? remembered, required List<int> liveIds, int? defaultId}) {
    if (liveIds.isEmpty) return OrgChoice(null, remembered != null);
    if (remembered != null && liveIds.contains(remembered)) return OrgChoice(remembered, false);
    final id = defaultId != null && liveIds.contains(defaultId) ? defaultId : liveIds.first;
    return OrgChoice(id, remembered != null);
  }

  /// The notice for [OrgChoice.fellBack]: [lostName] (null = unknown) is no longer available, [nowName] (null = no
  /// organization left -> the personal space) is shown instead.
  static String orgGoneText({String? lostName, String? nowName}) {
    final lost = lostName == null || lostName.trim().isEmpty ? null : lostName.trim();
    final now = nowName == null || nowName.trim().isEmpty ? null : nowName.trim();
    final ar = StringBuffer(lost == null ? 'لم تعد المؤسسة السابقة متاحة لك' : 'لم تعد مؤسسة «$lost» متاحة لك');
    final en = StringBuffer(lost == null ? 'Your previous organization is no longer available' : '«$lost» is no longer available to you');
    if (now == null) {
      ar.write(' — أنت الآن في حسابك الشخصي.');
      en.write(' — you are in your personal space.');
    } else {
      ar.write(' — فتحنا «$now».');
      en.write(' — opened «$now» instead.');
    }
    return AppConfig.lang == 'ar' ? ar.toString() : en.toString();
  }

  /// Shows the "organization gone" notice (also called by OrgSession). Replaceable in tests.
  static void Function(String text) showGoneNotice = (text) => showAppNotice(text);

  int? get currentOrgId => current == null ? null : _id(_map(current!['organization'])['id']);

  /// Total of what waits in every organization (badge on the switcher while in Individual mode).
  int get pendingTotal => _id(_overview['pending_total']) ?? 0;

  /// THE rule of "which home does this organization open?" (one answer for the switcher, a notification tap, a deep
  /// link and a remembered Organization mode): [entry] (an overview item) is an organization where I am NOT a
  /// student (staff of any kind: admin, teacher, assistant, any management right) -> the organization dashboard
  /// ('/org_dashboard', D-103). Only an organization where I study opens the member home (Organization mode). So a
  /// teacher who is also staff of an organization never lands on the student-style member home of that organization.
  static bool opensDashboard(Map<String, dynamic> entry) {
    final roles = entry['roles'];
    return !(roles is List && roles.any((r) => '$r' == 'student'));
  }

  /// Is every live organization of [entries] one where I study (and manage nothing)? Then the organization
  /// dashboard has nothing for me: it shows "This dashboard is for staff" (D-103).
  static bool studentOnly(List<Map<String, dynamic>> entries) =>
      entries.isNotEmpty && entries.every((e) => !opensDashboard(e) && e['manage'] == null);

  /// The organization the person chose last (Organization mode or the dashboard), read before the overview is
  /// loaded: the dashboard opens it again on a cold start.
  static Future<int?> storedOrgId(int? userId) async {
    if (userId == null) return null;
    try {
      final p = await SharedPreferences.getInstance();
      return p.getInt(orgKeyFor(userId));
    } catch (_) {
      return null;
    }
  }

  /// The organization dashboard switched to [orgId]: remembered as "the last organization" (the same key as
  /// [setMode]) and the next cold start of an org-admin / org-staff opens the dashboard again. The mode is left
  /// alone (in Organization mode the member view follows the same organization).
  Future<void> rememberDashboardOrg(int orgId, {int? userId}) async {
    final uid = userId ?? _userId;
    if ((userId == null || userId == _userId) && _orgId != orgId) {
      _orgId = orgId;
      if (isOrg) notifyListeners();
    }
    if (uid == null) return;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(orgKeyFor(uid), orgId);
      await p.setBool(personalHomeKey(uid), false);
    } catch (_) {}
  }

  /// Storage key of the last organization chosen (per user).
  static String orgKeyFor(int userId) => 'app_mode_org.$userId';

  /// Storage key of "this person last chose their personal space" (read synchronously by the cold-start routing).
  static String personalHomeKey(int userId) => 'app_mode_personal.$userId';

  /// Personal dashboard route — where "leave the organization" lands when the first screen was an org page.
  static const String personalRoute = '/dashboard';

  /// Cold-start home of an org-admin / org-staff login: the personal space when they left their organization last
  /// time ([personalHomeKey]), else [orgHome].
  static String orgRoleHome(String orgHome, {bool? personal}) => personal == true ? personalRoute : orgHome;

  /// The organization pages that are app roots (role homes). Leaving the organization from one of them replaces it.
  static bool isOrgRoute(String? name) => name == '/org_dashboard' || name == '/org_member';

  /// What waits in one organization (to do + approvals).
  static int pendingOf(Map<String, dynamic> entry) =>
      (_id(_map(entry['todo'])['total']) ?? 0) + (_id(_map(entry['approvals'])['total']) ?? 0);

  // ── lifecycle ─────────────────────────────────────────────────────────────

  String get _modeKey => 'app_mode.${_userId ?? 0}';
  String get _orgKey => orgKeyFor(_userId ?? 0);

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
      final before = {for (final e in liveEntries) _id(_map(e['organization'])['id']): orgNameOf(_map(e['organization']))};
      final r = await ApiClient().get(overviewPath);
      if (r is Map) {
        _overview = Map<String, dynamic>.from(r);
        refreshFailed = false;
        if (!_remembered) {
          // first launch on this device → the smart default from the server
          _mode = _overview['suggested_mode'] == 'organization' ? AppMode.organization : AppMode.individual;
        }
        _settleAfterOverview(before);
      }
    } catch (_) {
      // offline / old server (404) / paywall: keep the last answer (the list stays, Retry is offered)
      refreshFailed = true;
    } finally {
      _loading = false;
      loaded = true;
      notifyListeners();
    }
  }

  /// A fresh overview arrived: (1) Organization mode is only ever the member home of an organization where I study
  /// ([opensDashboard] = false) - a staff organization is entered through the dashboard; (2) a remembered
  /// organization that is gone falls back WITH a visible notice, never silently.
  void _settleAfterOverview(Map<int?, String> before) {
    final live = liveEntries;
    final liveIds = [for (final e in live) _id(_map(e['organization'])['id']) ?? -1];
    final gone = _orgId != null && !liveIds.contains(_orgId);
    if (gone && _mode == AppMode.organization) {
      final lostName = before[_orgId];
      final choice = resolveOrgId(remembered: _orgId, liveIds: liveIds, defaultId: _id(_overview['default_org_id']));
      final nowEntry = choice.orgId == null
          ? null
          : live.firstWhere((e) => _id(_map(e['organization'])['id']) == choice.orgId);
      _orgId = choice.orgId;
      if (nowEntry == null) _mode = AppMode.individual;
      showGoneNotice(orgGoneText(lostName: lostName, nowName: nowEntry == null ? null : orgNameOf(_map(nowEntry['organization']))));
      _persist();
    } else if (gone) {
      _orgId = null; // not looking at it: forget it quietly
      _persist();
    }
    final cur = current;
    if (_mode == AppMode.organization && cur != null && opensDashboard(cur)) {
      _mode = AppMode.individual; // rule: staff organizations open the dashboard, not the member home
      _persist();
    }
  }

  Future<void> _persist() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_modeKey, _mode.name);
      if (_orgId != null) {
        await p.setInt(_orgKey, _orgId!);
      } else {
        await p.remove(_orgKey);
      }
      if (_userId != null) await p.setBool(personalHomeKey(_userId!), _mode == AppMode.individual);
    } catch (_) {}
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
      if (_userId != null) await p.setBool(personalHomeKey(_userId!), m == AppMode.individual);
    } catch (_) {}
  }

  void toggle() => setMode(isOrg ? AppMode.individual : AppMode.organization);

  /// Deep link / notification for an organization → open it in Organization mode.
  /// Once the person's organizations are known, an id that is not one of them (a typed `/org/<id>`) opens nothing:
  /// neither the mode nor the remembered organization changes.
  ///
  /// An organization where I am staff ([opensDashboard]) is only remembered (the caller opens its dashboard); the
  /// member home of Organization mode is for the ones where I study.
  Future<void> openOrg(int orgId) async {
    final entry = liveEntries.where((e) => _id(_map(e['organization'])['id']) == orgId).firstOrNull;
    if (loaded && entry == null) return;
    if (entry != null && opensDashboard(entry)) {
      if (isOrg) await setMode(AppMode.individual, orgId: orgId);
      return rememberDashboardOrg(orgId);
    }
    return setMode(AppMode.organization, orgId: orgId);
  }

  /// Does [orgId] open the dashboard? (null = the overview does not list it: the caller decides from `/org/mine`.)
  bool? opensDashboardFor(int orgId) {
    final e = entries.where((e) => _id(_map(e['organization'])['id']) == orgId).firstOrNull;
    return e == null ? null : opensDashboard(e);
  }

  /// Logout.
  Future<void> reset() => bindUser(null);

  // ── organization context (timezone / 12h-24h + org feature offs) ─────────

  /// Applies an organization's context (null = back to the platform defaults). Replaceable in tests.
  @visibleForTesting
  static void Function(int? orgId) applyContext = (id) => id == null ? OrgPlatformContext.close() : OrgPlatformContext.open(id);

  int? _appliedOrg;

  /// Every state change re-checks which organization is open: entering / switching applies its context,
  /// leaving Organization mode clears it. Only transitions act, so the management dashboard (OrgSession) is not
  /// overridden by unrelated refreshes.
  @override
  void notifyListeners() {
    final want = isOrg ? currentOrgId : null;
    if (want != _appliedOrg) {
      final had = _appliedOrg;
      _appliedOrg = want;
      if (want != null || had != null) applyContext(want);
    }
    super.notifyListeners();
  }

  /// Re-applies the organization shown in Organization mode (after a page opened another organization's context,
  /// e.g. returning from the management dashboard).
  ///
  /// In Individual mode it CLEARS the context: before, it only re-applied an organization, so after leaving the
  /// management dashboard / a department the personal space kept that organization's timezone and feature offs.
  void applyOrgContext() {
    final want = isOrg ? currentOrgId : null;
    _appliedOrg = want;
    applyContext(want);
  }

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
