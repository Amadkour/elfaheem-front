// Auto-grade job, front pack F2 (D-688 / D-689): the parsers over REAL server payloads (contract A3 – A5, A7, B2,
// B3, C1 – C4) in test/fixtures/payloads/autograde/, written by the back's tests/contract/dump_autograde_payloads.py
// from its e2e runs (synthetic students, signatures scrubbed), and the pure helpers the review screens draw from.
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

/// The recorded reply (`payload`) of a fixture written by the back's dump.
Map<String, dynamic> fx(String name) {
  final j = jsonDecode(File('test/fixtures/payloads/autograde/$name.json').readAsStringSync()) as Map;
  return Map<String, dynamic>.from((j['payload'] ?? j) as Map);
}

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('online review (A3)', () {
    final q = ReviewQueue.fromJson(fx('review_queue'));

    test('a long answer: tier, kind, points with spans into the answer', () {
      final it = q.items.firstWhere((i) => i.auto?.kind == 'long');
      final a = it.auto!;
      expect(a.tier, 'review');
      expect(a.decided, isFalse);
      expect(a.version, startsWith('tiers:'));
      expect(it.questionKind, 'long');
      expect(a.points, hasLength(3));
      expect(a.coveredPoints.map((p) => p.idx), [0, 2]);
      expect(a.missingPoints.map((p) => p.idx), [1]);
      for (final p in a.coveredPoints) {
        expect(it.answerText.substring(p.start!, p.end!), p.sentence);
      }
      final runs = autoPointRuns(it.answerText, a.points);
      expect(runs.map((r) => r.$1).join(), it.answerText);
      expect(runs.any((r) => r.$2 == 'matched'), isTrue);
    });

    test('word and short answers: the tier that settled them, keywords found / missing', () {
      final tiers = {for (final i in q.items) if (i.auto != null) i.auto!.tier};
      expect(tiers, containsAll(['exact', 'fuzzy', 'nli']));
      final exact = q.items.firstWhere((i) => i.auto?.tier == 'exact');
      expect(exact.auto!.decided, isTrue);
      expect(exact.auto!.kind, 'short');
      expect(exact.auto!.found, isNotEmpty);
      expect(autoTierText('fuzzy'), contains('spelling'));
    });

    test('a remembered decision settles the same answer (memory hit)', () {
      final m = ReviewQueue.fromJson(fx('review_queue_memory')).items.single;
      final a = m.auto!;
      expect(a.tier, 'memory');
      expect(a.memory!.verdict, 'wrong');
      expect(a.memory!.decisions, 1);
      expect(a.missing, ['increases']);
      expect(autoTierHint(a), contains('1 decision'));
    });

    test('an older proposal has no tier: no AutoGrade, nothing breaks', () {
      expect(AutoGrade.fromJson(null), isNull);
      expect(AutoGrade.fromJson({'tier': ''}), isNull);
      expect(AutoGrade.fromJson({'score': 1, 'criteria': []}), isNull);
    });
  });

  test('NB2 readings in the review queue (B3): character boxes and the near miss of a line', () {
    final q = ReviewQueue.fromJson(fx('review_queue_nb2'));
    final word = q.items.firstWhere((i) => i.nb2?.unit == 'chars');
    expect(word.nb2!.chars.map((c) => c.ch).join(), 'cell');
    expect(word.nb2!.lowCount, 0);
    expect(word.fromPaperReader, isTrue);
    final line = q.items.firstWhere((i) => i.nb2?.nearMissFrom != null);
    expect(line.nb2!.unit, 'line');
    expect(line.nb2!.chars, isEmpty);
  });

  test('paper answers read reading.auto (A4); essay runs too', () {
    final long = fx('paper_item_long');
    final item = OmrReviewItem.fromJson(long);
    expect(item.auto!.kind, 'long');
    expect(item.auto!.decided, isFalse);
    expect(item.auto!.points.map((p) => p.state), ['matched', 'unsure', 'matched']);
    final exact = fx('paper_item_exact');
    final s = EssaySuggestion.fromJson(exact);
    expect(s.auto!.tier, 'exact');
    expect(s.auto!.decided, isTrue);
    expect(s.auto!.score, 2);
    expect(EssaySuggestion.fromJson({'id': 5, 'status': 'open', 'reading': {'suggested_score': 1}}).auto, isNull);
  });

  test('autoPointRuns: overlaps (contradicted wins), clipped spans, empty text', () {
    const pts = [
      AutoPoint(idx: 0, text: 'a', start: 0, end: 6, state: 'partial'),
      AutoPoint(idx: 1, text: 'b', start: 4, end: 99, state: 'contradicted'),
    ];
    expect(autoPointRuns('abcdefgh', pts), [('abcd', 'partial'), ('efgh', 'contradicted')]);
    expect(autoPointRuns('', pts), isEmpty);
    expect(autoPointRuns('abc', const [AutoPoint(idx: 0, text: 'x', state: 'missing')]), [('abc', null)]);
  });

  test('answer memory list (A5)', () {
    final items = answerMemoryOf(fx('answer_memory'));
    final m = items.single;
    expect(m.verdict, 'wrong');
    expect(m.conflict, isFalse);
    expect(m.source, 'mark');
    expect(answerMemoryVerdictText(m.verdict), 'Wrong');
  });

  group('model hub benchmarks (C) and the judge (A7)', () {
    final b = HubBenchmarks.fromJson(fx('benchmarks'));

    test('roles, the default, results with the reasons a model cannot be chosen', () {
      expect(b.roles.map((r) => r.role), containsAll(['embedding', 'nli', 'digits']));
      final nli = b.role('nli')!;
      expect(nli.provisional, isTrue);
      expect(nli.hasChoice, isFalse);
      expect(nli.defaultId, 5);
      expect(nli.defaultRule, 'best_accuracy_then_latency');
      expect(nli.results, hasLength(3));
      final gone = nli.results.firstWhere((r) => r.modelId == null);
      expect(gone.selectable, isFalse);
      expect(gone.reason!.code, 'not_in_library');
      expect(nli.results.firstWhere((r) => r.modelId == 5).isDefault, isTrue);
      final off = b.runners.firstWhere((r) => !r.available);
      expect(off.reason!.text, contains('missing'));
      expect(b.run, isNull);
    });

    test('a run: started and done', () {
      final started = HubBenchRun.fromJson(fx('bench_run_started'))!;
      final done = HubBenchRun.fromJson(fx('bench_run_done'))!;
      expect(done.live, isFalse);
      expect(done.errors, isEmpty);
      expect(done.fraction, 1.0);
      expect(hubBenchRunText(done), isNotEmpty);
      expect(started.roles, ['embedding', 'nli']);
      expect(HubBenchRun.fromJson(null), isNull);
    });

    test('the choice reply', () {
      final c = HubBenchChoice.fromJson(fx('bench_choice'));
      expect(c.choiceId, c.effectiveId);
      expect(c.activation.stage, 'ready_to_confirm');
    });

    test('the nli row carries the judge switch; others do not', () {
      final ov = HubOverview.fromJson(fx('models_overview_judge_off'));
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
