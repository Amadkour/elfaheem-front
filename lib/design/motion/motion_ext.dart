// lib/design/motion/motion_ext.dart
//
// Shorthands for the motion library (KIT_SPEC §4.2): `Card(item).mDeal(i)` wraps the widget in the move with its
// defaults.
library;

import 'package:flutter/widgets.dart';

import 'motion_entry.dart';
import 'motion_live.dart';
import 'motion_press.dart';
import 'motion_spec.dart';
import 'motion_wipe.dart';

extension AppMotionX on Widget {
  Widget mFlip([int i = 0]) => AppFlipIn(index: i, child: this);

  Widget mDeal([int i = 0]) => AppDeal(index: i, child: this);

  Widget mWobble([int i = 0]) => AppWobble(index: i, child: this);

  Widget mPop({Duration delay = Duration.zero}) => AppPop(delay: delay, child: this);

  Widget mSlap({Duration delay = AppMotionSpec.slapDelay}) => AppSlap(delay: delay, child: this);

  Widget mWipe() => AppWipe(child: this);

  Widget mJelly() => AppJelly(child: this);

  Widget mBreathe({Color? color}) => AppBreathe(color: color, child: this);
}
