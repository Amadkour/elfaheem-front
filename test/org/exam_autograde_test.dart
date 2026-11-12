// Auto-grade job, front pack F2 (D-688 / D-689): the parsers over the contract payloads (A3 – A5, A7, C1 – C4) in
// test/fixtures/payloads/autograde/, and the pure helpers the review screens draw from.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/models_hub/models_hub_api.dart';
import 'package:flutter_education_app/features/admin/models/ai_models_bench.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_autograde.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_review.dart';
import 'package:flutter_education_app/features/shared/exam_engine/hub/grade/essay_run.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/review/omr_review.dart';
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> fx(String name) =>
    Map<String, dynamic>.from(jsonDecode(File('test/fixtures/payloads/autograde/$name.json').readAsStringSync()) as Map);

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('online review (A3)', () {
    final q = ReviewQueue.fromJson(fx('review_queue'));

    test('a long answer: tier, kind, points with spans', () {
      final it = q.items[0];
      final a = it.auto!;
      expect(a.tier, 'nli');
      expect(a.kind, 'long');
      expect(a.decided, isFalse);
      expect(a.version, 'tiers:2026.11.12-1');
      expect(it.questionKind, 'long');
      expect(a.coveredPoints.map((p) => p.idx), [0, 1]);
      expect(a.missingPoints.map((p) => p.idx), [2]);
      expect(a.contradictedPoints.single.idx, 3);
      expect(a.points[2].sentence, isNull);
      expect(a.points[2].hasSpan, isFalse);
      expect(it.answerText.substring(a.points[1].start!, a.points[1].end!), 'Light is quicker than sound');
    });

    test('a word answer: memory, keywords, NB2 boxes with the doubtful one', () {
      final it = q.items[1];
      final a = it.auto!;
      expect(a.tier, 'memory');
      expect(a.memory!.id, 41);
      expect(a.memory!.decisions, 3);
      expect(a.found, ['1250']);
      expect(a.missing, isEmpty);
      final nb2 = it.nb2!;
      expect(nb2.chars.map((c) => c.ch).join(), '1250');
      expect([for (final c in nb2.chars) c.low], [false, true, false, false]);
      expect(nb2.chars[1].alt, '7');
      expect(nb2.lowCount, 1);
      expect(nb2.nearMissFrom, '1750');
      expect(it.fromPaperReader, isTrue);
      expect(autoTierHint(a), contains('3 decisions'));
    });

    test('an older proposal has no tier: no AutoGrade, nothing breaks', () {
      expect(q.items[2].auto, isNull);
      expect(q.items[2].nb2, isNull);
      expect(AutoGrade.fromJson(null), isNull);
      expect(AutoGrade.fromJson({'tier': ''}), isNull);
    });
  });

  test('paper short answer reads reading.auto (A4); essay run too', () {
    final reading = fx('paper_short_auto');
    final item = OmrReviewItem.fromJson({'id': 9, 'kind': 'short_answer', 'code': 'short_answer', 'status': 'open', 'reading': reading});
    expect(item.auto!.tier, 'nli');
    expect(item.auto!.decided, isTrue);
    expect(item.auto!.points.map((p) => p.state), ['matched', 'partial', 'missing']);
    final s = EssaySuggestion.fromJson({'id': 5, 'status': 'open', 'reading': reading});
    expect(s.auto!.score, 2);
    expect(EssaySuggestion.fromJson({'id': 5, 'status': 'open', 'reading': {'suggested_score': 1}}).auto, isNull);
  });

  group('autoPointRuns', () {
    test('runs keep the text whole and carry the point states', () {
      final q = ReviewQueue.fromJson(fx('review_queue'));
      final it = q.items[0];
      final runs = autoPointRuns(it.answerText, it.auto!.points);
      expect(runs.map((r) => r.$1).join(), it.answerText);
      expect(runs.first, ('Both start at the same moment', 'matched'));
      expect(runs.where((r) => r.$2 == 'contradicted').single.$1, 'it arrives first');
      expect(runs.last, ('.', null));
    });

    test('overlaps: contradicted wins; out-of-range spans are clipped; empty text', () {
      const pts = [
        AutoPoint(idx: 0, text: 'a', start: 0, end: 6, state: 'partial'),
        AutoPoint(idx: 1, text: 'b', start: 4, end: 99, state: 'contradicted'),
      ];
      expect(autoPointRuns('abcdefgh', pts), [('abcd', 'partial'), ('efgh', 'contradicted')]);
      expect(autoPointRuns('', pts), isEmpty);
      expect(autoPointRuns('abc', const [AutoPoint(idx: 0, text: 'x', state: 'missing')]), [('abc', null)]);
    });
  });

  test('answer memory list (A5)', () {
    final items = answerMemoryOf(fx('bench_misc')['answer_memory'] as Map<String, dynamic>);
    expect(items.map((i) => i.id), [41, 42]);
    expect(items[1].conflict, isTrue);
    expect(items[1].source, 'paper');
    expect(answerMemoryVerdictText(items[0].verdict), 'Right');
  });

  group('model hub benchmarks (C) and the judge (A7)', () {
    final b = HubBenchmarks.fromJson(fx('benchmarks'));

    test('roles, defaults, choices, results', () {
      expect(b.roles.map((r) => r.role), ['nli', 'embedding', 'digits']);
      final nli = b.role('nli')!;
      expect(nli.provisional, isTrue);
      expect(nli.hasChoice, isFalse);
      expect(nli.defaultId, 7);
      expect(nli.defaultRule, 'best_accuracy_then_latency');
      expect(nli.metricLabel, 'Entail / contradict accuracy');
      final top = nli.results.first;
      expect(top.accuracy, 91.4);
      expect(top.latencyP95Ms, 61.0);
      expect(top.peakRamMb, 612);
      expect(top.sizeBytes, 338679132);
      expect(top.isDefault && top.isActive, isTrue);
      expect(nli.results[1].seeded, isTrue);
      expect(nli.results[1].downloaded, isFalse);
      final emb = b.role('embedding')!;
      expect(emb.hasChoice, isTrue);
      expect(emb.choiceId, 3);
      expect(emb.headline.length, 2);
      expect(emb.extra.single.dataset, 'grading-gold-ar-v1');
      final dim = emb.results[1];
      expect(dim.modelId, isNull);
      expect(dim.selectable, isFalse);
      expect(dim.reason!.code, 'embedding_dim_unsupported');
      AppConfig.lang = 'ar';
      expect(dim.reason!.text, contains('384'));
      expect(b.role('digits')!.defaultId, isNull);
      expect(b.runners.last.available, isFalse);
    });

    test('runs: live, progress, done with errors', () {
      final r = b.run!;
      expect(r.live, isTrue);
      expect(r.fraction, closeTo(1 / 3, 1e-9));
      expect(hubBenchRunText(r), contains('2 of 3'));
      final done = HubBenchRun.fromJson(fx('bench_misc')['run_done'])!;
      expect(done.live, isFalse);
      expect(done.errors.single['model_id'], 9);
      expect(hubBenchRunText(done), contains('1 error'));
      expect(HubBenchRun.fromJson(null), isNull);
    });

    test('choice reply and clear', () {
      final c = HubBenchChoice.fromJson(fx('bench_misc')['choice']);
      expect(c.choiceId, 9);
      expect(c.activation.stage, 'testing');
      expect(c.activation.pending?.modelId, 9);
      final cleared = HubBenchChoice.fromJson(fx('bench_misc')['choice_cleared']);
      expect(cleared.choiceId, isNull);
      expect(cleared.effectiveId, 7);
      expect(cleared.activation.stage, 'active');
    });

    test('the nli row carries the judge; others do not', () {
      final ov = HubOverview.fromJson(fx('bench_misc')['overview_nli']);
      expect(ov.role('nli')!.judge, 'off');
      expect(ov.role('nli')!.judgeOn, isFalse);
      expect(ov.role('embedding')!.judge, isNull);
      expect(ov.role('embedding')!.judgeOn, isTrue);
    });

    test('numbers and the live event name', () {
      expect(hubBenchScore(91.4), contains('91.4'));
      expect(hubBenchScore(null), '—');
      expect(hubBenchMs(6.4), contains('6.4 ms'));
      expect(hubBenchMs(1340), contains('1.3 s'));
      expect(LiveEvents.serverTypes, contains(LiveEvents.modelBenchmark));
    });
  });
}
