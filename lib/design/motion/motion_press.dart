// lib/design/motion/motion_press.dart
//
// M9 AppJelly (KIT_SPEC §4.2): press feedback that squashes (.94, 1.04) on pointer down and springs back with an
// overshoot. Passive like AppPressScale: a Listener, the child's own InkWell gets the tap. `wide` (a full-width
// button or a card) squashes less. No transform under Reduce motion (the ink ripple is the feedback).
library;

import 'package:flutter/widgets.dart';

import '../app_motion_kit.dart' show appMotionOff;
import 'motion_spec.dart';

class AppJelly extends StatefulWidget {
  const AppJelly({super.key, required this.child, this.enabled = true, this.wide = false});

  final Widget child;
  final bool enabled;
  final bool wide;

  @override
  State<AppJelly> createState() => _AppJellyState();
}

class _AppJellyState extends State<AppJelly> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: AppMotionSpec.jelly);
  late final Animation<double> _t =
      CurvedAnimation(parent: _c, curve: AppMotionSpec.jellyCurve, reverseCurve: AppMotionSpec.jellyCurve.flipped);

  bool get _on => widget.enabled && !appMotionOff(context);

  void _down() {
    if (_on) _c.forward();
  }

  void _up() {
    if (_c.value > 0) _c.reverse();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (sx, sy) = widget.wide ? (.97, 1.02) : (.94, 1.04);
    return Listener(
      onPointerDown: (_) => _down(),
      onPointerUp: (_) => _up(),
      onPointerCancel: (_) => _up(),
      child: AnimatedBuilder(
        animation: _t,
        child: widget.child,
        builder: (context, child) {
          final k = _t.value;
          if (k == 0 || !_on) return child!;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.diagonal3Values(1 + (sx - 1) * k, 1 + (sy - 1) * k, 1),
            child: child,
          );
        },
      ),
    );
  }
}
