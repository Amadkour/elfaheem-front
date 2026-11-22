// lib/features/games/engines/memory_engine.dart — the `memory` engine (Learning Hub v2 §3, D-1584): every pair's `a`
// and `b` are face-down cards, shuffled; turn two over, a pair stays up, two that do not belong turn back. Score =
// pairs, less one for every wrong try beyond the first [pairs] (a first look at the cards is free), never below 0;
// max = pairs ([MemoryEngine.scoreFor]).
// config = {prompt_ar, prompt_en, pairs: [{a, b}]} (2..10)
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/engines/match_engine.dart';
import 'package:flutter_education_app/features/games/shell/game_shell.dart';
import 'package:flutter_education_app/features/learn_kit/learn_kit.dart';

/// One card: which pair it belongs to and which side it shows.
typedef MemoryCard = ({int pair, bool isA});

class MemoryEngine extends StatefulWidget {
  const MemoryEngine({super.key, required this.config, required this.onFinished, this.random, this.flipBack = const Duration(milliseconds: 900)});

  final Map<String, dynamic> config;
  final void Function(int score, int maxScore) onFinished;
  final Random? random;

  /// How long two cards that do not belong stay up.
  final Duration flipBack;

  /// The pairs of [config] (the same shape as `match`).
  static List<({String a, String b})> pairsOf(Map<String, dynamic> config) => MatchEngine.pairsOf(config);

  /// [pairs] less one per wrong try beyond the first [pairs], clamped to 0..pairs.
  static int scoreFor(int pairs, int misses) => (pairs - max(0, misses - pairs)).clamp(0, pairs).toInt();

  @override
  State<MemoryEngine> createState() => _MemoryEngineState();
}

class _MemoryEngineState extends State<MemoryEngine> {
  late final List<({String a, String b})> _pairs;
  late final List<MemoryCard> _cards;
  final List<int> _open = [];
  final Set<int> _matched = {};
  int _misses = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _pairs = MemoryEngine.pairsOf(widget.config);
    _cards = learnShuffle([
      for (var i = 0; i < _pairs.length; i++) ...[(pair: i, isA: true), (pair: i, isA: false)],
    ], random: widget.random);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  bool get _done => _pairs.isNotEmpty && _matched.length == _pairs.length;

  int get _score => MemoryEngine.scoreFor(_pairs.length, _misses);

  void _closeOpen() {
    _timer?.cancel();
    _timer = null;
    if (mounted) setState(_open.clear);
  }

  void _tap(int k) {
    if (_matched.contains(_cards[k].pair) || _open.contains(k)) return;
    // two that did not belong are still up: turn them back at once and go on with this card
    if (_open.length == 2) {
      _timer?.cancel();
      _timer = null;
      _open.clear();
    }
    setState(() => _open.add(k));
    if (_open.length < 2) return;
    final a = _cards[_open[0]], b = _cards[_open[1]];
    final right = a.pair == b.pair;
    if (right) {
      setState(() {
        _matched.add(a.pair);
        _open.clear();
      });
    } else {
      setState(() => _misses++);
      _timer = Timer(widget.flipBack, _closeOpen);
    }
    GameShellScope.maybeOf(context)
        ?.report(done: _matched.length, score: (_matched.length - max(0, _misses - _pairs.length)).clamp(0, _pairs.length).toInt(), correct: right);
  }

  String _label(MemoryCard card) => card.isA ? _pairs[card.pair].a : _pairs[card.pair].b;

  @override
  Widget build(BuildContext context) {
    if (_pairs.length < 2) {
      return AppEmpty(icon: Icons.grid_view_rounded, title: t('لا توجد بطاقات في هذه اللعبة', 'This game has no cards'));
    }
    final prompt = learnText('${widget.config['prompt_ar'] ?? ''}', '${widget.config['prompt_en'] ?? ''}');
    final inShell = GameShellScope.maybeOf(context) != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!inShell) ...[
        LearnProgressHeader(
          current: _matched.length,
          total: _pairs.length,
          label: t('وجدت ${_matched.length} من ${_pairs.length}', 'Found ${_matched.length} of ${_pairs.length}'),
        ),
        const SizedBox(height: AppSpace.md),
      ],
      LearnPrompt(text: prompt.isEmpty ? t('اقلب بطاقتين وابحث عن كل زوج.', 'Turn two cards over and find every pair.') : prompt),
      const SizedBox(height: AppSpace.sm),
      LayoutBuilder(builder: (context, box) {
        final cols = (box.maxWidth / 120).floor().clamp(2, 5);
        final w = (box.maxWidth - AppSpace.xs * (cols - 1)) / cols;
        return Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (var k = 0; k < _cards.length; k++)
            SizedBox(
              width: w,
              child: MemoryCardTile(
                key: ValueKey('memory.card.$k'),
                index: k,
                label: _label(_cards[k]),
                faceUp: _open.contains(k) || _matched.contains(_cards[k].pair),
                matched: _matched.contains(_cards[k].pair),
                wrong: _open.length == 2 && _open.contains(k),
                onTap: _matched.contains(_cards[k].pair) ? null : () => _tap(k),
              ),
            ),
        ]);
      }),
      if (_done) ...[
        const SizedBox(height: AppSpace.md),
        LearnFeedback(
          correct: _score == _pairs.length,
          neutral: _score < _pairs.length,
          title: t('وجدت كل الأزواج', 'Every pair found'),
          explanation: _misses == 0 ? null : t('محاولات خاطئة: $_misses', 'Wrong tries: $_misses'),
          actionLabel: t('النتيجة', 'See result'),
          onAction: () => widget.onFinished(_score, _pairs.length),
        ),
      ],
    ]);
  }
}

/// One card with plain values: face down (a "?" on the primary wash), face up (its text), matched (the success
/// tint) or one of two that do not belong (the danger edge).
class MemoryCardTile extends StatelessWidget {
  const MemoryCardTile({
    super.key,
    required this.index,
    required this.label,
    required this.faceUp,
    this.matched = false,
    this.wrong = false,
    this.onTap,
  });

  final int index;
  final String label;
  final bool faceUp, matched, wrong;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = matched ? c.success : (wrong ? c.danger : c.primary);
    final bg = !faceUp ? c.primaryWash : (matched ? appTintOn(context, c.success) : c.cardBg);
    final ink = matched ? appInkOn(context, c.success, bg) : c.textDark;
    final face = faceUp
        ? Text(label,
            key: const ValueKey('up'),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: AppType.row(context).copyWith(color: ink))
        : Icon(Icons.question_mark_rounded, key: const ValueKey('down'), color: c.primary, size: AppIconSize.lg);
    return Semantics(
      button: onTap != null,
      label: faceUp ? label : t('بطاقة ${index + 1}، مقلوبة', 'Card ${index + 1}, face down'),
      excludeSemantics: true,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardAll,
          side: BorderSide(color: faceUp ? tone : c.divider, width: faceUp ? 1.5 : AppBorder.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouch.primary + AppSpace.md),
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.xs),
              child: Center(
                child: AnimatedSwitcher(
                  duration: AppMotion.of(context).fast,
                  transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
                  child: face,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
