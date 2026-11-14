// lib/features/org/advising/adv_api.dart — the HTTP client of the Academic Advising module, one method per server
// route of docs/advising/PHASE2.md (status, enable / disable), PHASE3.md (settings, advisors, conflicts, students,
// distribution, handovers) and PHASE4.md (workspace, student 360, categories, flags, notes, timeline). Every method throws `ApiException` (wrap calls in `orgCall` from org_v3.dart
// to toast `orgErrorText`); answers are parsed into adv_models.dart. A missing route (older server) surfaces as
// `orgEndpointMissing`, and the screens then say the feature needs a server update.
library;

import '../../../core/api_client.dart';
import '../../admin/admin_common.dart' show asInt, asMap, asMapList;
import '../org_providers.dart' show orgBase;
import 'adv_models.dart';

class AdvApi {
  AdvApi(this.orgId, {ApiClient? client}) : _api = client ?? ApiClient();

  final int orgId;
  final ApiClient _api;

  String get base => '$orgBase/orgs/$orgId/advising';

  /// Eligibility, on / off, the directors, what I am and (admins / directors) the organization's counts.
  Future<AdvStatus> status() async => AdvStatus.fromJson(asMap(await _api.get('$base/status')));

  /// Org admin. [deptId] = the department that leads advising; null = the existing Academic Advising department,
  /// else a new one. Idempotent; 403 `advising_not_available` for an ineligible organization.
  Future<AdvStatus> enable({int? deptId}) async => AdvStatus.fromJson(asMap(await _api.post('$base/enable', body: {'dept_id': deptId})));

  /// Org admin. Every record is kept.
  Future<AdvStatus> disable() async => AdvStatus.fromJson(asMap(await _api.post('$base/disable')));

  /// The organization's departments the advising may be given to ([advDeptChoices]).
  Future<List<AdvDeptOption>> departmentChoices() async =>
      advDeptChoices(asMapList(asMap(await _api.get('$orgBase/orgs/$orgId/departments'))['items']));

  // ── Phase 3: settings ─────────────────────────────────────────────────────

  /// Manage. The effective settings, the defaults, the organization's row, the scope rows and the choices.
  Future<AdvPolicyBundle> policy() async => AdvPolicyBundle.fromJson(asMap(await _api.get('$base/policy')));

  /// Manage. Replaces one scope row's settings (`{}` = inherit everything); answers the GET body.
  Future<AdvPolicyBundle> savePolicy(AdvSettingsDraft draft) async =>
      AdvPolicyBundle.fromJson(asMap(await _api.put('$base/policy', body: draft.toBody())));

  /// Manage. Removes a scope row (never the organization's own).
  Future<AdvPolicyBundle> deletePolicyScope(int policyId) async =>
      AdvPolicyBundle.fromJson(asMap(await _api.delete('$base/policy/$policyId')));

  // ── Advisors ──────────────────────────────────────────────────────────────

  /// Manage. [status] `available` · `away` · `warn` · `over` · `all`; [sort] `load` · `name`.
  Future<AdvPage<AdvAdvisor>> advisors({String q = '', String status = 'all', String sort = 'load', int page = 1, int size = 25}) async =>
      AdvPage.fromJson(
        asMap(await _api.get('$base/advisors', queryParams: {
          if (q.trim().isNotEmpty) 'q': q.trim(),
          'status': status,
          'sort': sort,
          'page': page,
          'size': size,
        })),
        AdvAdvisor.fromJson,
      );

  /// Any staff member: my own advisor card (`eligible` false and zero loads when I advise nobody).
  Future<AdvAdvisor> myAdvisor() async => AdvAdvisor.fromJson(asMap(await _api.get('$base/advisors/me')));

  /// The whole profile. An advisor may change only office, contact note and bio of their own.
  Future<AdvAdvisor> saveProfile(int userId, AdvProfileDraft draft) async =>
      AdvAdvisor.fromJson(asMap(await _api.put('$base/advisors/$userId', body: draft.toJson())));

  // ── Conflicts of interest ─────────────────────────────────────────────────

  /// Manage. One advisor's ([advisorUserId]) or one student's ([memberId]) conflicts.
  Future<AdvPage<AdvConflict>> conflicts({int? advisorUserId, int? memberId, int page = 1, int size = 100}) async => AdvPage.fromJson(
        asMap(await _api.get('$base/conflicts', queryParams: {'advisor_user_id': ?advisorUserId, 'member_id': ?memberId, 'page': page, 'size': size})),
        AdvConflict.fromJson,
      );

  /// 409 `advising_conflict_exists` for a pair already recorded.
  Future<AdvConflict> addConflict({required int advisorUserId, required int memberId, required String reason, String? note}) async =>
      AdvConflict.fromJson(asMap(await _api.post('$base/conflicts', body: {
        'advisor_user_id': advisorUserId,
        'member_id': memberId,
        'reason': reason,
        'note': (note ?? '').trim().isEmpty ? null : note!.trim(),
      })));

  Future<void> removeConflict(int id) async => _api.delete('$base/conflicts/$id');

  // ── Students and manual assignment ────────────────────────────────────────

  /// Manage: the whole organization; an advisor: their own advisees. [filter] `all` · `unassigned` · `away` · `locked`.
  Future<AdvPage<AdvStudent>> students({
    String q = '',
    String filter = 'all',
    int? deptId,
    int? programId,
    String? level,
    String? cohort,
    int? advisorUserId,
    int page = 1,
    int size = 25,
  }) async =>
      AdvPage.fromJson(
        asMap(await _api.get('$base/students', queryParams: {
          if (q.trim().isNotEmpty) 'q': q.trim(),
          'filter': filter,
          'dept_id': ?deptId,
          'program_id': ?programId,
          'level': ?level,
          'cohort': ?cohort,
          'advisor_user_id': ?advisorUserId,
          'page': page,
          'size': size,
        })),
        AdvStudent.fromJson,
      );

  /// Manage. The whole assignment of one student; 422 `advising_single_mode` / `advising_bad_advisor`, 409
  /// `advising_conflict` / `advising_over_capacity`.
  Future<AdvStudent> saveAdvisors(int memberId, AdvAdvisorsDraft draft, {required bool multi}) async =>
      AdvStudent.fromJson(asMap(await _api.put('$base/students/$memberId/advisors', body: draft.toJson(multi: multi))));

  Future<List<AdvHistoryEntry>> history(int memberId) async =>
      [for (final m in asMapList(asMap(await _api.get('$base/students/$memberId/history'))['items'])) AdvHistoryEntry.fromJson(m)];

  // ── Distribution ──────────────────────────────────────────────────────────

  /// Manage. Pure: nothing is written except the run row.
  Future<AdvPlan> preview(AdvPlanRequest request) async => AdvPlan.fromJson(asMap(await _api.post('$base/assign/preview', body: request.toJson())));

  /// Manage. 409 `plan_stale` when the data changed since the preview; the same plan twice answers the stored result.
  /// [forceOverCapacity] (with a [reason], else 422 `advising_reason_required`) also places the students the preview
  /// left out for capacity, above the maximum.
  Future<AdvApplyResult> apply(String planHash, {bool forceOverCapacity = false, String? reason}) async =>
      AdvApplyResult.fromJson(asMap(await _api.post('$base/assign/apply', body: {
        'plan_hash': planHash,
        'force_over_capacity': forceOverCapacity,
        'reason': reason,
      })));

  Future<AdvPage<AdvRun>> runs({int page = 1, int size = 10}) async =>
      AdvPage.fromJson(asMap(await _api.get('$base/assign/runs', queryParams: {'page': page, 'size': size})), AdvRun.fromJson);

  // ── Handovers ─────────────────────────────────────────────────────────────

  /// Manage: every handover; an advisor ([mine]): theirs.
  Future<AdvPage<AdvHandover>> handovers({bool mine = false, bool pending = false, int page = 1, int size = 25}) async => AdvPage.fromJson(
        asMap(await _api.get('$base/handovers', queryParams: {if (mine) 'mine': 1, if (pending) 'pending': 1, 'page': page, 'size': size})),
        AdvHandover.fromJson,
      );

  /// The receiving advisor.
  Future<AdvHandover> acknowledge(int id) async => AdvHandover.fromJson(asMap(await _api.post('$base/handovers/$id/ack')));

  // ── Phase 4: the workspace ────────────────────────────────────────────────

  /// An advisor: their own advisees (the advisor filter is ignored); manage: the whole organization. Default order:
  /// the risk score, highest first. Facets `open` · `urgent` · `no_contact_30d` · `total`.
  Future<AdvPage<AdvCaseItem>> workspace(AdvWorkspaceQuery query, {required bool manage}) async =>
      AdvPage.fromJson(asMap(await _api.get('$base/workspace', queryParams: query.toQuery(manage: manage))), AdvCaseItem.fromJson);

  /// The student 360. 404 `advising_not_found` for a student the caller does not advise.
  Future<AdvCaseProfile> profile(int memberId) async => AdvCaseProfile.fromJson(asMap(await _api.get('$base/students/$memberId/profile')));

  // ── Categories ────────────────────────────────────────────────────────────

  Future<List<AdvCategory>> categories() async =>
      [for (final m in asMapList(asMap(await _api.get('$base/categories'))['items'])) AdvCategory.fromJson(m)];

  /// Manage. The key is made by the server.
  Future<AdvCategory> addCategory(AdvCategoryDraft draft) async =>
      AdvCategory.fromJson(asMap(await _api.post('$base/categories', body: draft.toJson(create: true))));

  /// Manage. The whole category. Also answers how many student-visible notes became team-only (`notes_downgraded`,
  /// when the category turned sensitive).
  Future<(AdvCategory, int)> saveCategory(int id, AdvCategoryDraft draft) async {
    final j = asMap(await _api.put('$base/categories/$id', body: draft.toJson()));
    return (AdvCategory.fromJson(j), asInt(j['notes_downgraded']));
  }

  /// Manage. 409 `advising_category_in_use` while open flags use it; a system category is never deleted.
  Future<void> deleteCategory(int id) async => _api.delete('$base/categories/$id');

  // ── Flags ─────────────────────────────────────────────────────────────────

  /// [status] `open` · `closed` · `all`. `restricted` counts the flags the caller may not read.
  Future<AdvPage<AdvFlag>> flags(int memberId, {String status = 'open'}) async =>
      AdvPage.fromJson(asMap(await _api.get('$base/students/$memberId/flags', queryParams: {'status': status})), AdvFlag.fromJson);

  /// 422 `advising_bad_accommodation` for an accommodation the category does not list.
  Future<AdvFlag> addFlag(int memberId, AdvFlagDraft draft) async =>
      AdvFlag.fromJson(asMap(await _api.post('$base/students/$memberId/flags', body: draft.toJson())));

  /// The owner or manage; the whole flag.
  Future<AdvFlag> saveFlag(int id, AdvFlagDraft draft) async => AdvFlag.fromJson(asMap(await _api.put('$base/flags/$id', body: draft.toJson())));

  /// 409 `advising_bad_transition`; 422 `advising_outcome_required` for `resolved` without an outcome.
  Future<AdvFlag> setFlagStatus(int id, String status, {String? outcomeNote}) async => AdvFlag.fromJson(asMap(await _api.post('$base/flags/$id/status', body: {
        'status': status,
        'outcome_note': (outcomeNote ?? '').trim().isEmpty ? null : outcomeNote!.trim(),
      })));

  /// Newest first.
  Future<List<AdvFlagEvent>> flagHistory(int id) async =>
      [for (final m in asMapList(asMap(await _api.get('$base/flags/$id/history'))['items'])) AdvFlagEvent.fromJson(m)];

  // ── Notes ─────────────────────────────────────────────────────────────────

  Future<AdvPage<AdvNote>> notes(int memberId, {int page = 1, int size = 20}) async => AdvPage.fromJson(
        asMap(await _api.get('$base/students/$memberId/notes', queryParams: {'page': page, 'size': size})),
        AdvNote.fromJson,
      );

  /// Idempotent by the draft's `client_id`: the same id again answers the note already made (200).
  Future<AdvNote> addNote(int memberId, AdvNoteDraft draft) async =>
      AdvNote.fromJson(asMap(await _api.post('$base/students/$memberId/notes', body: draft.toJson())));

  /// The author only; the whole note.
  Future<AdvNote> saveNote(int id, AdvNoteDraft draft) async => AdvNote.fromJson(asMap(await _api.put('$base/notes/$id', body: draft.toJson(create: false))));

  /// The author or manage.
  Future<void> deleteNote(int id) async => _api.delete('$base/notes/$id');

  // ── Timeline ──────────────────────────────────────────────────────────────

  /// Newest first; [before] = the previous page's `next` cursor.
  Future<AdvTimelinePage> timeline(int memberId, {String? before, int size = 30}) async => AdvTimelinePage.fromJson(
        asMap(await _api.get('$base/students/$memberId/timeline', queryParams: {'before': ?before, 'size': size})),
      );

  /// Member side: is advising on, am I a student / an advisor there, and my own advisors.
  static Future<AdvMemberStatus> memberStatus(int orgId, {ApiClient? client}) async =>
      AdvMemberStatus.fromJson(asMap(await (client ?? ApiClient()).get('$orgBase/public/$orgId/advising/status')));
}
