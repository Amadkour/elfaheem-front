// lib/features/games/core/game_grade.dart — the Dart grader of Games v4 (Games v4 T12, CONTRACT §5–§7). It mirrors the
// server's items_grade.grade; both are checked against docs/games-v4/grading_vectors_v4.json
// (test/games/v4_grading_test.dart). Pure Dart: no Flutter, no clock.
//
//   gradeTrace(items, trace)   → GradeResult, or throws BadTrace (the whole trace is refused)
//   GradeState                 the same rules one entry at a time, for the live score of a session
//   simulateProgram            the robot (loops expanded, 200 steps, walls end the run)
//   starsOf / rankPoints / ageBand / srsStep / coinsForStars
library;

import 'dart:math' as math;

import 'game_items.dart';

const int kMinStepMs = 400;
const int kMaxTrace = 500;
const int kProgramRuns = 3;
const int kProgramMaxSteps = 200;
const int kGhostMax = 200;
const Map<String, int> kDifficultyPercent = {'easy': 100, 'medium': 125, 'hard': 150};
const List<String> kEndValues = ['done', 'timer', 'lives', 'quit'];
const Set<String> kNoSpeedBonusTemplates = {'growing_tree'};

/// A refused trace; [why] is the reason word of the vectors (`option`, `slot`, `ms`, `end`, `empty`, …).
class BadTrace implements Exception {
  const BadTrace(this.why);
  final String why;
  @override
  String toString() => 'BadTrace($why)';
}

class GradeResult {
  const GradeResult({
    required this.score,
    required this.maxScore,
    required this.counted,
    required this.durationMs,
    required this.end,
    required this.perItem,
    required this.ghost,
  });
  final int score, maxScore, counted, durationMs;

  /// `done` / `timer` / `lives` / `quit`.
  final String end;
  final List<int> perItem;

  /// `[[ms, 1 | 0]]`, one per counted entry, at most 200.
  final List<List<int>> ghost;

  int get stars => starsOf(score, maxScore);

  /// `too_fast`: the round was quicker than a human can answer.
  bool get tooFast => durationMs < counted * kMinStepMs;
}

int _int(Object? v, int lo, int hi, String why) {
  if (v is! int || v < lo || v > hi) throw BadTrace(why);
  return v;
}

List<int> _ints(Object? v, int n, String why, {int loLen = 0}) {
  if (v is! List || v.length < loLen) throw BadTrace(why);
  final out = [for (final x in v) _int(x, 0, n - 1, why)];
  if (out.toSet().length != out.length) throw BadTrace(why);
  return out;
}

int _len(Object? v) => v is List ? v.length : 0;

int _flatLen(List cmds) {
  var n = 0;
  for (final c in cmds) {
    n += 1 + (c is Map ? _len(c['do']) : 0);
  }
  return n;
}

const _basic = ['F', 'L', 'R'];

void _checkProgram(Map<String, dynamic> b, Object? a) {
  if (a is! List || a.isEmpty || a.length > 60) throw const BadTrace('program');
  final allowed = [for (final c in (b['cmds'] as List)) c as String];
  for (final c in a) {
    if (c is String) {
      if (!_basic.contains(c) || !allowed.contains(c)) throw const BadTrace('program_cmd');
    } else if (c is Map) {
      if (!allowed.contains('LOOP') || c.length != 2 || !c.containsKey('loop') || !c.containsKey('do')) {
        throw const BadTrace('program_cmd');
      }
      _int(c['loop'], 2, 9, 'program_loop');
      final d = c['do'];
      if (d is! List || d.isEmpty || d.length > 10) throw const BadTrace('program_loop');
      for (final x in d) {
        if (x is! String || !_basic.contains(x) || !allowed.contains(x)) throw const BadTrace('program_cmd');
      }
    } else {
      throw const BadTrace('program_cmd');
    }
  }
  if (_flatLen(a) > 60) throw const BadTrace('program');
}

/// One simulated run of the robot.
class ProgramRun {
  const ProgramRun({
    required this.reached,
    required this.bumped,
    required this.steps,
    required this.length,
    required this.x,
    required this.y,
    required this.dir,
    required this.points,
  });
  final bool reached, bumped;
  final int steps, length, x, y, dir, points;
}

/// CONTRACT §6 "Program simulation". [b] is the item's body, [a] the command list.
ProgramRun simulateProgram(Map<String, dynamic> b, List a) {
  final start = b['start'] as List;
  var x = (start[0] as num).toInt(), y = (start[1] as num).toInt(), d = (start[2] as num).toInt();
  final goal = b['goal'] as List;
  final gx = (goal[0] as num).toInt(), gy = (goal[1] as num).toInt();
  final w = (b['w'] as num).toInt(), h = (b['h'] as num).toInt();
  final walls = <int>{
    for (final p in (b['walls'] as List? ?? const [])) ((p as List)[0] as int) * 1000 + (p[1] as int),
  };
  final flat = <String>[];
  for (final c in a) {
    if (c is Map) {
      for (var k = 0; k < (c['loop'] as int); k++) {
        flat.addAll([for (final s in (c['do'] as List)) s as String]);
      }
    } else {
      flat.add(c as String);
    }
  }
  const dx = [0, 1, 0, -1], dy = [-1, 0, 1, 0];
  var steps = 0;
  var reached = false, bumped = false;
  for (final c in flat) {
    if (steps >= kProgramMaxSteps) break;
    steps++;
    if (c == 'L') {
      d = (d + 3) % 4;
    } else if (c == 'R') {
      d = (d + 1) % 4;
    } else {
      final nx = x + dx[d], ny = y + dy[d];
      if (nx < 0 || nx >= w || ny < 0 || ny >= h || walls.contains(nx * 1000 + ny)) {
        bumped = true;
        break;
      }
      x = nx;
      y = ny;
      if (x == gx && y == gy) {
        reached = true;
        break;
      }
    }
  }
  final length = _flatLen(a);
  var pts = 0;
  if (reached && length <= (b['max'] as num)) pts = length <= (b['par'] as num) ? 2 : 1;
  return ProgramRun(reached: reached, bumped: bumped, steps: steps, length: length, x: x, y: y, dir: d, points: pts);
}

/// Checks the shape and range of one entry's `a` and returns the unit key "first try" is counted by.
String _unitKey(GameItem it, Object? a) {
  final b = it.body;
  switch (it.type) {
    case ItemType.mcq:
      _int(a, 0, _len(b['options']) - 1, 'option');
      return 'x';
    case ItemType.trueFalse:
      _int(a, 0, 1, 'bool');
      return 'x';
    case ItemType.selectAll:
      _ints(a, _len(b['options']), 'options');
      return 'x';
    case ItemType.sequence:
      if (a is! List || a.length != 2) throw const BadTrace('slot');
      final slot = _int(a[0], 0, _len(b['tokens']) - 1, 'slot');
      if (!(b['blanks'] as List).contains(slot)) throw const BadTrace('slot');
      _int(a[1], 0, _len(b['tokens']) + _len(b['extra']) - 1, 'token');
      return 's$slot';
    case ItemType.classify:
      if (a is! List || (a.length != 2 && a.length != 3)) throw const BadTrace('classify');
      final tok = _int(a[0], 0, _len(b['tokens']) - 1, 'token');
      _int(a[1], 0, _len(b['buckets']) - 1, 'bucket');
      if (a.length == 3) {
        final cases = b['cases'];
        if (cases is! List || cases.isEmpty || (b['tokens'] as List)[tok]['case'] == null) throw const BadTrace('case');
        _int(a[2], 0, cases.length - 1, 'case');
        return 'c$tok';
      }
      return 'b$tok';
    case ItemType.pair:
      if (a is! List || a.length != 2) throw const BadTrace('pair');
      final ia = _int(a[0], 0, _len(b['pairs']) - 1, 'pair');
      _int(a[1], 0, _len(b['pairs']) - 1, 'pair');
      return 'p$ia';
    case ItemType.fraction:
      if (a is! List || a.length != 2) throw const BadTrace('fraction');
      _int(a[0], 0, 999, 'fraction');
      _int(a[1], 1, 999, 'fraction');
      return 'x';
    case ItemType.program:
      _checkProgram(b, a);
      return 'x';
    case ItemType.combine:
      _ints(a, _len(b['ingredients']), 'ingredients', loLen: 1);
      return 'x';
  }
}

int _unitPoints(GameItem it, Object? a) {
  final b = it.body;
  switch (it.type) {
    case ItemType.mcq:
      return a == b['answer'] ? 1 : 0;
    case ItemType.trueFalse:
      return ((a == 1) == (b['answer'] == true)) ? 1 : 0;
    case ItemType.selectAll:
      final picked = (a as List).toSet();
      final hits = picked.intersection((b['answers'] as List).toSet()).length;
      return math.max(0, hits - (picked.length - hits));
    case ItemType.sequence:
      final l = a as List;
      final slot = l[0] as int, tok = l[1] as int;
      final eq = b['eq'] as List;
      return (tok < _len(b['tokens']) && eq[tok] == eq[slot]) ? 1 : 0;
    case ItemType.classify:
      final l = a as List;
      final tok = (b['tokens'] as List)[l[0] as int] as Map;
      if (l.length == 3) return (b['cases'] as List)[l[2] as int]['key'] == tok['case'] ? 1 : 0;
      return (b['buckets'] as List)[l[1] as int]['key'] == tok['bucket'] ? 1 : 0;
    case ItemType.pair:
      final l = a as List;
      return l[0] == l[1] ? 1 : 0;
    case ItemType.fraction:
      final l = a as List;
      int rn, rd;
      if (b.containsKey('op')) {
        final x = b['a'] as List, y = b['b'] as List;
        final an = x[0] as int, ad = x[1] as int, bn = y[0] as int, bd = y[1] as int;
        rn = b['op'] == 'add' ? an * bd + bn * ad : an * bd - bn * ad;
        rd = ad * bd;
      } else {
        rn = b['n'] as int;
        rd = b['d'] as int;
      }
      return (l[0] as int) * rd == rn * (l[1] as int) ? 1 : 0;
    case ItemType.combine:
      final ing = b['ingredients'] as List;
      final got = {for (final k in (a as List)) (ing[k as int] as Map)['key']};
      final want = (b['answer'] as List).toSet();
      return got.length == want.length && got.containsAll(want) ? 1 : 0;
    case ItemType.program:
      return simulateProgram(b, a as List).points;
  }
}

/// What one accepted entry did: [counted] when it was a unit's first try (it feeds the ghost), [points] it scored.
class EntryResult {
  const EntryResult({required this.counted, required this.points, required this.ms});
  final bool counted;
  final int points, ms;
}

/// The grading rules one entry at a time. [gradeTrace] runs the whole trace through it; a session runs the live one.
class GradeState {
  GradeState(this.items) : perItem = List.filled(items.length, 0);
  final List<GameItem> items;
  final List<int> perItem;
  final List<List<int>> ghost = [];
  final Set<String> _seen = {};
  final Map<int, int> _runs = {};
  int counted = 0, lastMs = 0;
  String end = 'done';

  int get score => perItem.fold(0, (a, b) => a + b);
  int get maxScore => items.fold(0, (a, b) => a + b.max);

  /// Validates and applies one entry (throws [BadTrace]). [last]: no entry follows (an end entry must be last).
  EntryResult add(Map e, {required bool last}) {
    final ms = e['ms'];
    if (ms is! int || ms < lastMs) throw const BadTrace('ms');
    lastMs = ms;
    final i = e['i'];
    if (i is! int || i < -1 || i >= items.length) throw const BadTrace('i');
    if (i == -1) {
      if (!last || !kEndValues.contains(e['a'])) throw const BadTrace('end');
      end = e['a'] as String;
      return EntryResult(counted: false, points: 0, ms: ms);
    }
    final it = items[i];
    final a = e['a'];
    final unit = _unitKey(it, a);
    final hinted = e['h'] == true;
    if (it.type == ItemType.program) {
      final k = _runs[i] ?? 0;
      if (k >= kProgramRuns) return EntryResult(counted: false, points: 0, ms: ms);
      _runs[i] = k + 1;
      final pts = hinted ? 0 : simulateProgram(it.body, a as List).points;
      if (k == 0) {
        counted++;
        ghost.add([ms, pts > 0 ? 1 : 0]);
      }
      if (pts > perItem[i]) perItem[i] = pts;
      return EntryResult(counted: k == 0, points: pts, ms: ms);
    }
    if (!_seen.add('$i:$unit')) return EntryResult(counted: false, points: 0, ms: ms);
    counted++;
    final pts = hinted ? 0 : _unitPoints(it, a);
    perItem[i] += pts;
    ghost.add([ms, pts > 0 ? 1 : 0]);
    return EntryResult(counted: true, points: pts, ms: ms);
  }

  GradeResult result() {
    if (counted == 0) throw const BadTrace('empty');
    return GradeResult(
      score: score,
      maxScore: maxScore,
      counted: counted,
      durationMs: lastMs,
      end: end,
      perItem: List.unmodifiable(perItem),
      ghost: ghost.length > kGhostMax ? ghost.sublist(0, kGhostMax) : ghost,
    );
  }
}

/// Grades a whole trace against the draw's items; throws [BadTrace] when it is refused.
GradeResult gradeTrace(List<GameItem> items, Object? trace) {
  if (trace is! List || trace.isEmpty || trace.length > kMaxTrace) throw const BadTrace('trace');
  final st = GradeState(items);
  for (var pos = 0; pos < trace.length; pos++) {
    final e = trace[pos];
    if (e is! Map) throw const BadTrace('entry');
    st.add(e, last: pos == trace.length - 1);
  }
  return st.result();
}

/// 3 stars at 90 %, 2 at 60 %, 1 at 30 % (integer maths).
int starsOf(int score, int max) {
  if (max <= 0) return 0;
  if (score * 10 >= max * 9) return 3;
  if (score * 10 >= max * 6) return 2;
  if (score * 10 >= max * 3) return 1;
  return 0;
}

/// CONTRACT §7 rank points: [difficulty] is `easy` / `medium` / `hard`.
int rankPoints({
  required List<GameItem> items,
  required int score,
  required int max,
  required int durationMs,
  required String difficulty,
  required bool sacred,
  required String template,
}) {
  if (starsOf(score, max) == 0) return 0;
  final base = (200 * score + max) ~/ (2 * max);
  final parMs = items.fold<int>(0, (a, b) => a + b.parSeconds) * 1000;
  final bonus = (sacred || kNoSpeedBonusTemplates.contains(template) || parMs == 0)
      ? 0
      : math.max(0, 200 - (100 * durationMs) ~/ parMs);
  return (base * (kDifficultyPercent[difficulty] ?? 125) * (1000 + bonus) + 50000) ~/ 100000;
}

/// An item difficulty 1–2 is easy, 3 medium, 4–5 hard.
String difficultyName(int itemDifficulty) => itemDifficulty <= 2 ? 'easy' : (itemDifficulty == 3 ? 'medium' : 'hard');

/// The learner's age band from the date of birth, else from the school grade (`grade + 5`); nulls when neither.
({String? band, String? source}) ageBand({DateTime? dob, int? grade, required DateTime today}) {
  int age;
  String src;
  if (dob != null) {
    final beforeBirthday = today.month < dob.month || (today.month == dob.month && today.day < dob.day);
    age = today.year - dob.year - (beforeBirthday ? 1 : 0);
    src = 'dob';
  } else if (grade != null) {
    age = grade + 5;
    src = 'grade';
  } else {
    return (band: null, source: null);
  }
  final band = age < 10 ? '6-9' : (age < 14 ? '10-13' : (age < 18 ? '14-17' : '18+'));
  return (band: band, source: src);
}

/// Days until due per Leitner box 1..5.
const List<int> kSrsDays = [1, 3, 7, 14, 30];

/// The SRS ladder: [box] is the current box (null = no row). Null result = nothing changes (right, no row).
({int box, int dueInDays, int lapsesAdded})? srsStep(int? box, {required bool right}) {
  if (!right) return (box: 1, dueInDays: kSrsDays[0], lapsesAdded: 1);
  if (box == null) return null;
  final nb = math.min(5, box + 1);
  return (box: nb, dueInDays: kSrsDays[nb - 1], lapsesAdded: 0);
}

/// The coins a play of a level pays: each of the three stars once, `reward ~/ 3` for stars 1 and 2, the rest for star 3.
int coinsForStars({required int reward, required int starsBefore, required int starsNow}) {
  final third = reward ~/ 3;
  var total = 0;
  for (var s = starsBefore + 1; s <= starsNow && s <= 3; s++) {
    total += s == 3 ? reward - 2 * third : third;
  }
  return total;
}
