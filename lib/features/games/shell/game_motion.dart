// lib/features/games/shell/game_motion.dart — the games' motion (Games v3 §1, D-1740): every duration comes from the
// app's motion tokens through [GameMotion.of], so Reduce motion (the person's, the system's, or the Super Admin's
// `app.animations` switch) turns each one into zero and every widget here shows its end state at once.
//
//   GameMotion      tap 180 · snap 220 · settle 300 · celebrate 600 · stagger 60 · hold 600 (ms, from AppMotion)
//   GameShake       a horizontal shake: 3 decaying cycles of ±AppSpace.xs over `settle`, each time [trigger] changes
//   GamePulse       a scale pulse 1 → 1.06 → 1 over `snap` (easeOutBack), each time [trigger] changes; [delay] staggers
//                   a wave
//   GamePopIn       an entrance: fades in and settles from 90 % after [delay] (the memory deal-in, a check icon)
//   GameDraggable   the drag look: lift (scale 1.04 and a shadow that cross-fades from level 1 to 3 over `tap`), the
//                   1:1 follow through a ValueListenable<Offset> (no setState, no easing), and the gestures (a long
//                   press on touch, a plain drag with a mouse); the caller decides where it lands
//   GameDragOffset  the follow offset with the two ways back: `snapTo` (a drop on a target, `snap`) and `returnHome`
//                   (a drop elsewhere, `settle`, emphasized)
//   GameFlight      a copy of a chip flies from one widget to another in the overlay (fill_blank, word_puzzle);
//                   `wrong:` shakes it there and flies it back
//   GameComboChip   "×3" in the shell's header after three right answers in a row; it bumps on each new one
//
// Low-end rules (§1): only transform, opacity and colour move; no shader, blur or saveLayer; one RepaintBoundary
// around each moving part. Nothing here loops.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;

/// How long a wrong state stays readable under Reduce motion, where every motion token is zero (D-1742): it is
/// reading time, not motion, so it keeps the value it has with motion on (`slow × 2`).
const Duration kGameReadHold = Duration(milliseconds: 600);

/// The games' durations, curves and sizes, all from the app's tokens (Games v3 §1).
@immutable
class GameMotion {
  const GameMotion._(this._m);

  factory GameMotion.of(BuildContext context) => GameMotion._(AppMotion.of(context));

  final AppMotion _m;

  /// Reduce motion: every duration below is zero (but [hold]).
  bool get off => _m.off;

  /// Colour changes, a drag's lift.
  Duration get tap => _m.fast;

  /// Drops, pulses, retractions.
  Duration get snap => _m.base;

  /// Returns, flips, draw-ins.
  Duration get settle => _m.slow;

  /// The finish's deal-in.
  Duration get celebrate => _m.slow * 2;

  /// The gap between items of a sequence.
  Duration get stagger => _m.fast ~/ 3;

  /// How long a wrong state stays before it goes back to idle.
  Duration get hold => _m.off ? kGameReadHold : _m.slow * 2;

  /// Moves.
  static const Curve move = AppEase.out;

  /// A return or a flip.
  static const Curve turn = AppMotion.emphasized;

  /// A pop.
  static const Curve pop = Curves.easeOutBack;

  /// The shake's amplitude.
  static const double shake = AppSpace.xs;

  /// A right answer's pulse, the solved word's wave and a lifted drag.
  static const double pulse = 1.06, wave = 1.12, lift = 1.04;
}

// ─────────────────────────────────────────────────────────────────────────────
//  One-shot moves
// ─────────────────────────────────────────────────────────────────────────────

/// The shared part of a move that plays once each time [trigger] changes (never on the first build, never under
/// Reduce motion), [delay] after the change.
abstract class _OneShot extends StatefulWidget {
  const _OneShot({super.key, required this.trigger, required this.child, this.delay = Duration.zero, this.enabled = true});

  final Object? trigger;
  final Widget child;
  final Duration delay;
  final bool enabled;
}

abstract class _OneShotState<T extends _OneShot> extends State<T> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this);

  /// The move's own length (after the delay).
  Duration length(GameMotion m);

  /// 0..1 along the move (0 while waiting for the delay).
  double get k {
    final total = c.duration?.inMicroseconds ?? 0;
    if (total == 0) return 1;
    final wait = widget.delay.inMicroseconds / total;
    if (c.value <= wait) return 0;
    return ((c.value - wait) / (1 - wait)).clamp(0.0, 1.0);
  }

  @override
  void didUpdateWidget(T old) {
    super.didUpdateWidget(old);
    if (old.trigger == widget.trigger || widget.trigger == null || !widget.enabled) return;
    final m = GameMotion.of(context);
    if (m.off) {
      c.value = 0;
      return;
    }
    final len = length(m);
    if (len == Duration.zero) return;
    c
      ..duration = widget.delay + len
      ..forward(from: 0);
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  Widget frame(Widget Function(double k, Widget child) builder) => AnimatedBuilder(
        animation: c,
        child: RepaintBoundary(child: widget.child),
        // the wrapper is always there (idle = the identity), so starting or ending a move never remounts the child
        builder: (_, child) => builder(c.isAnimating ? k : 0, child!),
      );
}

/// The horizontal offset of a decaying shake at [k] (0..1): 3 cycles of ±[amplitude], fading to 0 (pure, tested).
double gameShakeAt(double k, {double amplitude = GameMotion.shake}) =>
    k <= 0 || k >= 1 ? 0 : amplitude * math.sin(k * math.pi * 2 * 3) * (1 - k);

/// A wrong answer's shake: 3 decaying cycles of ±[GameMotion.shake] over `settle` each time [trigger] changes.
/// [enabled] false (a tile that holds an ayah, §1): never.
class GameShake extends _OneShot {
  const GameShake({super.key, required super.trigger, required super.child, super.delay, super.enabled});

  @override
  State<GameShake> createState() => _GameShakeState();
}

class _GameShakeState extends _OneShotState<GameShake> {
  @override
  Duration length(GameMotion m) => m.settle;

  @override
  Widget build(BuildContext context) =>
      frame((k, child) => Transform.translate(offset: Offset(gameShakeAt(k), 0), child: child));
}

/// The scale of a pulse at [k] (0..1): 1 → [peak] by 45 %, then back to 1 with a small overshoot (pure).
double gamePulseAt(double k, {double peak = GameMotion.pulse}) {
  if (k <= 0 || k >= 1) return 1;
  if (k < 0.45) return 1 + (peak - 1) * Curves.easeOut.transform(k / 0.45);
  return peak + (1 - peak) * GameMotion.pop.transform((k - 0.45) / 0.55);
}

/// A right answer's pulse: 1 → [peak] → 1 over `snap` each time [trigger] changes; [delay] staggers a wave.
class GamePulse extends _OneShot {
  const GamePulse({super.key, required super.trigger, required super.child, super.delay, super.enabled, this.peak = GameMotion.pulse});

  final double peak;

  @override
  State<GamePulse> createState() => _GamePulseState();
}

class _GamePulseState extends _OneShotState<GamePulse> {
  @override
  Duration length(GameMotion m) => m.snap;

  @override
  Widget build(BuildContext context) =>
      frame((k, child) => Transform.scale(scale: gamePulseAt(k, peak: widget.peak), child: child));
}

/// An entrance: fades in and settles from 90 % over `snap` (easeOutBack), [delay] after the first build. Under Reduce
/// motion it is simply there.
class GamePopIn extends StatefulWidget {
  const GamePopIn({super.key, required this.child, this.delay = Duration.zero});

  final Widget child;
  final Duration delay;

  @override
  State<GamePopIn> createState() => _GamePopInState();
}

class _GamePopInState extends State<GamePopIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, value: 1);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final m = GameMotion.of(context);
    if (m.off) return;
    _c
      ..duration = widget.delay + m.snap
      ..forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (_, child) {
        if (!_c.isAnimating) return Opacity(opacity: 1, child: Transform.scale(scale: 1, child: child));
        final total = _c.duration!.inMicroseconds;
        final wait = total == 0 ? 0.0 : widget.delay.inMicroseconds / total;
        final k = _c.value <= wait ? 0.0 : ((_c.value - wait) / (1 - wait)).clamp(0.0, 1.0);
        return Opacity(
          opacity: math.min(1, k * 2),
          child: Transform.scale(scale: 0.9 + 0.1 * GameMotion.pop.transform(k), child: child),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Drag
// ─────────────────────────────────────────────────────────────────────────────

/// A drag's follow offset: set [value] while the finger moves (1:1, no easing); when it lets go, [snapTo] glides
/// to a target over `snap` or [returnHome] glides back over `settle` (emphasized). Under Reduce motion both are
/// instant.
class GameDragOffset extends ValueNotifier<Offset> {
  GameDragOffset({required TickerProvider vsync})
      : _c = AnimationController(vsync: vsync),
        super(Offset.zero) {
    _c.addListener(() => value = Offset.lerp(_from, _to, _curve.transform(_c.value))!);
  }

  final AnimationController _c;
  Offset _from = Offset.zero, _to = Offset.zero;
  Curve _curve = GameMotion.move;

  bool get moving => _c.isAnimating;

  /// Glides from where it is to [to]; [onDone] when there.
  void glide(Offset to, Duration d, Curve curve, [VoidCallback? onDone]) {
    _c.stop();
    if (d == Duration.zero) {
      value = to;
      onDone?.call();
      return;
    }
    _from = value;
    _to = to;
    _curve = curve;
    _c.duration = d;
    _c.forward(from: 0).whenCompleteOrCancel(() => onDone?.call());
  }

  void snapTo(Offset to, GameMotion m, [VoidCallback? onDone]) => glide(to, m.snap, GameMotion.move, onDone);

  void returnHome(GameMotion m, [VoidCallback? onDone]) => glide(Offset.zero, m.settle, GameMotion.turn, onDone);

  /// Stops any glide where it is.
  void hold() => _c.stop();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }
}

/// The look and the gestures of a draggable game piece. [offset] (null: the piece stays put, e.g. a match tile whose
/// line follows the finger instead) moves it 1:1; [lifted] scales it to [GameMotion.lift] and cross-fades its shadow
/// from level 1 to level 3 over `tap` (two prebuilt shadow layers, never an animated blur). Touch starts a drag with a
/// long press (a plain swipe still scrolls the page); a mouse drags at once. The piece's own tap path is untouched.
class GameDraggable extends StatelessWidget {
  const GameDraggable({
    super.key,
    required this.child,
    this.offset,
    this.lifted = false,
    this.enabled = true,
    this.onStart,
    this.onMove,
    this.onEnd,
    this.onCancel,
    this.radius,
  });

  final Widget child;
  final ValueListenable<Offset>? offset;
  final bool lifted, enabled;

  /// Global positions of the pointer.
  final ValueChanged<Offset>? onStart, onMove, onEnd;
  final VoidCallback? onCancel;
  final BorderRadius? radius;

  @override
  Widget build(BuildContext context) {
    final m = GameMotion.of(context);
    final r = radius ?? AppRadius.controlAll;
    final raised = AppElevation.of(context, 3);
    Widget piece = TweenAnimationBuilder<double>(
      tween: Tween(end: lifted ? 1 : 0),
      duration: m.tap,
      curve: GameMotion.move,
      child: child,
      builder: (context, v, child) {
        // the raised shadow's colour fades in over the resting one; its blur never changes
        final shadow = [
          for (final s in raised) s.copyWith(color: s.color.withValues(alpha: s.color.a * v)),
        ];
        return Transform.scale(
          scale: 1 + (GameMotion.lift - 1) * v,
          child: DecoratedBox(decoration: BoxDecoration(borderRadius: r, boxShadow: shadow), child: child),
        );
      },
    );
    final o = offset;
    if (o != null) {
      piece = ValueListenableBuilder<Offset>(
        valueListenable: o,
        child: piece,
        builder: (_, v, child) => Transform.translate(offset: v, child: child),
      );
    }
    piece = RepaintBoundary(child: piece);
    if (!enabled || onStart == null) return piece;
    // a mouse drags at once; touch and a stylus after a long press (so a swipe still scrolls)
    return GestureDetector(
      supportedDevices: const {PointerDeviceKind.mouse, PointerDeviceKind.trackpad},
      onPanStart: (d) => onStart?.call(d.globalPosition),
      onPanUpdate: (d) => onMove?.call(d.globalPosition),
      onPanEnd: (d) => onEnd?.call(d.globalPosition),
      onPanCancel: onCancel,
      child: GestureDetector(
        supportedDevices: const {PointerDeviceKind.touch, PointerDeviceKind.stylus, PointerDeviceKind.invertedStylus},
        onLongPressStart: (d) => onStart?.call(d.globalPosition),
        onLongPressMoveUpdate: (d) => onMove?.call(d.globalPosition),
        onLongPressEnd: (d) => onEnd?.call(d.globalPosition),
        onLongPressCancel: onCancel,
        child: piece,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Flight
// ─────────────────────────────────────────────────────────────────────────────

/// A copy of a piece flies from one widget to another over the page (Games v3 §1: fill_blank, word_puzzle).
abstract final class GameFlight {
  /// Flies [child] (at its own size) from the centre of [from] to the centre of [to] over `snap`. With [wrong] it then
  /// shakes there and flies back. Completes at once (nothing drawn) under Reduce motion or when either widget is not
  /// on screen.
  static Future<void> fly(BuildContext context, {required GlobalKey from, required GlobalKey to, required Widget child, bool wrong = false}) {
    final m = GameMotion.of(context);
    final overlay = Overlay.maybeOf(context);
    final a = _rect(from), b = _rect(to);
    if (m.off || overlay == null || a == null || b == null) return Future.value();
    final ob = overlay.context.findRenderObject();
    if (ob is! RenderBox || !ob.hasSize) return Future.value();
    final origin = ob.localToGlobal(Offset.zero);
    final start = a.shift(-origin);
    final end = Rect.fromCenter(center: b.center - origin, width: a.width, height: a.height);
    final done = Completer<void>();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _FlightView(
        from: start,
        to: end,
        wrong: wrong,
        snap: m.snap,
        settle: m.settle,
        onDone: () {
          entry.remove();
          if (!done.isCompleted) done.complete();
        },
        child: child,
      ),
    );
    overlay.insert(entry);
    return done.future;
  }

  static Rect? _rect(GlobalKey k) {
    final b = k.currentContext?.findRenderObject();
    if (b is! RenderBox || !b.hasSize || !b.attached) return null;
    return b.localToGlobal(Offset.zero) & b.size;
  }
}

class _FlightView extends StatefulWidget {
  const _FlightView({
    required this.from,
    required this.to,
    required this.wrong,
    required this.snap,
    required this.settle,
    required this.onDone,
    required this.child,
  });

  final Rect from, to;
  final bool wrong;
  final Duration snap, settle;
  final VoidCallback onDone;
  final Widget child;

  @override
  State<_FlightView> createState() => _FlightViewState();
}

class _FlightViewState extends State<_FlightView> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final double _in, _shake;

  @override
  void initState() {
    super.initState();
    final snap = widget.snap.inMicroseconds.toDouble();
    final total = widget.wrong ? snap * 2 + widget.settle.inMicroseconds : snap;
    _in = snap / total;
    _shake = widget.wrong ? (snap + widget.settle.inMicroseconds) / total : 1;
    _c = AnimationController(vsync: this, duration: Duration(microseconds: total.round()))
      ..forward().whenCompleteOrCancel(widget.onDone);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Offset _at(double v) {
    if (v <= _in) return Offset.lerp(widget.from.center, widget.to.center, GameMotion.move.transform(v / _in))!;
    if (v <= _shake) {
      final k = (v - _in) / (_shake - _in);
      return widget.to.center + Offset(gameShakeAt(k), 0);
    }
    final k = (v - _shake) / (1 - _shake);
    return Offset.lerp(widget.to.center, widget.from.center, GameMotion.turn.transform(k))!;
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          child: Material(type: MaterialType.transparency, child: widget.child),
          builder: (_, child) {
            final p = _at(_c.value);
            // the piece is centred on the point (it keeps its own size)
            return Stack(children: [
              Positioned(left: p.dx, top: p.dy, child: FractionalTranslation(translation: const Offset(-0.5, -0.5), child: child!)),
            ]);
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Combo
// ─────────────────────────────────────────────────────────────────────────────

/// Right answers in a row from which the combo shows (Games v3 §1: it adds no points).
const int kGameComboFrom = 3;

/// "×3" after [kGameComboFrom] right answers in a row; bumps on each new one. Nothing below that.
class GameComboChip extends StatelessWidget {
  const GameComboChip({super.key, required this.streak});

  final int streak;

  @override
  Widget build(BuildContext context) {
    if (streak < kGameComboFrom) return const SizedBox.shrink();
    final gold = appToneColor(context, AppTone.gold);
    final tint = appTintOn(context, gold);
    return Semantics(
      label: t('$streak إجابات صحيحة متتالية', '$streak right in a row'),
      excludeSemantics: true,
      child: AppBump(
        key: const ValueKey('games.shell.combo'),
        trigger: streak,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs),
          decoration: BoxDecoration(
            color: tint,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: gold, width: AppBorder.hairline),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.local_fire_department_rounded, size: AppIconSize.sm, color: appInkOn(context, gold, tint)),
            const SizedBox(width: AppSpace.xxs),
            Text('×$streak',
                style: AppType.label(context).copyWith(
                    color: appInkOn(context, gold, tint),
                    fontFeatures: const [FontFeature.liningFigures(), FontFeature.tabularFigures()])),
          ]),
        ),
      ),
    );
  }
}
