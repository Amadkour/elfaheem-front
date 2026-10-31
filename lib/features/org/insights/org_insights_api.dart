// lib/features/org/insights/org_insights_api.dart
//
// GET /api/v1/org/orgs/{id}/insights (spec §4) and the period the person last picked per organization (device-local,
// every read / write in try/catch: private windows and cleared storage just fall back to the server's default).
//
//   OrgInsightsApi.load(orgId, query)   → OrgInsightsLoad: data · forbidden (403: students, members without
//                                         rights) · missing (an older server: bare 404 / 405 → the caller keeps its
//                                         old trends) · error (friendly text + Retry)
//   OrgInsightsPrefs.read / write       the saved OrgPeriodChoice ('org_insights_period_<orgId>')
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/app_time.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../org_providers.dart' show orgBase;
import '../org_v3.dart' show orgEndpointMissing, orgErrorText;
import 'org_insights.dart';

class OrgInsightsLoad {
  const OrgInsightsLoad._({this.data, this.error, this.code, this.missing = false, this.forbidden = false});

  const OrgInsightsLoad.ok(OrgInsights d) : this._(data: d);
  const OrgInsightsLoad.missing() : this._(missing: true);
  const OrgInsightsLoad.forbidden([String? code]) : this._(forbidden: true, code: code);
  const OrgInsightsLoad.failed(String message, [String? code]) : this._(error: message, code: code);

  final OrgInsights? data;

  /// The text to show (already user-safe, bilingual).
  final String? error;

  /// The server's code (bad_range · range_too_long · date_out_of_range · term_not_found · org_forbidden · student_forbidden …).
  final String? code;

  /// The server has no insights route yet.
  final bool missing;

  /// The caller may not see insights here: draw nothing.
  final bool forbidden;

  bool get ok => data != null;

  /// The period was refused (a stale saved term, a bad custom range): ask again with the server's default.
  bool get badPeriod =>
      code == 'term_not_found' || code == 'bad_range' || code == 'range_too_long' || code == 'date_out_of_range';
}

/// The real call; a test or a render hands its own [OrgInsightsSource] to the section instead.
typedef OrgInsightsSource = Future<OrgInsightsLoad> Function(int orgId, Map<String, String>? query);

abstract final class OrgInsightsApi {
  static Future<OrgInsightsLoad> load(int orgId, Map<String, String>? query, {ApiClient? api}) async {
    try {
      final r = await (api ?? ApiClient()).get('$orgBase/orgs/$orgId/insights', queryParams: query);
      return OrgInsightsLoad.ok(OrgInsights.fromJson(r));
    } catch (e) {
      final err = ApiException.from(e);
      if (orgEndpointMissing(err)) return const OrgInsightsLoad.missing();
      if (err.statusCode == 403) return OrgInsightsLoad.forbidden(err.code);
      return OrgInsightsLoad.failed(orgErrorText(err), err.code);
    }
  }
}

/// Insights may be asked for before the section exists: the org home starts the call IN PARALLEL with its dashboard
/// call when the session already says the person sees Insights first (an admin), so the section's data is not a
/// second step of a waterfall. The section then takes that answer ([loadShared]) instead of asking again. An
/// answer nobody took within [maxAge] is dropped (the dashboard said `can_insights: false`, the page closed …).
/// Today in the effective timezone (the organization's while it is open), as a calendar day.
DateTime orgInsightsToday() {
  final w = AppTime.toZone(DateTime.now().toUtc());
  return DateTime.utc(w.year, w.month, w.day);
}

abstract final class OrgInsightsPrefetch {
  static const maxAge = Duration(seconds: 30);
  static final Map<String, (DateTime, Future<OrgInsightsLoad>)> _inflight = {};

  static String _key(int orgId, Map<String, String>? q) {
    final e = (q ?? const <String, String>{}).entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return '$orgId?${e.map((x) => '${x.key}=${x.value}').join('&')}';
  }

  /// Starts GET …/insights with the period saved for [orgId] (a term choice asks for the server's default: the
  /// terms are not known yet — the section does the same on its first call). [today] = the org's calendar day.
  static Future<void> start(int orgId, DateTime today, {ApiClient? api}) async {
    final saved = await OrgInsightsPrefs.read(orgId);
    final q = saved?.query(const [], today);
    final key = _key(orgId, q);
    final have = _inflight[key];
    if (have != null && DateTime.now().difference(have.$1) < maxAge) return;
    _inflight[key] = (DateTime.now(), OrgInsightsApi.load(orgId, q, api: api));
  }

  /// The prefetched answer for exactly this request (taken once), else a new call.
  static Future<OrgInsightsLoad> loadShared(int orgId, Map<String, String>? query, {ApiClient? api}) {
    final hit = _inflight.remove(_key(orgId, query));
    if (hit != null && DateTime.now().difference(hit.$1) < maxAge) return hit.$2;
    return OrgInsightsApi.load(orgId, query, api: api);
  }

  @visibleForTesting
  static void reset() => _inflight.clear();
}

/// Whether the session already says I see Insights here — the server's `insights_allowed`
/// (services/organization/dashboards.py): an org admin, or `students` / `academic` / `courses` view org-wide or in
/// at least one department. The dashboard's `can_insights` stays the final word for drawing the section.
bool orgInsightsAllowedBy({required String access, required bool Function(String module) canAnyView}) =>
    access == 'admin' || const ['students', 'academic', 'courses'].any(canAnyView);

abstract final class OrgInsightsPrefs {
  static String _key(int orgId) => 'org_insights_period_$orgId';

  static Future<OrgPeriodChoice?> read(int orgId) async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key(orgId));
      return raw == null ? null : OrgPeriodChoice.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(int orgId, OrgPeriodChoice? choice) async {
    try {
      final p = await SharedPreferences.getInstance();
      if (choice == null) {
        await p.remove(_key(orgId));
      } else {
        await p.setString(_key(orgId), jsonEncode(choice.toJson()));
      }
    } catch (_) {}
  }
}
