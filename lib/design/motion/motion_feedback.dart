// lib/design/motion/motion_feedback.dart
//
// M15 (KIT_SPEC §4.2): a wrong answer shakes (physical, not mirrored) with a live-coloured ring; a right one nods
// with an ok-coloured ring. Under Reduce motion only the ring shows for 360 ms: it still tells right from wrong.
library;

import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:flutter/widgets.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import '../app_motion_kit.dart' show appMotionOff;
import 'motion_gate.dart' show motionKeyframes;
import 'motion_spec.dart';

enum AppFeedbackKind { shake, nod }

class AppFeedbackController extends ChangeNotifier {
  AppFeedbackKind? _kind;
  int _serial = 0;

  AppFeedbackKind? get kind => _kind;
  int get serial => _serial;

  void shake() => _fire(AppFeedbackKind.shake);

  void nod() => _fire(AppFeedbackKind.nod);

  void _fire(AppFeedbackKind k) {
    _kind = k;
    _serial++;
    notifyListeners();
  }
}

class AppFeedback extends StatefulWidget {
  const AppFeedback({super.key, required this.controller, required this.child, this.borderRadius});

  final AppFeedbackController controller;
  final Widget child;
  final BorderRadius? borderRadius;

  @override
  State<AppFeedback> createState() => _AppFeedbackState();
}

class _AppFeedbackState extends State<AppFeedback> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: AppMotionSpec.feedback);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_go);
  }

  @override
  void didUpdateWidget(AppFeedback old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_go);
      widget.controller.addListener(_go);
    }
  }

  void _go() => _c.forward(from: 0);

  @override
  void dispose() {
    widget.controller.removeListener(_go);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kit = context.colors.kit;
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        if (!_c.isAnimating) return child!;
        final shake = widget.controller.kind == AppFeedbackKind.shake;
        final t = _c.value;
        final still = appMotionOff(context);
        final ring = shake ? kit.live.color.withValues(alpha: .4) : kit.ok.color.withValues(alpha: .45);
        final Offset offset;
        if (still) {
          offset = Offset.zero;
        } else if (shake) {
          offset = Offset(motionKeyframes(t, const [0, .2, .4, .6, .8, 1], const [0, -7, 7, -7, 7, 0]), 0);
        } else {
          offset = Offset(0, motionKeyframes(Curves.easeOut.transform(t), const [0, .4, .7, 1], const [0, 5, -2, 0]));
        }
        return Transform.translate(
          offset: offset,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: widget.borderRadius,
              border: Border.all(color: ring, width: 3),
            ),
            child: child,
          ),
        );
      },
    );
  }
}
