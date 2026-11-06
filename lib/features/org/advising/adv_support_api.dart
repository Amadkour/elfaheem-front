// lib/features/org/advising/adv_support_api.dart — the HTTP client of Academic Advising Phase 7 (docs/advising/PHASE7.md):
// the request options and the approval chain, requests and referrals with their actions, support plans,
// accommodations and the 360's Support block (staff, `/orgs/{id}/advising/…`), plus the student's own calls
// (`/public/{id}/advising/…`). Every method throws `ApiException` (wrap calls in `orgCall`); answers are parsed into
// adv_support_models.dart. Attachments are uploaded first through governance (`uploadGovAttachment`).
library;

import '../../../core/api_client.dart';
import '../../admin/admin_common.dart' show asMap, asMapList;
import '../governance/gov_models.dart' show GovAttachment;
import '../org_providers.dart' show orgBase;
import '../org_v3.dart' show orgUtc;
import 'adv_models.dart' show AdvPage;
import 'adv_support_models.dart';

String? _opt(String? s) => (s ?? '').trim().isEmpty ? null : s!.trim();

class AdvSupportApi {
  AdvSupportApi(this.orgId, {ApiClient? client}) : _api = client ?? ApiClient();

  final int orgId;
  final ApiClient _api;

  String get base => '$orgBase/orgs/$orgId/advising';

  // ── Options and the chain ─────────────────────────────────────────────────

  /// Advisor · manage: support types, referral targets (suggested first), categories, templates, priorities.
  Future<AdvRequestOptions> options() async => AdvRequestOptions.fromJson(asMap(await _api.get('$base/request-options')));

  /// Manage: the organization's chain, the defaults, the scopes that set their own, the choices.
  Future<AdvChainConfig> chain() async => AdvChainConfig.fromJson(asMap(await _api.get('$base/request-chain')));

  /// Manage. [steps] null removes the scope's chain (it inherits). 422 `advising_chain_invalid` `{index, reason}`.
  Future<AdvChainConfig> saveChain({required String scopeType, String? scopeRef, List<AdvChainStep>? steps}) async =>
      AdvChainConfig.fromJson(asMap(await _api.put('$base/request-chain', body: {
        'scope_type': scopeType,
        'scope_ref': scopeType == 'org' ? null : scopeRef,
        'steps': steps == null ? null : [for (final s in steps) s.toJson()],
      })));

  /// The chain this student's request would follow, each step resolved or skipped with its reason.
  Future<AdvChainPreview> previewChain(int memberId) async =>
      AdvChainPreview.fromJson(asMap(await _api.get('$base/request-chain/preview', queryParams: {'member_id': memberId})));

  // ── Requests and referrals ────────────────────────────────────────────────

  /// Envelope + `restricted` + `facets` (`review` · `needs_info` · `overdue` · `open`).
  Future<AdvPage<AdvRequest>> requests(AdvRequestQuery query) async =>
      AdvPage.fromJson(asMap(await _api.get('$base/requests', queryParams: query.toQuery())), AdvRequest.fromJson);

  /// A draft ([submit] false) or a submitted request. Idempotent by the draft's `client_id`.
  Future<AdvRequest> create(int memberId, AdvRequestDraft draft, {bool submit = false}) async =>
      AdvRequest.fromJson(asMap(await _api.post('$base/students/$memberId/requests', body: draft.toJson(submit: submit))));

  /// The detail (chain, history, agenda).
  Future<AdvRequest> request(int id) async => AdvRequest.fromJson(asMap(await _api.get('$base/requests/$id')));

  /// The author, a draft only; the whole object. 409 `advising_stale`.
  Future<AdvRequest> save(int id, AdvRequestDraft draft, {required int version}) async =>
      AdvRequest.fromJson(asMap(await _api.put('$base/requests/$id', body: draft.toJson(version: version))));

  /// The author, a draft only.
  Future<void> delete(int id) async => _api.delete('$base/requests/$id');

  Future<AdvRequest> submit(int id, {required int version}) async =>
      AdvRequest.fromJson(asMap(await _api.post('$base/requests/$id/submit', body: {'version': version})));

  /// Manage, at `director_review`. [decision] `approve` · `reject` · `needs_info`; [version] = the work item's.
  Future<AdvRequest> review(int id, {required String decision, String? note, required int version}) async =>
      AdvRequest.fromJson(asMap(await _api.post('$base/requests/$id/review', body: {'decision': decision, 'note': _opt(note), 'version': version})));

  /// The submitting advisor (or manage) answers the director's info request.
  Future<AdvRequest> answerInfo(int id, {required String answer, List<GovAttachment> attachments = const []}) async =>
      AdvRequest.fromJson(asMap(await _api.post('$base/requests/$id/info', body: {
        'answer': answer.trim(),
        'attachments': [for (final a in attachments) a.toJson()],
      })));

  /// The submitter, after a rejection: a new round from the first step.
  Future<AdvRequest> resubmit(int id, {required String title, required String body, List<GovAttachment> attachments = const [], String? note}) async =>
      AdvRequest.fromJson(asMap(await _api.post('$base/requests/$id/resubmit', body: {
        'title': title.trim(),
        'body': body.trim(),
        'attachments': [for (final a in attachments) a.toJson()],
        'note': _opt(note),
      })));

  /// Before a decision: outcome `withdrawn`.
  Future<AdvRequest> cancel(int id, {String? reason}) async =>
      AdvRequest.fromJson(asMap(await _api.post('$base/requests/$id/cancel', body: {'reason': _opt(reason)})));

  /// After a decision, with a follow-up note: stage `closed`.
  Future<AdvRequest> close(int id, {required String note}) async =>
      AdvRequest.fromJson(asMap(await _api.post('$base/requests/$id/close', body: {'note': note.trim()})));

  // ── Support plans ─────────────────────────────────────────────────────────

  Future<List<AdvSupportPlan>> plans(int memberId, {String? status}) async => [
        for (final m in asMapList(asMap(await _api.get('$base/students/$memberId/plans', queryParams: {'status': ?status}))['items'])) AdvSupportPlan.fromJson(m),
      ];

  Future<AdvSupportPlan> createPlan(int memberId, AdvPlanDraft draft) async =>
      AdvSupportPlan.fromJson(asMap(await _api.post('$base/students/$memberId/plans', body: draft.toJson())));

  /// The whole plan; items with an id are kept, without one are new, missing ones are removed.
  Future<AdvSupportPlan> savePlan(int id, AdvPlanDraft draft, {required int version}) async =>
      AdvSupportPlan.fromJson(asMap(await _api.put('$base/plans/$id', body: draft.toJson(version: version))));

  /// A draft only.
  Future<void> deletePlan(int id) async => _api.delete('$base/plans/$id');

  /// The review the follow-up date asked for; [nextFollowUpAt] must be in the future (422 `advising_bad_dates`).
  Future<AdvSupportPlan> reviewPlan(int id, {String? note, DateTime? nextFollowUpAt}) async =>
      AdvSupportPlan.fromJson(asMap(await _api.post('$base/plans/$id/review', body: {'note': _opt(note), 'next_follow_up_at': orgUtc(nextFollowUpAt)})));

  /// 409 `advising_plan_transition`; `completed` without a note 422 `advising_outcome_required`.
  Future<AdvSupportPlan> setPlanStatus(int id, String status, {String? outcomeNote}) async =>
      AdvSupportPlan.fromJson(asMap(await _api.post('$base/plans/$id/status', body: {'status': status, 'outcome_note': _opt(outcomeNote)})));

  Future<AdvSupportPlan> setPlanItemStatus(int planId, int itemId, String status, {String? note}) async =>
      AdvSupportPlan.fromJson(asMap(await _api.post('$base/plans/$planId/items/$itemId/status', body: {'status': status, 'note': _opt(note)})));

  // ── Accommodations ────────────────────────────────────────────────────────

  Future<List<AdvAccommodationGrant>> accommodations(int memberId, {String? status}) async => [
        for (final m in asMapList(asMap(await _api.get('$base/students/$memberId/accommodations', queryParams: {'status': ?status}))['items']))
          AdvAccommodationGrant.fromJson(m),
      ];

  /// Manage. 409 `advising_accommodation_active` for a key the student already has.
  Future<List<AdvAccommodationGrant>> grant(int memberId, AdvGrantDraft draft) async => [
        for (final m in asMapList(asMap(await _api.post('$base/students/$memberId/accommodations', body: draft.toJson()))['items'])) AdvAccommodationGrant.fromJson(m),
      ];

  /// Manage.
  Future<AdvAccommodationGrant> endAccommodation(int id, {String? reason}) async =>
      AdvAccommodationGrant.fromJson(asMap(await _api.post('$base/accommodations/$id/end', body: {'reason': _opt(reason)})));

  /// Manage: the organization's accommodations (exam and teaching follow-up).
  Future<AdvPage<AdvAccommodationGrant>> orgAccommodations({String status = 'active', String q = '', int? programId, int page = 1, int size = 25}) async => AdvPage.fromJson(
        asMap(await _api.get('$base/accommodations', queryParams: {
          if (status.isNotEmpty) 'status': status,
          if (q.trim().isNotEmpty) 'q': q.trim(),
          'program_id': ?programId,
          'page': page,
          'size': size,
        })),
        AdvAccommodationGrant.fromJson,
      );

  // ── 360 ───────────────────────────────────────────────────────────────────

  Future<AdvSupportSummary> support(int memberId) async => AdvSupportSummary.fromJson(asMap(await _api.get('$base/students/$memberId/support')));

  // ── The student (own membership only) ─────────────────────────────────────

  static String _member(int orgId) => '$orgBase/public/$orgId/advising';

  /// My submitted requests and referrals (newest first), my visible plans, my active accommodations.
  static Future<AdvMemberSupport> memberSupport(int orgId, {ApiClient? client}) async =>
      AdvMemberSupport.fromJson(asMap(await (client ?? ApiClient()).get('${_member(orgId)}/support')));

  /// 404 `advising_not_found` for another student's request.
  static Future<AdvStudentRequest> memberRequest(int orgId, int id, {ApiClient? client}) async =>
      AdvStudentRequest.fromJson(asMap(await (client ?? ApiClient()).get('${_member(orgId)}/requests/$id')));

  /// A student-owned item of a visible active plan: `done` · `open`.
  static Future<AdvSupportPlan> tickPlanItem(int orgId, int planId, int itemId, String status, {ApiClient? client}) async =>
      AdvSupportPlan.fromJson(asMap(await (client ?? ApiClient()).post('${_member(orgId)}/plans/$planId/items/$itemId/status', body: {'status': status})));
}
