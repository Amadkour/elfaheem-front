// lib/design/motion/motion_live.dart
//
// M8 AppBreathe (KIT_SPEC §4.2): a live thing breathes (scale 1 → 1.03 → 1 over 2.4 s) while two rings spread from
// it, the second half a beat later. A LOOP: parked under Reduce motion (syncMotionLoop in didChangeDependencies),
// outside a student area, and when the screen's budget has its three loops already.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import '../app_area.dart';
import '../app_display.dart' show syncMotionLoop;
import '../app_tokens.dart';
import 'motion_budget.dart';
import 'motion_spec.dart';

class AppBreathe extends StatefulWidget {
  const AppBreathe({super.key, required this.child, this.color, this.borderRadius, this.active = true});

  final Widget child;
  final Color? color;
  final BorderRadius? borderRadius;
  final bool active;

  @override
  State<AppBreathe> createState() => AppBreatheState();
}

class AppBreatheState extends State<AppBreathe> with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(vsync: this, duration: AppMotionSpec.breathe);
  AppMotionBudgetState? _budget;
  bool _granted = true;
  bool _claimed = false;

  /// Ring gap outside the child.
  static const double _gap = 4;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_claimed) {
      _claimed = true;
      _budget = AppMotionBudget.maybeOf(context);
      _granted = _budget?.claimLoop(this) ?? true;
    }
    _sync();
  }

  @override
  void didUpdateWidget(AppBreathe old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _sync();
  }

  bool get _runs => widget.active && _granted && AppAreaScope.playful(context);

  void _sync() {
    if (!_runs) {
      controller.stop();
      controller.value = 0;
      return;
    }
    syncMotionLoop(context, controller, rest: 0);
  }

  @override
  void dispose() {
    _budget?.releaseLoop(this);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? context.colors.kit.live.color;
    final radius = widget.borderRadius ?? BorderRadius.circular(AppRadius.pill);
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: controller,
        child: widget.child,
        builder: (context, child) {
          final v = controller.value;
          if (!controller.isAnimating) return child!;
          final scale = 1 + 0.03 * Curves.easeInOut.transform(v < .5 ? v * 2 : (1 - v) * 2);
          Widget ring(double phase) {
            final k = Curves.easeOut.transform(phase);
            return Positioned(
              left: -_gap,
              right: -_gap,
              top: -_gap,
              bottom: -_gap,
              child: IgnorePointer(
                child: Opacity(
                  opacity: (0.55 * (1 - k)).clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: 1 + 0.35 * k,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: radius,
                        border: Border.all(color: color, width: AppBorder.focus),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }

          return Stack(clipBehavior: Clip.none, children: [
            ring(v),
            ring((v + .5) % 1),
            Transform.scale(scale: scale, child: child),
          ]);
        },
      ),
    );
  }
}
