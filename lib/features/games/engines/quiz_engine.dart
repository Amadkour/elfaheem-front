// lib/features/games/engines/quiz_engine.dart — the `quiz` engine (D-1346): one question at a time, pick an option,
// see right / wrong at once, Next. Score = right answers, max = questions.
// config = {shuffle: bool, questions: [{prompt_ar, prompt_en, options: [string], answer: index}]}
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/shell/game_shell.dart';
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
  int _i = 0, _score = 0;
  int? _picked;

  @override
  void initState() {
    super.initState();
    final all = QuizEngine.questionsOf(widget.config);
    _qs = widget.config['shuffle'] == true ? learnShuffle(all, random: widget.random, avoidIdentity: false) : all;
  }

  void _pick(int i) {
    if (_picked != null) return;
    setState(() {
      _picked = i;
      if (i == _qs[_i].answer) _score++;
    });
    GameShellScope.maybeOf(context)?.report(done: _i + 1, score: _score, correct: i == _qs[_i].answer);
  }

  void _next() {
    if (_i + 1 >= _qs.length) {
      widget.onFinished(_score, _qs.length);
      return;
    }
    setState(() {
      _i++;
      _picked = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_qs.isEmpty) {
      return AppEmpty(icon: Icons.quiz_rounded, title: t('لا توجد أسئلة في هذه اللعبة', 'This game has no questions'));
    }
    final q = _qs[_i];
    final last = _i + 1 >= _qs.length;
    final marks = [
      for (var k = 0; k < q.options.length; k++)
        _picked == null
            ? LearnMark.idle
            : k == q.answer
                ? (k == _picked ? LearnMark.correct : LearnMark.missed)
                : (k == _picked ? LearnMark.wrong : LearnMark.idle),
    ];
    // inside a GameShell the shell draws the progress and the score
    final inShell = GameShellScope.maybeOf(context) != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!inShell) ...[
        LearnProgressHeader(current: _i + 1, total: _qs.length, score: _score),
        const SizedBox(height: AppSpace.md),
      ],
      LearnPrompt(key: ValueKey('quiz.q.$_i'), text: q.prompt),
      const SizedBox(height: AppSpace.sm),
      LearnOptionList(options: q.options, marks: marks, onSelect: _picked == null ? _pick : null),
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
