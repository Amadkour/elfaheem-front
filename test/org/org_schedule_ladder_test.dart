// The relaxation ladder — pure logic: the config (GET …/ladder) and its operations, the decision a waiting run asks,
// the live counters, the report (result.ladder) and its texts. Field names follow services/organization/
// schedule_ladder.py (report / _option / _decide / catalog / TEXT / DEFAULTS).
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/org/org_schedule_generate.dart' show LiveStep;
import 'package:flutter_education_app/features/org/org_schedule_ladder.dart';
import 'package:flutter_education_app/features/org/org_v3.dart';
import 'package:flutter_test/flutter_test.dart';

/// GET …/schedules/{sid}/ladder as the server answers it.
Map<String, dynamic> ladderJson() => {
      'ladder': [
        {'key': 'free_moves', 'mode': 'auto'},
        {'key': 'rooms', 'mode': 'auto'},
        {'key': 'ta_limits', 'mode': 'ask'},
        {'key': 'doctor_limits', 'mode': 'locked'},
        {'key': 'split_groups', 'mode': 'auto'},
        {'key': 'open_times', 'mode': 'ask'},
        {'key': 'student_times', 'mode': 'ask'},
        {'key': 'capacity', 'mode': 'locked'},
        {'key': 'student_clash', 'mode': 'locked'},
      ],
      'options': {'budget_s': 600, 'solve_s': null, 'decision_timeout_s': 300, 'overflow_pct': 15, 'max_new_periods': 1, 'max_new_days': 0, 'max_new_rooms': 4, 'fork_options': 2},
      'catalog': {
        'rungs': [
          for (final k in ladderRungKeys)
            {'key': k, 'name_ar': ladderText[k]!.$1, 'name_en': ladderText[k]!.$2, 'why_ar': ladderText[k]!.$3, 'why_en': ladderText[k]!.$4, 'default_mode': ladderDefault.firstWhere((d) => d.$1 == k).$2},
        ],
        'fixed': [
          {'key': 'person_double', 'ar': 'لا عضو في حصتين معاً', 'en': 'No one teaches two sessions at once'},
          {'key': 'room_double', 'ar': 'لا قاعة لحصتين معاً', 'en': 'No room hosts two sessions at once'},
        ],
        'modes': ['auto', 'ask', 'locked'],
        'default': [for (final (k, m) in ladderDefault) {'key': k, 'mode': m}],
        'options': {'budget_s': 1200, 'solve_s': null, 'decision_timeout_s': 900, 'overflow_pct': 10, 'max_new_periods': 2, 'max_new_days': 1, 'max_new_rooms': 6, 'fork_options': 3},
      },
      'presets': [
        {
          'id': 'p1',
          'name': 'Exams week',
          'ladder': [{'key': 'open_times', 'mode': 'auto'}, {'key': 'free_moves', 'mode': 'ask'}],
          'options': {'budget_s': 300},
        },
      ],
      'version': 12,
    };

/// schedule_ladder.Run._option() for a possible rung.
Map<String, dynamic> optionJson(String key, {int placed = 172, int gain = 12, int broken = 3, bool complete = false, bool recommended = false, int rank = 1}) => {
      'id': key,
      'rung': key,
      'name_ar': ladderText[key]!.$1,
      'name_en': ladderText[key]!.$2,
      'possible': true,
      'why_ar': ladderText[key]!.$3,
      'why_en': ladderText[key]!.$4,
      'rank': rank,
      if (recommended) ...{'recommended': true, 'reason_ar': 'يضع أكبر عدد من الحصص بأقل القواعد كسراً', 'reason_en': 'Places the most sessions with the fewest rules broken'},
      'impact': {
        'placed': placed,
        'required': 180,
        'gain': gain,
        'unplaced': 180 - placed,
        'broken': broken,
        'broken_by_rung': {key: broken},
        'people': 2,
        'complete': complete,
        'note': {'rung': key, 'people': 5, 'weekly_caps_dropped': 1},
        'seconds': 14.2,
      },
    };

Map<String, dynamic> decisionJson() => {
      'id': 'd1',
      'reason': 'stack',
      'unplaced': 20,
      'placed': 160,
      'required': 180,
      'top': [{'reason': 'no_room_fits', 'n': 12}, {'reason': 'teacher_unavailable', 'n': 8}],
      'options': [
        optionJson('ta_limits', recommended: true),
        optionJson('rooms', placed: 180, gain: 20, broken: 5, complete: true, rank: 2),
        {'id': 'open_times', 'rung': 'open_times', 'name_ar': 'فتح أوقات جديدة', 'name_en': 'Open new times', 'possible': false, 'why_ar': 'لا شيء يمكن إضافته هنا', 'why_en': 'Nothing left to add here', 'rank': 3},
        {'id': 'stop', 'rung': null, 'name_ar': 'التوقف هنا والإبقاء على أفضل نتيجة', 'name_en': 'Stop here and keep the best so far', 'possible': true, 'rank': 4, 'why_ar': 'الحصص المتبقية تبقى بلا موعد', 'why_en': 'The remaining sessions stay unplaced'},
      ],
      'recommended': 'ta_limits',
      'situation_ar': 'بقي 20 حصة بلا موعد ولا تكفي خطوة واحدة من السلّم لإكمال الجدول — اختر كيف نتابع.',
      'situation_en': '20 session(s) are still unplaced and no single rung completes the timetable — choose how to continue.',
    };

/// GET …/runs/{rid} while the run waits for the creator.
Map<String, dynamic> waitingRun() => {
      'id': 44,
      'schedule_id': 9,
      'status': 'waiting',
      'progress': 55,
      'summary': {
        'live': true,
        'stage': 'decision',
        'elapsed_s': 95,
        'budget_s': 600,
        'ladder_live': {'placed': 160, 'required': 180, 'unplaced': 20, 'broken': 0, 'rung': 'ta_limits', 'stage': 'decision', 'elapsed_s': 95, 'budget_s': 600, 'solves': 4},
        'steps': [
          {'id': 1, 'kind': 'prepare', 'text_ar': 'حُمّلت البيانات', 'text_en': 'Data loaded', 'done': true, 'elapsed_s': 0.4},
          {'id': 2, 'kind': 'round', 'text_ar': 'المحاولة الصارمة: 180 حصة بكل القواعد', 'text_en': 'Strict solve: 180 sessions with every rule', 'done': true, 'rung': 'free_moves', 'elapsed_s': 1.0},
          {'id': 3, 'kind': 'round', 'text_ar': 'تجربة: حدود المعيدين', 'text_en': 'Trying: TA limits', 'done': true, 'rung': 'ta_limits', 'note': {'people': 5}, 'elapsed_s': 60.0},
          {'id': 4, 'kind': 'decision', 'text_ar': 'بانتظار قرار منشئ الجدول…', 'text_en': 'Waiting for the creator\'s decision…', 'done': false, 'elapsed_s': 94.0},
        ],
        'decision': decisionJson(),
      },
    };

/// schedule.result after a complete ladder run.
Map<String, dynamic> completeResult() => {
      'status': 'feasible_relaxed',
      'stats': {'sessions_required': 180, 'sessions_placed': 180, 'soft_cost': 12},
      'broken': [
        {'rule': 'teacher_unavailable', 'rung': 'ta_limits', 'tier': 'assistant_prefs', 'course_id': 10, 'kind': 'lab', 'group_no': 2, 'block_id': 'b1', 'day': 'monday', 'period_ids': [3], 'user_id': 7},
        {'rule': 'teacher_day_limit', 'rung': 'ta_limits', 'tier': 'assistant_prefs', 'course_id': 11, 'kind': 'lecture', 'group_no': null, 'block_id': 'b2', 'day': 'tuesday', 'period_ids': [1, 2], 'user_id': 8},
        {'rule': 'new_period', 'rung': 'open_times', 'tier': 'other_soft', 'course_id': 12, 'kind': 'lecture', 'group_no': null, 'block_id': 'b3', 'day': 'sunday', 'period_ids': [-1001], 'detail': {'start': 900, 'end': 960, 'label': '+1'}},
        {'rule': 'room_kind', 'rung': 'rooms', 'tier': 'rooms', 'course_id': 13, 'kind': 'lecture', 'group_no': null, 'block_id': 'b4', 'day': 'sunday', 'period_ids': [2], 'room_id': 5},
      ],
      'ladder': {
        'status': 'complete',
        'valid': true,
        'ladder': [for (final (i, (k, m)) in ladderDefault.indexed) {'key': k, 'mode': m, 'order': i}],
        'rungs': [
          {'key': 'free_moves', 'mode': 'auto', 'tried': true, 'applied': true, 'placed_before': 0, 'placed_after': 160, 'broken': 0, 'seconds': 54.0, 'attempts': 2},
          {'key': 'ta_limits', 'mode': 'auto', 'tried': true, 'applied': true, 'placed_before': 160, 'placed_after': 172, 'broken': 2, 'seconds': 30.1, 'note': {'rung': 'ta_limits', 'people': 5, 'weekly_caps_dropped': 1}},
          {'key': 'doctor_limits', 'mode': 'auto', 'tried': true, 'applied': false, 'placed_before': 172, 'placed_after': 172, 'seconds': 28.0, 'note': {'skipped': 'no_gain'}},
          {'key': 'rooms', 'mode': 'auto', 'tried': true, 'applied': true, 'placed_before': 172, 'placed_after': 176, 'broken': 3, 'seconds': 31.0, 'note': {'rung': 'rooms', 'new_rooms': 1}},
          {'key': 'split_groups', 'mode': 'auto', 'tried': false, 'applied': false, 'note': {'skipped': 'nothing_to_add'}},
          {'key': 'open_times', 'mode': 'ask', 'tried': true, 'applied': true, 'placed_before': 176, 'placed_after': 180, 'broken': 4, 'seconds': 29.5, 'note': {'rung': 'open_times', 'new_period': {'id': -1001, 'order': 9, 'start': 900, 'end': 960, 'label': '+1', 'virtual': true}}},
        ],
        'decisions': [
          {'id': 'd1', 'reason': 'ask', 'chosen': 'open_times', 'by': 'user', 'recommended': 'open_times', 'at_s': 150.2, 'options': [{'id': 'open_times', 'rank': 1, 'possible': true, 'impact': {'placed': 180}, 'recommended': true}, {'id': 'stop', 'rank': 2, 'possible': true, 'impact': null, 'recommended': null}]},
        ],
        'blocked_by': [],
        'structural': {
          'rooms': [{'id': -1, 'kind': 'lab', 'capacity': 40, 'capabilities': ['pc'], 'exclusive': true, 'virtual': true, 'sessions': 3}],
          'periods': [{'id': -1001, 'order': 9, 'start': 900, 'end': 960, 'label': '+1', 'virtual': true, 'sessions': 4}],
          'days': [],
          'splits': [],
        },
        'proof': {'hard_vs_relaxed': 0, 'hard_vs_original': 4, 'never_broken_violations': 0, 'findings': []},
        'seed': 7,
        'auto': false,
        'solves': 7,
        'solve_s': 54.0,
        'elapsed_s': 233.4,
        'budget_s': 1200,
        'completion_pct': 100,
      },
    };

Map<String, dynamic> incompleteResult() {
  final r = completeResult();
  r['stats'] = {'sessions_required': 180, 'sessions_placed': 170, 'soft_cost': 3};
  r['broken'] = [];
  r['ladder'] = {
    ...r['ladder'] as Map<String, dynamic>,
    'status': 'incomplete',
    'completion_pct': 94,
    'blocked_by': [
      {'key': 'capacity', 'name_ar': 'تجاوز السعة', 'name_en': 'Over capacity', 'would_complete': false, 'placed_after': 176, 'required': 180},
      {'key': 'student_clash', 'name_ar': 'تعارض الطلاب', 'name_en': 'Student clash', 'would_complete': true, 'placed_after': 180, 'required': 180},
    ],
    'structural': {'rooms': [], 'periods': [], 'days': [], 'splits': []},
    'proof': {'hard_vs_relaxed': 0, 'hard_vs_original': 0, 'never_broken_violations': 0, 'findings': []},
  };
  return r;
}

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('LadderConfig', () {
    test('of: ladder, options, catalog, presets, version — every field name as the server writes it', () {
      final c = LadderConfig.of(ladderJson());
      expect(c.ladder.map((r) => r.key), ['free_moves', 'rooms', 'ta_limits', 'doctor_limits', 'split_groups', 'open_times', 'student_times', 'capacity', 'student_clash']);
      expect(c.rung('ta_limits')!.mode, 'ask');
      expect(c.rung('doctor_limits')!.locked, isTrue);
      expect(c.options.budgetS, 600);
      expect(c.options.solveS, isNull);
      expect(c.options.decisionTimeoutS, 300);
      expect(c.options.overflowPct, 15);
      expect(c.options.maxNewPeriods, 1);
      expect(c.options.maxNewDays, 0);
      expect(c.options.maxNewRooms, 4);
      expect(c.options.forkOptions, 2);
      expect(c.rungs.length, 9);
      expect(c.catalogRung('rooms')!.name, 'Rooms');
      expect(c.catalogRung('rooms')!.why, 'A room outside its times, another kind of hall for a theory session, or a new room / lab');
      expect(c.catalogRung('open_times')!.defaultMode, 'ask');
      expect(c.fixed.map((f) => f.key), ['person_double', 'room_double']);
      expect(c.fixed.first.text, 'No one teaches two sessions at once');
      expect(c.modes, ['auto', 'ask', 'locked']);
      expect(c.defaultLadder.map((r) => r.key).toList(), ladderRungKeys);
      expect(c.presets.single.id, 'p1');
      expect(c.presets.single.name, 'Exams week');
      expect(c.presets.single.ladder.first.key, 'free_moves', reason: 'a preset is normalized: free_moves first and auto');
      expect(c.presets.single.ladder.first.mode, 'auto');
      expect(c.presets.single.ladder[1].key, 'open_times');
      expect(c.presets.single.ladder.length, 9);
      expect(c.presets.single.options.budgetS, 300);
      expect(c.presets.single.options.forkOptions, 3, reason: 'defaults filled');
      expect(c.version, 12);
      expect(c.isDefault, isFalse);
      AppConfig.lang = 'ar';
      expect(c.catalogRung('rooms')!.name, 'القاعات');
      expect(c.fixed.first.text, 'لا عضو في حصتين معاً');
    });

    test('of: an empty / older answer gives the built-in catalog and the default ladder', () {
      final c = LadderConfig.of(const {});
      expect(c.ladder.map((r) => (r.key, r.mode)).toList(), ladderDefault);
      expect(c.rungs.map((r) => r.key).toList(), ladderRungKeys);
      expect(c.fixed.length, 5);
      expect(c.isDefault, isTrue);
      expect(c.options.budgetS, 1200);
      expect(c.version, isNull);
      expect(c.toBody(), {
        'ladder': [for (final (k, m) in ladderDefault) {'key': k, 'mode': m}],
        'options': const LadderOptions().toJson(),
      });
    });

    test('normalizeLadder: unknown keys and duplicates dropped, missing rungs appended, free_moves first and auto', () {
      final l = normalizeLadder(const [LadderRung('rooms', 'ask'), LadderRung('bogus', 'auto'), LadderRung('rooms', 'locked'), LadderRung('free_moves', 'locked')]);
      expect(l.first.key, 'free_moves');
      expect(l.first.mode, 'auto');
      expect(l[1].key, 'rooms');
      expect(l[1].mode, 'ask');
      expect(l.map((r) => r.key).toSet(), ladderRungKeys.toSet());
      expect(l.length, 9);
      expect(LadderRung.of(const {'key': 'rooms', 'mode': 'weird'}).mode, 'auto', reason: 'a bad mode falls back to auto');
    });

    test('moveRung: free_moves is pinned first; moving past the ends or onto the first place is a no-op', () {
      final c = LadderConfig.of(ladderJson());
      final up = c.moveRung('ta_limits', -1);
      expect(up.ladder.map((r) => r.key).take(3), ['free_moves', 'ta_limits', 'rooms']);
      expect(c.ladder.map((r) => r.key).take(3), ['free_moves', 'rooms', 'ta_limits'], reason: 'the input is never mutated');
      expect(identical(c.moveRung('rooms', -1), c), isTrue, reason: 'onto the first place');
      expect(identical(c.moveRung('rooms', -5), c), isTrue);
      expect(identical(c.moveRung('student_clash', 1), c), isTrue, reason: 'past the end');
      expect(identical(c.moveRung('free_moves', 1), c), isTrue);
      expect(identical(c.moveRung('free_moves', 3), c), isTrue);
      expect(identical(c.moveRung('nope', 1), c), isTrue);
      expect(identical(c.moveRung('rooms', 0), c), isTrue);
      final down = c.moveRung('rooms', 2);
      expect(down.ladder.map((r) => r.key).take(4), ['free_moves', 'ta_limits', 'doctor_limits', 'rooms']);
      expect(c.moveRung('ta_limits', 6).ladder.last.key, 'ta_limits');
      expect(c.moveRung('ta_limits', 6).ladder.first.key, 'free_moves');
    });

    test('setMode: modes validated, free_moves always auto, unknown key is a no-op', () {
      final c = LadderConfig.of(ladderJson());
      expect(c.setMode('rooms', 'locked').rung('rooms')!.mode, 'locked');
      expect(c.setMode('rooms', 'ask').rung('rooms')!.asks, isTrue);
      expect(c.rung('rooms')!.mode, 'auto', reason: 'immutable');
      expect(identical(c.setMode('rooms', 'maybe'), c), isTrue);
      expect(identical(c.setMode('free_moves', 'locked'), c), isTrue);
      expect(c.setMode('free_moves', 'ask').rung('free_moves')!.mode, 'auto');
      expect(identical(c.setMode('nope', 'auto'), c), isTrue);
      expect(c.setMode('rooms', 'locked').toBody()['ladder'], anyElement(equals({'key': 'rooms', 'mode': 'locked'})));
    });

    test('resetToDefault / applyPreset / toBody', () {
      final c = LadderConfig.of(ladderJson());
      final d = c.resetToDefault();
      expect(d.isDefault, isTrue);
      expect(d.options.budgetS, 1200);
      expect(d.rungs.length, 9, reason: 'the catalog is kept');
      expect(d.presets.length, 1);
      expect(d.version, 12);
      final p = c.applyPreset(c.presets.single);
      expect(p.ladder[1].key, 'open_times');
      expect(p.options.budgetS, 300);
      final body = c.toBody();
      expect(body.keys, ['ladder', 'options']);
      expect((body['ladder'] as List).length, 9);
      expect((body['ladder'] as List).first, {'key': 'free_moves', 'mode': 'auto'});
      expect(body['options'], {'budget_s': 600, 'solve_s': null, 'decision_timeout_s': 300, 'overflow_pct': 15, 'max_new_periods': 1, 'max_new_days': 0, 'max_new_rooms': 4, 'fork_options': 2, 'deterministic': false});
      expect(LadderOptions.of({'deterministic': true}).deterministic, isTrue);
      expect(const LadderOptions().copyWith(deterministic: true).toJson()['deterministic'], isTrue);
      expect(c.options.copyWith(solveS: 30).toJson()['solve_s'], 30);
      expect(c.options.copyWith(solveS: 30).copyWith(clearSolveS: true).solveS, isNull);
      expect(c.presets.single.toJson()['options'], isA<Map>());
    });
  });

  group('rung texts', () {
    test('rungName / rungWhy in both languages; stop; unknown key', () {
      expect(rungName('ta_limits'), 'TA limits');
      expect(rungWhy('ta_limits'), 'A TA may teach outside their available times or over their daily / weekly cap');
      expect(rungName('stop'), 'stop here');
      expect(rungName('something_else'), 'something else');
      expect(rungWhy('something_else'), '');
      expect(rungName(null), '');
      AppConfig.lang = 'ar';
      expect(rungName('ta_limits'), 'حدود المعيدين');
      expect(rungWhy('capacity'), 'قاعة بعدد طلاب يزيد عن سعتها بنسبة محدودة');
      expect(rungName('stop'), 'التوقف هنا');
      for (final k in ladderRungKeys) {
        expect(ladderText[k], isNotNull);
        expect(rungName(k), isNotEmpty);
        expect(rungWhy(k), isNotEmpty);
      }
    });

    test('ladderStatusText', () {
      expect(ladderStatusText('complete'), 'Complete timetable');
      expect(ladderStatusText('incomplete'), 'Incomplete');
      expect(ladderStatusText('invalid'), 'Failed the final check');
      expect(ladderStatusText('time_limit'), 'Time limit reached');
      expect(ladderStatusText('stopped_by_creator'), 'Stopped by the creator');
      expect(ladderStatusText('cancelled'), 'Cancelled');
      expect(ladderStatusText('odd_thing'), 'odd thing');
      AppConfig.lang = 'ar';
      expect(ladderStatusText('complete'), 'جدول كامل');
      expect(ladderStatusText('time_limit'), 'انتهى الوقت');
    });
  });

  group('LadderDecision', () {
    test('of: situation, counters, top reasons, options with impact, the recommendation', () {
      final d = LadderDecision.of(decisionJson());
      expect(d.id, 'd1');
      expect(d.reason, 'stack');
      expect(d.unplaced, 20);
      expect(d.placed, 160);
      expect(d.required, 180);
      expect(d.top, [('no_room_fits', 12), ('teacher_unavailable', 8)]);
      expect(d.situation, startsWith('20 session(s) are still unplaced'));
      expect(d.options.length, 4);
      expect(d.recommended, 'ta_limits');
      expect(d.recommendedOption!.recommended, isTrue);
      expect(d.recommendedOption!.reason, 'Places the most sessions with the fewest rules broken');
      expect(d.possible.map((o) => o.id), ['ta_limits', 'rooms', 'stop']);
      final ta = d.options.first;
      expect(ta.rung, 'ta_limits');
      expect(ta.name, 'TA limits');
      expect(ta.rank, 1);
      expect(ta.impact!.placed, 172);
      expect(ta.impact!.required, 180);
      expect(ta.impact!.gain, 12);
      expect(ta.impact!.unplaced, 8);
      expect(ta.impact!.broken, 3);
      expect(ta.impact!.brokenByRung, {'ta_limits': 3});
      expect(ta.impact!.people, 2);
      expect(ta.impact!.complete, isFalse);
      expect(ta.impact!.note['weekly_caps_dropped'], 1);
      expect(ta.impact!.seconds, 14.2);
      final no = d.options[2];
      expect(no.possible, isFalse);
      expect(no.impact, isNull);
      expect(no.why, 'Nothing left to add here');
      final stop = d.options.last;
      expect(stop.isStop, isTrue);
      expect(stop.rung, isNull);
      expect(stop.name, 'Stop here and keep the best so far');
      AppConfig.lang = 'ar';
      expect(d.situation, startsWith('بقي 20 حصة'));
      expect(stop.name, 'التوقف هنا والإبقاء على أفضل نتيجة');
    });

    test('impactText: one line per option, in both languages', () {
      final d = LadderDecision.of(decisionJson());
      expect(impactText(d.options[0]), 'places 12 more (8 left) · breaks 3 rule(s) · 2 people');
      expect(impactText(d.options[1]), 'completes the timetable (180 of 180) · breaks 5 rule(s) · 2 people');
      expect(impactText(d.options[2]), 'Nothing left to add here');
      expect(impactText(d.options[3]), 'The remaining sessions stay unplaced');
      expect(impactText(LadderOption.of({'id': 'rooms', 'possible': true, 'impact': {'placed': 160, 'required': 180, 'gain': 0, 'unplaced': 20, 'broken': 0}})), 'places nothing more · breaks no rule');
      AppConfig.lang = 'ar';
      expect(impactText(d.options[0]), 'يضع 12 حصة إضافية (8 تبقى) · يكسر 3 قاعدة · 2 شخص');
      expect(impactText(d.options[1]), 'يُكمل الجدول (180 من 180) · يكسر 5 قاعدة · 2 شخص');
      expect(impactText(d.options[3]), 'الحصص المتبقية تبقى بلا موعد');
    });

    test('of: an option without server names takes the TEXT names', () {
      final o = LadderOption.of(const {'id': 'rooms', 'rung': 'rooms', 'possible': true, 'rank': 2});
      expect(o.name, 'Rooms');
      expect(o.why, '');
      expect(o.recommended, isFalse);
      expect(o.impact, isNull);
    });
  });

  group('LadderLive', () {
    test('of: counters from summary.ladder_live, the steps, the decision; isWaiting from the run status', () {
      final l = LadderLive.of(waitingRun())!;
      expect(l.placed, 160);
      expect(l.required, 180);
      expect(l.unplaced, 20);
      expect(l.broken, 0);
      expect(l.rung, 'ta_limits');
      expect(l.rungLabel, 'TA limits');
      expect(l.stage, 'decision');
      expect(l.elapsedS, 95);
      expect(l.budgetS, 600);
      expect(l.solves, 4);
      expect(l.pct, 88);
      expect(l.hasBest, isTrue);
      expect(l.status, 'waiting');
      expect(l.isWaiting, isTrue);
      expect(l.steps.length, 4);
      expect(l.done.length, 3);
      expect(l.current!.kind, 'decision');
      expect(l.current!.text, 'Waiting for the creator\'s decision…');
      expect(l.steps[2].rung, 'ta_limits');
      expect(l.steps[2].note, {'people': 5});
      expect(l.steps[2].elapsedS, 60.0);
      expect(l.steps[1].isAttempt, isTrue);
      expect(l.decision!.id, 'd1');
      expect(l.decision!.options.length, 4);
    });

    test('of: a running run has no decision; a non-ladder run gives null; counters fall back to the summary', () {
      final run = waitingRun();
      run['status'] = 'running';
      (run['summary'] as Map).remove('decision');
      (run['summary'] as Map)['ladder_live'] = {'placed': 10, 'required': 180, 'unplaced': 170, 'broken': 0, 'rung': 'free_moves', 'solves': 1};
      final l = LadderLive.of(run)!;
      expect(l.isWaiting, isFalse);
      expect(l.decision, isNull);
      expect(l.stage, 'decision', reason: 'summary.stage when ladder_live has none');
      expect(l.elapsedS, 95);
      expect(l.budgetS, 600);
      expect(LadderLive.of({'id': 1, 'status': 'running', 'summary': {'live': true, 'round': 2}}), isNull);
      expect(LadderLive.of(null), isNull);
      expect(LadderLive.of(const {'id': 1, 'status': 'queued', 'summary': {'ladder_live': {}}}), isNull, reason: 'an empty map is not a ladder run');
    });
  });

  group('LadderReport', () {
    test('of: every field of result.ladder plus the result counters', () {
      final r = LadderReport.of(completeResult())!;
      expect(r.status, 'complete');
      expect(r.complete, isTrue);
      expect(r.valid, isTrue);
      expect(r.ladder.map((x) => x.key).toList(), ladderRungKeys);
      expect(r.ladder[5].mode, 'ask');
      expect(r.rungs.length, 6);
      expect(r.rungs.first.attempts, 2);
      expect(r.rungs.first.seconds, 54.0);
      expect(r.rungs[1].placedBefore, 160);
      expect(r.rungs[1].placedAfter, 172);
      expect(r.rungs[1].gain, 12);
      expect(r.rungs[1].broken, 2);
      expect(r.rungs[1].note['weekly_caps_dropped'], 1);
      expect(r.rungs[1].name, 'TA limits');
      expect(r.rungs[2].applied, isFalse);
      expect(r.rungs[2].skipped, 'no_gain');
      expect(r.rungs[4].tried, isFalse);
      expect(r.rungs[4].skipped, 'nothing_to_add');
      expect(r.rungs[5].mode, 'ask');
      expect(r.applied.map((x) => x.key), ['ta_limits', 'rooms', 'open_times']);
      expect(r.decisions.single.id, 'd1');
      expect(r.decisions.single.reason, 'ask');
      expect(r.decisions.single.chosen, 'open_times');
      expect(r.decisions.single.chosenName, 'Open new times');
      expect(r.decisions.single.by, 'user');
      expect(r.decisions.single.recommended, 'open_times');
      expect(r.decisions.single.followedRecommendation, isTrue);
      expect(r.decisions.single.atS, 150.2);
      expect(r.decisions.single.options.length, 2);
      expect(r.blockedBy, isEmpty);
      expect(r.bestBlocked, isNull);
      expect(r.structural.rooms.single['capacity'], 40);
      expect(r.structural.periods.single['label'], '+1');
      expect(r.structural.days, isEmpty);
      expect(r.structural.splits, isEmpty);
      expect(r.structural.total, 2);
      expect(r.structural.lines, ['1 new room(s)', '1 new period(s)']);
      expect(r.proof.hardVsRelaxed, 0);
      expect(r.proof.hardVsOriginal, 4);
      expect(r.proof.neverBrokenViolations, 0);
      expect(r.proof.clean, isTrue);
      expect(r.provenClean, isTrue);
      expect(r.completionPct, 100);
      expect(r.elapsedS, 233.4);
      expect(r.budgetS, 1200);
      expect(r.solves, 7);
      expect(r.seed, 7);
      expect(r.auto, isFalse);
      expect(r.placed, 180);
      expect(r.required, 180);
      expect(r.unplaced, 0);
      expect(r.broken.length, 4);
      expect(r.brokenByRung, {'ta_limits': 2, 'rooms': 1, 'open_times': 1});
      expect(r.brokenByRung.keys.toList(), ['ta_limits', 'rooms', 'open_times'], reason: 'ladder order');
    });

    test('of: not a ladder result → null; a bare report falls back to the rungs for the placed count', () {
      expect(LadderReport.of(const {'stats': {'sessions_placed': 3}}), isNull);
      final r = LadderReport.of({'ladder': {'status': 'time_limit', 'rungs': [{'key': 'free_moves', 'applied': true, 'placed_after': 150}, {'key': 'rooms', 'applied': true, 'placed_before': 150, 'placed_after': 170}]}})!;
      expect(r.placed, 170);
      expect(r.required, 0);
      expect(r.valid, isTrue);
      expect(r.status, 'time_limit');
      expect(r.structural.isEmpty, isTrue);
      expect(r.proof.clean, isTrue);
    });

    test('blockedBy / proof on an incomplete run; days as plain strings are accepted', () {
      final r = LadderReport.of(incompleteResult())!;
      expect(r.status, 'incomplete');
      expect(r.complete, isFalse);
      expect(r.placed, 170);
      expect(r.unplaced, 10);
      expect(r.blockedBy.length, 2);
      expect(r.blockedBy.first.key, 'capacity');
      expect(r.blockedBy.first.name, 'Over capacity');
      expect(r.blockedBy.first.wouldComplete, isFalse);
      expect(r.blockedBy.first.placedAfter, 176);
      expect(r.blockedBy.first.required, 180);
      expect(r.bestBlocked!.key, 'student_clash', reason: 'the one that would complete it');
      expect(r.proof.hardVsOriginal, 0);
      expect(LadderBlocked.of(const {'key': 'rooms'}).name, 'Rooms', reason: 'names from TEXT when the server sends none');
      expect(LadderStructural.of(const {'days': ['friday']}).days, [{'day': 'friday'}]);
      final removed = LadderStructural.of(const {
        'rooms': [{'id': 1, 'created_id': 9, 'removed': true}, {'id': 2, 'created_id': 10}],
        'periods': [{'id': -1001, 'created_id': 5, 'removed': true}],
        'splits': [{'course_id': 1, 'kind': 'lecture', 'from': 1, 'groups': 3, 'staff': [{'group_no': 1, 'teacher_id': 7, 'new': false}, {'group_no': 3, 'teacher_id': 8, 'new': true}]}],
      });
      expect(removed.removedRooms, 1);
      expect(removed.removedPeriods, 1);
      expect(removed.newStaff, 1);
      expect(removed.lines, ['2 new room(s) (1 removed again)', '1 new period(s) (1 removed again)', '1 group(s) split (1 handed to a colleague)']);
      expect(LadderStructural.of(const {'days': ['friday'], 'splits': [{'course_id': 1, 'kind': 'lab', 'from': 1, 'groups': 2, 'sizes': [20, 20], 'sessions': 4}]}).lines, ['1 new day(s)', '1 group(s) split']);
      final only = LadderReport(blockedBy: const [LadderBlocked(key: 'capacity', nameAr: 'a', nameEn: 'b', placedAfter: 176, required: 180), LadderBlocked(key: 'rooms', nameAr: 'c', nameEn: 'd', placedAfter: 178, required: 180)]);
      expect(only.bestBlocked!.key, 'rooms', reason: 'none completes it: the one that places the most');
    });

    test('summaryText: complete, in both languages', () {
      final r = LadderReport.of(completeResult())!;
      expect(r.summaryText(), 'Complete: 180 of 180 placed, 4 rule(s) bent (TA limits ×2, Rooms ×1, Open new times ×1), 1 new room(s), 1 new period(s), proven conflict-free');
      AppConfig.lang = 'ar';
      expect(r.summaryText(), 'مكتمل: وُضعت 180 من 180 حصة، كُسرت 4 قاعدة (حدود المعيدين ×2، القاعات ×1، فتح أوقات جديدة ×1)، 1 قاعة جديدة، 1 فترة جديدة، مُثبت خلوّه من التعارضات');
    });

    test('summaryText: complete without any break; not proven when the proof is not clean', () {
      final res = completeResult();
      res['broken'] = [];
      (res['ladder'] as Map)['structural'] = {'rooms': [], 'periods': [], 'days': [], 'splits': []};
      expect(LadderReport.of(res)!.summaryText(), 'Complete: 180 of 180 placed, no rule bent, proven conflict-free');
      (res['ladder'] as Map)['proof'] = {'hard_vs_relaxed': 0, 'hard_vs_original': 0, 'never_broken_violations': 1};
      expect(LadderReport.of(res)!.summaryText(), 'Complete: 180 of 180 placed, no rule bent, not proven conflict-free');
      expect(LadderReport.of(res)!.provenClean, isFalse);
    });

    test('summaryText: incomplete names what blocks completion; time limit / stopped / cancelled / invalid', () {
      final r = LadderReport.of(incompleteResult())!;
      expect(r.summaryText(), 'Incomplete: 170 of 180 placed, no rule bent — unlocking "Student clash" would complete it');
      AppConfig.lang = 'ar';
      expect(r.summaryText(), 'غير مكتمل: وُضعت 170 من 180 حصة، بلا كسر أي قاعدة — فتح «تعارض الطلاب» يُكمل الجدول');
      AppConfig.lang = 'en';

      final res = incompleteResult();
      (res['ladder'] as Map)['blocked_by'] = [{'key': 'capacity', 'name_ar': 'تجاوز السعة', 'name_en': 'Over capacity', 'would_complete': false, 'placed_after': 176, 'required': 180}];
      expect(LadderReport.of(res)!.summaryText(), 'Incomplete: 170 of 180 placed, no rule bent — unlocking "Over capacity" would place 176 of 180');
      (res['ladder'] as Map)['blocked_by'] = [];
      expect(LadderReport.of(res)!.summaryText(), 'Incomplete: 170 of 180 placed, no rule bent — no locked rung would complete it — check the data');
      (res['ladder'] as Map)['status'] = 'time_limit';
      expect(LadderReport.of(res)!.summaryText(), 'Time limit: 170 of 180 placed, no rule bent');
      (res['ladder'] as Map)['status'] = 'stopped_by_creator';
      expect(LadderReport.of(res)!.summaryText(), 'Stopped by you: 170 of 180 placed, no rule bent');
      (res['ladder'] as Map)['status'] = 'cancelled';
      expect(LadderReport.of(res)!.summaryText(), 'Cancelled: nothing in the timetable changed');
      (res['ladder'] as Map)['status'] = 'invalid';
      (res['ladder'] as Map)['valid'] = false;
      (res['ladder'] as Map)['proof'] = {'hard_vs_relaxed': 2, 'hard_vs_original': 2, 'never_broken_violations': 2};
      final bad = LadderReport.of(res)!;
      expect(bad.summaryText(), 'The final check failed: the result has 2 disallowed conflict(s) and nothing was saved');
      expect(bad.provenClean, isFalse);
      expect(bad.valid, isFalse);
    });
  });

  group('brokenRuleLine', () {
    const names = {10: 'Maths', 11: 'Physics'};
    const people = {7: 'Sara', 8: 'Omar'};
    const rooms = {5: 'Hall A'};
    const periods = {3: 'P3', 1: 'P1'};

    test('every rule key, with the course, the cell and the rung', () {
      final r = LadderReport.of(completeResult())!;
      expect(brokenRuleLine(r.broken[0], names: names, people: people, periods: periods), 'Maths (lab G2) monday · P3: Sara at a time they are unavailable — TA limits');
      expect(brokenRuleLine(r.broken[1], names: names, people: people, periods: periods), 'Physics (lecture) tuesday · P1: Omar over their daily cap — TA limits');
      expect(brokenRuleLine(r.broken[2]), 'course 12 (lecture) sunday: a new period +1 — Open new times');
      expect(brokenRuleLine(r.broken[3], rooms: rooms), 'course 13 (lecture) sunday: a theory session in Hall A of another kind — Rooms');

      String line(String rule, [Map<String, dynamic> extra = const {}]) => brokenRuleLine({'rule': rule, 'course_id': 10, 'kind': 'lecture', ...extra}, names: names, people: people, rooms: rooms);
      expect(line('teacher_week_limit', {'user_id': 8}), 'Maths (lecture): Omar over their weekly cap');
      expect(line('teacher_unavailable'), 'Maths (lecture): a staff member at a time they are unavailable');
      expect(line('room_unavailable', {'room_id': 5}), 'Maths (lecture): Hall A at a time it is unavailable');
      expect(line('room_capabilities', {'room_id': 5}), 'Maths (lecture): Hall A lacks required equipment');
      expect(line('room_capacity', {'room_id': 9}), 'Maths (lecture): a room over its capacity');
      expect(line('new_room', {'detail': {'kind': 'lab', 'capacity': 40, 'capabilities': []}}), 'Maths (lecture): a proposed new room (lab, 40 seats)');
      expect(line('new_day', {'day': 'friday', 'detail': {'day': 'friday'}}), 'Maths (lecture) friday: a new day friday');
      expect(line('group_split', {'group_no': 3, 'detail': {'from': 1, 'groups': 3, 'sizes': [20, 20, 20]}}), 'Maths (lecture G3): a group split into 3 instead of 1');
      expect(line('students_unavailable'), 'Maths (lecture): students at a time they are unavailable');
      expect(line('students_busy_elsewhere'), 'Maths (lecture): students busy in another active timetable');
      expect(line('students_clash'), 'Maths (lecture): students in two sessions at once');
      expect(line('something_new'), 'Maths (lecture): something new');
    });

    test('Arabic', () {
      AppConfig.lang = 'ar';
      final r = LadderReport.of(completeResult())!;
      expect(brokenRuleLine(r.broken[0], names: names, people: people, periods: periods), 'Maths (معمل مج2) monday · P3: Sara في وقت غير متاح له — حدود المعيدين');
      expect(brokenRuleLine(r.broken[2]), 'مقرر 12 (محاضرة) sunday: فترة جديدة +1 — فتح أوقات جديدة');
      expect(brokenRuleLine(const {'rule': 'students_clash', 'course_id': 1}), 'مقرر 1 (محاضرة): طلاب في حصتين في الوقت نفسه');
    });
  });

  test('runIsOpen: queued, running and waiting are open; the rest are not', () {
    expect(runIsOpen(const {'status': 'queued'}), isTrue);
    expect(runIsOpen(const {'status': 'running'}), isTrue);
    expect(runIsOpen(const {'status': 'waiting'}), isTrue);
    expect(runIsOpen(const {'status': 'succeeded'}), isFalse);
    expect(runIsOpen(const {'status': 'failed'}), isFalse);
    expect(runIsOpen(const {'status': 'cancelled'}), isFalse);
    expect(runIsOpen(null), isFalse);
    expect(runStatusLabels()['waiting'], 'Waiting for your decision');
  });

  group('widget texts and orderings', () {
    test('ladderHeadline: queued / failed / waiting, the open step, the stage, the rung', () {
      expect(ladderHeadline(const LadderLive(status: 'queued')), 'Queued — generation starts in a moment');
      expect(ladderHeadline(const LadderLive(status: 'failed')), 'Generation failed — nothing changed');
      expect(ladderHeadline(LadderLive.of(waitingRun())!), 'Waiting for your decision');
      final step = LiveStep.of(const {'id': 3, 'kind': 'round', 'text_en': 'Trying: Rooms — a room outside its times', 'text_ar': 'x', 'done': false});
      expect(ladderHeadline(LadderLive(status: 'running', steps: [step])), 'Trying: Rooms — a room outside its times');
      expect(ladderHeadline(const LadderLive(status: 'running', stage: 'prepare')), 'Loading the data…');
      expect(ladderHeadline(const LadderLive(status: 'running', stage: 'save')), 'Saving the timetable…');
      expect(ladderHeadline(const LadderLive(status: 'running', stage: 'round', rung: 'rooms')), 'Trying: Rooms');
      expect(ladderHeadline(const LadderLive(status: 'running')), 'Generating…');
      AppConfig.lang = 'ar';
      expect(ladderHeadline(const LadderLive(status: 'running', stage: 'round', rung: 'rooms')), 'تجربة: القاعات');
      expect(ladderStatusOpen('waiting'), isTrue);
      expect(ladderStatusOpen('succeeded'), isFalse);
    });

    test('orderedOptions: possible rungs by rank, then impossible, stop last', () {
      final d = LadderDecision.of(decisionJson());
      expect(orderedOptions(d).map((o) => o.id), ['ta_limits', 'rooms', 'open_times', 'stop']);
      final shuffled = LadderDecision.of({
        ...decisionJson(),
        'options': [
          {'id': 'stop', 'possible': true, 'rank': 1},
          optionJson('rooms', rank: 3),
          {'id': 'capacity', 'possible': false, 'rank': 2},
          optionJson('ta_limits', rank: 2),
        ],
      });
      expect(orderedOptions(shuffled).map((o) => o.id), ['ta_limits', 'rooms', 'capacity', 'stop']);
    });

    test('rungResultText / rungSkippedText: applied, skipped, locked, not tried', () {
      final r = LadderReport.of(completeResult())!;
      expect(rungResultText(r.rungs[0]), '160 placed, nothing bent · 54 s');
      expect(rungResultText(r.rungs[1]), '+12 placed · 2 rule(s) bent · 30 s');
      expect(rungResultText(r.rungs[2]), 'skipped: no gain');
      expect(rungResultText(r.rungs[4]), 'skipped: nothing to add');
      expect(rungResultText(const LadderRungResult(key: 'capacity', mode: 'locked')), 'locked — not tried');
      expect(rungResultText(const LadderRungResult(key: 'capacity', mode: 'auto')), 'not tried');
      expect(rungResultText(const LadderRungResult(key: 'rooms', tried: true, note: {'skipped': 'passed_over'})), 'skipped: passed over by you');
      expect(rungSkippedText(null), '');
      expect(rungSkippedText('not_relevant'), 'cannot touch what blocks the rest');
      expect(rungResultText(const LadderRungResult(key: 'ta_limits', note: {'skipped': 'not_relevant', 'reasons': ['rooms_busy']})),
          'skipped: cannot touch what blocks the rest');
      expect(rungSkippedText('something_else'), 'something else');
      AppConfig.lang = 'ar';
      expect(rungResultText(r.rungs[2]), 'تُخطّيت: لم يضف حصة');
    });

    test('decisionByText and pendingBlockIds', () {
      expect(decisionByText('user'), 'by you');
      expect(decisionByText('timeout'), 'automatically after the timeout');
      expect(decisionByText('auto'), 'automatically');
      final broken = [
        {'block_id': 'b1', 'decision': null},
        {'block_id': 'b1', 'decision': null},
        {'block_id': 'b2', 'decision': 'accept'},
        {'block_id': 'b3', 'decision': null},
        {'block_id': 'b4'},
      ];
      expect(pendingBlockIds(broken), ['b1', 'b3'], reason: 'one id per block; decided blocks and blocks without a decision field are not proposals');
      expect(pendingBlockIds(const []), isEmpty);
    });
  });
}
