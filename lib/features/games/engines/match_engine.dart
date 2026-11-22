// lib/features/games/engines/match_engine.dart — the `match` engine (D-1346): two columns, the `a` side in order and
// the `b` side shuffled; tap one on each side to pair them. A right pair locks green, a wrong one shows red until
// the next tap (or for `hold`). Score = pairs matched with no wrong try, max = pairs.
// config = {prompt_ar, prompt_en, pairs: [{a, b}]}
//
// Games v3 (§1, D-1740): connector lines. [MatchConnectorPainter] sits in a Stack over both columns (IgnorePointer,
// its own RepaintBoundary) and draws, between the two facing edges of each pair ([matchAnchors], so RTL needs no
// branch), a cubic curve that draws in over `settle` with end dots that pop. While a tile is dragged (a long press
// on touch, a plain drag with a mouse) a live line follows the finger and the tile under it gets the primary edge;
// letting go on it is the same try as two taps. A right pair's line stays in one of five tones and both tiles pulse;
// a wrong one is drawn red, both tiles shake, and it retracts over `snap`. Tap-tap pairing stays, and so do the
// tiles' Semantics. In a quran / tajweed game no live line crosses the tiles and nothing shakes.
// Trace (CONTRACT §3): one entry per try, `i` = the left tile's pair, `a` = the picked right tile's pair.
library;

import 'dart:async';
import 'dart:math';
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/shell/game_motion.dart';
import 'package:flutter_education_app/features/games/shell/game_shell.dart';
import 'package:flutter_education_app/features/games/shell/game_tile.dart';
import 'package:flutter_education_app/features/learn_kit/learn_kit.dart';

/// The two points a connector joins: the mid-points of the edges of [a] and [b] that face each other, chosen by
/// comparing their centres' x, so the same code serves LTR and RTL (pure, tested).
(Offset, Offset) matchAnchors(Rect a, Rect b) =>
    a.center.dx <= b.center.dx ? (a.centerRight, b.centerLeft) : (a.centerLeft, b.centerRight);

/// The connector from [p0] to [p3]: a cubic with `P1 = P0 + (Δx/2, 0)` and `P2 = P3 − (Δx/2, 0)`.
Path matchConnectorPath(Offset p0, Offset p3) {
  final h = (p3.dx - p0.dx) / 2;
  return Path()
    ..moveTo(p0.dx, p0.dy)
    ..cubicTo(p0.dx + h, p0.dy, p3.dx - h, p3.dy, p3.dx, p3.dy);
}

/// What the painter draws: the settled pairs (each with its tone), the one drawing in, the wrong try and the live
/// line of a drag. Changes notify the painter only; the tiles never rebuild for it.
class MatchConnectorModel extends ChangeNotifier {
  /// (left pair, right row, tone index), in the order they were matched.
  final List<(int, int, int)> settled = [];

  /// The settled line still drawing in (its left pair), or null.
  int? drawing;

  /// The wrong try (left pair, right row), or null.
  (int, int)? wrong;

  /// A drag: from (left side?, index) to the finger (board-local), or null.
  (bool, int, Offset)? live;

  void changed() => notifyListeners();
}

/// Draws the connectors of a [MatchConnectorModel] over the board. [rectOf] gives a tile's rect in the board's
/// coordinates at paint time (null = not laid out), so a scroll or a relayout never leaves a line behind.
class MatchConnectorPainter extends CustomPainter {
  MatchConnectorPainter({
    required this.model,
    required this.draw,
    required this.wrongT,
    required this.rectOf,
    required this.tones,
    required this.danger,
    required this.live,
    required this.still,
    this.wrongDrawShare = 0.58,
    this.stroke = AppBorder.line,
  }) : super(repaint: Listenable.merge([model, draw, wrongT]));

  final MatchConnectorModel model;

  /// 0..1: the newest settled line's draw-in.
  final Animation<double> draw;

  /// 0..1 over the wrong line's life: draw-in for the first [MatchConnectorPainter.wrongDrawShare], then retract.
  final Animation<double> wrongT;
  final Rect? Function(bool left, int index) rectOf;
  final List<Color> tones;
  final Color danger, live;

  /// Reduce motion: every line is drawn whole, the wrong one until it clears.
  final bool still;
  final double stroke;

  /// The share of the wrong line's life spent drawing in: `settle` of `settle + snap`.
  final double wrongDrawShare;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final dot = Paint()..style = PaintingStyle.fill;
    for (final (l, r, tone) in model.settled) {
      final k = model.drawing == l && !still ? draw.value : 1.0;
      _line(canvas, l, r, k, tones[tone % tones.length], line, dot);
    }
    final w = model.wrong;
    if (w != null) {
      double k;
      if (still) {
        k = 1;
      } else {
        final v = wrongT.value;
        k = v <= wrongDrawShare ? v / wrongDrawShare : 1 - (v - wrongDrawShare) / (1 - wrongDrawShare);
      }
      if (k > 0) _line(canvas, w.$1, w.$2, k.clamp(0.0, 1.0), danger, line, dot);
    }
    final lv = model.live;
    if (lv != null) {
      final a = rectOf(lv.$1, lv.$2);
      if (a != null) {
        final (p0, _) = matchAnchors(a, Rect.fromCenter(center: lv.$3, width: 0, height: 0));
        canvas.drawPath(matchConnectorPath(p0, lv.$3), line..color = live);
        canvas.drawCircle(p0, stroke * 1.5, dot..color = live);
      }
    }
  }

  void _line(Canvas canvas, int l, int r, double k, Color color, Paint line, Paint dot) {
    final a = rectOf(true, l), b = rectOf(false, r);
    if (a == null || b == null || k <= 0) return;
    final (p0, p3) = matchAnchors(a, b);
    final path = matchConnectorPath(p0, p3);
    line.color = color;
    dot.color = color;
    if (k >= 1) {
      canvas.drawPath(path, line);
    } else {
      for (final PathMetric m in path.computeMetrics()) {
        canvas.drawPath(m.extractPath(0, m.length * k), line);
      }
    }
    // end dots: the start one at once, the far one pops as the line arrives
    canvas.drawCircle(p0, stroke * 1.5, dot);
    final pop = k >= 1 ? 1.0 : (k < 0.8 ? 0.0 : GameMotion.pop.transform((k - 0.8) / 0.2));
    if (pop > 0) canvas.drawCircle(p3, stroke * 1.5 * pop, dot);
  }

  @override
  bool shouldRepaint(MatchConnectorPainter old) =>
      old.model != model ||
      old.draw != draw ||
      old.wrongT != wrongT ||
      old.still != still ||
      old.danger != danger ||
      old.live != live ||
      old.stroke != stroke ||
      old.wrongDrawShare != wrongDrawShare ||
      !_sameColors(old.tones, tones);

  static bool _sameColors(List<Color> a, List<Color> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// The five tones a right pair's line cycles through (§1: from AppTone).
List<Color> matchLineTones(BuildContext context) => [
      for (final tone in const [AppTone.brand, AppTone.gold, AppTone.info, AppTone.success, AppTone.warning])
        appToneColor(context, tone),
    ];

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

class _MatchEngineState extends State<MatchEngine> with TickerProviderStateMixin {
  late final List<({String a, String b})> _pairs;

  /// The right column: _right[k] is the pair index drawn at row k.
  late final List<int> _right;
  final Set<int> _matched = {};
  final Set<int> _missedOnce = {};
  int? _left, _rightPick;

  /// The last wrong try (left pair, right row), drawn red until the next tap or for `hold`.
  (int, int)? _wrong;
  Timer? _wrongTimer;

  final MatchConnectorModel _lines = MatchConnectorModel();
  late final AnimationController _draw = AnimationController(vsync: this, value: 1);
  late final AnimationController _wrongT = AnimationController(vsync: this, value: 1);
  final GlobalKey _board = GlobalKey();
  late final List<GlobalKey> _leftKeys, _rightKeys;

  /// A move per tile: `a{i}` / `b{row}` → the pulse / shake trigger.
  final Map<String, int> _pulse = {}, _shake = {};
  int _seq = 0;

  /// A drag: from which tile, and the tile under the finger.
  (bool, int)? _dragFrom, _hover;

  @override
  void initState() {
    super.initState();
    _pairs = MatchEngine.pairsOf(widget.config);
    _right = learnShuffle([for (var i = 0; i < _pairs.length; i++) i], random: widget.random);
    _leftKeys = [for (var i = 0; i < _pairs.length; i++) GlobalKey()];
    _rightKeys = [for (var i = 0; i < _pairs.length; i++) GlobalKey()];
  }

  @override
  void dispose() {
    _wrongTimer?.cancel();
    _draw.dispose();
    _wrongT.dispose();
    _lines.dispose();
    super.dispose();
  }

  bool get _done => _pairs.isNotEmpty && _matched.length == _pairs.length;

  bool get _sacred => GameShellScope.maybeOf(context)?.sacred ?? false;

  void _clearWrong() {
    _wrongTimer?.cancel();
    _wrongTimer = null;
    _wrong = null;
    _lines.wrong = null;
    _lines.changed();
  }

  void _tapLeft(int i) {
    if (_matched.contains(i)) return;
    setState(() {
      _clearWrong();
      _left = _left == i ? null : i;
    });
    if (_rightPick == null && _left != null) GameShellScope.maybeOf(context)?.sound(GameSound.tap);
    _try();
  }

  void _tapRight(int row) {
    if (_matched.contains(_right[row])) return;
    setState(() {
      _clearWrong();
      _rightPick = _rightPick == row ? null : row;
    });
    if (_left == null && _rightPick != null) GameShellScope.maybeOf(context)?.sound(GameSound.tap);
    _try();
  }

  void _try() {
    final l = _left, r = _rightPick;
    if (l == null || r == null) return;
    final right = _right[r] == l;
    final shell = GameShellScope.maybeOf(context);
    shell?.record(l, _right[r]);
    final m = GameMotion.of(context);
    setState(() {
      _seq++;
      if (right) {
        _matched.add(l);
        _pulse['a$l'] = _pulse['b$r'] = _seq;
        _lines.settled.add((l, r, _lines.settled.length));
        _lines.drawing = l;
        _draw
          ..duration = m.settle
          ..forward(from: 0);
      } else {
        _missedOnce.add(l);
        _wrong = (l, r);
        _shake['a$l'] = _shake['b$r'] = _seq;
        _lines.wrong = (l, r);
        _wrongT
          ..duration = m.settle + m.snap
          ..forward(from: 0);
        _wrongTimer?.cancel();
        _wrongTimer = Timer(m.hold, () {
          if (mounted) setState(_clearWrong);
        });
      }
      _left = _rightPick = null;
    });
    _lines.changed();
    shell?.report(done: _matched.length, score: _matched.difference(_missedOnce).length, correct: right);
  }

  static double _wrongShare(GameMotion m) {
    final all = (m.settle + m.snap).inMicroseconds;
    return all == 0 ? 0.5 : m.settle.inMicroseconds / all;
  }

  // ── drag ──────────────────────────────────────────────────────────────────

  RenderBox? get _boardBox {
    final b = _board.currentContext?.findRenderObject();
    return b is RenderBox && b.hasSize ? b : null;
  }

  Rect? _rect(bool left, int index) {
    final keys = left ? _leftKeys : _rightKeys;
    if (index < 0 || index >= keys.length) return null;
    final b = keys[index].currentContext?.findRenderObject();
    final board = _boardBox;
    if (b is! RenderBox || !b.hasSize || !b.attached || board == null) return null;
    return b.localToGlobal(Offset.zero, ancestor: board) & b.size;
  }

  /// The tile on the other side of [from] under [local] (board coordinates), or null.
  (bool, int)? _hit(bool fromLeft, Offset local) {
    for (var k = 0; k < _pairs.length; k++) {
      final matched = fromLeft ? _matched.contains(_right[k]) : _matched.contains(k);
      if (matched) continue;
      final r = _rect(!fromLeft, k);
      if (r != null && r.inflate(AppSpace.xxs).contains(local)) return (!fromLeft, k);
    }
    return null;
  }

  void _dragStart(bool left, int index, Offset global) {
    final board = _boardBox;
    if (board == null) return;
    setState(() {
      _clearWrong();
      _dragFrom = (left, index);
      if (left) {
        _left = index;
      } else {
        _rightPick = index;
      }
    });
    GameShellScope.maybeOf(context)?.sound(GameSound.tap);
    if (!_sacred) {
      _lines.live = (left, index, board.globalToLocal(global));
      _lines.changed();
    }
  }

  void _dragMove(Offset global) {
    final from = _dragFrom, board = _boardBox;
    if (from == null || board == null) return;
    final local = board.globalToLocal(global);
    if (!_sacred) {
      _lines.live = (from.$1, from.$2, local);
      _lines.changed();
    }
    final h = _hit(from.$1, local);
    if (h != _hover) setState(() => _hover = h);
  }

  void _dragEnd(Offset _) {
    final h = _hover;
    _lines.live = null;
    _lines.changed();
    setState(() {
      _dragFrom = null;
      _hover = null;
    });
    if (h == null) return;
    if (h.$1) {
      _left = h.$2;
    } else {
      _rightPick = h.$2;
    }
    _try();
  }

  void _dragCancel() {
    _lines.live = null;
    _lines.changed();
    if (_dragFrom != null || _hover != null) {
      setState(() {
        _dragFrom = null;
        _hover = null;
      });
    }
  }

  GameTileState _leftState(int i) {
    if (_matched.contains(i)) return GameTileState.correct;
    if (_wrong?.$1 == i) return GameTileState.wrong;
    return _left == i ? GameTileState.selected : GameTileState.idle;
  }

  GameTileState _rightState(int row) {
    if (_matched.contains(_right[row])) return GameTileState.correct;
    if (_wrong?.$2 == row) return GameTileState.wrong;
    return _rightPick == row ? GameTileState.selected : GameTileState.idle;
  }

  Widget _tile(bool left, int k) {
    final pair = left ? k : _right[k];
    final matched = _matched.contains(pair);
    final id = left ? 'a$k' : 'b$k';
    final tile = GameTile(
      key: ValueKey(left ? 'match.a.$k' : 'match.b.$k'),
      label: left ? _pairs[k].a : _pairs[pair].b,
      state: left ? _leftState(k) : _rightState(k),
      hover: _hover == (left, k),
      pulse: _pulse[id],
      shake: _shake[id],
      shakeEnabled: !_sacred,
      semanticsHint: matched ? null : t('اضغط ثم اضغط شريكه', 'Tap it, then tap its partner'),
      onTap: matched ? null : () => left ? _tapLeft(k) : _tapRight(k),
    );
    return KeyedSubtree(
      key: left ? _leftKeys[k] : _rightKeys[k],
      child: GameDraggable(
        enabled: !matched,
        lifted: _dragFrom == (left, k),
        onStart: (g) => _dragStart(left, k, g),
        onMove: _dragMove,
        onEnd: _dragEnd,
        onCancel: _dragCancel,
        child: tile,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_pairs.isEmpty) {
      return AppEmpty(icon: Icons.join_inner_rounded, title: t('لا توجد أزواج في هذه اللعبة', 'This game has no pairs'));
    }
    final c = context.colors;
    final prompt = learnText('${widget.config['prompt_ar'] ?? ''}', '${widget.config['prompt_en'] ?? ''}');
    final score = _pairs.length - _missedOnce.length;
    final inShell = GameShellScope.maybeOf(context) != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!inShell) ...[
        LearnProgressHeader(
          current: _matched.length,
          total: _pairs.length,
          label: t('وصّلت ${_matched.length} من ${_pairs.length}', 'Matched ${_matched.length} of ${_pairs.length}'),
        ),
        const SizedBox(height: AppSpace.md),
      ],
      LearnPrompt(text: prompt.isEmpty ? t('صِل كل عنصر بما يناسبه.', 'Match each item to its partner.') : prompt),
      const SizedBox(height: AppSpace.sm),
      RepaintBoundary(
        child: LayoutBuilder(builder: (context, box) {
          // the gutter the connectors run in: wider when there is room
          final gutter = box.maxWidth < 480 ? AppSpace.xl : AppSpace.xxl;
          return Stack(key: _board, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (var i = 0; i < _pairs.length; i++) ...[
                    if (i > 0) const SizedBox(height: AppSpace.xs),
                    _tile(true, i),
                  ],
                ]),
              ),
              SizedBox(width: gutter),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (var k = 0; k < _right.length; k++) ...[
                    if (k > 0) const SizedBox(height: AppSpace.xs),
                    _tile(false, k),
                  ],
                ]),
              ),
            ]),
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: MatchConnectorPainter(
                      model: _lines,
                      draw: _draw,
                      wrongT: _wrongT,
                      rectOf: _rect,
                      tones: matchLineTones(context),
                      danger: c.danger,
                      live: c.primary.withValues(alpha: 0.6),
                      still: GameMotion.of(context).off,
                      wrongDrawShare: _wrongShare(GameMotion.of(context)),
                    ),
                  ),
                ),
              ),
            ),
          ]);
        }),
      ),
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
