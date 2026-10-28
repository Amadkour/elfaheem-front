// The assistant's monitoring alerts and the extractive gate's report (rag_alerts.dart): parsing (tolerant of every
// missing key), the value / detail texts in both languages, the rules document the form edits, the home's
// "Needs you" rows (ragAdminAlert, AdminHomeData.withAlerts), and the weekly report.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/admin/admin_home_data.dart';
import 'package:flutter_education_app/features/shared/rag/rag_alerts.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> alertJson({String key = 'p95_latency', String state = 'open', String severity = 'warning', Object? value = 41200,
        Object? threshold = 30000, String unit = 'ms', Map<String, dynamic>? detail, int id = 1}) =>
    {
      'id': id,
      'key': key,
      'rule': key.split('.').first,
      'state': state,
      'severity': severity,
      'value': value,
      'threshold': threshold,
      'unit': unit,
      'detail': detail ?? {'questions': 42, 'window_hours': 1},
      'title': {'ar': 'زمن إجابة المساعد مرتفع', 'en': 'Assistant answers are slow'},
      'opened_at': '2026-10-28T10:00:00Z',
      'last_seen_at': '2026-10-28T10:05:00Z',
      'resolved_at': state == 'open' ? null : '2026-10-28T11:00:00Z',
      'resolved_by': null,
      'notified': true,
    };

Map<String, dynamic> rulesJson() => {
      'enabled': true,
      'p95_latency': {'enabled': true, 'threshold_s': 30, 'window_hours': 1, 'min_questions': 1},
      'not_found_rate': {'enabled': true, 'threshold_pct': 25, 'window_hours': 24, 'min_questions': 20},
      'thumbs_down_rate': {'enabled': true, 'threshold_pct': 20, 'window_days': 7, 'min_votes': 10},
      'ingest_failures': {'enabled': true, 'threshold': 0, 'window_hours': 24},
      'polling_share': {'enabled': true, 'threshold_pct': 50, 'window_hours': 1, 'min_answers': 20},
      'model_fallback': {'enabled': true},
    };

Map<String, dynamic> alertsJson() => {
      'items': [
        alertJson(),
        alertJson(id: 2, key: 'not_found_rate', value: 0.3103, threshold: 0.25, unit: 'ratio', detail: {'questions': 29, 'not_found': 9, 'window_hours': 24}),
        alertJson(id: 3, key: 'model_fallback.generator', severity: 'danger', value: null, threshold: null, unit: 'state',
            detail: {'model': 'generator', 'problem': 'promoted_not_served', 'served': 'qwen3@int4', 'expected': 'ft-1'}),
        alertJson(id: 4, key: 'ingest_failures', state: 'resolved', severity: 'danger', value: 2, threshold: 0, unit: 'count',
            detail: {'failed': 2, 'window_hours': 24}),
      ],
      'rules': rulesJson(),
      'defaults': rulesJson(),
      'polling_signal': true,
      'interval_seconds': 300,
    };

Map<String, dynamic> gateJson() => {
      'since': '2026-09-07T00:00:00Z',
      'weeks': [
        {'week': '2026-W43', 'start': '2026-10-19', 'refused': 0, 'answered': 0, 'not_found': 0, 'rejected': 0, 'writer_answered': 0, 'helpful': 0, 'unhelpful': 0},
        {'week': '2026-W44', 'start': '2026-10-26', 'refused': 3, 'answered': 1, 'not_found': 1, 'rejected': 1, 'writer_answered': 1, 'helpful': 0, 'unhelpful': 1},
      ],
      'totals': {'refused': 3, 'answered': 1, 'not_found': 1, 'rejected': 1, 'writer_answered': 1, 'helpful': 0, 'unhelpful': 1, 'p50_ms': 14200},
      'items': [
        {'query_id': 9, 'question': 'How many devices?', 'answer': 'Two.', 'context': 'app', 'org_id': null, 'outcome': 'answered',
          'writer_answered': true, 'writer': 'qwen3-1.7b', 'generator': 'llm:qwen3-1.7b', 'fallback': null, 'latency_ms': 14200,
          'helpful': false, 'comment': 'too long', 'at': '2026-10-28T09:00:00Z'},
        {'query_id': 8, 'question': 'Course question', 'context': 'docs', 'org_id': null, 'outcome': 'rejected', 'writer_answered': false},
        {'query_id': 7, 'question': 'Org question', 'context': 'docs', 'org_id': 4, 'outcome': 'not_found'},
      ],
    };

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('RagAlert', () {
    test('parses and formats every unit', () {
      final d = RagAlertsData.fromJson(alertsJson());
      expect(d.items.length, 4);
      expect(d.open.map((a) => a.id).toList(), [1, 2, 3]);
      expect(d.resolved.single.key, 'ingest_failures');
      expect(d.pollingSignal, isTrue);
      expect(d.intervalSeconds, 300);
      final p95 = d.items[0];
      expect(p95.isOpen && !p95.isDanger && p95.notified, isTrue);
      expect(p95.valueText, '41.2 s > 30.0 s');
      expect(p95.detailText, '42 questions in 1 h');
      expect(p95.title, 'Assistant answers are slow');
      expect(d.items[1].valueText, '31% > 25%');
      expect(d.items[1].detailText, '9 of 29 questions in 24 h');
      expect(d.items[2].isDanger, isTrue);
      expect(d.items[2].valueText, 'generator · promoted version not served');
      expect(d.items[2].detailText, 'Served: qwen3@int4');
      expect(d.items[3].valueText, '2 > 0');
      AppConfig.lang = 'ar';
      expect(p95.title, 'زمن إجابة المساعد مرتفع');
      expect(d.items[1].detailText, contains('29'));
    });

    test('polling_share: the rule, its fields and the alert', () {
      final d = RagAlertsData.fromJson(alertsJson());
      expect(ragAlertRuleKeys, contains('polling_share'));
      expect(d.rules!.has('polling_share'), isTrue);
      expect(d.rules!.fields('polling_share'), ['threshold_pct', 'window_hours', 'min_answers']);
      expect(d.rules!.withField('polling_share', 'min_answers', 30).toJson()['polling_share'],
          {'enabled': true, 'threshold_pct': 50, 'window_hours': 1, 'min_answers': 30});
      expect(ragAlertFieldLabel('min_answers'), 'Minimum answers');
      expect(ragAlertRuleTitle('polling_share'), 'Answers by polling');
      expect(ragAlertRuleHint('polling_share'), isNotEmpty);
      final a = RagAlert.fromJson(alertJson(id: 5, key: 'polling_share', value: 0.6, threshold: 0.5, unit: 'ratio',
          detail: {'answers': 20, 'poll': 12, 'stream': 7, 'mixed': 1, 'window_hours': 1}));
      expect(a.valueText, '60% > 50%');
      expect(a.detailText, '12 of 20 answers by polling in 1 h');
      AppConfig.lang = 'ar';
      expect(a.detailText, contains('20'));
      expect(ragAlertRuleTitle('polling_share'), isNot('Answers by polling'));
    });

    test('tolerates an empty payload and missing keys', () {
      final d = RagAlertsData.fromJson(const {});
      expect(d.items, isEmpty);
      expect(d.rules, isNull);
      final a = RagAlert.fromJson(const {'key': 'thumbs_down_rate'});
      expect(a.rule, 'thumbs_down_rate');
      expect(a.title, 'Thumbs-down rate'); // no title from the server: the app's own
      expect(a.valueText, '');
      expect(a.openedAt, isNull);
    });

    test('ragAlertValueText', () {
      expect(ragAlertValueText(850, 'ms'), '850 ms');
      expect(ragAlertValueText(12400, 'ms'), '12.4 s');
      expect(ragAlertValueText(0.255, 'ratio'), '26%');
      expect(ragAlertValueText(3, 'count'), '3');
      expect(ragAlertValueText(null, 'ms'), '—');
      expect(ragAlertValueText(1, null), '—');
    });
  });

  group('RagAlertRules', () {
    test('edits are copies; toJson sends the whole document', () {
      final r = RagAlertRules(rulesJson());
      expect(r.enabled, isTrue);
      expect(r.fields('not_found_rate'), ['threshold_pct', 'window_hours', 'min_questions']);
      expect(r.fields('model_fallback'), isEmpty);
      expect(r.field('p95_latency', 'threshold_s'), 30);
      final r2 = r.withField('p95_latency', 'threshold_s', 45).withRule('ingest_failures', false).withEnabled(false);
      expect(r.field('p95_latency', 'threshold_s'), 30);
      expect(r.ruleOn('ingest_failures'), isTrue);
      expect(r2.field('p95_latency', 'threshold_s'), 45);
      expect(r2.ruleOn('ingest_failures'), isFalse);
      expect(r2.enabled, isFalse);
      final j = r2.toJson();
      expect(j['p95_latency'], {'enabled': true, 'threshold_s': 45, 'window_hours': 1, 'min_questions': 1});
      expect(j.keys.toSet(), rulesJson().keys.toSet());
      expect(ragAlertRuleKeys.every(r.has), isTrue);
    });
  });

  group('the home', () {
    test('ragAdminAlert + withAlerts', () {
      final d = RagAlertsData.fromJson(alertsJson());
      final rows = [for (final a in d.open) ragAdminAlert(a)];
      expect(rows.first.key, 'rag.p95_latency');
      expect(rows.first.isRag, isTrue);
      expect(rows.first.title, 'Assistant answers are slow');
      expect(rows.first.hint, '41.2 s > 30.0 s');
      expect(rows[2].isDanger, isTrue);
      final home = AdminHomeData.fromOverview({
        'alerts': [
          {'key': 'jobs_failed_24h', 'severity': 'danger', 'count': 2},
        ],
      });
      expect(identical(home.withAlerts(const []), home), isTrue);
      final merged = home.withAlerts(rows);
      expect(merged.alerts.map((a) => a.key).toList(), ['jobs_failed_24h', 'rag.p95_latency', 'rag.not_found_rate', 'rag.model_fallback.generator']);
      expect(merged.hasAlerts, isTrue);
      expect(merged.jobsFailed24h, 2);
      expect(merged.queueTotal(0), 2 + 3);
      expect(home.alerts.length, 1);
      expect(const AdminAlert(key: 'jobs_failed_24h', severity: 'danger', count: 1).isRag, isFalse);
    });
  });

  group('RagGateReport', () {
    test('totals, weeks, items', () {
      final r = RagGateReport.fromJson(gateJson());
      expect(r.isEmpty, isFalse);
      expect(r.totals.refused, 3);
      expect(r.totals.writerRate, closeTo(1 / 3, 1e-9));
      expect(r.p50Ms, 14200);
      expect(r.weeks.length, 2);
      expect(r.weeks.first.writerRate, isNull);
      final first = r.items.first;
      expect(first.writerAnswered, isTrue);
      expect(first.writer, 'qwen3-1.7b');
      expect(first.helpful, isFalse);
      expect(first.comment, 'too long');
      expect(first.promotable, isTrue);
      expect(r.items[1].promotable, isFalse); // a personal course: no Q&A scope
      expect(r.items[2].promotable, isTrue);
      expect(r.items[1].helpful, isNull);
      expect(ragGateOutcomeText('rejected'), 'Rejected by checks');
      AppConfig.lang = 'ar';
      expect(ragGateOutcomeText('answered'), 'أجاب');
    });

    test('an empty report', () {
      final r = RagGateReport.fromJson(const {});
      expect(r.isEmpty, isTrue);
      expect(r.items, isEmpty);
      expect(r.p50Ms, isNull);
    });
  });
}
