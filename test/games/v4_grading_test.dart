// Games v4 T12: the Dart grader and GameSession against docs/games-v4/grading_vectors_v4.json (CONTRACT §5–§7).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_education_app/features/games/core/game_grade.dart';
import 'package:flutter_education_app/features/games/core/game_items.dart';
import 'package:flutter_education_app/features/games/core/game_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final v = jsonDecode(File('docs/games-v4/grading_vectors_v4.json').readAsStringSync()) as Map<String, dynamic>;
  final itemDefs = v['items'] as Map<String, dynamic>;

  GameItem item(String name, int n) {
    final d = Map<String, dynamic>.from(itemDefs[name] as Map);
    return GameItem.fromJson(d, n: n)!;
  }

  test('constants block', () {
    final c = v['constants'] as Map<String, dynamic>;
    expect(kMinStepMs, c['min_step_ms']);
    expect(kMaxTrace, c['max_trace']);
    expect(kProgramRuns, c['program_runs']);
    expect(kProgramMaxSteps, c['program_max_steps']);
    expect(kGhostMax, c['ghost_max_events']);
    expect(kDifficultyPercent, (c['difficulty_percent'] as Map).cast<String, int>());
    expect(kEndValues, c['end_values']);
    expect(kNoSpeedBonusTemplates, (c['no_speed_bonus_templates'] as List).toSet());
    final par = c['par_s'] as Map<String, dynamic>;
    for (final t in ItemType.values) {
      expect(kParSeconds[t], par[t.wire], reason: t.wire);
    }
    expect({for (final t in ItemType.values) if (t.perUnit) t.wire}, (c['par_per_unit_types'] as List).toSet());
  });

  group('grading cases', () {
    for (final c in v['cases'] as List) {
      final name = c['name'] as String;
      test(name, () {
        final items = [for (var i = 0; i < (c['items'] as List).length; i++) item((c['items'] as List)[i] as String, i)];
        if (c['valid'] == false) {
          expect(() => gradeTrace(items, c['trace']), throwsA(isA<BadTrace>().having((e) => e.why, 'why', c['why'])));
          return;
        }
        final r = gradeTrace(items, c['trace']);
        expect(r.score, c['score']);
        expect(r.maxScore, c['max_score']);
        expect(r.perItem, (c['per_item'] as List).cast<int>());
        expect(r.counted, c['counted']);
        expect(r.durationMs, c['duration_ms']);
        expect(r.end, c['end']);
        expect(r.stars, c['stars']);
        expect(r.tooFast, c['too_fast']);
        expect(r.ghost, [for (final g in c['ghost'] as List) (g as List).cast<int>()]);
        expect(
          rankPoints(
            items: items,
            score: r.score,
            max: r.maxScore,
            durationMs: r.durationMs,
            difficulty: c['difficulty'] as String,
            sacred: c['sacred'] == true,
            template: c['template'] as String,
          ),
          c['rank_points'],
        );
      });
    }
  });

  group('program runs', () {
    for (final c in v['program_runs'] as List) {
      test(c['name'] as String, () {
        final it = item(c['item'] as String, 0);
        final r = simulateProgram(it.body, c['a'] as List);
        expect(r.reached, c['reached']);
        expect(r.bumped, c['bumped']);
        expect(r.steps, c['steps']);
        expect(r.length, c['length']);
        expect([r.x, r.y, r.dir], [c['x'], c['y'], c['dir']]);
        expect(r.points, c['points']);
      });
    }
  });

  test('age bands', () {
    for (final c in v['age_bands'] as List) {
      final dob = c['dob'] == null ? null : DateTime.parse(c['dob'] as String);
      final r = ageBand(dob: dob, grade: c['grade'] as int?, today: DateTime.parse(c['today'] as String));
      expect(r.band, c['age_band'], reason: '$c');
      expect(r.source, c['age_source'], reason: '$c');
    }
  });

  test('srs ladder', () {
    for (final c in v['srs'] as List) {
      final before = c['before'] as Map?;
      final r = srsStep(before?['box'] as int?, right: c['right'] as bool);
      final after = c['after'] as Map?;
      if (after == null) {
        expect(r, isNull);
      } else {
        expect([r!.box, r.dueInDays, r.lapsesAdded], [after['box'], after['due_in_days'], after['lapses_added']]);
      }
    }
  });

  test('coins per star', () {
    for (final c in v['coins'] as List) {
      expect(
        coinsForStars(reward: c['coins_reward'] as int, starsBefore: c['stars_before'] as int, starsNow: c['stars_now'] as int),
        c['coins_awarded'],
        reason: '$c',
      );
    }
  });

  group('GameSession', () {
    List<GameItem> two() => [item('mcq_capital', 0), item('mcq_planet', 1)];

    test('scores live, finishes done and grades the trace', () {
      var t = 0;
      final s = GameSession(items: two(), nowMs: () => t);
      GameSession? done;
      s.onFinished = (x) => done = x;
      s.start();
      t = 3000;
      expect(s.answer(0, 0)!.points, 1);
      t = 5000;
      s.answer(1, 0);
      expect(s.score, 1);
      expect(s.maxScore, 2);
      expect(s.finish(), isNotNull);
      expect(done, same(s));
      expect(s.result!.score, 1);
      expect(s.trace.map((e) => e['ms']), [3000, 5000]);
      expect(s.answer(1, 2), isNull);
    });

    test('a malformed answer records nothing; pause stops the clock', () {
      var t = 0;
      final s = GameSession(items: two(), nowMs: () => t)..start();
      expect(s.answer(0, 9), isNull);
      expect(s.trace, isEmpty);
      t = 1000;
      s.pause();
      t = 9000;
      expect(s.answer(0, 0), isNull);
      s.resume();
      t = 9500;
      s.answer(0, 0);
      expect(s.trace.single['ms'], 1500);
    });

    test('lives end the round with the end entry', () {
      var t = 0;
      final s = GameSession(
        items: two(),
        settings: const GameSettings(lives: 2, penalty: 'lives'),
        nowMs: () => t,
      )..start();
      t = 1000;
      s.answer(0, 1);
      expect(s.lives, 1);
      t = 2000;
      s.answer(1, 0);
      expect(s.finished, isTrue);
      expect(s.endedBy, 'lives');
      expect(s.trace.last, {'i': -1, 'a': 'lives', 'ms': 2000});
    });

    test('the timer ends the round', () {
      var t = 0;
      final s = GameSession(items: two(), settings: const GameSettings(timerS: 2), nowMs: () => t)..start();
      t = 1000;
      s.answer(0, 0);
      s.tick();
      expect(s.finished, isFalse);
      t = 2000;
      s.tick();
      expect(s.endedBy, 'timer');
      expect(s.result!.score, 1);
      s.dispose();
    });

    test('sacred override and growing_tree rule', () {
      final a = GameSettings.fromJson({'penalty': 'lives', 'lives': 3, 'timer_s': 60}, sacred: true);
      expect([a.penalty, a.calm, a.timeBonus, a.timerS], ['soft', true, false, 60]);
      final g = GameSettings.fromJson({'penalty': 'lives', 'lives': 3, 'timer_s': 60}, sacred: false, template: 'growing_tree');
      expect([g.penalty, g.lives, g.timerS], ['none', 0, 0]);
    });

    test('fromDraw reads a draw and refuses an unknown item type', () {
      final draw = {
        'draw_id': 'd1',
        'seed': 5,
        'sacred': false,
        'template': 'challenge_quiz',
        'settings': {'timer_s': 0},
        'items': [
          {'n': 0, 'type': 'true_false', 'body': {'answer': true}},
        ],
      };
      final s = GameSession.fromDraw(draw)!;
      expect(s.items.single.max, 1);
      expect(s.drawId, 'd1');
      expect(GameSession.fromDraw({...draw, 'items': [{'type': 'hologram', 'body': {}}]}), isNull);
    });
  });
}
