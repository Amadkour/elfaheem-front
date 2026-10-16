// lib/features/parent/parent_link_providers.dart
// Providers for: student link code · parent link/children · parent reports · admin parent-link.
// All extend the project's BaseProvider (run() turns ApiException into errorMessage).
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/base_provider.dart';

import 'parent_widgets.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  STUDENT — generate / show the link code
// ═════════════════════════════════════════════════════════════════════════════
class StudentLinkProvider extends BaseProvider {
  StudentLinkProvider({ApiClient? api}) : _api = api ?? ApiClient();
  final ApiClient _api;

  /// The plain code only exists right after generating (the server stores a hash).
  String? code;
  DateTime? expiresAt;
  bool hasActive = false;
  List<Map<String, dynamic>> parents = [];

  int get secondsLeft {
    if (expiresAt == null) return 0;
    final s = expiresAt!.difference(DateTime.now().toUtc()).inSeconds;
    return s < 0 ? 0 : s;
  }

  bool get codeVisible => code != null && secondsLeft > 0;

  Future<void> load() async {
    final a = await run(() => _api.get('/api/v1/student/parent-link/code'));
    if (a is Map) {
      hasActive = a['active'] == true;
      if (hasActive) {
        expiresAt = DateTime.tryParse('${a['expires_at']}')?.toUtc();
      } else {
        code = null;
        expiresAt = null;
      }
    }
    final p = await run(() => _api.get('/api/v1/student/parent-link/parents'), makLoading: false);
    if (p != null) parents = plList(p);
    notifyListeners();
  }

  Future<bool> generate() async {
    final r = await run(() => _api.post('/api/v1/student/parent-link/code', body: {}));
    if (r is! Map) return false;
    code = '${r['code']}';
    expiresAt = DateTime.tryParse('${r['expires_at']}')?.toUtc();
    hasActive = true;
    notifyListeners();
    return true;
  }

  Future<bool> unlink(int linkId) async {
    final r = await run(() => _api.delete('/api/v1/student/parent-link/parents/$linkId'));
    if (r == null) return false;
    parents.removeWhere((e) => e['link_id'] == linkId);
    notifyListeners();
    return true;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  PARENT — link, requests, children
// ═════════════════════════════════════════════════════════════════════════════
class ParentLinkProvider extends BaseProvider {
  ParentLinkProvider({ApiClient? api}) : _api = api ?? ApiClient();
  final ApiClient _api;

  Map<String, dynamic> config = {};
  List<Map<String, dynamic>> requests = [];
  List<Map<String, dynamic>> children = [];

  String get mode => '${config['mode'] ?? 'easy'}';
  List<Map<String, dynamic>> get fields => plList(config['fields']);
  List<Map<String, dynamic>> get documents => plList(config['documents']);
  int get pendingCount => requests.where((r) => r['status'] == 'pending').length;

  Future<void> loadAll() async {
    final c = await run(() => _api.get('/api/v1/parent/link/config'));
    if (c is Map) config = Map<String, dynamic>.from(c);
    final r = await run(() => _api.get('/api/v1/parent/link/requests'), makLoading: false);
    if (r != null) requests = plList(r);
    final ch = await run(() => _api.get('/api/v1/parent/children'), makLoading: false);
    if (ch != null) children = plList(ch);
    notifyListeners();
  }

  Future<void> refreshChildrenAndRequests() async {
    final r = await run(() => _api.get('/api/v1/parent/link/requests'), makLoading: false);
    if (r != null) requests = plList(r);
    final ch = await run(() => _api.get('/api/v1/parent/children'), makLoading: false);
    if (ch != null) children = plList(ch);
    notifyListeners();
  }

  /// Returns the request (status approved | pending) or null (errorMessage holds the reason).
  Future<Map<String, dynamic>?> redeem(
      String code,
      Map<String, String> fieldValues,
      Map<String, PlatformFile> docs,
      ) async {
    final res = await run(() async {
      if (mode != 'advanced') {
        return await _api.post('/api/v1/parent/link/redeem',
            body: {'code': code, 'fields': fieldValues});
      }
      final form = FormData();
      form.fields
        ..add(MapEntry('code', code))
        ..add(MapEntry('fields', jsonEncode(fieldValues)));
      for (final e in docs.entries) {
        // file_picker v12+: bytes are read from the PlatformFile (no `withData`).
        List<int>? bytes;
        try {
          bytes = await e.value.readAsBytes();
        } catch (_) {
          bytes = null;
        }
        if (bytes == null) continue;
        form.files.add(MapEntry('doc_${e.key}', MultipartFile.fromBytes(bytes, filename: e.value.name)));
      }
      try {
        final r = await _api.dio.post('/api/v1/parent/link/redeem-docs', data: form);
        return r.data;
      } on DioException catch (e) {
        throw ApiException.from(e);
      }
    });
    if (res is! Map) return null;
    await refreshChildrenAndRequests();
    return Map<String, dynamic>.from(res);
  }

  Future<bool> cancel(int id) async {
    final r = await run(() => _api.post('/api/v1/parent/link/requests/$id/cancel', body: {}));
    if (r == null) return false;
    await refreshChildrenAndRequests();
    return true;
  }

  void reset() {
    config = {};
    requests = [];
    children = [];
    notifyListeners();
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  PARENT — reports of ALL children (daily + weekly + monthly in one call)
// ═════════════════════════════════════════════════════════════════════════════
class ParentReportsProvider extends BaseProvider {
  ParentReportsProvider({ApiClient? api}) : _api = api ?? ApiClient();
  final ApiClient _api;

  List<Map<String, dynamic>> children = [];
  DateTime refDate = DateTime.now();
  bool loaded = false;

  Future<void> load() async {
    final r = await run(() => _api.get('/api/v1/parent/reports',
        queryParams: {'period': 'all', 'date': plDate(refDate)}));
    if (r is Map) {
      children = plList(r['children']);
      loaded = true;
      notifyListeners();
    }
  }

  /// One child only: daily + weekly + monthly of /children/{id}/report.
  int? onlyStudentId;
  String onlyStudentName = '';

  Future<void> loadOne(int studentId, String name) async {
    onlyStudentId = studentId;
    onlyStudentName = name;
    final r = await run(() => _api.get('/api/v1/parent/children/$studentId/report',
        queryParams: {'period': 'all', 'date': plDate(refDate)}));
    if (r is Map) {
      children = [
        {
          'student': {'id': studentId, 'name': name},
          ...Map<String, dynamic>.from(r),
        }
      ];
      loaded = true;
      notifyListeners();
    }
  }

  Future<void> reload() => onlyStudentId == null ? load() : loadOne(onlyStudentId!, onlyStudentName);

  Future<void> setDate(DateTime d) async {
    refDate = d;
    await reload();
  }

  void reset() {
    children = [];
    loaded = false;
    notifyListeners();
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  PARENT — alert flags (priority, then newest first; read / dismiss state kept on the server)
// ═════════════════════════════════════════════════════════════════════════════
class ParentAlertsProvider extends BaseProvider {
  ParentAlertsProvider({ApiClient? api}) : _api = api ?? ApiClient();
  final ApiClient _api;

  List<Map<String, dynamic>> items = [];
  Map<String, int> counts = {'high': 0, 'medium': 0, 'low': 0};
  int unread = 0, unreadHigh = 0;
  bool loaded = false;

  // filters
  String sort = 'priority'; // priority | date
  String priority = ''; // '' = all | high | medium | low
  int? childId;
  bool showDismissed = false;
  int days = 30;

  List<Map<String, dynamic>> get visible =>
      priority.isEmpty ? items : items.where((a) => a['priority'] == priority).toList();

  Future<void> load({bool silent = false}) async {
    final r = await run(
          () => _api.get('/api/v1/parent/alerts', queryParams: {
        'sort': sort,
        'days': days,
        if (childId != null) 'child_id': childId,
        if (showDismissed) 'include_dismissed': 'true',
      }),
      makLoading: !silent && !loaded,
    );
    if (r is! Map) return;
    items = plList(r['items']);
    loaded = true;
    _recount();
    notifyListeners();
  }

  void _recount() {
    final live = items.where((a) => a['status'] != 'dismissed');
    counts = {for (final p in ['high', 'medium', 'low']) p: live.where((a) => a['priority'] == p).length};
    final un = items.where((a) => a['unread'] == true);
    unread = un.length;
    unreadHigh = un.where((a) => a['priority'] == 'high').length;
  }

  /// Optimistic update, then the server; reloads if the call fails.
  Future<void> setStatus(List<String> keys, String status) async {
    for (final a in items) {
      if (!keys.contains(a['key'])) continue;
      a['status'] = status == 'unread' ? 'unread' : status;
      a['unread'] = status == 'unread';
    }
    if (status == 'dismissed' && !showDismissed) {
      items.removeWhere((a) => keys.contains(a['key']));
    }
    _recount();
    notifyListeners();
    final r = await run(
            () => _api.post('/api/v1/parent/alerts/state', body: {'keys': keys, 'status': status}),
        makLoading: false);
    if (r == null) await load(silent: true);
  }

  Future<void> readAll() async {
    final keys = [for (final a in visible) if (a['unread'] == true) '${a['key']}'];
    if (keys.isEmpty) return;
    await setStatus(keys, 'read');
  }

  void setSort(String v) {
    sort = v;
    load(silent: true);
  }

  void setPriority(String v) {
    priority = priority == v ? '' : v;
    notifyListeners();
  }

  void setChild(int? id) {
    childId = id;
    load(silent: true);
  }

  void toggleDismissed() {
    showDismissed = !showDismissed;
    load(silent: true);
  }

  void reset() {
    items = [];
    loaded = false;
    unread = unreadHigh = 0;
    notifyListeners();
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  ADMIN — settings (super-admin) + requests
// ═════════════════════════════════════════════════════════════════════════════
class AdminParentLinkProvider extends BaseProvider {
  AdminParentLinkProvider({ApiClient? api}) : _api = api ?? ApiClient();
  final ApiClient _api;

  Map<String, dynamic> settings = {};

  Future<bool> loadSettings() async {
    final r = await run(() => _api.get('/api/v1/admin/parent-link/settings'));
    if (r is! Map) return false;
    settings = Map<String, dynamic>.from(r);
    notifyListeners();
    return true;
  }

  Future<bool> saveSettings(Map<String, dynamic> body) async {
    final r = await run(() => _api.put('/api/v1/admin/parent-link/settings', body: body));
    if (r is! Map) return false;
    settings = Map<String, dynamic>.from(r);
    notifyListeners();
    return true;
  }

  // requests list ----------------------------------------------------------
  List<Map<String, dynamic>> items = [];
  String status = 'pending';
  String mode = '';
  String search = '';
  int page = 1, pages = 1, pendingTotal = 0;
  bool loadingMore = false;

  Future<void> loadRequests({bool reset = true}) async {
    if (reset) page = 1;
    final r = await run(
          () => _api.get('/api/v1/admin/parent-link/requests', queryParams: {
        if (status.isNotEmpty) 'status': status,
        if (mode.isNotEmpty) 'mode': mode,
        if (search.trim().isNotEmpty) 'search': search.trim(),
        'page': page,
        'size': 20,
      }),
      makLoading: reset,
    );
    if (r is! Map) return;
    final list = plList(r['items']);
    items = reset ? list : [...items, ...list];
    pages = (r['pages'] as num?)?.toInt() ?? 1;
    pendingTotal = (r['pending_count'] as num?)?.toInt() ?? 0;
    notifyListeners();
  }

  Future<void> loadMore() async {
    if (loadingMore || page >= pages) return;
    loadingMore = true;
    page++;
    await loadRequests(reset: false);
    loadingMore = false;
    notifyListeners();
  }

  void setFilter({String? status, String? mode}) {
    if (status != null) this.status = status;
    if (mode != null) this.mode = mode;
    loadRequests();
  }

  Future<Map<String, dynamic>?> detail(int id) async {
    final r = await run(() => _api.get('/api/v1/admin/parent-link/requests/$id'));
    return r is Map ? Map<String, dynamic>.from(r) : null;
  }

  Future<Map<String, dynamic>?> decide(int id, {required bool approve, String note = ''}) async {
    final r = await run(() => _api.post(
        '/api/v1/admin/parent-link/requests/$id/${approve ? 'approve' : 'reject'}',
        body: {'note': note}));
    if (r is! Map) return null;
    await loadRequests();
    return Map<String, dynamic>.from(r);
  }

  /// {path, file_name, file_type} — path is relative to the API base URL.
  Future<Map<String, dynamic>?> documentLink(int docId) async {
    final r = await run(() => _api.get('/api/v1/admin/parent-link/documents/$docId/link'),
        makLoading: false);
    return r is Map ? Map<String, dynamic>.from(r) : null;
  }

  String absoluteUrl(String path) => '${_api.baseUrl}$path';
}