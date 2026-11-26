// lib/design/motion/motion_drift.dart
//
// M16 AppDriftShapes (KIT_SPEC §4.2, §4.5): three soft shapes drift behind a hero: a circle (11 s), a squircle
// outline (15 s, the other way) and a plus that turns once in 28 s. ONE repeating controller of 4620 s (the common
// period, so nothing jumps at the wrap). A LOOP: parked at the home positions under Reduce motion, outside a
// student area, or past the screen's loop budget. With [scroll], the shapes also shift for a parallax.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_education_app/config/theme/kit_palette.dart' show AppAccent, KitSet;
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import '../app_area.dart';
import '../app_display.dart' show syncMotionLoop;
import 'motion_budget.dart';
import 'motion_gate.dart' show kDeg;
import 'motion_spec.dart';

class AppDriftShapes extends StatefulWidget {
  const AppDriftShapes({super.key, required this.set, this.scroll, this.compact = false});

  final KitSet set;
  final ScrollController? scroll;
  final bool compact;

  @override
  State<AppDriftShapes> createState() => AppDriftShapesState();
}

class AppDriftShapesState extends State<AppDriftShapes> with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(vsync: this, duration: AppMotionSpec.driftPeriod);
  AppMotionBudgetState? _budget;
  bool _granted = true;
  bool _claimed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_claimed) {
      _claimed = true;
      _budget = AppMotionBudget.maybeOf(context);
      _granted = _budget?.claimLoop(this) ?? true;
    }
    if (!_granted || !AppAreaScope.playful(context)) {
      controller.stop();
      controller.value = 0;
    } else {
      syncMotionLoop(context, controller, rest: 0);
    }
  }

  @override
  void dispose() {
    _budget?.releaseLoop(this);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sun = c.kit.accent(AppAccent.sun).color;
    final scroll = widget.scroll;
    final listen = scroll == null ? controller : Listenable.merge([controller, scroll]);
    return IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: LayoutBuilder(builder: (context, box) {
            final w = box.maxWidth.isFinite ? box.maxWidth : 0.0;
            return AnimatedBuilder(
              animation: listen,
              builder: (context, _) {
                final moving = controller.isAnimating;
                final t = controller.value;
                final pa = moving ? (1 - math.cos(2 * math.pi * 420 * t)) / 2 : 0.0;
                final pb = moving ? (1 - math.cos(2 * math.pi * 308 * t)) / 2 : 0.0;
                final pc = moving ? 2 * math.pi * 165 * t : 0.0;
                final so = moving && scroll != null && scroll.hasClients ? scroll.offset : 0.0;
                final compact = widget.compact;
                final s1 = compact ? 150.0 : 240.0;
                final s2 = compact ? 72.0 : 120.0;
                final s3 = compact ? 40.0 : 64.0;
                return Stack(clipBehavior: Clip.hardEdge, children: [
                  PositionedDirectional(
                    top: (compact ? -70.0 : -110.0) + so * .10,
                    end: compact ? -20.0 : w * .06,
                    width: s1,
                    height: s1,
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..translateByDouble(22 * pa, -18 * pa, 0, 1)
                        ..rotateZ(8 * pa * kDeg),
                      child: DecoratedBox(
                        decoration:
                            BoxDecoration(shape: BoxShape.circle, color: widget.set.b.withValues(alpha: .20)),
                      ),
                    ),
                  ),
                  PositionedDirectional(
                    // compact: above the text like the reference phone (the spec's bottom 18 crossed the title)
                    top: (compact ? -40.0 : -54.0) + so * .18,
                    start: compact ? null : w * .44,
                    end: compact ? w * .30 : null,
                    width: s2,
                    height: s2,
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..translateByDouble(-22 * pb, 18 * pb, 0, 1)
                        ..rotateZ(-8 * pb * kDeg),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.all(Radius.circular(compact ? _sq2c : _sq2)),
                          border: Border.all(color: sun.withValues(alpha: .40), width: 3),
                        ),
                      ),
                    ),
                  ),
                  PositionedDirectional(
                    top: (compact ? 14.0 : 22.0) + so * .26,
                    end: w * (compact ? .44 : .52),
                    width: s3,
                    height: s3,
                    child: Transform.rotate(
                      angle: pc,
                      child: CustomPaint(painter: _PlusPainter(c.onHero.withValues(alpha: .14), compact ? 11 : 18)),
                    ),
                  ),
                ]);
              },
            );
          }),
        ),
      ),
    );
  }
}

const double _sq2 = 38;
const double _sq2c = 24;
const double _plusR = 6;

class _PlusPainter extends CustomPainter {
  _PlusPainter(this.color, this.bar);

  final Color color;
  final double bar;

  @override
  void paint(Canvas canvas, Size size) {
    const r = Radius.circular(_plusR);
    final o = size.center(Offset.zero);
    final plus = Path.combine(
      PathOperation.union,
      Path()..addRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: o, width: bar, height: size.height), r)),
      Path()..addRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: o, width: size.width, height: bar), r)),
    );
    canvas.drawPath(plus, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PlusPainter old) => old.color != color || old.bar != bar;
}
