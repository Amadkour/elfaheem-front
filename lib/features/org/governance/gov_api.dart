// lib/features/org/governance/gov_api.dart — the HTTP client of the governance module, one method per server route
// of docs/backend/governance-spec.md (§4 staff, §5 councils, §6 members). Every method throws `ApiException`
// (wrap calls in `orgCall` from org_v3.dart to toast `orgErrorText`); GET helpers parse into gov_models.dart.
// A missing route (older server) surfaces as `orgEndpointMissing` — screens then say the feature needs a server
// update.
library;

import '../../../core/api_client.dart';
import '../../admin/admin_common.dart' show asMap, asMapList;
import '../org_providers.dart' show orgBase;
import '../org_v3.dart' show orgUtc;
import 'gov_models.dart';

class GovApi {
  GovApi(this.orgId, {ApiClient? client}) : _api = client ?? ApiClient();

  final int orgId;
  final ApiClient _api;

  String get base => '$orgBase/orgs/$orgId/governance';
  static const memberBase = '$orgBase/public/governance';

  // ── entities · categories · settings ──────────────────────────────────

  Future<List<Entity>> entities({String? kind}) async {
    final r = await _api.get('$base/entities', queryParams: {'kind': ?kind});
    return [for (final e in asMapList(asMap(r)['items'])) Entity.fromJson(e)];
  }

  Future<dynamic> createEntity(Map<String, dynamic> body) => _api.post('$base/entities', body: body);

  Future<dynamic> patchEntity(int deptId, Map<String, dynamic> body) => _api.patch('$base/entities/$deptId', body: body);

  Future<List<Category>> categories(int deptId) async {
    final r = await _api.get('$base/entities/$deptId/categories');
    return [for (final c in asMapList(asMap(r)['items'])) Category.fromJson(c)];
  }

  Future<dynamic> createCategory(int deptId, Map<String, dynamic> body) => _api.post('$base/entities/$deptId/categories', body: body);

  Future<dynamic> updateCategory(int cid, Map<String, dynamic> body) => _api.put('$base/categories/$cid', body: body);

  Future<dynamic> deleteCategory(int cid) => _api.delete('$base/categories/$cid');

  /// The entity's approval chain (D-141): `{steps, kinds, can_edit}`; [] = one decision by the entity.
  Future<(List<ChainStep>, bool)> chain(int deptId) async {
    final m = asMap(await _api.get('$base/entities/$deptId/chain'));
    return ([for (final s in asMapList(m['steps'])) ChainStep.fromJson(s)], m['can_edit'] == true);
  }

  /// The whole list (org admin; 422 `chain_invalid` with the step `index`).
  Future<List<ChainStep>> saveChain(int deptId, List<ChainStep> steps) async {
    final m = asMap(await _api.put('$base/entities/$deptId/chain', body: {'steps': [for (final s in steps) s.toSettingsJson()]}));
    return [for (final s in asMapList(m['steps'])) ChainStep.fromJson(s)];
  }

  Future<Map<String, dynamic>> settings() async => asMap(await _api.get('$base/settings'));

  Future<dynamic> saveSettings(Map<String, dynamic> body) => _api.put('$base/settings', body: body);

  // ── items ─────────────────────────────────────────────────────────────

  /// [query] is the shared filter's query map (gov_filter.dart `ItemFilter.toQuery()`), plus `page` / `size`.
  Future<GovPage<WorkItem>> items(Map<String, dynamic> query) async {
    final r = await _api.get('$base/items', queryParams: _clean(query));
    return GovPage.from(r, WorkItem.fromJson);
  }

  Future<WorkItem> item(int id) async => WorkItem.fromJson(asMap(await _api.get('$base/items/$id')));

  Future<dynamic> createItem(Map<String, dynamic> body) => _api.post('$base/items', body: body);

  Future<dynamic> patchItem(int id, Map<String, dynamic> body) => _api.patch('$base/items/$id', body: body);

  Future<dynamic> deleteItem(int id) => _api.delete('$base/items/$id');

  Future<dynamic> route(int id, Map<String, dynamic> body) => _api.post('$base/items/$id/route', body: body);

  Future<dynamic> escalate(int id, {String? note}) => _api.post('$base/items/$id/escalate', body: {'note': ?note});

  /// Pull an item back from a council before its voting starts (409 `nothing_to_recall` / `recall_blocked`).
  Future<dynamic> recall(int id, {String? note}) => _api.post('$base/items/$id/recall', body: {'note': ?note});

  Future<dynamic> decide(int id, {required String outcome, String? note, required int version}) =>
      _api.post('$base/items/$id/decide', body: {'outcome': outcome, 'note': ?note, 'version': version});

  Future<dynamic> answerRoute(int id, int routeId, {required String answer, String? note, String? action}) =>
      _api.post('$base/items/$id/routes/$routeId/answer', body: {'answer': answer, 'note': ?note, 'action': ?action});

  /// D-890: an APPROVED item onward (`forwardBody`); 409 `not_approved` otherwise.
  Future<dynamic> forward(int id, Map<String, dynamic> body) => _api.post('$base/items/$id/forward', body: body);

  Future<dynamic> assign(int id, int? userId) => _api.post('$base/items/$id/assign', body: {'user_id': userId});

  Future<dynamic> setStatus(int id, String status, {String? note}) => _api.post('$base/items/$id/status', body: {'status': status, 'note': ?note});

  Future<dynamic> comment(int id, String body, {bool internal = false, List<GovAttachment> attachments = const []}) =>
      _api.post('$base/items/$id/comments', body: {
        'body': body,
        'internal': internal,
        if (attachments.isNotEmpty) 'attachments': [for (final a in attachments) a.toJson()],
      });

  Future<dynamic> bulk(List<int> ids, String op, {Map<String, dynamic>? route, int? userId, int? sessionId}) =>
      _api.post('$base/items/bulk', body: {'ids': ids, 'op': op, 'route': ?route, 'user_id': ?userId, 'session_id': ?sessionId});

  Future<Map<String, dynamic>> dashboard({int? deptId}) async => asMap(await _api.get('$base/dashboard', queryParams: {'dept_id': ?deptId}));
  /// The faculty overview (D-979): the usual numbers + `faculty` for the dean / vice deans / org admin (else absent).
  Future<Map<String, dynamic>> facultyDashboard() async => asMap(await _api.get('$base/dashboard', queryParams: {'scope': 'faculty'}));

  Future<List<SavedFilter>> savedFilters(String scope) async {
    final r = await _api.get('$base/saved-filters', queryParams: {'scope': scope});
    return [for (final f in asMapList(asMap(r)['items'])) SavedFilter.fromJson(f)];
  }

  Future<dynamic> saveFilter(String name, String scope, Map<String, dynamic> query) =>
      _api.post('$base/saved-filters', body: {'name': name, 'scope': scope, 'query': query});

  Future<dynamic> deleteSavedFilter(int id) => _api.delete('$base/saved-filters/$id');

  // ── delegation ────────────────────────────────────────────────────────

  Future<List<Delegation>> delegations(int deptId, {bool? active}) async {
    final r = await _api.get('$base/entities/$deptId/delegations', queryParams: {'active': ?active});
    return [for (final d in asMapList(asMap(r)['items'])) Delegation.fromJson(d)];
  }

  Future<dynamic> createDelegation(int deptId, Map<String, dynamic> body) => _api.post('$base/entities/$deptId/delegations', body: body);

  Future<dynamic> revokeDelegation(int id) => _api.delete('$base/delegations/$id');

  Future<List<Delegation>> myDelegations() async {
    final r = await _api.get('$base/me/delegations');
    return [for (final d in asMapList(asMap(r)['items'])) Delegation.fromJson(d)];
  }

  // ── forms ─────────────────────────────────────────────────────────────

  Future<dynamic> assignForm(int formId, {List<int>? userIds, List<int>? deptIds, List<String>? roles, DateTime? dueAt, bool must = false}) =>
      _api.post('$base/forms/$formId/assign', body: {
        'user_ids': ?userIds,
        'dept_ids': ?deptIds,
        'roles': ?roles,
        'due_at': orgUtc(dueAt),
        'must': must,
      });

  Future<Map<String, List<FormAssignment>>> formAssignments(int formId) async {
    final m = asMap(await _api.get('$base/forms/$formId/assignments'));
    return {
      for (final k in const ['submitted', 'pending', 'waived']) k: [for (final a in asMapList(m[k])) FormAssignment.fromJson(a)],
    };
  }

  Future<dynamic> remindForm(int formId) => _api.post('$base/forms/$formId/remind', body: const {});

  Future<dynamic> waiveAssignment(int formId, int userId) => _api.post('$base/forms/$formId/assignments/$userId/waive', body: const {});

  // ── export hub ────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> exportData(Map<String, dynamic> query) async =>
      asMap(await _api.get('$base/export/data', queryParams: _clean(query)));

  Future<List<ExportTemplate>> exportTemplates({String? module, String? lang, int? deptId}) async {
    final r = await _api.get('$base/export/templates', queryParams: {'module': ?module, 'lang': ?lang, 'dept_id': ?deptId});
    return [for (final x in asMapList(asMap(r)['items'])) ExportTemplate.fromJson(x)];
  }

  Future<dynamic> createExportTemplate(Map<String, dynamic> body) => _api.post('$base/export/templates', body: body);

  Future<dynamic> updateExportTemplate(int id, Map<String, dynamic> body) => _api.put('$base/export/templates/$id', body: body);

  Future<dynamic> deleteExportTemplate(int id) => _api.delete('$base/export/templates/$id');

  Future<dynamic> setDefaultExportTemplate(int id) => _api.post('$base/export/templates/$id/default', body: const {});

  Future<dynamic> shareExportTemplate(int id, bool shared) => _api.post('$base/export/templates/$id/share', body: {'shared': shared});

  // ── councils · sessions · voting (§5) ─────────────────────────────────

  Future<List<Council>> councils() async {
    final r = await _api.get('$base/councils');
    return [for (final c in asMapList(asMap(r)['items'])) Council.fromJson(c)];
  }

  /// Institutions v2: a chair is required (422 `head_required`); [headSelf] makes the caller the chair.
  Future<dynamic> createFacultyCouncil({String? nameAr, String? nameEn, int? headUserId, bool headSelf = false}) =>
      _api.post('$base/councils', body: {'level': 'faculty', 'name_ar': ?nameAr, 'name_en': ?nameEn, if (headSelf) 'head_self': true else 'head_user_id': ?headUserId});

  // Institutions v2 phase 3 (D-989 – D-990, gov_councils_setup.dart): which councils the institution has
  Future<Map<String, dynamic>> councilsSetup() async => asMap(await _api.get('$base/councils-setup'));

  /// 409 `council_has_open_agenda` {councils: [{id, name, open_agenda_items}]} = nothing applied.
  Future<Map<String, dynamic>> saveCouncilsSetup(Map<String, dynamic> body) async => asMap(await _api.put('$base/councils-setup', body: body));

  Future<Council> council(int cid) async => Council.fromJson(asMap(await _api.get('$base/councils/$cid')));

  Future<dynamic> saveCouncilSettings(int cid, CouncilSettings s) => _api.put('$base/councils/$cid/settings', body: s.toJson());

  Future<List<CouncilSession>> sessions(int cid, {String? status}) async {
    final r = await _api.get('$base/councils/$cid/sessions', queryParams: {'status': ?status});
    return [for (final s in asMapList(asMap(r)['items'])) CouncilSession.fromJson(s)];
  }

  Future<dynamic> createSession(int cid, {required String kind, required DateTime scheduledAt, String? title, List<int>? itemIds}) =>
      _api.post('$base/councils/$cid/sessions', body: {'kind': kind, 'scheduled_at': orgUtc(scheduledAt), 'title': ?title, 'item_ids': ?itemIds});

  Future<CouncilSession> session(int sid) async => CouncilSession.fromJson(asMap(await _api.get('$base/sessions/$sid')));

  Future<dynamic> patchSession(int sid, Map<String, dynamic> body) => _api.patch('$base/sessions/$sid', body: body);

  Future<dynamic> addToAgenda(int sid, List<int> itemIds) => _api.post('$base/sessions/$sid/agenda', body: {'item_ids': itemIds});

  Future<dynamic> removeFromAgenda(int sid, int aid) => _api.delete('$base/sessions/$sid/agenda/$aid');

  Future<dynamic> postponeAgenda(int sid, int aid) => _api.post('$base/sessions/$sid/agenda/$aid/postpone', body: const {});

  Future<dynamic> reorderAgenda(int sid, List<int> ids) => _api.put('$base/sessions/$sid/agenda/order', body: {'ids': ids});

  Future<dynamic> publishSession(int sid) => _api.post('$base/sessions/$sid/publish', body: const {});

  Future<dynamic> openVoting(int sid) => _api.post('$base/sessions/$sid/open-voting', body: const {});

  Future<dynamic> closeSession(int sid, int version) => _api.post('$base/sessions/$sid/close', body: {'version': version});

  Future<dynamic> cancelSession(int sid, {String? note}) => _api.post('$base/sessions/$sid/cancel', body: {'note': ?note});

  Future<dynamic> vote(int aid, String vote, {String? note}) => _api.post('$base/agenda/$aid/vote', body: {'vote': vote, 'note': ?note});

  Future<dynamic> escalateAgenda(int aid, {String? note}) => _api.post('$base/agenda/$aid/escalate', body: {'note': ?note});

  Future<Map<String, dynamic>> minutes(int sid) async => asMap(await _api.get('$base/sessions/$sid/minutes'));

  // ── Institutions S2 (D-965 – D-970) ───────────────────────────────────

  /// The roster: members with weights, the secretary, `can.roster`.
  Future<CouncilRoster> councilMembers(int cid) async => CouncilRoster.fromJson(asMap(await _api.get('$base/councils/$cid/members')));

  /// `rosterBody(...)`; 422 `weight_cap` `{user_id, cap_pct}`, `not_staff_member`, `council_settings_invalid`.
  Future<CouncilRoster> saveCouncilMembers(int cid, Map<String, dynamic> body) async =>
      CouncilRoster.fromJson(asMap(await _api.put('$base/councils/$cid/members', body: body)));

  /// The chair / secretary writes an item on the agenda (201 → the whole session).
  /// S3 (D-973): with a known [templateKey] a missing title / body comes from the template in [lang] and the item
  /// keeps its `suggested_decision`; no title and no known key → 422 `title_required`.
  Future<CouncilSession> writeAgendaItem(int sid, {String? title, String? body, String? templateKey, String? lang}) async =>
      CouncilSession.fromJson(asMap(await _api.post('$base/sessions/$sid/agenda/write',
          body: {'title': ?title, 'body': ?body, 'template_key': ?templateKey, 'lang': ?lang})));

  // ── Institutions S3 (D-971, D-973) ─────────────────────────────────────

  /// The department's ordered automatic routing rules and what the editor may offer (`AutoRouting.fromJson`).
  Future<Map<String, dynamic>> autoRouting(int deptId) async => asMap(await _api.get('$base/entities/$deptId/auto-routing'));

  /// The WHOLE ordered list (`[]` clears); 422 `auto_rule_invalid` `{index, field}`. Answer: the GET shape.
  Future<Map<String, dynamic>> saveAutoRouting(int deptId, List<Map<String, dynamic>> rules) async =>
      asMap(await _api.put('$base/entities/$deptId/auto-routing', body: {'rules': rules}));

  /// The nine decision templates (`{items: [...]}`).
  Future<List<Map<String, dynamic>>> decisionTemplates() async => asMapList(asMap(await _api.get('$base/decision-templates'))['items']);

  /// `{reminded, manual_reminded_at, next_allowed_at}`; 429 `remind_too_soon` `{retry_after}`.
  Future<Map<String, dynamic>> remindNonVoters(int sid) async => asMap(await _api.post('$base/sessions/$sid/remind', body: const {}));

  /// I have a conflict of interest on this row (→ the row JSON).
  Future<AgendaItem> declareConflict(int aid, {String? note}) async =>
      AgendaItem.fromJson(asMap(await _api.post('$base/agenda/$aid/conflict', body: {'note': ?note})));

  Future<AgendaItem> agendaResults(int aid) async => AgendaItem.fromJson(asMap(await _api.get('$base/agenda/$aid/results')));

  Future<List<AgendaItem>> myVotes() async {
    final r = await _api.get('$base/me/votes');
    return [for (final a in asMapList(asMap(r)['items'])) AgendaItem.fromJson(a)];
  }

  // ── members (§6, no organization in the path) ────────────────────────

  static Future<List<Entity>> memberEntities(int orgId, {ApiClient? client}) async {
    final r = await (client ?? ApiClient()).get('$memberBase/$orgId/entities');
    return [for (final e in asMapList(asMap(r)['items'])) Entity.fromJson(e)];
  }

  static Future<dynamic> memberSubmit(int orgId, Map<String, dynamic> body, {ApiClient? client}) =>
      (client ?? ApiClient()).post('$memberBase/$orgId/items', body: body);

  static Future<GovPage<WorkItem>> memberItems({int? orgId, String? status, int page = 1, ApiClient? client}) async {
    final r = await (client ?? ApiClient()).get('$memberBase/me/items', queryParams: {'org_id': ?orgId, 'status': ?status, 'page': page});
    return GovPage.from(r, WorkItem.fromJson);
  }

  static Future<WorkItem> memberItem(int id, {ApiClient? client}) async =>
      WorkItem.fromJson(asMap(await (client ?? ApiClient()).get('$memberBase/items/$id')));

  static Future<dynamic> memberComment(int id, String body, {List<GovAttachment> attachments = const [], ApiClient? client}) =>
      (client ?? ApiClient()).post('$memberBase/items/$id/comments', body: {
        'body': body,
        if (attachments.isNotEmpty) 'attachments': [for (final a in attachments) a.toJson()],
      });

  /// The requester edits a rejected item and sends it again (D-141): `{title?, body?, attachments?, note?}`.
  static Future<dynamic> memberResubmit(int id, Map<String, dynamic> body, {ApiClient? client}) =>
      (client ?? ApiClient()).post('$memberBase/items/$id/resubmit', body: body);

  /// Members to file a request FOR (D-140): names only; 403 `on_behalf_forbidden` without the right.
  static Future<List<GovPerson>> memberPeople(int orgId, {String? q, int? deptId, ApiClient? client}) async {
    final r = await (client ?? ApiClient()).get('$memberBase/$orgId/people', queryParams: {'q': ?(q?.trim().isEmpty ?? true ? null : q!.trim()), 'dept_id': ?deptId});
    return [for (final p in asMapList(asMap(r)['items'])) GovPerson.fromJson(p)];
  }

  /// The upload route of request / comment files (multipart `file`; real type and size checked by the server).
  static String uploadPath(int orgId) => '$memberBase/$orgId/attachments';

  /// A 10-minute link to an uploaded attachment, after the item's view check (`inline` for the preview).
  static Future<String> attachmentLink(int id, {bool inline = false, ApiClient? client}) async {
    final m = asMap(await (client ?? ApiClient()).get('$memberBase/attachments/$id', queryParams: {'inline': inline}));
    return '${m['url'] ?? ''}';
  }

  /// D-890: the member an approved item was forwarded to answers one required action.
  static Future<dynamic> memberAnswerRoute(int id, int routeId, {required String answer, String? note, String? action, ApiClient? client}) =>
      (client ?? ApiClient()).post('$memberBase/items/$id/routes/$routeId/answer', body: {'answer': answer, 'note': ?note, 'action': ?action});

  static Future<dynamic> memberWithdraw(int id, {ApiClient? client}) => (client ?? ApiClient()).post('$memberBase/items/$id/withdraw', body: const {});

  static Future<List<AgendaItem>> memberVotes({ApiClient? client}) async {
    final r = await (client ?? ApiClient()).get('$memberBase/me/votes');
    return [for (final a in asMapList(asMap(r)['items'])) AgendaItem.fromJson(a)];
  }

  static Future<dynamic> memberVote(int aid, String vote, {String? note, ApiClient? client}) =>
      (client ?? ApiClient()).post('$memberBase/agenda/$aid/vote', body: {'vote': vote, 'note': ?note});

  static Future<AgendaItem> memberDeclareConflict(int aid, {String? note, ApiClient? client}) async =>
      AgendaItem.fromJson(asMap(await (client ?? ApiClient()).post('$memberBase/agenda/$aid/conflict', body: {'note': ?note})));

  static Future<List<Delegation>> memberDelegations({ApiClient? client}) async {
    final r = await (client ?? ApiClient()).get('$memberBase/me/delegations');
    return [for (final d in asMapList(asMap(r)['items'])) Delegation.fromJson(d)];
  }

  static Future<List<FormAssignment>> memberAssignments({ApiClient? client}) async {
    final r = await (client ?? ApiClient()).get('$memberBase/me/assignments');
    return [for (final a in asMapList(asMap(r)['items'])) FormAssignment.fromJson(a)];
  }

  static Map<String, dynamic> _clean(Map<String, dynamic> q) => {
        for (final e in q.entries)
          if (e.value != null && '${e.value}'.isNotEmpty) e.key: e.value,
      };
}
