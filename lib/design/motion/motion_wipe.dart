// lib/design/motion/motion_wipe.dart
//
// M6 (KIT_SPEC §4.2): AppWipe opens its child from the reading start edge behind a slanted leading edge (right to
// left in Arabic); AppWipeSwitcher wipes a new child in over the old one when its key changes (a tab or a step).
// Student areas only; under Reduce motion the child is simply there / swaps at once.
library;

import 'package:flutter/widgets.dart';

import '../app_area.dart';
import '../app_motion_kit.dart' show appMotionOff;
import 'motion_budget.dart';
import 'motion_gate.dart';
import 'motion_spec.dart';

/// The wipe's clip at [t]: the leading edge's bottom lags its top by 20 % of the width.
class AppWipeClipper extends CustomClipper<Path> {
  AppWipeClipper(this.t, {required this.rtl});

  final double t;
  final bool rtl;

  @override
  Path getClip(Size size) {
    final w = size.width, h = size.height;
    final top = t * 1.2 * w;
    final bottom = top - 0.2 * w;
    double x(double v) => rtl ? w - v : v;
    return Path()
      ..moveTo(x(0), 0)
      ..lineTo(x(top.clamp(0, w)), 0)
      ..lineTo(x(bottom.clamp(0, w)), h)
      ..lineTo(x(0), h)
      ..close();
  }

  @override
  bool shouldReclip(AppWipeClipper old) => old.t != t || old.rtl != rtl;
}

class _Wiping extends StatelessWidget {
  const _Wiping({required this.t, required this.child});

  final Animation<double> t;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    return AnimatedBuilder(
      animation: t,
      builder: (context, child) => t.value >= 1 ? child! : ClipPath(clipper: AppWipeClipper(t.value, rtl: rtl), child: child),
      child: RepaintBoundary(child: child),
    );
  }
}

/// M6: the child opens from the start edge, once per route.
class AppWipe extends StatefulWidget {
  const AppWipe({super.key, required this.child, this.delay = Duration.zero, this.group = '', this.index = 0});

  final Widget child;
  final Duration delay;
  final String group;
  final int index;

  @override
  State<AppWipe> createState() => _AppWipeState();
}

class _AppWipeState extends State<AppWipe> with SingleTickerProviderStateMixin {
  AnimationController? _c;
  Animation<double>? _t;
  bool _decided = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) return;
    _decided = true;
    if (!motionMayPlay(context, MotionKind.wipe, '${widget.group}:${widget.index}')) return;
    final total = widget.delay + AppMotionSpec.wipe;
    final c = AnimationController(vsync: this, duration: total);
    _c = c;
    _t = CurvedAnimation(
        parent: c,
        curve: Interval(widget.delay.inMicroseconds / total.inMicroseconds, 1, curve: AppMotionSpec.wipeCurve));
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
    if (t == null) return widget.child;
    return _Wiping(t: t, child: widget.child);
  }
}

/// M6: when [switchKey] changes the new child wipes in over the old one, which is dropped at the end. Not an
/// entrance: it does not ask the budget.
class AppWipeSwitcher extends StatefulWidget {
  const AppWipeSwitcher({super.key, required this.child, required this.switchKey});

  final Widget child;
  final Object switchKey;

  @override
  State<AppWipeSwitcher> createState() => _AppWipeSwitcherState();
}

class _AppWipeSwitcherState extends State<AppWipeSwitcher> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: AppMotionSpec.wipe, value: 1)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed && _old != null && mounted) setState(() => _old = null);
    });
  late final Animation<double> _t = CurvedAnimation(parent: _c, curve: AppMotionSpec.wipeCurve);
  Widget? _old;

  @override
  void didUpdateWidget(AppWipeSwitcher old) {
    super.didUpdateWidget(old);
    if (old.switchKey == widget.switchKey) return;
    if (appMotionOff(context) || !AppAreaScope.playful(context)) {
      _old = null;
      _c.value = 1;
      return;
    }
    _old = KeyedSubtree(key: ValueKey(old.switchKey), child: old.child);
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = KeyedSubtree(key: ValueKey(widget.switchKey), child: widget.child);
    final old = _old;
    if (old == null) return current;
    return Stack(children: [
      IgnorePointer(child: old),
      _Wiping(t: _t, child: current),
    ]);
  }
}
