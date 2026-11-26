// lib/design/motion/motion_sheet.dart
//
// M14 (KIT_SPEC §4.2): the phone bottom sheet rises 500 ms, overshoots by 1.6 % of its height and settles; it goes
// in 200 ms. Under Reduce motion it is there at once.
library;

import 'package:flutter/animation.dart';
import 'package:flutter/widgets.dart';

import '../app_motion_kit.dart' show appMotionOff;
import 'motion_spec.dart';

/// `t < .7 ? 1.016 × Cubic(.2, .8, .2, 1)(t / .7) : 1.016 − .016 × easeOut((t − .7) / .3)`.
class PeekCurve extends Curve {
  const PeekCurve();

  static const Curve _rise = Cubic(.2, .8, .2, 1);

  @override
  double transformInternal(double t) => t < .7
      ? 1.016 * _rise.transform(t / .7)
      : 1.016 - .016 * Curves.easeOut.transform((t - .7) / .3);
}

/// The sheet route's [AnimationStyle].
AnimationStyle appPeekSheetStyle(BuildContext context) => appMotionOff(context)
    ? const AnimationStyle(duration: Duration.zero, reverseDuration: Duration.zero)
    : const AnimationStyle(
        duration: AppMotionSpec.sheetIn,
        reverseDuration: AppMotionSpec.sheetOut,
        curve: PeekCurve(),
        reverseCurve: Curves.easeInCubic,
      );
