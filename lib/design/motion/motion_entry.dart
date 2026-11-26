// lib/design/motion/motion_entry.dart
//
// The one-shot entrances of the redesign (KIT_SPEC §4.2): M1 AppFlipIn, M3 AppPop, M4 AppSlap, M5 AppDeal,
// M12 AppWobble, all on one private _Entry. Each plays once per route for its `group:index:kind`, asks the screen's
// AppMotionBudget, and draws its end state under Reduce motion (M4: the child rotated by `tilt`) or outside a
// student area (M1, M4, M5, M12; M3 stays available to every role).
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'motion_gate.dart';
import 'motion_spec.dart';

typedef _Pose = Widget Function(BuildContext context, double t, Widget child);

class _Entry extends StatefulWidget {
  const _Entry({
    required this.kind,
    required this.onceKey,
    required this.duration,
    required this.curve,
    required this.delay,
    required this.pose,
    required this.child,
    this.rest,
    this.playfulOnly = true,
    this.trigger,
    this.useTrigger = false,
  });

  final MotionKind kind;
  final String onceKey;
  final Duration duration;
  final Curve curve;
  final Duration delay;
  final _Pose pose;
  final Widget child;

  /// The end state when the move does not play (default: [child] as is).
  final Widget Function(Widget child)? rest;
  final bool playfulOnly;
  final Object? trigger;
  final bool useTrigger;

  @override
  State<_Entry> createState() => _EntryState();
}

class _EntryState extends State<_Entry> with SingleTickerProviderStateMixin {
  AnimationController? _c;
  Animation<double>? _t;
  bool _decided = false;

  void _play() {
    final total = widget.delay + widget.duration;
    final c = _c ??= AnimationController(vsync: this);
    c.duration = total;
    final start = total.inMicroseconds == 0 ? 0.0 : widget.delay.inMicroseconds / total.inMicroseconds;
    _t = CurvedAnimation(parent: c, curve: Interval(start, 1, curve: widget.curve));
    c.forward(from: 0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) return;
    _decided = true;
    if (widget.useTrigger) return; // a triggered pop never plays on its first build
    if (motionMayPlay(context, widget.kind, widget.onceKey, playfulOnly: widget.playfulOnly)) _play();
  }

  @override
  void didUpdateWidget(_Entry old) {
    super.didUpdateWidget(old);
    if (widget.useTrigger && old.trigger != widget.trigger &&
        motionMayPlay(context, widget.kind, widget.onceKey, playfulOnly: widget.playfulOnly, once: false)) {
      _play();
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    final c = _c;
    if (t == null || c == null || c.isCompleted) return widget.rest?.call(widget.child) ?? widget.child;
    final child = RepaintBoundary(child: widget.child);
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: t,
        builder: (context, _) {
          if (c.isCompleted) return widget.rest?.call(widget.child) ?? widget.child;
          return widget.pose(context, t.value, child);
        },
      ),
    );
  }
}

bool _rtl(BuildContext context) => Directionality.maybeOf(context) == TextDirection.rtl;

/// M1: the item turns in on its spine (the reading start edge) from −70° past +8° to flat, fading in by 60 %.
class AppFlipIn extends StatelessWidget {
  const AppFlipIn({super.key, required this.child, this.index = 0, this.delay = Duration.zero, this.group = ''});

  final Widget child;
  final int index;
  final Duration delay;
  final String group;

  @override
  Widget build(BuildContext context) => _Entry(
        kind: MotionKind.flip,
        onceKey: '$group:$index',
        duration: AppMotionSpec.flip,
        curve: AppMotionSpec.flipCurve,
        delay: AppMotionSpec.flipStagger * index + delay,
        pose: (context, t, child) {
          final rtl = _rtl(context);
          final deg = motionKeyframes(t, const [0, .6, 1], const [-70, 8, 0]) * (rtl ? 1 : -1);
          return Opacity(
            opacity: (t / .6).clamp(0.0, 1.0),
            child: Transform(
              alignment: rtl ? Alignment.centerRight : Alignment.centerLeft,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 1 / 900)
                ..rotateY(deg * kDeg),
              child: child,
            ),
          );
        },
        child: child,
      );
}

/// M3: a pop with a little turn (.6 → 1.08 → 1, −6° → +2° → 0). With [trigger] it plays again each time the
/// trigger changes (a selected option) and not on the first build. Available to every role.
class AppPop extends StatelessWidget {
  const AppPop({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.alignment = Alignment.center,
    this.trigger,
    this.group = '',
    this.index = 0,
  });

  final Widget child;
  final Duration delay;
  final Alignment alignment;
  final Object? trigger;
  final String group;
  final int index;

  @override
  Widget build(BuildContext context) => _Entry(
        kind: MotionKind.pop,
        onceKey: '$group:$index',
        duration: AppMotionSpec.pop,
        curve: AppMotionSpec.popCurve,
        delay: delay,
        playfulOnly: false,
        trigger: trigger,
        useTrigger: trigger != null,
        pose: (context, t, child) {
          final s = motionKeyframes(t, const [0, .6, 1], const [.6, 1.08, 1]);
          final r = motionKeyframes(t, const [0, .6, 1], const [-6, 2, 0]);
          return Opacity(
            opacity: (t / .6).clamp(0.0, 1.0),
            child: Transform(
              alignment: alignment,
              transform: Matrix4.identity()
                ..scaleByDouble(s, s, 1, 1)
                ..rotateZ(r * kDeg),
              child: child,
            ),
          );
        },
        child: child,
      );
}

/// M4: a sticker slapped on (1.6 → .94 → (1.04, .96) → 1), ending tilted by [tilt] degrees.
class AppSlap extends StatelessWidget {
  const AppSlap({
    super.key,
    required this.child,
    this.delay = AppMotionSpec.slapDelay,
    this.tilt = -3,
    this.group = '',
    this.index = 0,
  });

  final Widget child;
  final Duration delay;
  final double tilt;
  final String group;
  final int index;

  Widget _tilted(Widget child) =>
      tilt == 0 ? child : Transform.rotate(angle: tilt * kDeg, child: child);

  @override
  Widget build(BuildContext context) => _Entry(
        kind: MotionKind.slap,
        onceKey: '$group:$index',
        duration: AppMotionSpec.slap,
        curve: AppMotionSpec.slapCurve,
        delay: delay,
        rest: _tilted,
        pose: (context, t, child) {
          final sx = motionKeyframes(t, const [0, .55, .75, 1], const [1.6, .94, 1.04, 1]);
          final sy = motionKeyframes(t, const [0, .55, .75, 1], const [1.6, .94, .96, 1]);
          final r = -12 + (tilt + 12) * t.clamp(0.0, 1.0);
          return Opacity(
            opacity: (t / .3).clamp(0.0, 1.0),
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..rotateZ(r * kDeg)
                ..scaleByDouble(sx, sy, 1, 1),
              child: child,
            ),
          );
        },
        child: child,
      );
}

/// M5: a card dealt onto the table from the side (odd indexes from the other side), settling flat.
class AppDeal extends StatelessWidget {
  const AppDeal({super.key, required this.child, this.index = 0, this.delay = Duration.zero, this.group = ''});

  final Widget child;
  final int index;
  final Duration delay;
  final String group;

  @override
  Widget build(BuildContext context) => _Entry(
        kind: MotionKind.deal,
        onceKey: '$group:$index',
        duration: AppMotionSpec.deal,
        curve: AppMotionSpec.dealCurve,
        delay: AppMotionSpec.dealStagger * index + delay,
        pose: (context, t, child) {
          final side = (index.isOdd ? -1 : 1) * (_rtl(context) ? 1 : -1);
          final k = 1 - t;
          final s = .92 + .08 * t;
          return Opacity(
            opacity: t.clamp(0.0, 1.0),
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..translateByDouble(-40.0 * side * k, 30.0 * k, 0, 1)
                ..rotateZ(6 * side * k * kDeg)
                ..scaleByDouble(s, s, 1, 1),
              child: child,
            ),
          );
        },
        child: child,
      );
}

/// M12: a wobble in from the end side, rocking on its bottom edge before it settles.
class AppWobble extends StatelessWidget {
  const AppWobble({super.key, required this.child, this.index = 0, this.delay = Duration.zero, this.group = ''});

  final Widget child;
  final int index;
  final Duration delay;
  final String group;

  @override
  Widget build(BuildContext context) => _Entry(
        kind: MotionKind.wobble,
        onceKey: '$group:$index',
        duration: AppMotionSpec.wobble,
        curve: AppMotionSpec.wobbleCurve,
        delay: AppMotionSpec.wobbleStagger * index + delay,
        pose: (context, t, child) {
          final fromEnd = _rtl(context) ? -1.0 : 1.0;
          final dx = 40 * fromEnd * (1 - math.min(t / .4, 1));
          final r = motionKeyframes(t, const [0, .4, .65, .85, 1], const [8, -4, 3, -1.5, 0]);
          return Opacity(
            opacity: (t / .4).clamp(0.0, 1.0),
            child: Transform(
              alignment: Alignment.bottomCenter,
              transform: Matrix4.identity()
                ..translateByDouble(dx, 0, 0, 1)
                ..rotateZ(r * kDeg),
              child: child,
            ),
          );
        },
        child: child,
      );
}
