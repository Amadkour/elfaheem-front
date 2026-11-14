// lib/features/org/advising/adv_analytics_api.dart — the HTTP client of the Academic Advising analytics, outreach,
// compliance and health check (Phase 8, docs/advising/PHASE8.md): one method per server route; answers are parsed
// into adv_analytics_models.dart. Every method throws `ApiException` (wrap calls in `orgCall` to toast
// `orgErrorText`); a missing route (older server) surfaces as `orgEndpointMissing`, and the screens then say the
// feature needs a server update. Reports (PDF / Excel, scheduled e-mails) are Export Studio datasets: they go
// through `ExportStudioApi.instance` (adv_reports.dart), never through this client.
library;

import '../../../core/api_client.dart';
import '../../admin/admin_common.dart' show asMap, asMapList;
import '../org_providers.dart' show orgBase;
import 'adv_analytics_models.dart';
import 'adv_models.dart' show AdvCaseItem, AdvPage, AdvStatus;

/// A drill list: the workspace envelope and items, plus the metric it shows.
class AdvDrillResult {
  const AdvDrillResult({required this.page, this.metric = const AdvDrillMetric()});
  final AdvPage<AdvCaseItem> page;
  final AdvDrillMetric metric;
}

/// The staff status with the Phase 8 keys of `me` (analytics tier, may send outreach, health issues).
class AdvStatusPlus {
  const AdvStatusPlus(this.status, this.analytics);
  final AdvStatus status;
  final AdvAnalyticsMe analytics;
}

class AdvAnalyticsApi {
  AdvAnalyticsApi(this.orgId, {ApiClient? client}) : _api = client ?? ApiClient();

  final int orgId;
  final ApiClient _api;

  String get base => '$orgBase/orgs/$orgId/advising';

  /// The staff status (`GET …/status`) read once, parsed both as the Phase 2–4 status and as the Phase 8 keys.
  Future<AdvStatusPlus> status() async {
    final j = asMap(await _api.get('$base/status'));
    return AdvStatusPlus(AdvStatus.fromJson(j), AdvAnalyticsMe.fromStatus(j));
  }

  // ── Dashboard ─────────────────────────────────────────────────────────────

  /// Manage · aggregate: terms, programs, levels, cohorts, advisors (manage), categories, bands, metrics, the tier.
  Future<AdvAnalyticsOptions> options() async => AdvAnalyticsOptions.fromJson(asMap(await _api.get('$base/analytics/options')));

  /// Manage · aggregate. 422 `advising_bad_range` for a range over 400 days or reversed. The default view is the
  /// copy the server stores every 10 minutes (`computed_at`); [fresh] computes it now (an explicit Refresh only:
  /// 12 an hour per user, then 429 `advising_rate_limited`).
  Future<AdvOverview> overview(AdvAnalyticsFilter filter, {bool fresh = false}) async => AdvOverview.fromJson(
      asMap(await _api.get('$base/analytics/overview', queryParams: {...filter.toQuery(), if (fresh) 'fresh': 1})));

  /// Manage · aggregate. [sort] one of [advAdvisorStatSorts]; facets `active` · `inactive` · `over` · `warn`.
  Future<AdvPage<AdvAdvisorStat>> advisors(AdvAnalyticsFilter filter, {String q = '', String sort = 'load', int page = 1, int size = 25}) async => AdvPage.fromJson(
        asMap(await _api.get('$base/analytics/advisors', queryParams: {
          ...filter.toQuery(),
          if (q.trim().isNotEmpty) 'q': q.trim(),
          'sort': sort,
          'page': page,
          'size': size,
        })),
        AdvAdvisorStat.fromJson,
      );

  /// Manage: the students behind a figure. 422 `advising_bad_metric`; the aggregate tier 403 `advising_forbidden`.
  Future<AdvDrillResult> students(AdvDrill drill, AdvAnalyticsFilter filter, {String q = '', String sort = 'risk', int page = 1, int size = 25}) async {
    final j = asMap(await _api.get('$base/analytics/students', queryParams: {
      ...drill.toQuery(),
      ...filter.toQuery(),
      if (q.trim().isNotEmpty) 'q': q.trim(),
      'sort': sort,
      'page': page,
      'size': size,
    }));
    return AdvDrillResult(page: AdvPage.fromJson(j, AdvCaseItem.fromJson), metric: AdvDrillMetric.fromJson(asMap(j['metric'])));
  }

  /// Manage · aggregate. [termId] null = the latest term with results, else the current one.
  Future<AdvCompliance> compliance({int? termId}) async =>
      AdvCompliance.fromJson(asMap(await _api.get('$base/analytics/compliance', queryParams: {'term_id': ?termId})));

  /// Manage: the daily run now (202). 409 `advising_run_busy` (+ `run_id`); 429 `advising_rate_limited`.
  Future<AdvAnalyticsRun> refresh() async => AdvAnalyticsRun.fromJson(asMap(asMap(await _api.post('$base/analytics/refresh'))['run']));

  /// Manage. [kind] `daily` · `health` · null (both).
  Future<AdvPage<AdvAnalyticsRun>> runs({String? kind, int page = 1, int size = 20}) async => AdvPage.fromJson(
        asMap(await _api.get('$base/analytics/runs', queryParams: {'kind': ?kind, 'page': page, 'size': size})),
        AdvAnalyticsRun.fromJson,
      );

  // ── Health check ──────────────────────────────────────────────────────────

  /// Manage: the latest check.
  Future<AdvHealth> health() async => AdvHealth.fromJson(asMap(await _api.get('$base/health-check')));

  /// Manage: checks now and answers the result (budget shared with the refresh).
  Future<AdvHealth> runHealth() async => AdvHealth.fromJson(asMap(await _api.post('$base/health-check/run')));

  // ── Outreach ──────────────────────────────────────────────────────────────

  /// Manage · advisor: who would receive it (0 recipients is an answer, not an error).
  Future<AdvOutreachPreview> preview(AdvAudience audience) async =>
      AdvOutreachPreview.fromJson(asMap(await _api.post('$base/outreach/preview', body: {'audience': audience.toJson()})));

  /// Manage · advisor (202; a repeated `client_id` answers the stored one). 422 `advising_audience_empty` /
  /// `advising_audience_too_large` / `advising_bad_template`; 409 `advising_audience_changed` (+ `count`,
  /// `audience_hash`); 429 `advising_rate_limited`.
  Future<AdvOutreach> send(AdvAudience audience, String audienceHash, AdvOutreachDraft draft) async =>
      AdvOutreach.fromJson(asMap(await _api.post('$base/outreach', body: draft.toJson(audience, audienceHash))));

  /// Manage: every message ([mine] = only mine); an advisor: their own.
  Future<AdvPage<AdvOutreach>> outreachList({bool mine = false, int page = 1, int size = 20}) async => AdvPage.fromJson(
        asMap(await _api.get('$base/outreach', queryParams: {if (mine) 'mine': 1, 'page': page, 'size': size})),
        AdvOutreach.fromJson,
      );

  /// Manage · its sender: the message with its body and audience.
  Future<AdvOutreach> outreach(int id) async => AdvOutreach.fromJson(asMap(await _api.get('$base/outreach/$id')));

  /// Manage · its sender. [state] one of [advRecipientStates]; facets `unread` · `read` · `failed`.
  Future<AdvPage<AdvOutreachRecipient>> recipients(int id, {String state = 'all', String q = '', int page = 1, int size = 25}) async => AdvPage.fromJson(
        asMap(await _api.get('$base/outreach/$id/recipients', queryParams: {'state': state, if (q.trim().isNotEmpty) 'q': q.trim(), 'page': page, 'size': size})),
        AdvOutreachRecipient.fromJson,
      );

  /// The organization's active outreach templates (Phase 5 route).
  Future<List<AdvOutreachTemplate>> templates() async => [
        for (final m in asMapList(asMap(await _api.get('$base/templates', queryParams: {'kind': 'outreach'}))['items']))
          if (AdvOutreachTemplate.fromJson(m).active) AdvOutreachTemplate.fromJson(m),
      ];

  // ── Member side (the student, own membership) ─────────────────────────────

  static String _member(int orgId) => '$orgBase/public/$orgId/advising';

  /// The messages I received, newest first (`unread` in the envelope's facets or at its top).
  static Future<(AdvPage<AdvStudentMessage>, int)> memberOutreach(int orgId, {int page = 1, int size = 20, ApiClient? client}) async {
    final j = asMap(await (client ?? ApiClient()).get('${_member(orgId)}/outreach', queryParams: {'page': page, 'size': size}));
    final p = AdvPage.fromJson(j, AdvStudentMessage.fromJson);
    final unread = j.containsKey('unread') ? (j['unread'] as num?)?.toInt() ?? 0 : p.facet('unread');
    return (p, unread);
  }

  /// Idempotent; not a recipient → 404 `advising_not_found`.
  static Future<DateTime?> markOutreachRead(int orgId, int id, {ApiClient? client}) async {
    final j = asMap(await (client ?? ApiClient()).post('${_member(orgId)}/outreach/$id/read'));
    return AdvStudentMessage.fromJson({'id': id, 'read_at': j['read_at']}).readAt;
  }
}
