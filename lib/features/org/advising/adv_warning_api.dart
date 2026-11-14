// lib/features/org/advising/adv_warning_api.dart — the HTTP client of the early warning (docs/advising/PHASE6.md
// "API"): rules and their preview, engine runs, alerts, the advisor's digest choice, the student 360's block and
// the graduation list. Every method throws `ApiException` (callers wrap them in `orgCall` and word failures with
// `advWarningErrorText`); a route the server lacks (an older server) surfaces as `orgEndpointMissing`, and the
// screens then say the feature needs a server update.
library;

import '../../../core/api_client.dart';
import '../../admin/admin_common.dart' show asMap, asMapList;
import '../org_providers.dart' show orgBase;
import 'adv_models.dart' show AdvPage;
import 'adv_warning_models.dart';

/// The kill switch of the early warning (`org.advising.warning`, not org-manageable).
const advWarningFeatureKey = 'org.advising.warning';

class AdvWarningApi {
  AdvWarningApi(this.orgId, {ApiClient? client}) : _api = client ?? ApiClient();

  final int orgId;
  final ApiClient _api;

  String get base => '$orgBase/orgs/$orgId/advising';

  // ── Rules ─────────────────────────────────────────────────────────────────

  /// Manage · advisors read-only (`can_edit` false).
  Future<AdvRulesBundle> rules() async => AdvRulesBundle.fromJson(asMap(await _api.get('$base/rules')));

  /// Manage. 422 `advising_bad_rule` (+ `field`, `reason`) / `advising_bad_category`, 409 `advising_rule_limit`.
  Future<AdvRule> addRule(AdvRuleDraft draft, AdvRuleKind? kind) async =>
      AdvRule.fromJson(asMap(await _api.post('$base/rules', body: draft.toJson(kind, create: true))));

  /// Manage. The whole rule (no `kind`).
  Future<AdvRule> saveRule(int id, AdvRuleDraft draft, AdvRuleKind? kind) async =>
      AdvRule.fromJson(asMap(await _api.put('$base/rules/$id', body: draft.toJson(kind))));

  /// Manage. 409 `advising_rule_system` for a built-in rule (switch it off instead).
  Future<void> deleteRule(int id) async => _api.delete('$base/rules/$id');

  /// Manage. Over the facts of the last run; nothing is written.
  Future<AdvRulePreview> preview(AdvRuleDraft draft, AdvRuleKind? kind) async =>
      AdvRulePreview.fromJson(asMap(await _api.post('$base/rules/preview', body: draft.previewBody(kind))));

  // ── Engine runs ───────────────────────────────────────────────────────────

  /// Manage. 202 with the run, which goes on after the answer (`job_updated{kind: advising_warning, id}` when it
  /// ends); 409 `advising_run_busy` (+ `run_id`) while one runs.
  Future<AdvWarningRun> runNow() async => AdvWarningRun.fromJson(asMap(asMap(await _api.post('$base/warning/run'))['run']));

  /// Manage. [kind] `evaluate` · `digest` (null: both).
  Future<AdvPage<AdvWarningRun>> runs({String? kind, int page = 1, int size = 10}) async => AdvPage.fromJson(
        asMap(await _api.get('$base/warning/runs', queryParams: {'kind': ?kind, 'page': page, 'size': size})),
        AdvWarningRun.fromJson,
      );

  Future<AdvWarningRun> run(int id) async => AdvWarningRun.fromJson(asMap(await _api.get('$base/warning/runs/$id')));

  // ── Alerts ────────────────────────────────────────────────────────────────

  /// Manage: the organization's; an advisor: their own students'. Newest first; facets `urgent` · `high` · `last_7d`.
  Future<AdvPage<AdvAlert>> alerts(AdvAlertQuery query) async =>
      AdvPage.fromJson(asMap(await _api.get('$base/alerts', queryParams: query.toQuery())), AdvAlert.fromJson);

  /// The alerts that opened or joined one flag ([] for a flag opened by hand).
  Future<List<AdvAlert>> flagAlerts(int flagId) async =>
      [for (final m in asMapList(asMap(await _api.get('$base/flags/$flagId/alerts'))['items'])) AdvAlert.fromJson(m)];

  Future<AdvAlertPrefs> prefs() async => AdvAlertPrefs.fromJson(asMap(await _api.get('$base/alerts/prefs')));

  /// [digest] `inherit` · `off` · `daily` · `weekly`.
  Future<AdvAlertPrefs> savePrefs(String digest) async => AdvAlertPrefs.fromJson(asMap(await _api.put('$base/alerts/prefs', body: {'digest': digest})));

  // ── The student 360 and graduation ────────────────────────────────────────

  /// 404 `advising_not_found` for a student the caller does not advise.
  Future<AdvWarning> student(int memberId) async => AdvWarning.fromJson(asMap(await _api.get('$base/students/$memberId/warning')));

  /// Evaluates that student now (synchronous; the `adv_write` budget) and answers the same body.
  Future<AdvWarning> evaluateStudent(int memberId) async => AdvWarning.fromJson(asMap(await _api.post('$base/students/$memberId/warning/run')));

  /// Delay first, then name; facets `delayed` · `at_risk` · `on_track` · `unknown`.
  Future<AdvPage<AdvGraduationItem>> graduation(AdvGraduationQuery query) async =>
      AdvPage.fromJson(asMap(await _api.get('$base/graduation', queryParams: query.toQuery())), AdvGraduationItem.fromJson);
}
