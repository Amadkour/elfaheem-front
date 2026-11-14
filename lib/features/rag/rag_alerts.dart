// The assistant's monitoring alerts and the extractive gate's report — pure models + API (RAG service,
// /api/v1/rag/admin/…, back: rag_service/alerts.py, gate_report.py, routers/alerts.py). Unit-tested in
// test/org/rag_alerts_test.dart; the widgets are in rag_alerts_page.dart.
//
//   GET  /admin/alerts?state=open|resolved   {items: [RagAlert], rules, defaults, polling_signal, interval_seconds}
//   PUT  /admin/alerts/rules {any subset}    → {rules}  (Super Admin; 422 bad_setting)
//   POST /admin/alerts/evaluate              run the worker's evaluation now (Super Admin)
//   POST /admin/alerts/{id}/resolve          → the alert; not reopened until its condition cleared once
//   GET  /admin/gate-refused?weeks=8         the questions the extractive gate refused (D-066 evidence) → [RagGateReport]
//
// [ragAdminAlert] turns an open alert into a row of the super admin home's "Needs you" (admin_home_data.dart).
library;

import 'package:flutter_education_app/core/api_client.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show asBool, asDouble, asInt, asMap, asMapList, asStr, t;
import 'package:flutter_education_app/features/admin/admin_home_data.dart' show AdminAlert;
import 'package:flutter_education_app/features/exams/exam_engine_api.dart' show EngineResult, engineCall;

/// The rules the console edits, in the order it shows them.
const ragAlertRuleKeys = ['p95_latency', 'not_found_rate', 'thumbs_down_rate', 'ingest_failures', 'polling_share', 'model_fallback'];

/// "41.2 s" · "31%" · "3" · "—".
String ragAlertValueText(double? v, String? unit) {
  if (v == null) return '—';
  return switch (unit) {
    'ms' => v < 1000 ? '${v.round()} ms' : '${(v / 1000).toStringAsFixed(1)} s',
    'ratio' => '${(v * 100).round()}%',
    'count' => '${v.round()}',
    _ => '—',
  };
}

/// The label of a rule's number field.
String ragAlertFieldLabel(String field) => switch (field) {
      'threshold_s' => t('الحد (ثانية)', 'Threshold (seconds)'),
      'threshold_pct' => t('الحد (٪)', 'Threshold (%)'),
      'threshold' => t('الحد (عدد)', 'Threshold (count)'),
      'window_hours' => t('النافذة (ساعات)', 'Window (hours)'),
      'window_days' => t('النافذة (أيام)', 'Window (days)'),
      'min_questions' => t('أقل عدد من الأسئلة', 'Minimum questions'),
      'min_votes' => t('أقل عدد من التقييمات', 'Minimum votes'),
      'min_answers' => t('أقل عدد من الإجابات', 'Minimum answers'),
      _ => field,
    };

String ragAlertRuleTitle(String rule) => switch (rule) {
      'p95_latency' => t('زمن الإجابة (p95)', 'Answer time (p95)'),
      'not_found_rate' => t('نسبة «لم أجد إجابة»', 'Not-found rate'),
      'thumbs_down_rate' => t('نسبة التقييمات السلبية', 'Thumbs-down rate'),
      'ingest_failures' => t('فشل معالجة المستندات', 'Ingestion failures'),
      'polling_share' => t('الإجابات عبر الاستطلاع', 'Answers by polling'),
      'model_fallback' => t('النموذج المُحمَّل ليس المطلوب', 'Model fallback'),
      _ => rule,
    };

String ragAlertRuleHint(String rule) => switch (rule) {
      'p95_latency' => t('ينبّه حين يتجاوز زمن 95٪ من الإجابات الحد', 'Fires when 95% of answers take longer than the threshold'),
      'not_found_rate' => t('حصة الأسئلة التي لم تجد إجابة', 'Share of the questions that found no answer'),
      'thumbs_down_rate' => t('حصة التقييمات السلبية من كل التقييمات', 'Share of thumbs-down among the votes'),
      'ingest_failures' => t('مستندات فشلت معالجتها', 'Documents whose processing failed'),
      'polling_share' => t('حصة الإجابات التي وصلت للتطبيق بالاستطلاع لا بالبث المباشر',
          'Share of the answers the app got by polling instead of the live stream'),
      'model_fallback' => t('نموذج الكتابة أو الترتيب لم يُحمَّل أو عاد للنسخة الأصلية', 'The writer or re-ranker did not load, or fell back to the shipped model'),
      _ => '',
    };

class RagAlert {
  const RagAlert({
    required this.id,
    required this.key,
    this.rule = '',
    this.state = 'open',
    this.severity = 'warning',
    this.value,
    this.threshold,
    this.unit,
    this.detail = const {},
    this.titleAr = '',
    this.titleEn = '',
    this.openedAt,
    this.resolvedAt,
    this.resolvedBy,
    this.notified = false,
  });

  /// Tolerant of every missing key.
  factory RagAlert.fromJson(Map<String, dynamic> j) {
    final title = asMap(j['title']);
    final key = asStr(j['key']);
    return RagAlert(
      id: asInt(j['id']),
      key: key,
      rule: asStr(j['rule'], key.split('.').first),
      state: asStr(j['state'], 'open'),
      severity: asStr(j['severity'], 'warning'),
      value: j['value'] == null ? null : asDouble(j['value']),
      threshold: j['threshold'] == null ? null : asDouble(j['threshold']),
      unit: j['unit'] == null ? null : asStr(j['unit']),
      detail: asMap(j['detail']),
      titleAr: asStr(title['ar']),
      titleEn: asStr(title['en']),
      openedAt: DateTime.tryParse(asStr(j['opened_at'])),
      resolvedAt: DateTime.tryParse(asStr(j['resolved_at'])),
      resolvedBy: j['resolved_by'] == null ? null : asInt(j['resolved_by']),
      notified: asBool(j['notified']),
    );
  }

  final int id;
  final String key, rule, state, severity;
  final double? value, threshold;
  final String? unit;
  final Map<String, dynamic> detail;
  final String titleAr, titleEn;
  final DateTime? openedAt, resolvedAt;
  final int? resolvedBy;
  final bool notified;

  bool get isOpen => state == 'open';
  bool get isDanger => severity == 'danger';

  String get title {
    final s = t(titleAr, titleEn);
    return s.isEmpty ? ragAlertRuleTitle(rule) : s;
  }

  /// "41.2 s > 30 s" · "31% > 25%" · the model's problem.
  String get valueText {
    if (unit == 'state' || value == null) {
      final problem = asStr(detail['problem']);
      final model = asStr(detail['model']);
      final what = switch (problem) {
        'unavailable' => t('غير مُحمَّل', 'not loaded'),
        'promoted_not_served' => t('النسخة المعتمدة لم تُحمَّل', 'promoted version not served'),
        _ => problem,
      };
      return [if (model.isNotEmpty) model, if (what.isNotEmpty) what].join(' · ');
    }
    return '${ragAlertValueText(value, unit)} > ${ragAlertValueText(threshold, unit)}';
  }

  /// The window and the sample size behind the value.
  String get detailText {
    final d = detail;
    return switch (rule) {
      'p95_latency' => t('${asInt(d['questions'])} سؤال خلال ${asInt(d['window_hours'])} ساعة', '${asInt(d['questions'])} questions in ${asInt(d['window_hours'])} h'),
      'not_found_rate' => t('${asInt(d['not_found'])} من ${asInt(d['questions'])} سؤال خلال ${asInt(d['window_hours'])} ساعة',
          '${asInt(d['not_found'])} of ${asInt(d['questions'])} questions in ${asInt(d['window_hours'])} h'),
      'thumbs_down_rate' => t('${asInt(d['down'])} من ${asInt(d['votes'])} تقييم خلال ${asInt(d['window_days'])} يوم',
          '${asInt(d['down'])} of ${asInt(d['votes'])} votes in ${asInt(d['window_days'])} days'),
      'ingest_failures' => t('${asInt(d['failed'])} مستند خلال ${asInt(d['window_hours'])} ساعة', '${asInt(d['failed'])} documents in ${asInt(d['window_hours'])} h'),
      'polling_share' => t('${asInt(d['poll'])} من ${asInt(d['answers'])} إجابة بالاستطلاع خلال ${asInt(d['window_hours'])} ساعة',
          '${asInt(d['poll'])} of ${asInt(d['answers'])} answers by polling in ${asInt(d['window_hours'])} h'),
      'model_fallback' => asStr(d['served']).isEmpty ? '' : t('المُحمَّل: ${asStr(d['served'])}', 'Served: ${asStr(d['served'])}'),
      _ => '',
    };
  }
}

/// The rules document (`platform_settings.alerts`): a deep copy the form edits, sent back whole.
class RagAlertRules {
  RagAlertRules(Map<String, dynamic> json) : _j = _copy(json);

  final Map<String, dynamic> _j;

  static Map<String, dynamic> _copy(Map<String, dynamic> j) => {
        for (final e in j.entries) e.key: e.value is Map ? Map<String, dynamic>.from(asMap(e.value)) : e.value,
      };

  bool get enabled => _j['enabled'] != false;
  bool ruleOn(String rule) => asMap(_j[rule])['enabled'] != false;

  /// The number fields of a rule, in the server's order (`enabled` left out).
  List<String> fields(String rule) => [for (final k in asMap(_j[rule]).keys) if (k != 'enabled') k];
  num field(String rule, String f) {
    final v = asMap(_j[rule])[f];
    return v is num ? v : num.tryParse('$v') ?? 0;
  }

  bool has(String rule) => _j[rule] is Map;

  RagAlertRules withEnabled(bool v) => RagAlertRules({..._j, 'enabled': v});
  RagAlertRules withRule(String rule, bool v) => RagAlertRules({..._j, rule: {...asMap(_j[rule]), 'enabled': v}});
  RagAlertRules withField(String rule, String f, num v) => RagAlertRules({..._j, rule: {...asMap(_j[rule]), f: v}});

  Map<String, dynamic> toJson() => _copy(_j);
}

class RagAlertsData {
  const RagAlertsData({this.items = const [], this.rules, this.pollingSignal = false, this.intervalSeconds = 300});

  factory RagAlertsData.fromJson(Map<String, dynamic> j) => RagAlertsData(
        items: [for (final r in asMapList(j['items'])) RagAlert.fromJson(r)],
        rules: j['rules'] is Map ? RagAlertRules(asMap(j['rules'])) : null,
        pollingSignal: asBool(j['polling_signal']),
        intervalSeconds: asInt(j['interval_seconds'], 300),
      );

  final List<RagAlert> items;
  final RagAlertRules? rules;

  /// Whether the server records how answers reached the app (rag_0015: the `polling_share` rule); false on an
  /// older server, whose rules then simply lack that rule.
  final bool pollingSignal;
  final int intervalSeconds;

  List<RagAlert> get open => [for (final a in items) if (a.isOpen) a];
  List<RagAlert> get resolved => [for (final a in items) if (!a.isOpen) a];
}

/// An open alert as a row of the super admin home's "Needs you" (count 1; title / hint from the alert itself).
AdminAlert ragAdminAlert(RagAlert a) => AdminAlert(
      key: 'rag.${a.key}',
      severity: a.severity,
      count: 1,
      deepLink: 'rag_alerts',
      title: a.title,
      hint: a.valueText,
    );

// ── the extractive gate's report ─────────────────────────────────────────────────────────────────────────────

String ragGateOutcomeText(String outcome) => switch (outcome) {
      'answered' => t('أجاب', 'Answered'),
      'not_found' => t('لم يجد', 'Not found'),
      'rejected' => t('رفضته الفحوص', 'Rejected by checks'),
      _ => outcome,
    };

class RagGateWeek {
  const RagGateWeek({this.week = '', this.start = '', this.refused = 0, this.answered = 0, this.notFound = 0, this.rejected = 0,
      this.writerAnswered = 0, this.helpful = 0, this.unhelpful = 0});

  factory RagGateWeek.fromJson(Map<String, dynamic> j) => RagGateWeek(
        week: asStr(j['week']),
        start: asStr(j['start']),
        refused: asInt(j['refused']),
        answered: asInt(j['answered']),
        notFound: asInt(j['not_found']),
        rejected: asInt(j['rejected']),
        writerAnswered: asInt(j['writer_answered']),
        helpful: asInt(j['helpful']),
        unhelpful: asInt(j['unhelpful']),
      );

  final String week, start;
  final int refused, answered, notFound, rejected, writerAnswered, helpful, unhelpful;

  /// The writer's own answers as a share of the refused questions; null without any.
  double? get writerRate => refused == 0 ? null : writerAnswered / refused;
}

class RagGateItem {
  const RagGateItem({required this.queryId, this.question = '', this.answer = '', this.context = 'app', this.orgId, this.outcome = '',
      this.writerAnswered = false, this.writer, this.latencyMs, this.helpful, this.comment = '', this.at});

  factory RagGateItem.fromJson(Map<String, dynamic> j) => RagGateItem(
        queryId: asInt(j['query_id']),
        question: asStr(j['question']),
        answer: asStr(j['answer']),
        context: asStr(j['context'], 'app'),
        orgId: j['org_id'] == null ? null : asInt(j['org_id']),
        outcome: asStr(j['outcome']),
        writerAnswered: asBool(j['writer_answered']),
        writer: j['writer'] == null ? null : asStr(j['writer']),
        latencyMs: j['latency_ms'] == null ? null : asInt(j['latency_ms']),
        helpful: j['helpful'] is bool ? j['helpful'] as bool : null,
        comment: asStr(j['comment']),
        at: DateTime.tryParse(asStr(j['at'])),
      );

  final int queryId;
  final String question, answer, context, outcome, comment;
  final int? orgId, latencyMs;
  final bool writerAnswered;
  final String? writer;

  /// The asker's later thumbs (null: not rated).
  final bool? helpful;
  final DateTime? at;

  /// Course / organization questions without an organization cannot become a Q&A pair.
  bool get promotable => queryId > 0 && (context != 'docs' || orgId != null);
}

class RagGateReport {
  const RagGateReport({this.weeks = const [], this.totals = const RagGateWeek(), this.p50Ms, this.items = const []});

  factory RagGateReport.fromJson(Map<String, dynamic> j) {
    final tot = asMap(j['totals']);
    return RagGateReport(
      weeks: [for (final r in asMapList(j['weeks'])) RagGateWeek.fromJson(r)],
      totals: RagGateWeek.fromJson(tot),
      p50Ms: tot['p50_ms'] == null ? null : asInt(tot['p50_ms']),
      items: [for (final r in asMapList(j['items'])) RagGateItem.fromJson(r)],
    );
  }

  final List<RagGateWeek> weeks;
  final RagGateWeek totals;
  final int? p50Ms;
  final List<RagGateItem> items;

  bool get isEmpty => totals.refused == 0;
}

// ── API ──────────────────────────────────────────────────────────────────────────────────────────────────────

class RagAlertsApi {
  RagAlertsApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;
  static const base = '/api/v1/rag/admin';

  Future<EngineResult> list({String? state, int limit = 50}) =>
      engineCall(() => _api.get('$base/alerts', queryParams: {'state': ?state, 'limit': limit}));
  Future<EngineResult> saveRules(Map<String, dynamic> rules) => engineCall(() => _api.put('$base/alerts/rules', body: rules));
  Future<EngineResult> evaluate() => engineCall(() => _api.post('$base/alerts/evaluate'));
  Future<EngineResult> resolve(int id) => engineCall(() => _api.post('$base/alerts/$id/resolve'));
  Future<EngineResult> gateRefused({int weeks = 8, int limit = 100}) =>
      engineCall(() => _api.get('$base/gate-refused', queryParams: {'weeks': weeks, 'limit': limit}));
}
