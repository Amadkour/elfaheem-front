// lib/features/games/engines/match_engine.dart — the `match` engine (D-1346): two columns, the `a` side in order and
// the `b` side shuffled; tap one on each side to pair them. A right pair locks green, a wrong one shows red until
// the next tap. Score = pairs matched with no wrong try, max = pairs.
// config = {prompt_ar, prompt_en, pairs: [{a, b}]}
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/learn_kit/learn_kit.dart';

class MatchEngine extends StatefulWidget {
  const MatchEngine({super.key, required this.config, required this.onFinished, this.random});

  final Map<String, dynamic> config;
  final void Function(int score, int maxScore) onFinished;
  final Random? random;

  static List<({String a, String b})> pairsOf(Map<String, dynamic> config) => [
        if (config['pairs'] is List)
          for (final p in config['pairs'] as List)
            if (p is Map && '${p['a'] ?? ''}'.isNotEmpty && '${p['b'] ?? ''}'.isNotEmpty) (a: '${p['a']}', b: '${p['b']}'),
      ];

  @override
  State<MatchEngine> createState() => _MatchEngineState();
}

class _MatchEngineState extends State<MatchEngine> {
  late final List<({String a, String b})> _pairs;

  /// The right column: _right[k] is the pair index drawn at row k.
  late final List<int> _right;
  final Set<int> _matched = {};
  final Set<int> _missedOnce = {};
  int? _left, _rightPick;

  /// The last wrong try (left pair, right row), drawn red until the next tap.
  (int, int)? _wrong;

  @override
  void initState() {
    super.initState();
    _pairs = MatchEngine.pairsOf(widget.config);
    _right = learnShuffle([for (var i = 0; i < _pairs.length; i++) i], random: widget.random);
  }

  bool get _done => _pairs.isNotEmpty && _matched.length == _pairs.length;

  void _tapLeft(int i) {
    if (_matched.contains(i)) return;
    setState(() {
      _wrong = null;
      _left = _left == i ? null : i;
    });
    _try();
  }

  void _tapRight(int row) {
    if (_matched.contains(_right[row])) return;
    setState(() {
      _wrong = null;
      _rightPick = _rightPick == row ? null : row;
    });
    _try();
  }

  void _try() {
    final l = _left, r = _rightPick;
    if (l == null || r == null) return;
    setState(() {
      if (_right[r] == l) {
        _matched.add(l);
      } else {
        _missedOnce.add(l);
        _wrong = (l, r);
      }
      _left = _rightPick = null;
    });
  }

  LearnMark _leftMark(int i) {
    if (_matched.contains(i)) return LearnMark.correct;
    if (_wrong?.$1 == i) return LearnMark.wrong;
    return _left == i ? LearnMark.selected : LearnMark.idle;
  }

  LearnMark _rightMark(int row) {
    if (_matched.contains(_right[row])) return LearnMark.correct;
    if (_wrong?.$2 == row) return LearnMark.wrong;
    return _rightPick == row ? LearnMark.selected : LearnMark.idle;
  }

  @override
  Widget build(BuildContext context) {
    if (_pairs.isEmpty) {
      return AppEmpty(icon: Icons.join_inner_rounded, title: t('لا توجد أزواج في هذه اللعبة', 'This game has no pairs'));
    }
    final prompt = learnText('${widget.config['prompt_ar'] ?? ''}', '${widget.config['prompt_en'] ?? ''}');
    final score = _pairs.length - _missedOnce.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LearnProgressHeader(
        current: _matched.length,
        total: _pairs.length,
        label: t('وصّلت ${_matched.length} من ${_pairs.length}', 'Matched ${_matched.length} of ${_pairs.length}'),
      ),
      const SizedBox(height: AppSpace.md),
      LearnPrompt(text: prompt.isEmpty ? t('صِل كل عنصر بما يناسبه.', 'Match each item to its partner.') : prompt),
      const SizedBox(height: AppSpace.sm),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < _pairs.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpace.xs),
              LearnOptionTile(
                key: ValueKey('match.a.$i'),
                label: _pairs[i].a,
                mark: _leftMark(i),
                onTap: _matched.contains(i) ? null : () => _tapLeft(i),
              ),
            ],
          ]),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var k = 0; k < _right.length; k++) ...[
              if (k > 0) const SizedBox(height: AppSpace.xs),
              LearnOptionTile(
                key: ValueKey('match.b.$k'),
                label: _pairs[_right[k]].b,
                mark: _rightMark(k),
                onTap: _matched.contains(_right[k]) ? null : () => _tapRight(k),
              ),
            ],
          ]),
        ),
      ]),
      if (_done) ...[
        const SizedBox(height: AppSpace.md),
        LearnFeedback(
          correct: _missedOnce.isEmpty,
          // every pair is matched: a finish, not a failure, even after a slip (the score says how many were first try)
          neutral: _missedOnce.isNotEmpty,
          explanation: _missedOnce.isEmpty
              ? null
              : t('${_pairs.length - _missedOnce.length} من ${_pairs.length} من أول محاولة',
                  '${_pairs.length - _missedOnce.length} of ${_pairs.length} on the first try'),
          title: _missedOnce.isEmpty ? t('وصّلت كل الأزواج من أول مرة!', 'Every pair on the first try!') : t('اكتملت الأزواج', 'All pairs matched'),
          actionLabel: t('النتيجة', 'See result'),
          onAction: () => widget.onFinished(score, _pairs.length),
        ),
      ],
    ]);
  }
}
