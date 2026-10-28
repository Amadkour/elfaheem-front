// RAG monitoring (Track E.7): the console's `monitoring` block (RagMonitoring: paths, latency per path, rates, the
// daily series and the half-window deltas), the super admin home's summary (AdminAssistantHealth), the formatters,
// and the settings' `conversation_retention_days` (parsed, clamped, always in the PUT body).
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/admin/admin_home_data.dart';
import 'package:flutter_education_app/features/shared/rag/rag_admin_console.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> monitoringJson({int days = 14}) => {
      'days': days,
      'since': '2026-10-15T00:00:00Z',
      'questions': 140,
      'latency_ms': {
        'p50': 900,
        'p95': 14000,
        'by_path': {
          'qa_direct': {'questions': 20, 'count': 20, 'p50': 30, 'p95': 70},
          'cache': {'questions': 30, 'count': 29, 'p50': 12, 'p95': 35},
          'extractive': {'questions': 60, 'count': 60, 'p50': 450, 'p95': 3200},
          'model': {'questions': 30, 'count': 28, 'p50': 11000, 'p95': 15800},
        },
      },
      'cache_hit_rate': 0.2143,
      'qa_direct_rate': 0.1429,
      'qa_example_rate': 0.05,
      'no_answer_rate': 0.1,
      'fallback_rate': 0.0214,
      'helpful_rate': 0.8,
      'counts': {'no_answer': 14, 'cache_hits': 30, 'qa_direct': 20},
      'delivery': {'stream': 70, 'poll': 25, 'mixed': 5, 'reported': 100, 'poll_rate': 0.25},
      'by_day': [
        for (var i = 0; i < days; i++)
          {
            'day': '2026-10-${(15 + i).toString().padLeft(2, '0')}',
            'questions': 10,
            'no_answer': i < days ~/ 2 ? 2 : 1,
            'cache_hits': i < days ~/ 2 ? 1 : 3,
            'qa_direct': 1,
            'p50_ms': i == 0 ? null : 800 + i,
          },
      ],
    };

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('RagMonitoring', () {
    test('parses paths in order, rates, latency and days', () {
      final m = RagMonitoring.fromJson(monitoringJson());
      expect(m.days, 14);
      expect(m.questions, 140);
      expect((m.p50, m.p95), (900, 14000));
      expect(m.byPath.keys.toList(), ragPaths);
      expect(m.byPath['cache']!.questions, 30);
      expect(m.byPath['cache']!.count, 29);
      expect(m.byPath['model']!.p95, 15800);
      expect(m.cacheHitRate, 0.2143);
      expect(m.noAnswerRate, 0.1);
      expect(m.helpfulRate, 0.8);
      expect(m.byDay.length, 14);
      expect(m.byDay.first.p50Ms, isNull);
      expect((m.pollRate, m.deliveryReported), (0.25, 100));
      final older = RagMonitoring.fromJson({...monitoringJson()}..remove('delivery'));
      expect((older.pollRate, older.deliveryReported), (null, 0));
      expect(m.byDay.first.dayLabel, '15');
      expect(m.hasActivity, isTrue);
    });

    test('sparks and half-window deltas', () {
      final m = RagMonitoring.fromJson(monitoringJson());
      expect(m.questionsSpark, List.filled(14, 10.0));
      expect(m.questionsDelta, 0); // the same volume in both halves
      expect(m.noAnswerSpark.first, closeTo(.2, 1e-9));
      expect(m.noAnswerDelta, closeTo(-50, 1e-9)); // 20 % → 10 %
      expect(m.cacheDelta, closeTo(200, 1e-9)); // 10 % → 30 %
      expect(m.qaDirectDelta, closeTo(0, 1e-9));
      expect(m.recent(7).length, 7);
      expect(m.recent(7).first.day, '2026-10-22');
      expect(m.recent(30).length, 14);
    });

    test('an empty window and an older server', () {
      final empty = RagMonitoring.fromJson({'days': 7, 'questions': 0, 'by_day': [for (var i = 0; i < 7; i++) {'day': '2026-10-0${i + 1}', 'questions': 0}]});
      expect(empty.hasActivity, isFalse);
      expect(empty.noAnswerRate, isNull);
      expect(empty.noAnswerSpark, List.filled(7, 0.0));
      expect(empty.noAnswerDelta, isNull);
      expect(empty.questionsDelta, isNull);
      expect(empty.byPath['model']!.p50, isNull);
      expect(RagOverview.fromJson({}).monitoring, isNull);
      expect(RagOverview.fromJson({'monitoring': monitoringJson()}).monitoring!.questions, 140);
    });

    test('halfRateDelta needs a base in both halves', () {
      expect(halfRateDelta([1, 1], [10, 10]), 0);
      expect(halfRateDelta([0, 1], [10, 10]), isNull); // no rate in the first half
      expect(halfRateDelta([1, 0], [10, 0]), isNull); // no question in the second half
      expect(halfRateDelta([1], [10]), isNull);
      expect(halfRateDelta([1, 2], [10]), isNull);
    });

    test('formatters and labels', () {
      expect(ragMsText(null), '—');
      expect(ragMsText(45), '45 ms');
      expect(ragMsText(1234), '1.2 s');
      expect(ragPctText(null), '—');
      expect(ragPctText(.2143), '21%');
      expect(ragPathLabel('qa_direct'), 'Direct Q&A');
      expect(ragPathLabel('anything'), 'Quoted from documents');
      AppConfig.lang = 'ar';
      expect(ragPathLabel('cache'), 'من الذاكرة المؤقتة');
    });
  });

  group('AdminAssistantHealth (the home card)', () {
    test('parses the summary', () {
      final h = AdminAssistantHealth.fromJson({
        'days': 7,
        'questions': 1234,
        'no_answer_rate': 0.125,
        'cache_hit_rate': 0.3,
        'latency_ms': {'p50': 12400, 'p95': 20000},
        'by_day': [for (var i = 0; i < 7; i++) {'day': '2026-10-2$i', 'questions': i, 'no_answer': 0}],
      });
      expect(h.days, 7);
      expect(h.questions, 1234);
      expect(h.noAnswerText, '13%');
      expect(h.p50Text, '12.4 s');
      expect(h.cacheHitRate, 0.3);
      expect(h.daily, [0, 1, 2, 3, 4, 5, 6]);
      expect(h.spark.last, 6.0);
    });

    test('tolerates every missing key', () {
      final h = AdminAssistantHealth.fromJson({});
      expect(h.days, 7);
      expect(h.questions, 0);
      expect(h.noAnswerText, '—');
      expect(h.p50Text, '—');
      expect(h.daily, isEmpty);
      expect(AdminAssistantHealth.fromJson({'latency_ms': {'p50': 850}}).p50Text, '850 ms');
    });
  });

  group('settings: conversation_retention_days', () {
    test('parsed with the server default, clamped, always sent', () {
      expect(RagAdminSettings.fromJson({'settings': {}}).conversationRetentionDays, 90);
      expect(RagAdminSettings.fromJson({'settings': {'conversation_retention_days': 0}}).conversationRetentionDays, 0);
      expect(RagAdminSettings.fromJson({'settings': {'conversation_retention_days': 99999}}).conversationRetentionDays, 3650);
      final s = RagAdminSettings.fromJson({'settings': {'conversation_retention_days': 30, 'answer_style': 'concise'}});
      expect(s.toJson()['conversation_retention_days'], 30);
      final edited = s.copyWith(conversationRetentionDays: 0);
      expect(edited.toJson()['conversation_retention_days'], 0);
      expect(edited.toJson()['answer_style'], 'concise'); // the PUT keeps every other field
      expect(s.copyWith(generator: 'extractive').conversationRetentionDays, 30);
    });
  });
}
