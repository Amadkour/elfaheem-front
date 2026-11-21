// lib/features/self_learning/sl_motion.dart — the two small motions of the learning cards (D-1604), one-shot only
// (nothing loops), both still under Reduce motion (appMotionOff: the person's, the system's or `app.animations`):
//
//   SlFeedbackIn(child:)     a feedback panel fades in and rises 8 px once (240 ms, ease-out)
//   SlCelebration(play:)     a light burst of dots around a right answer, once (900 ms); nothing under Reduce motion
//
// Used by the self-learning review card and the nahw round (the same feedback motion in both).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';

/// Fades [child] in and lifts it 8 px, once per mount.
class SlFeedbackIn extends StatelessWidget {
  const SlFeedbackIn({super.key, required this.child});

  final Widget child;

  static const double _rise = 8;

  @override
  Widget build(BuildContext context) {
    if (appMotionOff(context)) return child;
    return RepaintBoundary(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 240),
        curve: AppEase.out,
        child: child,
        builder: (_, v, child) => Opacity(
          opacity: v,
          child: Transform.translate(offset: Offset(0, _rise * (1 - v)), child: child),
        ),
      ),
    );
  }
}

/// A light burst of small dots from the start-top corner of its box, played once when mounted with [play]. Draws
/// nothing (and starts no ticker) under Reduce motion. Decorative: no semantics, no hit testing.
class SlCelebration extends StatefulWidget {
  const SlCelebration({super.key, this.play = true});

  final bool play;

  @override
  State<SlCelebration> createState() => _SlCelebrationState();
}

class _SlCelebrationState extends State<SlCelebration> with SingleTickerProviderStateMixin {
  AnimationController? _c;
  bool _decided = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) return;
    _decided = true;
    if (!widget.play || appMotionOff(context)) return;
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) return const SizedBox.shrink();
    final colors = context.colors;
    final tones = [colors.success, appToneColor(context, AppTone.gold), colors.primary];
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: c,
            builder: (_, _) => c.isCompleted
                ? const SizedBox.shrink()
                : CustomPaint(painter: _BurstPainter(t: AppEase.out.transform(c.value), tones: tones, rtl: rtl)),
          ),
        ),
      ),
    );
  }
}

class _BurstPainter extends CustomPainter {
  _BurstPainter({required this.t, required this.tones, required this.rtl});

  final double t;
  final List<Color> tones;
  final bool rtl;

  static const int _dots = 12;
  static const double _reach = 44;
  static const double _dot = 3.5;

  @override
  void paint(Canvas canvas, Size size) {
    // the burst comes from the feedback glyph (the start edge, first line)
    final origin = Offset(rtl ? size.width - AppSpace.lg : AppSpace.lg, AppSpace.lg);
    final fade = (1 - t).clamp(0.0, 1.0);
    for (var i = 0; i < _dots; i++) {
      final a = (i / _dots) * 2 * math.pi + 0.3;
      final d = _reach * t * (0.7 + 0.3 * ((i * 7) % 5) / 4);
      final p = origin + Offset(math.cos(a) * d, math.sin(a) * d);
      final paint = Paint()..color = tones[i % tones.length].withValues(alpha: fade);
      canvas.drawCircle(p, _dot * (1 - 0.4 * t), paint);
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.t != t || old.rtl != rtl;
}
