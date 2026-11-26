// lib/design/motion/motion_pill.dart
//
// M13 AppMorphPill (KIT_SPEC §4.2): the selected pill of a segmented strip or the phone bottom bar slides behind the
// row of items with a small overshoot. Equal slots unless [widths] is given. Not a loop and not an entrance: it does
// not ask the budget; under Reduce motion the pill jumps.
library;

import 'package:flutter/widgets.dart';

import '../app_motion_kit.dart' show appMotionOff;
import '../app_tokens.dart';
import 'motion_spec.dart';

class AppMorphPill extends StatefulWidget {
  const AppMorphPill({
    super.key,
    required this.count,
    required this.index,
    required this.child,
    this.inset = const EdgeInsets.all(AppSpace.xxs),
    this.gap = AppSpace.xxs,
    this.radius,
    this.color,
    this.shadow,
    this.widths,
  });

  final int count;
  final int index;

  /// The row of items, drawn over the pill.
  final Widget child;
  final EdgeInsets inset;
  final double gap;
  final BorderRadius? radius;
  final Color? color;
  final List<BoxShadow>? shadow;

  /// Each item's width (a strip whose tabs hug their labels); null = equal slots.
  final List<double>? widths;

  @override
  State<AppMorphPill> createState() => _AppMorphPillState();
}

class _AppMorphPillState extends State<AppMorphPill> with SingleTickerProviderStateMixin {
  late final AnimationController _first = AnimationController(vsync: this, duration: AppMotionSpec.pillFirst);
  bool _decided = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) return;
    _decided = true;
    if (appMotionOff(context)) {
      _first.value = 1;
    } else {
      _first.forward();
    }
  }

  @override
  void dispose() {
    _first.dispose();
    super.dispose();
  }

  /// The pill's (start, width) inside [width].
  (double, double) _slot(double width) {
    final w = widget;
    final n = w.count <= 0 ? 1 : w.count;
    final i = w.index.clamp(0, n - 1);
    final ws = w.widths;
    if (ws != null && ws.length == n) {
      var start = w.inset.left;
      for (var k = 0; k < i; k++) {
        start += ws[k] + w.gap;
      }
      return (start, ws[i]);
    }
    final room = width - w.inset.horizontal - w.gap * (n - 1);
    final slot = room / n;
    return (w.inset.left + i * (slot + w.gap), slot < 0 ? 0 : slot);
  }

  @override
  Widget build(BuildContext context) {
    final off = appMotionOff(context);
    final d = off ? Duration.zero : AppMotionSpec.pill;
    return LayoutBuilder(builder: (context, box) {
      final (start, width) = _slot(box.maxWidth.isFinite ? box.maxWidth : 0);
      return Stack(children: [
        AnimatedPositionedDirectional(
          duration: d,
          curve: AppMotionSpec.pillCurve,
          start: start,
          width: width,
          top: widget.inset.top,
          bottom: widget.inset.bottom,
          child: AnimatedBuilder(
            animation: _first,
            builder: (context, child) {
              final t = Curves.easeOutCubic.transform(_first.value);
              if (t >= 1) return child!;
              return Opacity(
                opacity: t,
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.diagonal3Values(.4 + .6 * t, 1, 1),
                  child: child,
                ),
              );
            },
            child: AnimatedContainer(
              duration: d,
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: widget.radius ?? BorderRadius.circular(AppRadius.pill),
                boxShadow: widget.shadow,
              ),
            ),
          ),
        ),
        widget.child,
      ]);
    });
  }
}
