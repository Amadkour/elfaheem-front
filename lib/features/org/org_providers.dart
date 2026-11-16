// lib/features/org/org_providers.dart
//
// Organization state.
//   OrgSession            global (register in core/providers.dart) — the organizations whose dashboard I open
//                         (GET /org/mine?members=1: admin · staff · member without rights, never where I study,
//                         D-103), the selected one, my access + permissions there → drives the switcher, the sections
//                         and hides forbidden buttons; reloads on `org_access_changed` and on a 403
//                         org_forbidden / student_forbidden from any org call while the dashboard watches it
//   OrgMembersProvider    paged members (students | teachers | staff)     — created locally by the page
//   OrgCoursesProvider    paged organization courses                      — created locally by the page
//   OrgScheduleProvider   periods · rooms · availability · loads · schedules · slots — created locally by the schedule tab
//   OrgMembershipProvider teacher / student side: search · join · my organizations · org courses · my timetable
//   OrgDashController     the org-admin home's one call (GET …/dashboard → OrgHomeData): cached per organization,
//                         reloads on open / resume / pull / `attention_changed{org_id}` — created by the dashboard
library;

import 'dart:async';
import 'dart:convert' show jsonEncode;

import 'package:dio/dio.dart' show DioException, InterceptorsWrapper;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/app_mode.dart' show AppModeController;
import 'package:flutter_education_app/core/attention/attention_service.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/utils/live_events.dart';

import '../admin/admin_common.dart';
import '../admin/admin_providers.dart';
import 'home/org_home_logic.dart' show OrgTask, OrgTaskAction, OrgTaskOutcome, OrgTaskQueue, orgTaskOutcome;
import 'org_dashboard_model.dart';
import 'org_fix_actions.dart' show registerOrgFixActions;
import 'org_platform_context.dart';
import 'org_schedule_ladder.dart';
import 'org_v3.dart';

const orgBase = '/api/v1/org';

// ═════════════════════════════════════════════════════════════════════════════
//  Session (global)
// ═════════════════════════════════════════════════════════════════════════════

/// What I am in one organization of `/org/mine?members=1` (D-103): `admin` (org / platform admin), `staff` (any
/// right, org-wide or in a department) or `member` (a live, non-student membership without any right). An older
/// server sends no `access`: it is derived the same way from `my_role` / `is_admin` / the permission maps.
String orgAccessOf(Map<String, dynamic>? item) {
  if (item == null) return 'member';
  final a = '${item['access'] ?? ''}';
  if (a == 'admin' || a == 'staff' || a == 'member') return a;
  if (item['is_admin'] == true || const ['org_admin', 'platform_admin'].contains(item['my_role'])) return 'admin';
  bool anyRight(dynamic m) => m is Map && m.values.any((v) => v is List ? v.isNotEmpty : v is Map && anyRight(v));
  if (anyRight(item['permissions']) || anyRight(item['dept_permissions'])) return 'staff';
  return 'member';
}

/// The server's code on a 403 that means "my access here changed": `org_forbidden` / `student_forbidden` (in
/// `detail.code`, a bare `detail` string or a top-level `code`); null for anything else.
String? orgAccessDeniedCode(dynamic body) {
  final m = ApiException.asMap(body);
  if (m == null) return null;
  final d = m['detail'];
  final code = d is Map ? '${d['code'] ?? ''}' : (d is String ? d : '${m['code'] ?? ''}');
  return code == 'org_forbidden' || code == 'student_forbidden' ? code : null;
}

/// The organization id of an org route (`/api/v1/org/orgs/12/…` → 12), null for the others.
int? orgIdOfPath(String path) {
  final m = RegExp(r'/org/orgs/(\d+)').firstMatch(path);
  return m == null ? null : int.tryParse(m.group(1)!);
}

/// What `/org_dashboard` shows (D-103).
enum OrgGate {
  /// `/mine` (or, when nothing is listed, the membership overview) is still loading.
  loading,

  /// At least one organization to manage / work in: the dashboard.
  dashboard,

  /// I only study in my organizations (or the server answered 403 student_forbidden): "This dashboard is for staff".
  staffOnly,

  /// An older server that does not list members without rights in `/mine`: their member page ('/org_member').
  memberPage,

  /// No organization at all: create the first one (org admins / teachers, never students).
  createFirst,
}

/// The routing decision of the organization dashboard, pure (unit-tested). [overview] = the live items of
/// `GET /org/public/me/overview` (only read when `/mine` lists nothing).
OrgGate orgDashboardGate({
  required bool loaded,
  required bool hasItems,
  bool studentBlocked = false,
  String? userRole,
  bool overviewLoaded = false,
  List<Map<String, dynamic>> overview = const [],
}) {
  if (!loaded) return OrgGate.loading;
  if (hasItems) return OrgGate.dashboard;
  if (studentBlocked) return OrgGate.staffOnly;
  if (userRole == 'org-admin') return OrgGate.createFirst;
  if (!overviewLoaded) return OrgGate.loading;
  if (AppModeController.studentOnly(overview)) return OrgGate.staffOnly;
  if (overview.any(AppModeController.opensDashboard)) return OrgGate.memberPage;
  if (userRole == 'student') return OrgGate.staffOnly;
  return OrgGate.createFirst;
}

class OrgSession extends AdminBase {
  /// UX v3 phase 6: the organization's one-tap error fixes (open_members · open_agenda · setup_councils) are
  /// registered app-wide with the session, which every org screen reads.
  OrgSession() {
    registerOrgFixActions();
  }

  List<Map<String, dynamic>> items = [];   // flat, path-sorted, each has depth / parent_id / my_role / permissions
  int? currentId;
  bool loaded = false;
  final ValueNotifier<int> epoch = ValueNotifier(0);   // bump → every org tab reloads

  Map<String, dynamic>? get current {
    for (final o in items) {
      if (o['id'] == currentId) return o;
    }
    return null;
  }

  String get name {
    final o = current;
    if (o == null) return '';
    final ar = (o['name_ar'] ?? '').toString(), en = (o['name_en'] ?? '').toString();
    return t(ar.isNotEmpty ? ar : en, en.isNotEmpty ? en : ar);
  }

  static String nameOf(Map<String, dynamic> o) {
    final ar = (o['name_ar'] ?? '').toString(), en = (o['name_en'] ?? '').toString();
    return t(ar.isNotEmpty ? ar : en, en.isNotEmpty ? en : ar);
  }

  bool get isOrgAdmin => const ['org_admin', 'platform_admin'].contains(current?['my_role']);

  /// `admin` | `staff` | `member` in the selected organization ([orgAccessOf]).
  String get access => orgAccessOf(current);

  /// My membership role there (teacher · teacher_assistant · admin_assistant …), null when my access is only
  /// inherited / a grant without membership, or on an older server.
  String? get memberRole {
    final r = current?['member_role'];
    return r == null || '$r'.isEmpty ? null : '$r';
  }

  /// Organizations whose org calls answered 403 student_forbidden (left out of [items] until my access changes).
  final Set<int> _studentBlocked = {};

  /// The server said I study where I tried to open the dashboard.
  bool get studentBlocked => _studentBlocked.isNotEmpty;

  int? _wanted;

  /// Opens [id] as soon as it is listed: at once when loaded, else on the next [load] (the switcher of a personal
  /// home pushes '/org_dashboard' on it).
  void open(int id) {
    _wanted = id;
    if (loaded && items.any((o) => asInt(o['id']) == id)) {
      _wanted = null;
      select(id);
    }
  }

  /// v2: may I create a new ROOT organization (university …)? Sub-organizations need `sub_orgs.insert`.
  bool canCreateRoot = false;

  /// pending | approved | rejected | suspended (an ancestor's suspension counts too).
  String get status => '${current?['status'] ?? 'approved'}';
  bool get approved => status == 'approved';

  static String _alias(String module, String action) =>
      module == 'requests' && action == 'update' ? 'approve' : action;   // v1 call sites keep working

  /// Is [action] on [module] allowed for me in the selected organization — org-wide, or inside [deptId]?
  bool can(String module, [String action = 'view', int? deptId]) {
    if (isOrgAdmin) return true;
    final a = _alias(module, action);
    final p = current?['permissions'];
    if (p is Map && p[module] is List && (p[module] as List).contains(a)) return true;
    if (deptId != null) {
      final d = current?['dept_permissions'];
      final m = d is Map ? d['$deptId'] : null;
      if (m is Map && m[module] is List) return (m[module] as List).contains(a);
    }
    return false;
  }

  /// Org-wide OR in at least one department (to decide whether a menu entry is shown at all).
  bool canAny(String module, [String action = 'view']) {
    if (can(module, action)) return true;
    final d = current?['dept_permissions'];
    if (d is! Map) return false;
    final a = _alias(module, action);
    return d.values.any((m) => m is Map && m[module] is List && (m[module] as List).contains(a));
  }

  /// Departments where I have any right (empty for org-wide people — they see every department).
  Set<int> get myDeptIds {
    final d = current?['dept_permissions'];
    return d is Map ? {for (final k in d.keys) int.tryParse('$k') ?? -1} : <int>{};
  }

  String get base => '$orgBase/orgs/$currentId';

  /// `members=1` (D-103): also the organizations where I am a member without any right, each item with `access`
  /// and `member_role`; never one where I study. An older server ignores the parameter.
  /// The selection: the organization asked for by [open], else the current one ([keepSelection]), else [prefer]
  /// (the last one chosen, AppModeController.storedOrgId), else the first.
  Future<void> load({bool keepSelection = true, int? prefer}) async {
    final before = currentId;
    final beforeName = name;
    final r = await run(() => api.get('$orgBase/mine', queryParams: const {'members': '1'}));
    loadFailed = r is! Map;
    if (r is Map) {
      items = [
        for (final o in asMapList(r['items']))
          if (!_studentBlocked.contains(asInt(o['id']))) o,
      ];
      canCreateRoot = r['can_create_root'] == true;
      bool listed(int? id) => id != null && items.any((o) => asInt(o['id']) == id);
      final asked = _wanted;
      final pick = [_wanted, if (keepSelection) currentId, prefer].where(listed).firstOrNull;
      currentId = pick ?? (items.isEmpty ? null : asInt(items.first['id']));
      // one load answers the request: an organization /mine does not list (one where I only study) must not stay
      // wanted and be selected by some later listing
      _wanted = null;
      // the organization I was in (or chose last) is gone: say so, never show another one silently
      final ctl = AppModeController.instance;
      final wasId = keepSelection ? (before ?? prefer) : null;
      // the remembered one (cold start) may simply be an organization where I study (not in /mine): only a
      // membership overview that does not list it either proves it is gone
      final gone = wasId != null && !listed(wasId) && !listed(asked) &&
          (before != null || (ctl.loaded && ctl.opensDashboardFor(wasId) == null));
      if (gone) {
        if (currentId != null) ctl.rememberDashboardOrg(currentId!);
        AppModeController.showGoneNotice(AppModeController.orgGoneText(
            lostName: before == null ? null : beforeName, nowName: currentId == null ? null : name));
      }
    }
    loaded = true;
    OrgPlatformContext.open(approved ? currentId : null);   // org timezone / 12h-24h + org feature offs
    notifyListeners();
  }

  /// The last `/org/mine` call failed (offline / server error): [items] is the LAST KNOWN list, and the screens show
  /// an error with Retry ([errorMessage]) instead of looking like "no organizations".
  bool loadFailed = false;

  /// Switches to [id]: the previous organization's per-org state goes first (timezone / 12h-24h, feature offs, the
  /// attention focus), then [id]'s context loads; every section reloads (epoch) and pushed pages of the old one
  /// close themselves (OrgPushedPage).
  void select(int id) {
    if (id == currentId) return;
    OrgPlatformContext.close();
    AttentionService.instance.focusOrg(null);
    currentId = id;
    OrgPlatformContext.open(approved ? id : null);
    epoch.value++;
    notifyListeners();
  }

  // ── access changes while the dashboard is open (D-103, spec §6) ──────────

  static OrgSession? _watching;
  static bool _interceptorOn = false;
  StreamSubscription<LiveEvent>? _accessSub;
  Future<void>? _accessReload;
  DateTime? _lastAccessReload;

  /// A 403 org_forbidden reloads `/mine` at most this often (a button I may not use must not hammer it).
  static const accessReloadGap = Duration(seconds: 10);

  /// The dashboard is on screen: follow `org_access_changed` and the 403s of every org call (one Dio interceptor,
  /// installed once, that only acts while a session watches).
  void watchAccess() {
    _watching = this;
    _accessSub ??= LiveEvents.instance.listen({LiveEvents.orgAccessChanged}, (e) {
      final id = e.orgId;
      if (id != null) _studentBlocked.remove(id);
      if (id == null) _studentBlocked.clear();
      reloadAccess(force: true, always: true); // team / department changes live in the dashboard payload
    });
    if (_interceptorOn) return;
    _interceptorOn = true;
    api.dio.interceptors.add(InterceptorsWrapper(onError: (e, handler) {
      _onApiError(e);
      handler.next(e);
    }));
  }

  void unwatchAccess() {
    if (identical(_watching, this)) _watching = null;
    _accessSub?.cancel();
    _accessSub = null;
  }

  static void _onApiError(DioException e) {
    final s = _watching;
    if (s == null || e.response?.statusCode != 403) return;
    final path = e.requestOptions.path;
    if (!path.contains('$orgBase/')) return;
    final code = orgAccessDeniedCode(e.response?.data);
    if (code != null) s.accessDenied(code, orgId: orgIdOfPath(path));
  }

  /// An org call answered 403 [code]: a student is blocked from that organization's dashboard; either way my
  /// access is reloaded (the current organization kept when still listed, else the next, else the gate's page).
  void accessDenied(String code, {int? orgId}) {
    final student = code == 'student_forbidden';
    if (student) {
      final id = orgId ?? currentId;
      if (id != null) _studentBlocked.add(id);
    }
    reloadAccess(force: student);
  }

  /// Reloads `/mine?members=1`; when my organization or my rights there changed, every section reloads (epoch).
  Future<void> reloadAccess({bool force = false, bool always = false}) {
    final running = _accessReload;
    if (running != null) return running;
    final last = _lastAccessReload;
    if (!force && last != null && DateTime.now().difference(last) < accessReloadGap) return Future.value();
    _lastAccessReload = DateTime.now();
    final before = currentId;
    final sig = _accessSig(current);
    return _accessReload = load().then((_) {
      if (always || currentId != before || _accessSig(current) != sig) epoch.value++;
    }).whenComplete(() => _accessReload = null);
  }

  static String _accessSig(Map<String, dynamic>? o) => o == null
      ? ''
      : jsonEncode([o['access'], o['my_role'], o['member_role'], o['permissions'], o['dept_permissions']]);

  Future<bool> createOrg(Map<String, dynamic> body) async {
    final r = await call(() => api.post('$orgBase/orgs', body: body), ok: t('تم إنشاء المؤسسة', 'Organization created'));
    if (r is Map) {
      await load();
      select(asInt(r['id']));
      return true;
    }
    return false;
  }

  Future<bool> updateOrg(Map<String, dynamic> body) async {
    final r = await call(() => api.put(base, body: body), ok: t('تم الحفظ', 'Saved'));
    if (r != null) await load();
    return r != null;
  }

  Future<bool> deleteOrg() async {
    final r = await call(() => api.delete(base), ok: t('تم الحذف', 'Deleted'));
    if (r != null) await load(keepSelection: false);
    return r != null;
  }

  /// Sends a rejected application back for review.
  Future<bool> resubmit() async {
    final r = await call(() => api.post('$base/resubmit'), ok: t('أُعيد إرسال الطلب للمراجعة', 'Sent back for review'));
    if (r != null) await load();
    return r != null;
  }

  Future<Map<String, dynamic>?> details() async {
    final r = await run(() => api.get(base), makLoading: false);
    return r is Map ? Map<String, dynamic>.from(r) : null;
  }

  /// Rotates the printed join code. The app uses the multi-code route on the code's own row (`legacy_code_id` of the
  /// join settings, admins only); a server that does not send the id (older) keeps the legacy route.
  Future<String?> regenerateCode() async {
    final cid = await legacyCodeId();
    final r = await call(() => cid != null ? api.post('$base/join/codes/$cid/regenerate') : api.post('$base/join-code/regenerate'));
    if (r is Map) {
      await load();
      return regeneratedCodeOf(r);
    }
    return null;
  }

  Future<int?> legacyCodeId() async {
    try {
      final s = await api.get('$base/join/settings');
      return legacyCodeIdOf(s);
    } catch (_) {
      return null;                              // settings unreadable: the legacy route still works
    }
  }

  Future<Map<String, dynamic>?> overview() async {
    final r = await run(() => api.get('$base/overview'), makLoading: false);
    return r is Map ? Map<String, dynamic>.from(r) : null;
  }

  /// Excel template / export → {url, filename}. The caller opens the url.
  Future<Map<String, dynamic>?> file(String path, [Map<String, dynamic>? query]) async {
    final r = await call(() => api.get('$base/$path', queryParams: query));
    return r is Map ? Map<String, dynamic>.from(r) : null;
  }

  Future<Map<String, dynamic>?> importExcel(String kind, String fileName, {String? filePath, Uint8List? bytes}) async {
    final r = await call(() => api.postMultipart('$base/import/$kind',
        fields: const {}, fileField: 'file', fileName: fileName, filePath: filePath, fileBytes: bytes));
    return r is Map ? Map<String, dynamic>.from(r) : null;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Paged lists
// ═════════════════════════════════════════════════════════════════════════════

class OrgMembersProvider extends AdminPagedProvider {
  OrgMembersProvider(this.session, this.roles, {this.status = 'active'});
  final OrgSession session;
  final String roles;     // 'student' | 'teacher' | 'teacher_assistant,admin_assistant'
  String status;

  @override
  String get path => '${session.base}/members';

  @override
  Map<String, dynamic> get filters => {'role': roles, 'status': status};

  Future<void> setStatusFilter(String s) {
    status = s;
    return refresh();
  }

  Future<Map<String, dynamic>?> add(Map<String, dynamic> body) async {
    final r = await call(() => api.post(path, body: body));
    if (r is Map && r['status'] == 'invited') {
      // C7: 202, an existing account is invited; no member row exists yet, so the list is not touched
      toast(t('تم إرسال دعوة — ينضم بعد قبولها', 'Invitation sent — they join once they accept'));
      return Map<String, dynamic>.from(r);
    }
    if (r != null) toast(t('تمت الإضافة', 'Added'));
    if (r is Map) await refresh();
    return r is Map ? Map<String, dynamic>.from(r) : null;
  }

  Future<bool> update(int id, Map<String, dynamic> body) async {
    final r = await call(() => api.put('$path/$id', body: body), ok: t('تم الحفظ', 'Saved'));
    if (r != null) await refresh();
    return r != null;
  }

  Future<bool> remove(int id) async {
    final r = await call(() => api.delete('$path/$id'), ok: t('تمت الإزالة', 'Removed'));
    if (r != null) await refresh();
    return r != null;
  }

  Future<bool> setPermissions(int id, Map<String, List<String>> perms) async {
    final r = await call(() => api.put('$path/$id/permissions', body: {'permissions': perms}),
        ok: t('تم حفظ الصلاحيات', 'Permissions saved'));
    if (r != null) await refresh();
    return r != null;
  }

  Future<bool> decide(int id, bool approve) async {
    final r = await call(() => api.post('${session.base}/requests/$id/${approve ? 'approve' : 'reject'}'));
    if (r != null) await refresh();
    return r != null;
  }
}

class OrgCoursesProvider extends AdminPagedProvider {
  OrgCoursesProvider(this.session);
  final OrgSession session;

  @override
  String get path => '${session.base}/courses';

  @override
  Map<String, dynamic> get filters => {};

  Future<bool> save(int? id, Map<String, dynamic> body) async {
    final r = await call(() => id == null ? api.post(path, body: body) : api.put('$path/$id', body: body),
        ok: t('تم الحفظ', 'Saved'));
    if (r != null) await refresh();
    return r != null;
  }

  Future<bool> unlink(int id) async {
    final r = await call(() => api.delete('$path/$id'), ok: t('تم فصل الكورس عن المؤسسة', 'Course removed from the organization'));
    if (r != null) await refresh();
    return r != null;
  }

  Future<Map<String, dynamic>?> enroll(int courseId, List<int> studentIds) async {
    final r = await call(() => api.post('$path/$courseId/enroll', body: {'student_ids': studentIds}));
    if (r is Map) await refresh();
    return r is Map ? Map<String, dynamic>.from(r) : null;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Schedule
// ═════════════════════════════════════════════════════════════════════════════

const orgDays = ['saturday', 'sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday'];

class OrgScheduleProvider extends AdminBase {
  OrgScheduleProvider(this.session);
  final OrgSession session;

  List<Map<String, dynamic>> periods = [], rooms = [], loads = [], schedules = [], slots = [], staff = [];
  List<Map<String, dynamic>> conflicts = [], warnings = [];
  Map<String, dynamic>? schedule;
  bool loaded = false;

  String get base => session.base;

  // v3: facility types · academic terms · generation runs
  List<String> builtinKinds = const ['lecture', 'lab', 'hall', 'office', 'other'];
  List<Map<String, dynamic>> facilityTypes = [], terms = [];
  /// GET …/schedules/term-needs: the current / next term without a timetable, with the server's blockers
  List<Map<String, dynamic>> termNeeds = [];
  bool termNeedsLoaded = false;
  Map<String, dynamic>? genRun;      // the run being followed (queued / running / waiting / just finished)
  EventOrPoll? _poll;                // the run follow: the live event or the fallback poll, one request in flight
  int _followSeq = 0;                // bumped by every _follow: a poll of an older follow never writes genRun
  bool _disposed = false;

  Future<void> loadSetup() async {
    final rs = await Future.wait([
      run(() => api.get('$base/periods'), makLoading: false),
      run(() => api.get('$base/rooms'), makLoading: false),
      run(() => api.get('$base/loads'), makLoading: false),
      run(() => api.get('$base/schedules'), makLoading: false),
      run(() => api.get('$orgBase/orgs/${session.currentId}/members',
          queryParams: {'role': 'teacher,teacher_assistant,admin_assistant', 'size': 100}), makLoading: false),
      orgCall(() => api.get('$base/facility-types'), quiet: true),
      orgCall(() => api.get('$base/academic/terms'), quiet: true),
      orgCall(() => api.get('$base/schedules/term-needs'), quiet: true),
    ]);
    if (_disposed) return;
    List<Map<String, dynamic>> items(dynamic r) => r is Map ? asMapList(r['items']) : [];
    periods = items(rs[0]);
    rooms = items(rs[1]);
    loads = items(rs[2]);
    schedules = items(rs[3]);
    staff = items(rs[4]);
    final ft = rs[5] as OrgCall, tm = rs[6] as OrgCall;
    if (ft.ok) {
      builtinKinds = [for (final k in (ft.map['builtin'] as List? ?? const [])) '$k'];
      facilityTypes = asMapList(ft.map['items']);
    }
    terms = asMapList(tm.map['items']);
    final tn = rs[7] as OrgCall;
    if (tn.ok) {
      termNeeds = asMapList(tn.map['items']);
      termNeedsLoaded = true;
    }
    loaded = true;
    notifyListeners();
  }

  /// kind key → label (built-in kinds + the organization's own facility types).
  Map<String, String> get kindLabels => {
        for (final k in builtinKinds) k: roomKindLabel(k),
        for (final f in facilityTypes) '${f['key']}': t('${f['label_ar'] ?? f['key']}', '${f['label_en'] ?? f['label_ar'] ?? f['key']}'),
      };

  @override
  void dispose() {
    _disposed = true;
    _poll?.dispose();
    super.dispose();
  }

  // ── v3: schedule scope (full replacement) ──

  /// POST (new) or PUT (existing) the whole draft. Returns the call; on success the list is refreshed.
  Future<OrgCall> saveDraft(ScheduleDraft d) async {
    final r = await orgCall(() => d.id == null ? api.post('$base/schedules', body: d.toBody()) : api.put('$base/schedules/${d.id}', body: d.toBody()),
        quiet: true);
    if (r.ok) {
      d.id = asInt(r.map['id']);
      await loadSetup();
    }
    return r;
  }

  // ── v3: generation as a job ──

  /// Starts a background generation and follows it until it ends. A run already in progress is followed instead.
  /// [persistSettings] false: [settings] apply to this run only (stored with its revision, not on the timetable).
  Future<OrgCall> startGeneration({Map<String, dynamic>? settings, bool keepLocked = true, int seed = 7, bool persistSettings = true, bool complete = false}) async {
    final id = schedule!['id'];
    final r = await orgCall(
        () => api.post('$base/schedules/$id/generate',
            queryParams: {'background': true},
            body: {'settings': ?settings, 'keep_locked': keepLocked, 'seed': seed, if (!persistSettings) 'persist_settings': false, if (complete) 'complete': true}),
        quiet: true);
    final run = r.ok ? asMap(r.map['run']) : (r.code == 'generation_running' ? asMap(r.detail['run']) : const <String, dynamic>{});
    if (run.isNotEmpty) {
      genRun = run;
      notifyListeners();
      _follow(asInt(id), asInt(run['id']));
    }
    return r;
  }

  /// The autopilot (POST …/autopilot, 202 {run}): data fixes → complete generation → every automatic remedy of every
  /// hard conflict → re-solve, as ONE background run the studio follows like a generation.
  Future<OrgCall> startAutopilot({List<String>? dataFixKeys}) async {
    final id = schedule!['id'];
    final r = await orgCall(() => api.post('$base/schedules/$id/autopilot', body: {'data_fix_keys': ?dataFixKeys}), quiet: true);
    final run = r.ok ? asMap(r.map['run']) : (r.code == 'generation_running' ? asMap(r.detail['run']) : const <String, dynamic>{});
    if (run.isNotEmpty) followRun(asInt(id), run);
    return r;
  }

  /// A term's timetable in one tap (POST …/schedules/auto {term_id}, 202 {schedule, run, existing}): the draft is
  /// created when the term has none and the autopilot runs on it; the timetable is opened and the run followed.
  Future<OrgCall> generateForTerm(int termId) async {
    final r = await orgCall(() => api.post('$base/schedules/auto', body: {'term_id': termId}), quiet: true);
    if (!r.ok) {
      final run = asMap(r.detail['run']);
      if (r.code == 'generation_running' && run['schedule_id'] != null) {   // someone already pressed it: follow that run
        final sid = asInt(run['schedule_id']);
        await loadSetup();
        await open(sid);
        followRun(sid, run);
        return const OrgCall(true);
      }
      return r;
    }
    final sid = asInt(asMap(r.map['schedule'])['id']);
    await loadSetup();
    await open(sid);
    followRun(sid, asMap(r.map['run']));
    return r;
  }

  /// GET …/autopilot/plan: the data fixes an attended run would apply (quiet; an older server has no route).
  Future<OrgCall> autopilotPlan() => orgCall(() => api.get('$base/schedules/${schedule!['id']}/autopilot/plan'), quiet: true);

  /// Follow [run] of [scheduleId] until it ends (the live panel reads [genRun]).
  void followRun(int scheduleId, Map<String, dynamic> run) {
    genRun = run;
    notifyListeners();
    if (runIsOpen(run)) _follow(scheduleId, asInt(run['id']));
  }

  /// Polls the run every 2 s until it is closed — every 10 s while the live stream is connected, where the event
  /// `job_updated{kind: schedule_run, id}` fetches at once. No time cap: a ladder run may wait for a decision for
  /// as long as the server allows. The run is lost only after 5 failed polls in a row or a 404; polls never
  /// overlap, and a poll of an earlier follow (another run, or a closed studio) never writes [genRun].
  void _follow(int scheduleId, int runId) {
    _poll?.dispose();
    final seq = ++_followSeq;
    var misses = 0;
    late final EventOrPoll w;
    w = EventOrPoll(
      kind: 'schedule_run',
      id: '$runId',
      every: const Duration(seconds: 2),
      fallbackEvery: const Duration(seconds: 10),
      poll: () async {
        final r = await orgCall(() => api.get('$base/schedules/$scheduleId/runs/$runId'), quiet: true);
        if (_disposed || seq != _followSeq) return w.stop();
        final lost = !r.ok && (++misses >= 5 || r.endpointMissing || r.error?.statusCode == 404);
        if (lost) {
          w.stop();
          genRun = {...?genRun, 'status': 'failed', 'error': t('انقطعت متابعة التوليد — أعد فتح الجدول', 'Lost track of the generation — reopen the timetable')};
          notifyListeners();
          return;
        }
        if (!r.ok) return;           // transient: keep following a few more times
        misses = 0;
        genRun = r.map;
        notifyListeners();
        if (!runIsOpen(genRun)) {
          w.stop();
          if (schedule?['id'] == scheduleId) await open(scheduleId);   // slots + result as stored by the server
          await loadSetup();
        }
      },
    );
    _poll = w;
    w.start();
  }

  // ── v4: the relaxation ladder (org_schedule_ladder.dart; server schedule_ladder.py) ──

  /// GET …/schedules/{sid}/ladder: the timetable's ladder, the catalog, the options and the presets. Null when the
  /// server has no ladder route yet (an older server) or the call failed (toasted).
  Future<LadderConfig?> loadLadder(int sid) async {
    final r = await orgCall(() => api.get('$base/schedules/$sid/ladder'), quiet: true);
    if (!r.ok) {
      if (!r.endpointMissing) toast(orgErrorText(r.error!), error: true);
      return null;
    }
    return LadderConfig.of(r.map);
  }

  /// PUT …/schedules/{sid}/ladder {ladder, options, expected_version}: the saved ladder as the server answers it
  /// (or [c] itself when the answer carries no ladder); null on failure (toasted; a 409 stale_version reloads the
  /// timetable).
  Future<LadderConfig?> saveLadder(int sid, LadderConfig c, {int? expectedVersion}) async {
    final r = await orgCall(
        () => api.put('$base/schedules/$sid/ladder', body: {...c.toBody(), 'expected_version': ?(expectedVersion ?? c.version)}),
        ok: t('حُفظ السلّم', 'Ladder saved'), quiet: true);
    if (!r.ok) {
      toast(orgErrorText(r.error!), error: true);
      if (r.code == 'stale_version' && schedule?['id'] == sid) await open(sid);
      return null;
    }
    if (schedule?['id'] == sid && r.map['version'] != null) schedule = {...?schedule, 'version': r.map['version']};
    final saved = r.map['ladder'] == null ? c : LadderConfig.of(r.map);
    return saved.copyWith(presets: saved.presets.isEmpty ? c.presets : saved.presets);
  }

  /// POST …/ladder-presets {name, ladder, options}: the preset the organization now keeps (null on failure).
  Future<LadderPreset?> savePreset(String name, LadderConfig c) async {
    final r = await orgCall(() => api.post('$base/ladder-presets', body: {'name': name.trim(), ...c.toBody()}), ok: t('حُفظ الإعداد', 'Preset saved'));
    if (!r.ok) return null;
    final m = asMap(r.map['preset'] ?? r.map);
    return m.isEmpty ? null : LadderPreset.of(m);
  }

  /// DELETE …/ladder-presets/{id}.
  Future<bool> deletePreset(String id) async {
    final r = await orgCall(() => api.delete('$base/ladder-presets/$id'), ok: t('حُذف الإعداد', 'Preset deleted'));
    return r.ok;
  }

  /// Starts a ladder run (POST …/generate?background=true {ladder: true, auto, seed}) and follows it; a run already
  /// in progress (409 generation_running) is followed instead. [auto] true: every decision is taken by the server.
  Future<OrgCall> startLadder(int sid, {required bool auto, int seed = 7}) async {
    final r = await orgCall(
        () => api.post('$base/schedules/$sid/generate', queryParams: {'background': true}, body: {'ladder': true, 'auto': auto, 'seed': seed}),
        quiet: true);
    final run = r.ok ? asMap(r.map['run']) : (r.code == 'generation_running' ? asMap(r.detail['run']) : const <String, dynamic>{});
    if (run.isNotEmpty) followRun(sid, run);
    return r;
  }

  /// Answers the decision a waiting ladder run asks for (POST …/runs/{rid}/decide {decision_id, option_id};
  /// [optionId] "auto" = the recommendation). The answer is the run as it is now, which the follow keeps reading.
  Future<OrgCall> decide(String decisionId, String optionId) async {
    final run = genRun;
    if (run == null) return const OrgCall(null);
    final sid = asInt(run['schedule_id'] ?? schedule?['id']);
    final r = await orgCall(() => api.post('$base/schedules/$sid/runs/${run['id']}/decide', body: {'decision_id': decisionId, 'option_id': optionId}));
    if (r.ok) {
      genRun = r.map['run'] != null ? asMap(r.map['run']) : (r.map['id'] != null ? r.map : {...run, 'status': 'running'});
      notifyListeners();
      if (_poll?.running != true) _follow(sid, asInt(run['id']));
    }
    return r;
  }

  /// Saves settings.rules ({key: locked|flexible}) on the timetable. PUT replaces the whole timetable, so every field
  /// is sent as stored (course_ids null = every course stays null).
  Future<OrgCall> saveRules(Map<String, String> rules) async {
    final s = schedule!;
    final id = asInt(s['id']);
    final body = {
      ...ScheduleDraft.fromJson(s).toBody(),
      'course_ids': s['course_ids'],
      'settings': {...asMap(s['settings']), 'rules': rules},
      'expected_version': ?s['version'],
    };
    final r = await orgCall(() => api.put('$base/schedules/$id', body: body), ok: t('حُفظت القواعد', 'Rules saved'), quiet: true);
    if (r.ok) await open(id);
    return r;
  }

  /// Accept (keep) or reject (remove) the sessions of generated blocks that broke a flexible rule.
  Future<OrgCall> decideProposals(List<String> blockIds, {required bool accept}) async {
    final id = schedule!['id'];
    final r = await orgCall(() => api.post('$base/schedules/$id/proposals/decide',
        body: {'block_ids': blockIds, 'accept': accept, 'expected_version': ?schedule!['version']}));
    if (r.ok) {
      _apply(r.map);
      await validate();
    }
    return r;
  }

  /// Cancels the run being followed — on ITS timetable (run.schedule_id; the open timetable when the run has none).
  Future<OrgCall> cancelGeneration() async {
    final run = genRun;
    final sid = run?['schedule_id'] ?? schedule?['id'];
    if (run == null || sid == null) return const OrgCall(null);
    final r = await orgCall(() => api.post('$base/schedules/${asInt(sid)}/runs/${run['id']}/cancel'));
    if (r.ok) {
      genRun = r.map;
      notifyListeners();
    }
    return r;
  }

  /// When a studio is opened, a run that is still going on the server is picked up again. Only an OPEN run is
  /// restored: a finished one belongs to the result already stored on the timetable and is never shown again as a
  /// failure / cancellation banner.
  Future<void> resumeRunIfAny() async {
    final id = schedule?['id'];
    if (id == null) return;
    final r = await orgCall(() => api.get('$base/schedules/$id/runs'), quiet: true);
    if (_disposed || schedule?['id'] != id) return;
    final runs = asMapList(r.map['items']);
    genRun = runs.cast<Map<String, dynamic>?>().firstWhere((x) => runIsOpen(x), orElse: () => null);
    notifyListeners();
    if (runIsOpen(genRun)) _follow(asInt(id), asInt(genRun!['id']));
  }

  // ── v3: revisions ──

  Future<List<Map<String, dynamic>>> revisions() async {
    final r = await orgCall(() => api.get('$base/schedules/${schedule!['id']}/revisions'));
    return asMapList(r.map['items']);
  }

  Future<bool> restoreRevision(int revId) async {
    final r = await orgCall(() => api.post('$base/schedules/${schedule!['id']}/revisions/$revId/restore'),
        ok: t('استُعيدت النسخة', 'Version restored'));
    if (r.ok) await open(asInt(schedule!['id']));
    return r.ok;
  }

  /// Saves the current slots (hand edits included) as a new version — POST …/revisions; an older server without the
  /// route is told apart by [OrgCall.endpointMissing].
  Future<OrgCall> saveSnapshot(String? label) => orgCall(
      () => api.post('$base/schedules/${schedule!['id']}/revisions', body: {'label': (label ?? '').trim().isEmpty ? null : label!.trim()}),
      quiet: true);

  /// Staff the timetable places in their unavailable time who have not agreed yet (409 staff_consent_pending):
  /// {pending: [uid], declined: [uid], agreed: [uid]} — publishing again with [force] needs a reason.
  Map<String, dynamic>? consentWait;

  /// Publishing: null when published; the server's hard conflicts when it refused (409 schedule_conflict).
  Future<List<Map<String, dynamic>>?> publish({bool force = false, String? reason}) async {
    final id = schedule!['id'];
    consentWait = null;
    final r = await orgCall(
        () => api.post('$base/schedules/$id/activate', queryParams: force ? {'force_consent': 'true', 'reason': reason ?? ''} : null),
        ok: t('تم نشر الجدول للجميع', 'Timetable published'), quiet: true);
    if (r.ok) {
      _apply({...r.map, 'items': slots});
      await loadSetup();
      return null;
    }
    if (r.code == 'schedule_conflict') return asMapList(r.detail['conflicts']);
    if (r.code == 'staff_consent_pending') {
      consentWait = r.detail;
      return const [];
    }
    toast(orgErrorText(r.error!), error: true);
    return const [];
  }

  List<Map<String, dynamic>> staffOf(String role) =>
      staff.where((m) => m['role'] == role).map((m) => Map<String, dynamic>.from(m['user'] as Map)).toList();

  Future<bool> _mut(Future<dynamic> Function() fn, {String? ok}) async {
    final r = await call(fn, ok: ok ?? t('تم الحفظ', 'Saved'));
    if (r != null) await loadSetup();
    return r != null;
  }

  Future<bool> savePeriod(int? id, Map<String, dynamic> b) =>
      _mut(() => id == null ? api.post('$base/periods', body: b) : api.put('$base/periods/$id', body: b));
  Future<bool> deletePeriod(int id) => _mut(() => api.delete('$base/periods/$id'), ok: t('تم الحذف', 'Deleted'));
  Future<bool> saveRoom(int? id, Map<String, dynamic> b) =>
      _mut(() => id == null ? api.post('$base/rooms', body: b) : api.put('$base/rooms/$id', body: b));
  Future<bool> deleteRoom(int id) => _mut(() => api.delete('$base/rooms/$id'), ok: t('تم الحذف', 'Deleted'));
  Future<bool> saveLoad(int courseId, Map<String, dynamic> b) => _mut(() => api.put('$base/loads/$courseId', body: b));

  Future<Set<String>?> getAvailability(String type, int id) async {
    final r = await run(() => api.get('$base/availability', queryParams: {'subject_type': type, 'subject_id': id}),
        makLoading: false);
    if (r is! Map) return null;
    if (r['everywhere'] == true) return <String>{};
    return asMapList(r['cells']).map((c) => '${c['day']}|${c['period_id']}').toSet();
  }

  Future<bool> setAvailability(String type, int id, Set<String> cells) async {
    final r = await call(() => api.put('$base/availability', body: {
          'subject_type': type,
          'subject_id': id,
          'cells': [
            for (final c in cells) {'day': c.split('|')[0], 'period_id': int.parse(c.split('|')[1])}
          ],
        }), ok: t('تم حفظ الأوقات المتاحة', 'Availability saved'));
    return r != null;
  }

  Future<Map<String, dynamic>?> createSchedule(String name, String? term,
      {DateTime? start, DateTime? end, List<int>? courseIds, List<String>? days}) async {
    String? d(DateTime? x) => x?.toIso8601String().substring(0, 10);
    final r = await call(() => api.post('$base/schedules', body: {
          'name': name,
          if (term != null && term.isNotEmpty) 'term_label': term,
          if (start != null) 'start_date': d(start),
          if (end != null) 'end_date': d(end),
          if (courseIds != null && courseIds.isNotEmpty) 'course_ids': courseIds,
          if (days != null && days.isNotEmpty) 'settings': {'days': days},
        }));
    if (r is Map) await loadSetup();
    return r is Map ? Map<String, dynamic>.from(r) : null;
  }

  Future<bool> deleteSchedule(int id) async {
    final r = await call(() => api.delete('$base/schedules/$id'), ok: t('تم الحذف', 'Deleted'));
    if (r != null) {
      if (schedule?['id'] == id) schedule = null;
      await loadSetup();
    }
    return r != null;
  }

  Future<void> open(int id) async {
    final r = await run(() => api.get('$base/schedules/$id'));
    if (r is Map) _apply(r);
    await validate();
  }

  void closeSchedule() {
    _poll?.dispose();
    _followSeq++;
    genRun = null;
    schedule = null;
    slots = [];
    conflicts = [];
    warnings = [];
    notifyListeners();
  }

  void _apply(Map r) {
    schedule = Map<String, dynamic>.from(r)..remove('items');
    slots = asMapList(r['items']);
    warnings = asMapList(r['warnings']);
    notifyListeners();
  }

  Future<bool> generate({Map<String, dynamic>? settings, bool keepLocked = true, int seed = 7}) async {
    final id = schedule!['id'];
    final r = await call(() => api.post('$base/schedules/$id/generate',
        body: {if (settings != null) 'settings': settings, 'keep_locked': keepLocked, 'seed': seed}));
    if (r is Map) {
      _apply(r);
      await validate();
      await loadSetup();
    }
    return r != null;
  }

  /// GET …/validate `independent`: {hard, by_code, findings} from the clean-room validator (empty on old servers).
  Map<String, dynamic> independent = const {};

  Future<void> validate() async {
    final id = schedule?['id'];
    if (id == null) return;
    final r = await run(() => api.get('$base/schedules/$id/validate'), makLoading: false);
    conflicts = r is Map ? asMapList(r['conflicts']) : [];
    independent = r is Map ? asMap(r['independent']) : const {};
    notifyListeners();
  }

  /// Returns null when saved, or the list of hard conflicts when the server answered 409.
  Future<List<Map<String, dynamic>>?> editSlot(int slotId, Map<String, dynamic> patch, {bool force = false}) =>
      _slotCall(() => api.put('$base/schedules/${schedule!['id']}/slots/$slotId', body: {...patch, if (force) 'force': true}));

  /// Pin / unpin a session (a pinned one is never moved by the generator). True when saved.
  Future<bool> setLocked(int slotId, bool locked) async => await editSlot(slotId, {'locked': locked}) == null;

  /// Change who teaches a session with a scope (course · weekly · once). [dryRun] returns the before / after plan
  /// (ReassignPlan) and writes nothing; otherwise the timetable is reloaded when the server applied it.
  Future<OrgCall> reassignSlot(int slotId, Map<String, dynamic> body, {bool dryRun = false}) async {
    final id = schedule?['id'];
    if (id == null) return const OrgCall(null);
    final r = await orgCall(
        () => api.post('$base/schedules/$id/slots/$slotId/reassign',
            body: {...body, if (!dryRun) 'expected_version': ?schedule?['version']}, queryParams: {if (dryRun) 'dry_run': true}),
        quiet: true);
    if (!dryRun && (r.ok || r.code == 'stale_version')) await open(asInt(id));
    return r;
  }

  /// Drag & drop: the slot shows in its new cell at once and goes back if the server refuses. Sends the version the
  /// user is looking at, so a timetable someone else just changed answers stale_version instead of being overwritten.
  Future<List<Map<String, dynamic>>?> moveSlot(Map<String, dynamic> slot, String day, int periodId, {bool force = false}) async {
    final id = slot['id'];
    final before = slots.firstWhere((x) => x['id'] == id, orElse: () => slot);
    slots = [for (final x in slots) x['id'] == id ? {...x, 'day': day, 'period_id': periodId} : x];
    notifyListeners();
    final res = await _slotCall(() => api.put('$base/schedules/${schedule!['id']}/slots/$id', body: {
          'day': day,
          'period_id': periodId,
          'expected_version': ?schedule!['version'],
          if (force) 'force': true,
        }));
    if (res != null) {
      slots = [for (final x in slots) x['id'] == id ? before : x];
      notifyListeners();
    }
    return res;
  }

  /// Instant check of a session being added / edited (dry_run: nothing is written) → {valid, conflicts}.
  Future<Map<String, dynamic>?> previewSlot(Map<String, dynamic> body, {int? slotId}) async {
    final id = schedule?['id'];
    if (id == null) return null;
    try {
      final r = slotId == null
          ? await api.post('$base/schedules/$id/slots', body: body, queryParams: {'dry_run': true})
          : await api.put('$base/schedules/$id/slots/$slotId', body: body, queryParams: {'dry_run': true});
      return asMap(r);
    } on ApiException {
      return null;
    }
  }

  /// strategy when it clashes: keep · replace · shift (small change) · regenerate (no conflicts left)
  /// [overrideReason] (needs schedule.approve) allows a hard unavailability and leaves a warning; double bookings
  /// can never be overridden.
  Future<List<Map<String, dynamic>>?> addSlot(Map<String, dynamic> body,
          {bool force = false, bool replace = false, String? strategy, String? overrideReason}) =>
      _slotCall(() => api.post('$base/schedules/${schedule!['id']}/slots', body: {
            ...body,
            if (force) 'force': true,
            'override_reason': ?overrideReason,
            if (replace) 'replace_conflicts': true,
            'strategy': ?strategy,
          }));

  // ── special periods (one-off sessions) ──
  List<Map<String, dynamic>> extras = [];

  Future<void> loadExtras() async {
    final id = schedule?['id'];
    if (id == null) return;
    final r = await run(() => api.get('$base/schedules/$id/extras'), makLoading: false);
    extras = r is Map ? asMapList(r['items']) : [];
    notifyListeners();
  }

  /// null = saved; otherwise the clashes the server reported.
  Future<List<Map<String, dynamic>>?> addExtra(Map<String, dynamic> body) async {
    try {
      await api.post('$base/schedules/${schedule!['id']}/extras', body: body);
      await loadExtras();
      toast(t('أُضيفت الفترة وأُبلغ الطلاب والمدرس 📅', 'Added — students and the teacher were notified 📅'));
      return null;
    } on ApiException catch (e) {
      final detail = ApiException.asMap(e.body)?['detail'];
      if (detail is Map && detail['conflicts'] is List) return asMapList(detail['conflicts']);
      toast(e.message, error: true);
      return [<String, dynamic>{'type': 'error'}];
    }
  }

  Future<void> deleteExtra(int id) async {
    final r = await call(() => api.delete('$base/schedules/${schedule!['id']}/extras/$id'),
        ok: t('أُلغيت الفترة وأُبلغ الطلاب', 'Cancelled — students were notified'));
    if (r != null) await loadExtras();
  }

  Future<List<Map<String, dynamic>>?> _slotCall(Future<dynamic> Function() fn) async {
    try {
      await fn();
      await open(asInt(schedule!['id']));
      return null;
    } on ApiException catch (e) {
      if (e.code == 'schedule_conflict') {
        final detail = ApiException.asMap(e.body)?['detail'];
        return asMapList(detail is Map ? detail['conflicts'] : null);
      }
      if (e.code == 'stale_version') {
        toast(orgErrorText(e), error: true);
        await open(asInt(schedule!['id']));
        return [<String, dynamic>{'type': 'error'}];
      }
      toast(e.message, error: true);
      return [<String, dynamic>{'type': 'error'}];
    }
  }

  Future<bool> deleteSlot(int slotId) async {
    final r = await call(() => api.delete('$base/schedules/${schedule!['id']}/slots/$slotId'));
    if (r != null) await open(asInt(schedule!['id']));
    return r != null;
  }

  Future<bool> setActive(bool on) async {
    final id = schedule!['id'];
    try {
      final r = await api.post('$base/schedules/$id/${on ? 'activate' : 'deactivate'}');
      toast(on ? t('تم نشر الجدول للجميع', 'Timetable published') : t('تم إيقاف النشر', 'Unpublished'));
      if (r is Map) _apply({...r, 'items': slots});
      await loadSetup();
      if (!on) {
        // back to a plain Draft: fresh slots / result / conflicts and no leftover run, so Create and Publish work again
        genRun = null;
        await open(asInt(id));
        await resumeRunIfAny();
      }
      return true;
    } on ApiException catch (e) {
      toast(e.message, error: true);
      return false;
    }
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Teacher / student side
// ═════════════════════════════════════════════════════════════════════════════

class OrgMembershipProvider extends AdminBase {
  List<Map<String, dynamic>> mine = [], results = [], courses = [], timetables = [];
  bool loaded = false;

  Future<void> loadMine() async {
    final r = await run(() => api.get('$orgBase/public/mine'), makLoading: false);
    mine = r is Map ? asMapList(r['items']) : [];
    loaded = true;
    notifyListeners();
  }

  Future<void> search(String q) async {
    final r = await run(() => api.get('$orgBase/public/search', queryParams: {if (q.isNotEmpty) 'q': q, 'size': 30}),
        makLoading: false);
    results = r is Map ? asMapList(r['items']) : [];
    notifyListeners();
  }

  /// → 'active' | 'pending' | null (failed; the reason was toasted)
  Future<String?> join({int? orgId, String? code}) async {
    try {
      // a code goes through the one-box endpoint: organization codes (role / department defaults), the legacy
      // organization code and department codes all work there
      final r = code != null
          ? await api.post('$orgBase/public/join/code', body: {'code': code})
          : await api.post('$orgBase/public/join', body: {'org_id': ?orgId});
      await loadMine();
      if (r is Map && r['kind'] == 'unit') {
        if (r['needs_form'] == true) {
          toast(t('هذا كود قسم له نموذج — افتحه من صفحة المؤسسة ← الأقسام', 'This department code has a form — open it from the organization page → Departments'));
          return null;
        }
        return r['joined'] == true ? 'active' : 'pending';
      }
      return r is Map ? r['status']?.toString() : null;
    } on ApiException catch (e) {
      // membership_ended: only this organization's membership is over — the account keeps working
      toast(orgErrorText(e), error: true);
      return e.code == 'code_required' ? 'code_required' : null;
    }
  }

  Future<bool> leave(int orgId) async {
    final r = await call(() => api.delete('$orgBase/public/$orgId/leave'), ok: t('تم الخروج من المؤسسة', 'Left the organization'));
    if (r != null) await loadMine();
    return r != null;
  }

  Future<void> loadCourses(int orgId, {String? search}) async {
    final r = await run(() => api.get('$orgBase/public/$orgId/courses', queryParams: {'size': 50, if (search != null && search.isNotEmpty) 'search': search}));
    courses = r is Map ? asMapList(r['items']) : [];
    notifyListeners();
  }

  Future<void> loadTimetable({int? orgId}) async {
    // hard timeout: the page ends in data, empty or an error with retry — never an endless spinner
    final r = await run(() => api
        .get('$orgBase/public/schedule/me', queryParams: {if (orgId != null) 'org_id': orgId})
        .timeout(const Duration(seconds: 20)));
    if (!hasError) timetables = r is Map ? asMapList(r['items']) : [];
    notifyListeners();
  }
}


// ═════════════════════════════════════════════════════════════════════════════
//  v2 generic helpers — used by departments · services · roles · member space · platform review
// ═════════════════════════════════════════════════════════════════════════════

/// Any paged list of the v2 API: `OrgPaged('${session.base}/complaints', {'status': 'active'})`.
/// The server's extra keys (stats, folders, form …) are in [extra].
class OrgPaged extends AdminPagedProvider {
  OrgPaged(this._path, [Map<String, dynamic>? filters]) : _filters = {...?filters};
  final String _path;
  final Map<String, dynamic> _filters;

  @override
  String get path => _path;

  @override
  Map<String, dynamic> get filters => _filters;

  Future<void> setFilter(String key, Object? value) {
    if (value == null || '$value'.isEmpty) {
      _filters.remove(key);
    } else {
      _filters[key] = value;
    }
    return refresh();
  }

  /// Replaces one row in place after a mutation (no reload, no scroll jump).
  void replaceRow(Map<String, dynamic> row) {
    final i = rows.indexWhere((r) => r['id'] == row['id']);
    if (i >= 0) {
      rows[i] = row;
      notifyListeners();
    }
  }
}

/// Thin mutation helper with the app's toasts: `final r = await OrgApi.i.post(url, body, ok: '…')`.
/// Returns the decoded body (or true) on success, null on failure (the server message was toasted).
class OrgApi extends AdminBase {
  OrgApi._();
  static final OrgApi i = OrgApi._();

  Future<Map<String, dynamic>?> getMap(String path, [Map<String, dynamic>? query]) async {
    try {
      final r = await api.get(path, queryParams: query);
      return r is Map ? Map<String, dynamic>.from(r) : null;
    } on ApiException catch (e) {
      toast(e.message, error: true);
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<dynamic> post(String path, [Map<String, dynamic>? body, String? ok]) =>
      call(() => api.post(path, body: body ?? const {}), ok: ok);

  Future<dynamic> put(String path, Map<String, dynamic> body, [String? ok]) => call(() => api.put(path, body: body), ok: ok);

  Future<dynamic> del(String path, [String? ok]) => call(() => api.delete(path), ok: ok);
}

String roomKindLabel(String k) =>
    {
      'lecture': t('قاعة محاضرات', 'Lecture room'),
      'lab': t('معمل', 'Lab'),
      'hall': t('مدرج', 'Hall'),
      'office': t('مكتب', 'Office'),
      'other': t('أخرى', 'Other'),
    }[k] ??
    k;

// ═════════════════════════════════════════════════════════════════════════════
//  Org-admin dashboard: GET …/dashboard → OrgHomeData (D-062)
// ═════════════════════════════════════════════════════════════════════════════

/// The org-admin home's one call. The last payload of every organization is kept, so switching back redraws at
/// once while the fresh one loads; it reloads on open ([ensure]), resume, pull ([load]) and on the live event
/// `attention_changed{org_id}`. [attentionEpoch] counts the changes of this organization's attention items in
/// GET /me/attention: a caller that pushed a page (a department dashboard) compares it on return and reloads
/// only when something changed — never after every visit.
class OrgDashController extends ChangeNotifier with WidgetsBindingObserver {
  OrgHomeData? data;
  bool failed = false;
  String? error;
  int attentionEpoch = 0;

  /// When the payload on screen arrived (the header's "Updated …").
  DateTime? loadedAt;

  /// "Needs your attention" (D-103 `tasks`): Home's rows and the one-tap decisions' optimistic state, shared with
  /// the full list (OrgTasksPage) so a row decided there is gone here too.
  final OrgTaskQueue tasks = OrgTaskQueue();

  /// How long a resume / live event may be after the last load before it counts (the in-flight load is shared).
  static const minGap = Duration(seconds: 10);

  String? _key;
  OrgSession? _session;
  final Map<int, OrgHomeData> _cache = {};
  Future<void>? _running;
  DateTime? _last;
  StreamSubscription<LiveEvent>? _live;
  String _fingerprint = '';
  bool _attached = false;

  int count(String key) => data?.count(key) ?? 0;

  /// Listen for resume and live events while the dashboard is on screen (the screen's initState / dispose).
  void attach() {
    if (_attached) return;
    _attached = true;
    WidgetsBinding.instance.addObserver(this);
    _live = LiveEvents.instance.listen({LiveEvents.attentionChanged}, _onLiveEvent);
    AttentionService.instance.addListener(_onFeed);
  }

  void detach() {
    if (!_attached) return;
    _attached = false;
    WidgetsBinding.instance.removeObserver(this);
    _live?.cancel();
    _live = null;
    AttentionService.instance.removeListener(_onFeed);
  }

  /// Called from the screen's build: a new organization (or epoch) starts a load; the cached payload shows meanwhile.
  void ensure(OrgSession s) {
    _session = s;
    final k = '${s.currentId}-${s.epoch.value}';
    if (k == _key || s.currentId == null) return;
    _key = k;
    data = _cache[s.currentId];
    _applyTasks();
    failed = false;
    error = null;
    _fingerprint = _feedFingerprint(s.currentId!);
    WidgetsBinding.instance.addPostFrameCallback((_) => load(s));
  }

  Future<void> load([OrgSession? session]) {
    final s = session ?? _session;
    if (s == null || s.currentId == null) return Future.value();
    _session = s;
    return _running ??= _load(s).whenComplete(() => _running = null);
  }

  /// A quiet reload (resume, live event): skipped when the last one is recent.
  Future<void> refreshQuiet() {
    if (_last != null && DateTime.now().difference(_last!) < minGap) return Future.value();
    return load();
  }

  Future<void> _load(OrgSession s) async {
    final want = _key;
    final id = s.currentId!;
    _last = DateTime.now();
    try {
      final r = await ApiClient().get('${s.base}/dashboard');
      if (want != _key) return;               // the organization changed meanwhile
      final d = OrgHomeData.fromJson(r);
      if (d != null) {
        data = d;
        _cache[id] = d;
        loadedAt = DateTime.now();
        _applyTasks();
      }
      failed = data == null;
      error = null;
    } catch (e) {
      if (want != _key) return;
      failed = data == null;
      error = ApiException.from(e).message;
    }
    notifyListeners();
  }

  void _applyTasks() {
    final d = data;
    tasks.apply(d?.tasks ?? const [], d?.tasksTotal ?? 0);
  }

  /// A one-tap decision: POST …/tasks/{task_id}/{action} {reason?, version?}. The row leaves at once
  /// ([OrgTaskQueue.begin]); a failure brings it back with a message, 409 `already_decided` / 404 `task_not_found`
  /// keep it gone. Returns the outcome and the text for the notice (the caller shows it).
  Future<(OrgTaskOutcome, String)> decide(OrgSession s, OrgTask task, OrgTaskAction action, {String? reason}) async {
    if (!tasks.begin(task.id)) return (OrgTaskOutcome.done, '');
    try {
      await ApiClient().post('${s.base}/tasks/${Uri.encodeComponent(task.id)}/${action.id}', body: {
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
        if (task.version != null) 'version': task.version,
      });
      tasks.settle(task.id, OrgTaskOutcome.done);
      _afterDecision();
      return (OrgTaskOutcome.done, action.doneText);
    } catch (e) {
      final err = ApiException.from(e);
      final outcome = orgTaskOutcome(err.statusCode, err.code);
      if (outcome == OrgTaskOutcome.handled) {
        tasks.settle(task.id, outcome);
        _afterDecision();
        return (outcome, t('شخص آخر تولّى هذا الطلب بالفعل', 'Someone already handled this'));
      }
      final msg = err.code != null ? orgErrorText(err) : err.message;
      tasks.settle(task.id, outcome, message: msg);
      return (outcome, msg);
    }
  }

  /// The server emits `attention_changed` after a decision; this only makes sure the counts follow even without
  /// the live stream (a quiet reload, skipped when one ran a moment ago).
  void _afterDecision() => Future<void>.delayed(const Duration(seconds: 2), refreshQuiet);

  void _onLiveEvent(LiveEvent e) {
    final id = _session?.currentId;
    if (id == null) return;
    if (e.orgId == null || e.orgId == id) refreshQuiet();
  }

  void _onFeed() {
    final id = _session?.currentId;
    if (id == null) return;
    final f = _feedFingerprint(id);
    if (f == _fingerprint) return;
    _fingerprint = f;
    attentionEpoch++;
    final armed = _armedUntil;
    if (armed != null) {
      _armedUntil = null;
      if (DateTime.now().isBefore(armed)) load();
    }
  }

  DateTime? _armedUntil;

  /// Back from a pushed page (a department dashboard): reload when the attention items changed since
  /// [epochBefore]; otherwise the feed's own refresh (the route observer asks for one) decides within 30 s —
  /// the home reloads only when THAT changes something, never after every visit.
  void afterReturn(int epochBefore) {
    if (attentionEpoch != epochBefore) {
      load();
      return;
    }
    _armedUntil = DateTime.now().add(const Duration(seconds: 30));
  }

  /// `tab/key/kind=count` of every item of this organization, in the feed's order.
  static String _feedFingerprint(int orgId) {
    final b = StringBuffer();
    for (final tab in AttentionTabs.orgSection.values) {
      for (final x in AttentionService.instance.items(tab, orgId: orgId)) {
        b.write('${x.tab}/${x.key}/${x.kind}=${x.count};');
      }
    }
    return b.toString();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refreshQuiet();
  }

  @override
  void dispose() {
    detach();
    tasks.dispose();
    super.dispose();
  }
}
