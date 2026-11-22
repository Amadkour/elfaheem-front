// lib/features/games/engines/memory_engine.dart — the `memory` engine (Learning Hub v2 §3, D-1584): every pair's `a`
// and `b` are face-down cards, shuffled; turn two over, a pair stays up, two that do not belong turn back. Score =
// pairs, less one for every wrong try beyond the first [pairs] (a first look at the cards is free), never below 0;
// max = pairs ([MemoryEngine.scoreFor]).
// config = {prompt_ar, prompt_en, pairs: [{a, b}]} (2..10)
//
// Games v3 (§1, D-1740): the cards deal in one after another (`stagger`), each turn is a 3D flip over `settle` (the
// face swaps half-way, the turn follows the reading direction), a found pair pulses, and two that do not belong
// shake and turn back after `hold`. Under Reduce motion a card simply shows its face.
// Trace (CONTRACT §3): one entry per try, on its second card: `i` = the first card's id, `a` = the second's, where a
// card's id is `2 × pair + (0 for a, 1 for b)`.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/engines/match_engine.dart';
import 'package:flutter_education_app/features/games/shell/game_motion.dart';
import 'package:flutter_education_app/features/games/shell/game_shell.dart';
import 'package:flutter_education_app/features/learn_kit/learn_kit.dart';

/// One card: which pair it belongs to and which side it shows.
typedef MemoryCard = ({int pair, bool isA});

class MemoryEngine extends StatefulWidget {
  const MemoryEngine({super.key, required this.config, required this.onFinished, this.random, this.flipBack});

  final Map<String, dynamic> config;
  final void Function(int score, int maxScore) onFinished;
  final Random? random;

  /// How long two cards that do not belong stay up (null = the flip, the shake and the motion's `hold`).
  final Duration? flipBack;

  /// The pairs of [config] (the same shape as `match`).
  static List<({String a, String b})> pairsOf(Map<String, dynamic> config) => MatchEngine.pairsOf(config);

  /// The trace's id of [card] (CONTRACT §3).
  static int cardId(MemoryCard card) => 2 * card.pair + (card.isA ? 0 : 1);

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

  /// A move per card index: the pulse (a found pair) and the shake (a miss).
  final Map<int, int> _pulse = {}, _shake = {};
  int _seq = 0;

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
    final shell = GameShellScope.maybeOf(context);
    if (_open.length < 2) {
      shell?.sound(GameSound.flip);
      return;
    }
    final a = _cards[_open[0]], b = _cards[_open[1]];
    final right = a.pair == b.pair;
    shell?.record(MemoryEngine.cardId(a), MemoryEngine.cardId(b));
    final m = GameMotion.of(context);
    _seq++;
    if (right) {
      setState(() {
        _matched.add(a.pair);
        _pulse[_open[0]] = _pulse[_open[1]] = _seq;
        _open.clear();
      });
    } else {
      final o0 = _open[0], o1 = _open[1];
      setState(() {
        _misses++;
        // the shake waits for the second card's flip
        _shake[o0] = _shake[o1] = _seq;
      });
      _timer = Timer(widget.flipBack ?? m.settle + m.settle + m.hold, _closeOpen);
    }
    shell
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
        final m = GameMotion.of(context);
        final sacred = GameShellScope.maybeOf(context)?.sacred ?? false;
        return RepaintBoundary(
          child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            for (var k = 0; k < _cards.length; k++)
              SizedBox(
                width: w,
                // the deal-in: one card after another
                child: GamePopIn(
                  delay: m.stagger * k,
                  child: GameShake(
                    trigger: _shake[k],
                    enabled: !sacred,
                    delay: m.settle,
                    child: GamePulse(
                      trigger: _pulse[k],
                      delay: m.settle,
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
                  ),
                ),
              ),
          ]),
        );
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
/// tint) or one of two that do not belong (the danger edge). A change of [faceUp] turns it over in 3D over `settle`
/// (the face swaps half-way; the turn follows the reading direction); under Reduce motion it just shows the face.
class MemoryCardTile extends StatefulWidget {
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
  State<MemoryCardTile> createState() => _MemoryCardTileState();
}

/// The flip's transform at [t] (0 = face down, 1 = face up): a perspective turn of π·t around the vertical axis,
/// mirrored in RTL (pure).
Matrix4 memoryFlipMatrix(double t, TextDirection dir) {
  final sign = dir == TextDirection.rtl ? -1.0 : 1.0;
  return Matrix4.identity()
    ..setEntry(3, 2, 0.0015)
    ..rotateY(pi * t * sign);
}

class _MemoryCardTileState extends State<MemoryCardTile> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, value: widget.faceUp ? 1 : 0);

  @override
  void didUpdateWidget(MemoryCardTile old) {
    super.didUpdateWidget(old);
    if (old.faceUp == widget.faceUp) return;
    final m = GameMotion.of(context);
    if (m.off) {
      _c.value = widget.faceUp ? 1 : 0;
      return;
    }
    _c.animateTo(widget.faceUp ? 1 : 0, duration: m.settle, curve: GameMotion.turn);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _face(BuildContext context, bool up) {
    final c = context.colors;
    final w = widget;
    final tone = w.matched ? c.success : (w.wrong ? c.danger : c.primary);
    final bg = !up ? c.primaryWash : (w.matched ? appTintOn(context, c.success) : c.cardBg);
    final ink = w.matched ? appInkOn(context, c.success, bg) : c.textDark;
    final face = up
        ? Text(w.label,
            key: const ValueKey('up'),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: AppType.row(context).copyWith(color: ink))
        : Icon(Icons.question_mark_rounded, key: const ValueKey('down'), color: c.primary, size: AppIconSize.lg);
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.cardAll,
        side: BorderSide(color: up ? tone : c.divider, width: up ? AppBorder.strong : AppBorder.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: w.onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTouch.primary + AppSpace.md),
          child: Stack(fit: StackFit.passthrough, children: [
            Padding(
              padding: const EdgeInsets.all(AppSpace.xs),
              child: Center(child: face),
            ),
            // never colour alone: a found pair carries a check, two that do not belong a cross
            if (up && (w.matched || w.wrong))
              PositionedDirectional(
                top: AppSpace.xxs,
                end: AppSpace.xxs,
                child: Icon(w.matched ? Icons.check_circle_rounded : Icons.cancel_rounded, size: AppIconSize.sm, color: tone),
              ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final dir = Directionality.of(context);
    return Semantics(
      button: w.onTap != null,
      label: w.faceUp ? w.label : t('بطاقة ${w.index + 1}، مقلوبة', 'Card ${w.index + 1}, face down'),
      excludeSemantics: true,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final v = _c.value;
          final up = v >= 0.5;
          if (v == 0 || v == 1) return _face(context, up);
          // past half-way the face is drawn turned back by π, so it reads the right way round
          return Transform(
            alignment: Alignment.center,
            transform: memoryFlipMatrix(v, dir),
            child: up
                ? Transform(alignment: Alignment.center, transform: memoryFlipMatrix(1, dir), child: _face(context, true))
                : _face(context, false),
          );
        },
      ),
    );
  }
}
