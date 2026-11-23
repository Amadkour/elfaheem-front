// lib/features/games/core/game_session.dart — one round of a Games v4 template (Games v4 T12, CONTRACT §2, §4, §5).
//
//   GameSettings   the merged template settings of a draw, with the sacred override and the growing_tree rule
//   GameSession    owns the items, settings, trace, score, lives, timer, calm mode, pause and finish(); a template only
//                  draws the game and reports `s.answer(i, a)`. A ChangeNotifier: templates listen to it.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'game_grade.dart';
import 'game_items.dart';

/// The settings object of a draw (CONTRACT §2 "Settings"), after the sacred override.
class GameSettings {
  const GameSettings({
    this.timerS = 0,
    this.lives = 0,
    this.speed = 3,
    this.penalty = 'soft',
    this.theme = 'auto',
    this.music = true,
    this.hints = true,
    this.tilt = false,
    this.count = 8,
    this.calm = false,
    this.timeBonus = true,
  });

  /// 0 = no timer.
  final int timerS;

  /// 0 = unlimited.
  final int lives;
  final int speed, count;

  /// `none` / `soft` / `lives`.
  final String penalty;

  /// `auto` / `kids` / `teen` / `adult`.
  final String theme;
  final bool music, hints, tilt;

  /// A calm round: no flashing, no red, no time pressure shown (sacred text).
  final bool calm;

  /// False for a sacred round: the timer pays no time bonus.
  final bool timeBonus;

  static int _i(Object? v, int d, int lo, int hi) => v is num ? v.toInt().clamp(lo, hi) : d;
  static bool _b(Object? v, bool d) => v is bool ? v : d;

  /// Reads the draw's `settings` and applies the rules again on the device: a sacred draw turns `penalty: lives` into
  /// `soft`, adds `calm` and pays no time bonus; `growing_tree` is always untimed, lifeless and penalty-free.
  factory GameSettings.fromJson(Object? j, {required bool sacred, String template = ''}) {
    final m = j is Map ? j : const {};
    var penalty = m['penalty'] is String ? m['penalty'] as String : 'soft';
    if (!const ['none', 'soft', 'lives'].contains(penalty)) penalty = 'soft';
    var timerS = _i(m['timer_s'], 0, 0, 900);
    var lives = _i(m['lives'], 0, 0, 9);
    var calm = _b(m['calm'], false);
    if (sacred) {
      if (penalty == 'lives') penalty = 'soft';
      calm = true;
    }
    if (template == 'growing_tree') {
      timerS = 0;
      lives = 0;
      penalty = 'none';
    }
    final theme = m['theme'] is String ? m['theme'] as String : 'auto';
    return GameSettings(
      timerS: timerS,
      lives: lives,
      speed: _i(m['speed'], 3, 1, 5),
      penalty: penalty,
      theme: const ['auto', 'kids', 'teen', 'adult'].contains(theme) ? theme : 'auto',
      music: _b(m['music'], true),
      hints: _b(m['hints'], true),
      tilt: _b(m['tilt'], false),
      count: _i(m['count'], 8, 1, 30),
      calm: calm,
      timeBonus: !sacred,
    );
  }
}

/// One round in progress. Create it from a draw ([GameSession.fromDraw]) or from parts (tests, preview).
class GameSession extends ChangeNotifier {
  GameSession({
    required this.items,
    this.settings = const GameSettings(),
    this.templateKey = '',
    this.sacred = false,
    this.difficulty = 'medium',
    this.drawId,
    this.roundId,
    this.seed = 0,
    this.reciter,
    this.onFinished,
    int Function()? nowMs,
  })  : _now = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch),
        _state = GradeState(items),
        _lives = settings.lives,
        _remainingS = settings.timerS;

  /// Builds the session from a `POST /games/{id}/draw` answer (or one `GET /pool` round). Null when the draw has no
  /// items or has an item this app cannot read (a newer server): the caller shows "needs a newer version".
  static GameSession? fromDraw(Map draw, {GameFinishedCallback? onFinished, int Function()? nowMs}) {
    final raw = draw['items'];
    if (raw is! List || raw.isEmpty) return null;
    final items = parseGameItems(raw);
    if (items.length != raw.length) return null;
    final sacred = draw['sacred'] == true;
    final template = (draw['template'] ?? '') as String;
    return GameSession(
      items: items,
      settings: GameSettings.fromJson(draw['settings'], sacred: sacred, template: template),
      templateKey: template,
      sacred: sacred,
      difficulty: (draw['difficulty'] as String?) ?? 'medium',
      drawId: draw['draw_id'] as String?,
      roundId: draw['round_id'] as String?,
      seed: (draw['seed'] as num?)?.toInt() ?? 0,
      reciter: draw['reciter'] is Map ? Map<String, dynamic>.from(draw['reciter'] as Map) : null,
      onFinished: onFinished,
      nowMs: nowMs,
    );
  }

  final List<GameItem> items;
  final GameSettings settings;
  final String templateKey;
  final bool sacred;
  final String difficulty;
  final String? drawId, roundId;
  final int seed;

  /// The draw's effective reciter (`{key, name_ar, name_en}`) or null.
  final Map<String, dynamic>? reciter;

  /// Called once, when the round ends (also when the timer or the lives end it, or the player quits).
  GameFinishedCallback? onFinished;

  final int Function() _now;
  final GradeState _state;
  final List<Map<String, dynamic>> _trace = [];
  Timer? _timer;
  int _lives;
  int _remainingS;
  int _startedAt = -1;
  int _pausedTotal = 0;
  int _pausedAt = -1;
  int _lastMs = 0;
  bool _finished = false;
  String _ended = 'done';
  GradeResult? _result;

  /// The trace so far, in the shape the server takes (CONTRACT §5); the end entry is last once finished.
  List<Map<String, dynamic>> get trace => List.unmodifiable(_trace);
  int get score => _state.score;
  int get maxScore => _state.maxScore;
  int get lives => _lives;
  bool get hasLives => settings.lives > 0 && settings.penalty == 'lives';

  /// Seconds left; only meaningful when [hasTimer].
  int get remainingS => _remainingS;
  bool get hasTimer => settings.timerS > 0;
  bool get calm => settings.calm;
  bool get paused => _pausedAt >= 0;
  bool get finished => _finished;

  /// The graded result, set by [finish]; null before, and null when the round had no counted answer.
  GradeResult? get result => _result;

  /// How the round ended: `done` / `timer` / `lives` / `quit`, null while it runs.
  String? get endedBy => _finished ? _ended : null;

  /// Milliseconds since the round first showed, pauses excluded, never decreasing.
  int get elapsedMs {
    if (_startedAt < 0) return 0;
    final at = _pausedAt >= 0 ? _pausedAt : _now();
    final v = at - _startedAt - _pausedTotal;
    if (v > _lastMs) _lastMs = v;
    return _lastMs;
  }

  /// Starts the clock (and the countdown). Safe to call again.
  void start() {
    if (_startedAt >= 0 || _finished) return;
    _startedAt = _now();
    if (hasTimer) _timer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
    notifyListeners();
  }

  /// One second of the countdown; ends the round with `timer` at zero. The internal timer calls it; tests may too.
  void tick() {
    if (!hasTimer || _finished || paused) return;
    if (_remainingS > 0) _remainingS--;
    if (_remainingS <= 0) {
      finish('timer');
    } else {
      notifyListeners();
    }
  }

  void pause() {
    if (_finished || paused || _startedAt < 0) return;
    _pausedAt = _now();
    notifyListeners();
  }

  void resume() {
    if (!paused) return;
    _pausedTotal += _now() - _pausedAt;
    _pausedAt = -1;
    notifyListeners();
  }

  /// A template reports an answer: item [i], answer [a] in the shape of CONTRACT §5, [hint] when a hint was used for
  /// the unit first. Returns what the entry did, or null when the round is over, paused or the answer is malformed
  /// (nothing is recorded then). A wrong first try costs a life when `penalty` is `lives`; the last life ends the
  /// round (`lives`).
  EntryResult? answer(int i, Object? a, {bool hint = false}) {
    if (_finished || paused) return null;
    if (_startedAt < 0) start();
    final e = <String, dynamic>{'i': i, 'a': a, 'ms': elapsedMs, if (hint) 'h': true};
    final EntryResult r;
    try {
      r = _state.add(e, last: false);
    } on BadTrace {
      return null;
    }
    _trace.add(e);
    if (r.counted && r.points == 0 && hasLives && _lives > 0) {
      _lives--;
      if (_lives == 0) {
        finish('lives');
        return r;
      }
    }
    notifyListeners();
    return r;
  }

  /// Ends the round (idempotent): adds the end entry, grades the trace and calls [onFinished]. [by] is `done`,
  /// `timer`, `lives` or `quit`. Returns the result, null when nothing counted.
  GradeResult? finish([String by = 'done']) {
    if (_finished) return _result;
    _finished = true;
    _timer?.cancel();
    _timer = null;
    _ended = by;
    if (by != 'done') _trace.add({'i': -1, 'a': by, 'ms': elapsedMs});
    try {
      _result = gradeTrace(items, _trace);
    } on BadTrace {
      _result = null;
    }
    notifyListeners();
    onFinished?.call(this);
    return _result;
  }

  /// Stars, rank points and the ghost of the finished round; null before [finish] or when nothing counted.
  int? get rankPointsNow => _result == null
      ? null
      : rankPoints(
          items: items,
          score: _result!.score,
          max: _result!.maxScore,
          durationMs: _result!.durationMs,
          difficulty: difficulty,
          sacred: sacred,
          template: templateKey,
        );

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}

typedef GameFinishedCallback = void Function(GameSession session);
