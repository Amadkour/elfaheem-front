// lib/features/games/engines/quiz_engine.dart — the `quiz` engine (D-1346): one question at a time, pick an option,
// see right / wrong at once, Next. Score = right answers, max = questions.
// config = {shuffle: bool, questions: [{prompt_ar, prompt_en, options: [string], answer: index}]}
//
// Games v3 (§1, D-1740): the options enter one after another (AppReveal, `stagger`); a right pick fills green and
// pulses, a wrong one shakes and the right option fills green a beat (`tap`) later. Trace (CONTRACT §3): one entry
// per answered question, `i` = the question's index in the config (before the shuffle), `a` = the option picked.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppReveal;
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/shell/game_motion.dart';
import 'package:flutter_education_app/features/games/shell/game_shell.dart';
import 'package:flutter_education_app/features/games/shell/game_tile.dart';
import 'package:flutter_education_app/features/learn_kit/learn_kit.dart';

typedef QuizQuestion = ({String prompt, List<String> options, int answer});

class QuizEngine extends StatefulWidget {
  const QuizEngine({super.key, required this.config, required this.onFinished, this.random});

  final Map<String, dynamic> config;
  final void Function(int score, int maxScore) onFinished;
  final Random? random;

  /// The playable questions of [config] (a question without options or with an answer out of range is skipped).
  static List<QuizQuestion> questionsOf(Map<String, dynamic> config) {
    final raw = config['questions'];
    final out = <QuizQuestion>[];
    if (raw is! List) return out;
    for (final q in raw) {
      if (q is! Map) continue;
      final opts = [if (q['options'] is List) for (final o in q['options'] as List) '$o'];
      final a = q['answer'];
      if (opts.length < 2 || a is! num || a.toInt() < 0 || a.toInt() >= opts.length) continue;
      out.add((prompt: learnText('${q['prompt_ar'] ?? ''}', '${q['prompt_en'] ?? ''}'), options: opts, answer: a.toInt()));
    }
    return out;
  }

  @override
  State<QuizEngine> createState() => _QuizEngineState();
}

class _QuizEngineState extends State<QuizEngine> {
  late final List<QuizQuestion> _qs;

  /// _order[k] = the config index of the question shown k-th (the trace names config indices).
  late final List<int> _order;
  int _i = 0, _score = 0;
  int? _picked;

  /// After a wrong pick the right option fills green a beat later.
  bool _showRight = false;
  Timer? _timer;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    final all = QuizEngine.questionsOf(widget.config);
    final idx = [for (var k = 0; k < all.length; k++) k];
    _order = widget.config['shuffle'] == true ? learnShuffle(idx, random: widget.random, avoidIdentity: false) : idx;
    _qs = [for (final k in _order) all[k]];
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _pick(int i) {
    if (_picked != null) return;
    final right = i == _qs[_i].answer;
    final shell = GameShellScope.maybeOf(context);
    shell?.record(_order[_i], i);
    setState(() {
      _picked = i;
      _seq++;
      if (right) _score++;
      _showRight = right;
    });
    if (!right) {
      final d = GameMotion.of(context).tap;
      if (d == Duration.zero) {
        setState(() => _showRight = true);
      } else {
        _timer = Timer(d, () {
          if (mounted) setState(() => _showRight = true);
        });
      }
    }
    shell?.report(done: _i + 1, score: _score, correct: right);
  }

  void _next() {
    if (_i + 1 >= _qs.length) {
      widget.onFinished(_score, _qs.length);
      return;
    }
    _timer?.cancel();
    setState(() {
      _i++;
      _picked = null;
      _showRight = false;
    });
  }

  GameTileState _state(int k, QuizQuestion q) {
    final p = _picked;
    if (p == null) return GameTileState.idle;
    if (k == p) return k == q.answer ? GameTileState.correct : GameTileState.wrong;
    if (k == q.answer) return _showRight ? GameTileState.hint : GameTileState.locked;
    return GameTileState.locked;
  }

  @override
  Widget build(BuildContext context) {
    if (_qs.isEmpty) {
      return AppEmpty(icon: Icons.quiz_rounded, title: t('لا توجد أسئلة في هذه اللعبة', 'This game has no questions'));
    }
    final q = _qs[_i];
    final last = _i + 1 >= _qs.length;
    // inside a GameShell the shell draws the progress and the score
    final shell = GameShellScope.maybeOf(context);
    final inShell = shell != null;
    final sacred = shell?.sacred ?? false;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!inShell) ...[
        LearnProgressHeader(current: _i + 1, total: _qs.length, score: _score),
        const SizedBox(height: AppSpace.md),
      ],
      LearnPrompt(key: ValueKey('quiz.q.$_i'), text: q.prompt),
      const SizedBox(height: AppSpace.sm),
      for (var k = 0; k < q.options.length; k++) ...[
        if (k > 0) const SizedBox(height: AppSpace.xs),
        AppReveal(
          group: 'quiz.$_i',
          index: k,
          child: GameTile(
            key: ValueKey('learn.option.$k'),
            label: q.options[k],
            index: k,
            state: _state(k, q),
            pulse: _picked == k && k == q.answer ? _seq : null,
            shake: _picked == k && k != q.answer ? _seq : null,
            shakeEnabled: !sacred,
            onTap: _picked == null ? () => _pick(k) : null,
          ),
        ),
      ],
      if (_picked != null) ...[
        const SizedBox(height: AppSpace.md),
        LearnFeedback(
          correct: _picked == q.answer,
          explanation: _picked == q.answer ? null : t('الإجابة الصحيحة: ${q.options[q.answer]}', 'The right answer: ${q.options[q.answer]}'),
          actionLabel: last ? t('النتيجة', 'See result') : t('التالي', 'Next'),
          onAction: _next,
        ),
      ],
    ]);
  }
}
