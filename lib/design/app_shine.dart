// lib/design/app_shine.dart
//
// THE light sweep of the app: a slanted band of light crossing a surface — the course attendance entry's shimmer
// (attendance_course_entry.dart), shared so every "premium" surface sweeps the same way (D-120):
//
//   Stack(children: [content, const Positioned.fill(child: AppShineBand())])
//
// [period] is one cycle; the band crosses during the first [sweep] part of it and rests out of sight for the rest,
// so 1.0 sweeps without a pause (the attendance entry, 2.6 s) and e.g. 0.3 of 6 s crosses in ~1.8 s then waits
// ~4 s (the home journey card). While it rests no ticker runs (a timer starts the next pass), so a resting card
// costs no frames. Decorative: Reduce motion parks it out of sight, and it never takes a tap.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../config/theme/theme_config_provider.dart';
import 'app_display.dart' show syncMotionLoop;

class AppShineBand extends StatefulWidget {
  const AppShineBand({
    super.key,
    this.color,
    this.period = const Duration(milliseconds: 2600),
    this.sweep = 1.0,
    this.width = 22,
  });

  /// The band's colour; null = the on-hero ink at 18 % (the attendance entry's, made for gradient surfaces).
  final Color? color;
  final Duration period;

  /// The part of [period] the band takes to cross (0 < sweep <= 1).
  final double sweep;
  final double width;

  @override
  State<AppShineBand> createState() => _AppShineBandState();
}

class _AppShineBandState extends State<AppShineBand> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: _crossing)..addStatusListener(_onStatus);
  Timer? _rest;
  bool _still = false;

  double get _sweep => widget.sweep.clamp(0.05, 1.0);

  /// The band's pass (the whole period when it never rests).
  Duration get _crossing => widget.period * _sweep;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sweep >= 1) {
      syncMotionLoop(context, _c, rest: 1);
      return;
    }
    _still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_still) {
      _rest?.cancel();
      _c.stop();
      _c.value = 1;
    } else if (!_c.isAnimating && _rest == null) {
      _c.forward(from: 0);
    }
  }

  void _onStatus(AnimationStatus s) {
    if (s != AnimationStatus.completed || _sweep >= 1 || _still || !mounted) return;
    _rest = Timer(widget.period - _crossing, () {
      _rest = null;
      if (mounted && !_still) _c.forward(from: 0);
    });
  }

  @override
  void didUpdateWidget(AppShineBand old) {
    super.didUpdateWidget(old);
    if (old.period != widget.period || old.sweep != widget.sweep) _c.duration = _crossing;
  }

  @override
  void dispose() {
    _rest?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? context.colors.onHero.withValues(alpha: 0.18);
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, box) => AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final p = _c.value;
            if (p >= 1 || (p <= 0 && !_c.isAnimating)) return const SizedBox.shrink();
            return Align(
              alignment: Alignment(-1.8 + 3.6 * p, 0),
              child: Transform.rotate(
                angle: 0.35,
                child: Container(width: widget.width, height: box.maxHeight.isFinite ? box.maxHeight * 2 : 200, color: color),
              ),
            );
          },
        ),
      ),
    );
  }
}
