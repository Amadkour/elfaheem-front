// lib/features/org/org_providers.dart
//
// Organization state.
//   OrgSession            global (register in core/providers.dart) — which organizations I manage, the selected one,
//                         my role + admin-assistant permissions there  → drives the switcher and hides forbidden buttons
//   OrgMembersProvider    paged members (students | teachers | staff)     — created locally by the page
//   OrgCoursesProvider    paged organization courses                      — created locally by the page
//   OrgScheduleProvider   periods · rooms · availability · loads · schedules · slots — created locally by the schedule tab
//   OrgMembershipProvider teacher / student side: search · join · my organizations · org courses · my timetable
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_education_app/core/api_client.dart';

import '../admin/admin_common.dart';
import '../admin/admin_providers.dart';
import 'org_platform_context.dart';
import 'org_v3.dart';

const orgBase = '/api/v1/org';

// ═════════════════════════════════════════════════════════════════════════════
//  Session (global)
// ═════════════════════════════════════════════════════════════════════════════

class OrgSession extends AdminBase {
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

  Future<void> load({bool keepSelection = true}) async {
    final r = await run(() => api.get('$orgBase/mine'));
    if (r is Map) {
      items = asMapList(r['items']);
      canCreateRoot = r['can_create_root'] == true;
      if (!keepSelection || !items.any((o) => o['id'] == currentId)) {
        currentId = items.isEmpty ? null : asInt(items.first['id']);
      }
    }
    loaded = true;
    OrgPlatformContext.open(approved ? currentId : null);   // org timezone / 12h-24h + org feature offs
    notifyListeners();
  }

  void select(int id) {
    if (id == currentId) return;
    currentId = id;
    OrgPlatformContext.open(approved ? id : null);
    epoch.value++;
    notifyListeners();
  }

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

  Future<String?> regenerateCode() async {
    final r = await call(() => api.post('$base/join-code/regenerate'));
    if (r is Map) {
      await load();
      return r['join_code']?.toString();
    }
    return null;
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
    final r = await call(() => api.post(path, body: body), ok: t('تمت الإضافة', 'Added'));
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
  Map<String, dynamic>? genRun;      // the run being followed (queued / running / just finished)
  Timer? _poll;
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
    _poll?.cancel();
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

  void _follow(int scheduleId, int runId) {
    _poll?.cancel();
    var misses = 0;
    final until = DateTime.now().add(const Duration(minutes: 4)); // the server's budget is 90 s; never follow forever
    _poll = Timer.periodic(const Duration(seconds: 2), (tm) async {
      final r = await orgCall(() => api.get('$base/schedules/$scheduleId/runs/$runId'), quiet: true);
      if (_disposed) return tm.cancel();
      final lost = !r.ok && (++misses >= 5 || r.endpointMissing || r.error?.statusCode == 404);
      if (lost || (r.ok && runIsOpen(r.map) && DateTime.now().isAfter(until))) {
        tm.cancel();
        genRun = {...?genRun, 'status': 'failed', 'error': t('انقطعت متابعة التوليد — أعد فتح الجدول', 'Lost track of the generation — reopen the timetable')};
        notifyListeners();
        return;
      }
      if (!r.ok) return;           // transient: keep following a few more times
      misses = 0;
      genRun = r.map;
      notifyListeners();
      if (!runIsOpen(genRun)) {
        tm.cancel();
        if (schedule?['id'] == scheduleId) await open(scheduleId);   // slots + result as stored by the server
        await loadSetup();
      }
    });
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

  Future<OrgCall> cancelGeneration() async {
    final run = genRun;
    if (run == null || schedule == null) return const OrgCall(null);
    final r = await orgCall(() => api.post('$base/schedules/${schedule!['id']}/runs/${run['id']}/cancel'));
    if (r.ok) {
      genRun = r.map;
      notifyListeners();
    }
    return r;
  }

  /// When a studio is opened, a run that is still going on the server is picked up again.
  Future<void> resumeRunIfAny() async {
    final id = schedule?['id'];
    if (id == null) return;
    final r = await orgCall(() => api.get('$base/schedules/$id/runs'), quiet: true);
    final runs = asMapList(r.map['items']);
    genRun = runs.isEmpty ? null : runs.first;
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
