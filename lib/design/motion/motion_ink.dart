// lib/design/motion/motion_ink.dart
//
// M2 ink: a stroke that draws itself (AppInkPath), a progress ring (AppInkRing) and the success tick (AppInkCheck);
// M7 AppSquiggle, the hand-drawn line under ONE key word of a hero title (KIT_SPEC §4.2). Under Reduce motion the
// full stroke is there on the first frame. M2 is available to every role; M7 only under a student area.
library;

import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/widgets.dart';
import 'package:flutter_education_app/config/theme/kit_palette.dart' show AppAccent;
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import '../app_motion_kit.dart' show appMotionOff;
import '../app_tokens.dart';
import 'motion_gate.dart';
import 'motion_spec.dart';

/// [path] trimmed to [t] of its length.
Path inkTrim(Path path, double t) {
  if (t >= 1) return path;
  final out = Path();
  if (t <= 0) return out;
  for (final PathMetric m in path.computeMetrics()) {
    out.addPath(m.extractPath(0, m.length * t), Offset.zero);
  }
  return out;
}

/// A one-shot 0 → 1 driver for the ink widgets: [delay] then [duration] on [curve], once per route for [onceKey].
class _InkDriver extends StatefulWidget {
  const _InkDriver({
    required this.kind,
    required this.onceKey,
    required this.builder,
    this.duration = AppMotionSpec.ink,
    this.delay = AppMotionSpec.inkDelay,
    this.curve = AppMotionSpec.inkCurve,
    this.playfulOnly = false,
  });

  final MotionKind kind;
  final String onceKey;
  final Duration duration, delay;
  final Curve curve;
  final bool playfulOnly;
  final Widget Function(BuildContext context, double t) builder;

  @override
  State<_InkDriver> createState() => _InkDriverState();
}

class _InkDriverState extends State<_InkDriver> with SingleTickerProviderStateMixin {
  AnimationController? _c;
  Animation<double>? _t;
  bool _decided = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) return;
    _decided = true;
    if (!motionMayPlay(context, widget.kind, widget.onceKey, playfulOnly: widget.playfulOnly)) return;
    final total = widget.delay + widget.duration;
    final c = AnimationController(vsync: this, duration: total);
    _c = c;
    _t = CurvedAnimation(
        parent: c, curve: Interval(widget.delay.inMicroseconds / total.inMicroseconds, 1, curve: widget.curve));
    c.forward();
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    if (t == null) return widget.builder(context, 1);
    return AnimatedBuilder(animation: t, builder: (context, _) => widget.builder(context, t.value));
  }
}

class _PathPainter extends CustomPainter {
  _PathPainter(this.path, this.t, this.color, this.width);

  final Path Function(Size) path;
  final double t;
  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      inkTrim(path(size), t),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_PathPainter old) => old.t != t || old.color != color || old.width != width;
}

/// M2: [path] draws itself over [child] (which gives the size), to [to] of its length.
class AppInkPath extends StatelessWidget {
  const AppInkPath({
    super.key,
    required this.path,
    required this.color,
    this.strokeWidth = AppBorder.line,
    this.to = 1,
    this.delay = AppMotionSpec.inkDelay,
    this.duration,
    this.child,
    this.group = '',
    this.index = 0,
  });

  final Path Function(Size) path;
  final Color color;
  final double strokeWidth;
  final double to;
  final Duration delay;
  final Duration? duration;
  final Widget? child;
  final String group;
  final int index;

  @override
  Widget build(BuildContext context) => _InkDriver(
        kind: MotionKind.ink,
        onceKey: 'path:$group:$index',
        delay: delay,
        duration: duration ?? AppMotionSpec.ink,
        builder: (context, t) => CustomPaint(
          foregroundPainter: _PathPainter(path, t * to, color, strokeWidth),
          child: child ?? const SizedBox.expand(),
        ),
      );
}

/// The ring's painter. [sweepSign] is +1 (clockwise) in LTR and −1 in RTL.
class AppInkRingPainter extends CustomPainter {
  AppInkRingPainter({required this.value, required this.color, required this.track, required this.stroke,
      required this.rtl});

  final double value;
  final Color color, track;
  final double stroke;
  final bool rtl;

  @visibleForTesting
  double get sweepSign => rtl ? -1 : 1;

  @override
  void paint(Canvas canvas, Size size) {
    final r = (math.min(size.width, size.height) - stroke) / 2;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: r);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * math.pi, false, p..color = track);
    final v = value.clamp(0.0, 1.0);
    if (v > 0) canvas.drawArc(rect, -math.pi / 2, sweepSign * 2 * math.pi * v, false, p..color = color);
  }

  @override
  bool shouldRepaint(AppInkRingPainter old) =>
      old.value != value || old.color != color || old.track != track || old.stroke != stroke || old.rtl != rtl;
}

/// M2: a progress ring that draws from 12 o'clock (clockwise in LTR, counter-clockwise in RTL) the first time, and
/// glides from the old value on a later change.
class AppInkRing extends StatefulWidget {
  const AppInkRing({
    super.key,
    required this.value,
    required this.color,
    required this.track,
    this.size = AppDashSize.ringSm,
    this.stroke = 5,
    this.center,
    this.delay = AppMotionSpec.inkDelay,
  });

  final double value;
  final Color color, track;
  final double size, stroke;
  final Widget? center;
  final Duration delay;

  @override
  State<AppInkRing> createState() => _AppInkRingState();
}

class _AppInkRingState extends State<AppInkRing> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);
  double _from = 0;
  double _to = 0;
  Curve _curve = AppMotionSpec.inkCurve;
  double _start = 0;
  bool _decided = false;

  double get _value {
    final k = _c.value <= _start ? 0.0 : (_c.value - _start) / (1 - _start);
    return _from + (_to - _from) * _curve.transform(k.clamp(0.0, 1.0));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) return;
    _decided = true;
    _to = widget.value;
    if (!motionMayPlay(context, MotionKind.ink, 'ring:${widget.key}', playfulOnly: false, once: false)) {
      _from = _to;
      _c.value = 1;
      return;
    }
    final total = widget.delay + AppMotionSpec.ink;
    _c.duration = total;
    _start = widget.delay.inMicroseconds / total.inMicroseconds;
    _c.forward(from: 0);
  }

  @override
  void didUpdateWidget(AppInkRing old) {
    super.didUpdateWidget(old);
    if (old.value == widget.value) return;
    _from = _value;
    _to = widget.value;
    _start = 0;
    _curve = AppMotion.curve;
    if (appMotionOff(context)) {
      _c.value = 1;
      _from = _to;
      return;
    }
    _c.duration = AppMotionSpec.inkGlide;
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) => CustomPaint(
          painter: AppInkRingPainter(
              value: _value, color: widget.color, track: widget.track, stroke: widget.stroke, rtl: rtl),
          child: child,
        ),
        child: widget.center == null ? null : Center(child: widget.center),
      ),
    );
  }
}

/// M2: the success mark: a circle (r 28 in a 64 box) then the tick `M20 33 l8 8 16 -17`.
class AppInkCheck extends StatelessWidget {
  const AppInkCheck({super.key, this.size = 72, this.color});

  final double size;
  final Color? color;

  static const Duration _total = Duration(milliseconds: 1100);

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.colors.kit.ok.color;
    return SizedBox.square(
      dimension: size,
      child: _InkDriver(
        kind: MotionKind.ink,
        onceKey: 'check',
        delay: Duration.zero,
        duration: _total,
        curve: Curves.linear,
        builder: (context, t) => CustomPaint(painter: _CheckPainter(t, c)),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter(this.t, this.color);

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 64;
    canvas.scale(k, k);
    // circle 700 ms from 150 ms, tick 400 ms from 700 ms, of 1100 ms
    final ms = t * 1100;
    final circle = AppMotionSpec.inkCurve.transform(((ms - 150) / 700).clamp(0.0, 1.0));
    final tick = AppMotionSpec.inkCurve.transform(((ms - 700) / 400).clamp(0.0, 1.0));
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final ring = Path()..addArc(Rect.fromCircle(center: const Offset(32, 32), radius: 28), -math.pi / 2, 2 * math.pi);
    canvas.drawPath(inkTrim(ring, circle), p);
    final mark = Path()
      ..moveTo(20, 33)
      ..relativeLineTo(8, 8)
      ..relativeLineTo(16, -17);
    canvas.drawPath(inkTrim(mark, tick), p);
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.t != t || old.color != color;
}

/// The squiggle `M2 6 Q17 0 32 6 T62 6 T92 6 T118 5` in a 120 × 10 box, stretched to [w] wide, its box's top at [y].
Path squigglePath(double w, double y) {
  final sx = w / 120;
  Offset o(double x, double yy) => Offset(x * sx, y + yy);
  final a = o(17, 0), b = o(32, 6), c1 = o(47, 12), d = o(62, 6), c2 = o(77, 0), e = o(92, 6), c3 = o(107, 12),
      f = o(118, 5);
  final s = o(2, 6);
  return Path()
    ..moveTo(s.dx, s.dy)
    ..quadraticBezierTo(a.dx, a.dy, b.dx, b.dy)
    ..quadraticBezierTo(c1.dx, c1.dy, d.dx, d.dy)
    ..quadraticBezierTo(c2.dx, c2.dy, e.dx, e.dy)
    ..quadraticBezierTo(c3.dx, c3.dy, f.dx, f.dy);
}

/// M7: a hand-drawn line under ONE key word ([child], a `Text`). Not mirrored in English. Student areas only.
class AppSquiggle extends StatelessWidget {
  const AppSquiggle({super.key, required this.child, this.color, this.delay = AppMotionSpec.squiggleDelay});

  final Widget child;
  final Color? color;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.colors.kit.accent(AppAccent.sun).color;
    return _InkDriver(
      kind: MotionKind.squiggle,
      onceKey: 'squiggle',
      delay: delay,
      duration: AppMotionSpec.squiggle,
      curve: AppMotionSpec.squiggleCurve,
      playfulOnly: true,
      builder: (context, t) => CustomPaint(
        foregroundPainter: _PathPainter((s) => squigglePath(s.width, s.height - 2), t, c, 4),
        child: child,
      ),
    );
  }
}
