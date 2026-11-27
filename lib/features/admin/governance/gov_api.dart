// lib/features/admin/governance/gov_api.dart
//
// The platform admins' governance (docs/redesign/api/governance.md): the course publish-review queue, the admin
// audit log and the admin roles editor. Plain models parsed from the server's JSON, and the calls.
//
//   GET  /api/v1/admin/publish-queue?status&page&size · POST /{course_id}/approve · /{course_id}/reject {reason}
//   GET|PUT /api/v1/admin/publish-queue/settings {require_review}
//   GET  /api/v1/admin/audit-log?actor_id&action&q&date_from&date_to&ok&page&size · GET /audit-log/facets
//   GET  /api/v1/admin/roles · POST · PUT /{id} · DELETE /{id} · PUT /roles/assignments/{user_id} · GET /roles/me
//
// Kill switches: admin.publish_queue, admin.audit_log, admin.roles. Live event `course_review` {course_id, status}.
library;

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';

const kPublishQueueKey = 'admin.publish_queue';
const kAuditLogKey = 'admin.audit_log';
const kAdminRolesKey = 'admin.roles';

/// The live event a review decision (or a new submission) sends.
const kCourseReviewEvent = 'course_review';

String _s(dynamic v) => v == null ? '' : '$v';
int? _i(dynamic v) => v is int ? v : (v is num ? v.toInt() : int.tryParse(_s(v)));
DateTime? _d(dynamic v) => v == null ? null : DateTime.tryParse('$v')?.toUtc();
Map<String, dynamic> _m(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Map<String, dynamic>> _l(dynamic v) => [if (v is List) for (final e in v) if (e is Map) Map<String, dynamic>.from(e)];

/// The name in the app's language, falling back to the other one.
String govName(String? ar, String? en) {
  final a = (ar ?? '').trim(), e = (en ?? '').trim();
  return AppConfig.lang == 'ar' ? (a.isNotEmpty ? a : e) : (e.isNotEmpty ? e : a);
}

// ── publish review ────────────────────────────────────────────────────────────

class PublishItem {
  const PublishItem({
    required this.courseId,
    required this.name,
    this.teacherName = '',
    this.imageUrl,
    this.status = 'pending_review',
    this.reason,
    this.submittedAt,
    this.decidedAt,
  });

  factory PublishItem.fromJson(Map<String, dynamic> j) => PublishItem(
        courseId: _i(j['course_id']) ?? 0,
        name: govName(j['name_ar'] as String?, j['name_en'] as String?),
        teacherName: _s(_m(j['teacher'])['name']),
        imageUrl: (j['image_url'] as String?)?.trim().isEmpty ?? true ? null : j['image_url'] as String,
        status: _s(j['review_status']),
        reason: j['review_reason'] as String?,
        submittedAt: _d(j['submitted_at']),
        decidedAt: _d(j['decided_at']),
      );

  final int courseId;
  final String name, teacherName, status;
  final String? imageUrl, reason;
  final DateTime? submittedAt, decidedAt;
}

class PublishPage {
  const PublishPage(this.items, this.total, this.hasMore, this.requireReview);

  final List<PublishItem> items;
  final int total;
  final bool hasMore, requireReview;
}

class GovApi {
  GovApi([ApiClient? api]) : _api = api ?? ApiClient.instance;

  final ApiClient _api;

  Future<PublishPage> queue({String status = 'pending_review', int page = 1, int size = 20}) async {
    final j = _m(await _api.get('/api/v1/admin/publish-queue', queryParams: {'status': status, 'page': page, 'size': size}));
    return PublishPage([for (final e in _l(j['items'])) PublishItem.fromJson(e)], _i(j['total']) ?? 0,
        j['has_more'] == true, j['require_review'] == true);
  }

  Future<bool> requireReview() async =>
      _m(await _api.get('/api/v1/admin/publish-queue/settings'))['require_review'] == true;

  Future<bool> setRequireReview(bool on) async =>
      _m(await _api.put('/api/v1/admin/publish-queue/settings', body: {'require_review': on}))['require_review'] == true;

  Future<void> approve(int courseId) => _api.post('/api/v1/admin/publish-queue/$courseId/approve');

  Future<void> reject(int courseId, String reason) =>
      _api.post('/api/v1/admin/publish-queue/$courseId/reject', body: {'reason': reason});

  // ── audit log ──

  Future<AuditPage> audit(AuditFilter f, {int page = 1, int size = 50}) async {
    final j = _m(await _api.get('/api/v1/admin/audit-log', queryParams: {...f.query(), 'page': page, 'size': size}));
    return AuditPage([for (final e in _l(j['items'])) AuditRow.fromJson(e)], _i(j['total']) ?? 0, j['has_more'] == true);
  }

  Future<AuditFacets> facets() async {
    final j = _m(await _api.get('/api/v1/admin/audit-log/facets'));
    return AuditFacets(
      actors: [for (final a in _l(j['actors'])) (id: _i(a['id']) ?? 0, name: _s(a['name']))],
      actions: [for (final a in _l(j['actions'])) _s(a['action'])],
    );
  }

  // ── roles ──

  Future<RolesOverview> roles() async => RolesOverview.fromJson(_m(await _api.get('/api/v1/admin/roles')));

  Future<void> createRole(String nameAr, String nameEn, List<String> perms) =>
      _api.post('/api/v1/admin/roles', body: {'name_ar': nameAr, 'name_en': nameEn, 'permissions': perms});

  Future<void> updateRole(int id, String nameAr, String nameEn, List<String> perms) =>
      _api.put('/api/v1/admin/roles/$id', body: {'name_ar': nameAr, 'name_en': nameEn, 'permissions': perms});

  Future<void> deleteRole(int id) => _api.delete('/api/v1/admin/roles/$id');

  Future<void> assign(int userId, int? roleId) =>
      _api.put('/api/v1/admin/roles/assignments/$userId', body: {'role_id': roleId});
}

// ── audit log ─────────────────────────────────────────────────────────────────

class AuditFilter {
  const AuditFilter({this.actorId, this.action, this.from, this.to});

  final int? actorId;
  final String? action;

  /// Local calendar days (sent as yyyy-mm-dd; the server takes a bare `date_to` as that whole day).
  final DateTime? from, to;

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> query() => {
        if (actorId != null) 'actor_id': actorId,
        if (action != null && action!.isNotEmpty) 'action': action,
        if (from != null) 'date_from': _day(from!),
        if (to != null) 'date_to': _day(to!),
      };

  bool get isEmpty => actorId == null && (action ?? '').isEmpty && from == null && to == null;
}

class AuditRow {
  const AuditRow({
    required this.id,
    required this.action,
    required this.actorName,
    this.actorRole = '',
    this.at,
    this.method = '',
    this.path = '',
    this.targetType,
    this.targetId,
    this.statusCode = 0,
    this.ip,
    this.userAgent,
    this.summary,
    this.changes = const {},
  });

  factory AuditRow.fromJson(Map<String, dynamic> j) {
    final actor = _m(j['actor']), target = _m(j['target']);
    return AuditRow(
      id: _i(j['id']) ?? 0,
      action: _s(j['action']),
      actorName: _s(actor['name']).isEmpty ? '#${_s(actor['id'])}' : _s(actor['name']),
      actorRole: _s(actor['role']),
      at: _d(j['at']),
      method: _s(j['method']),
      path: _s(j['path']),
      targetType: target['type'] as String?,
      targetId: target['id'] == null ? null : '${target['id']}',
      statusCode: _i(j['status_code']) ?? 0,
      ip: j['ip'] as String?,
      userAgent: j['user_agent'] as String?,
      summary: j['summary'] as String?,
      changes: _m(j['changes']),
    );
  }

  final int id, statusCode;
  final String action, actorName, actorRole, method, path;
  final DateTime? at;
  final String? targetType, targetId, ip, userAgent, summary;
  final Map<String, dynamic> changes;

  bool get ok => statusCode >= 200 && statusCode < 400;
  String get target => [?targetType, if (targetId != null) '#$targetId'].join(' ');
}

class AuditPage {
  const AuditPage(this.items, this.total, this.hasMore);

  final List<AuditRow> items;
  final int total;
  final bool hasMore;
}

class AuditFacets {
  const AuditFacets({this.actors = const [], this.actions = const []});

  final List<({int id, String name})> actors;
  final List<String> actions;
}

// ── roles ─────────────────────────────────────────────────────────────────────

class AdminRoleModel {
  const AdminRoleModel({
    required this.id,
    required this.key,
    required this.nameAr,
    required this.nameEn,
    this.builtin = false,
    this.permissions = const [],
    this.adminsCount = 0,
  });

  factory AdminRoleModel.fromJson(Map<String, dynamic> j) => AdminRoleModel(
        id: _i(j['id']) ?? 0,
        key: _s(j['key']),
        nameAr: _s(j['name_ar']),
        nameEn: _s(j['name_en']),
        builtin: j['builtin'] == true,
        permissions: [for (final p in (j['permissions'] as List? ?? const [])) '$p'],
        adminsCount: _i(j['admins_count']) ?? 0,
      );

  final int id, adminsCount;
  final String key, nameAr, nameEn;
  final bool builtin;
  final List<String> permissions;

  String get name => govName(nameAr, nameEn);
}

class PermGroup {
  const PermGroup({required this.id, required this.title, required this.items});

  factory PermGroup.fromJson(Map<String, dynamic> j) => PermGroup(
        id: _s(j['id']),
        title: govName(j['title_ar'] as String?, j['title_en'] as String?),
        items: [
          for (final i in _l(j['items'])) (key: _s(i['key']), title: govName(i['title_ar'] as String?, i['title_en'] as String?)),
        ],
      );

  final String id, title;
  final List<({String key, String title})> items;
}

class AdminPerson {
  const AdminPerson({required this.id, required this.name, required this.role, this.roleId});

  final int id;
  final String name, role;
  final int? roleId;

  bool get isSuper => role == 'super-admin';
}

class RolesOverview {
  const RolesOverview({this.roles = const [], this.catalog = const [], this.admins = const []});

  factory RolesOverview.fromJson(Map<String, dynamic> j) => RolesOverview(
        roles: [for (final r in _l(j['roles'])) AdminRoleModel.fromJson(r)],
        catalog: [for (final g in _l(j['catalog'])) PermGroup.fromJson(g)],
        admins: [
          for (final a in _l(j['admins']))
            AdminPerson(id: _i(a['id']) ?? 0, name: _s(a['name']), role: _s(a['role']), roleId: _i(a['role_id'])),
        ],
      );

  final List<AdminRoleModel> roles;
  final List<PermGroup> catalog;
  final List<AdminPerson> admins;
}
