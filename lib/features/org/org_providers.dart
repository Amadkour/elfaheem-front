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

import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_education_app/core/api_client.dart';

import '../admin/admin_common.dart';
import '../admin/admin_providers.dart';

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
    notifyListeners();
  }

  void select(int id) {
    if (id == currentId) return;
    currentId = id;
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

  Future<void> loadSetup() async {
    final rs = await Future.wait([
      run(() => api.get('$base/periods'), makLoading: false),
      run(() => api.get('$base/rooms'), makLoading: false),
      run(() => api.get('$base/loads'), makLoading: false),
      run(() => api.get('$base/schedules'), makLoading: false),
      run(() => api.get('$orgBase/orgs/${session.currentId}/members',
          queryParams: {'role': 'teacher,teacher_assistant,admin_assistant', 'size': 100}), makLoading: false),
    ]);
    List<Map<String, dynamic>> items(dynamic r) => r is Map ? asMapList(r['items']) : [];
    periods = items(rs[0]);
    rooms = items(rs[1]);
    loads = items(rs[2]);
    schedules = items(rs[3]);
    staff = items(rs[4]);
    loaded = true;
    notifyListeners();
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

  Future<Map<String, dynamic>?> createSchedule(String name, String? term) async {
    final r = await call(() => api.post('$base/schedules', body: {'name': name, if (term != null && term.isNotEmpty) 'term_label': term}));
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

  Future<void> validate() async {
    final id = schedule?['id'];
    if (id == null) return;
    final r = await run(() => api.get('$base/schedules/$id/validate'), makLoading: false);
    conflicts = r is Map ? asMapList(r['conflicts']) : [];
    notifyListeners();
  }

  /// Returns null when saved, or the list of hard conflicts when the server answered 409.
  Future<List<Map<String, dynamic>>?> editSlot(int slotId, Map<String, dynamic> patch, {bool force = false}) =>
      _slotCall(() => api.put('$base/schedules/${schedule!['id']}/slots/$slotId', body: {...patch, if (force) 'force': true}));

  Future<List<Map<String, dynamic>>?> addSlot(Map<String, dynamic> body, {bool force = false, bool replace = false}) =>
      _slotCall(() => api.post('$base/schedules/${schedule!['id']}/slots',
          body: {...body, if (force) 'force': true, if (replace) 'replace_conflicts': true}));

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
      final r = await api.post('$orgBase/public/join', body: {if (orgId != null) 'org_id': orgId, if (code != null) 'code': code});
      await loadMine();
      return r is Map ? r['status']?.toString() : null;
    } on ApiException catch (e) {
      toast(e.message, error: true);
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
    final r = await run(() => api.get('$orgBase/public/schedule/me', queryParams: {if (orgId != null) 'org_id': orgId}));
    timetables = r is Map ? asMapList(r['items']) : [];
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
