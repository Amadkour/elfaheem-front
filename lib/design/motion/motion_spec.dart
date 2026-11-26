// lib/design/motion/motion_spec.dart
//
// The timings of the redesign motion library M1–M16 (KIT_SPEC §4.2), in one table. `Cubic(a, b, c, d)` is CSS's
// `cubic-bezier(a, b, c, d)`.
library;

import 'package:flutter/animation.dart';

export 'motion_budget.dart' show MotionKind;

abstract final class AppMotionSpec {
  // M1 flip in
  static const Duration flip = Duration(milliseconds: 600);
  static const Curve flipCurve = Cubic(.2, .8, .2, 1);
  static const Duration flipStagger = Duration(milliseconds: 70);

  // M2 ink
  static const Duration ink = Duration(milliseconds: 900);
  static const Curve inkCurve = Cubic(.6, 0, .2, 1);
  static const Duration inkDelay = Duration(milliseconds: 200);
  static const Duration inkGlide = Duration(milliseconds: 300);

  // M3 pop
  static const Duration pop = Duration(milliseconds: 450);
  static const Curve popCurve = Cubic(.3, 1.4, .5, 1);

  // M4 slap
  static const Duration slap = Duration(milliseconds: 420);
  static const Curve slapCurve = Cubic(.3, .9, .4, 1);
  static const Duration slapDelay = Duration(milliseconds: 300);

  // M5 deal
  static const Duration deal = Duration(milliseconds: 500);
  static const Curve dealCurve = Cubic(.2, .9, .3, 1.1);
  static const Duration dealStagger = Duration(milliseconds: 60);

  // M6 wipe
  static const Duration wipe = Duration(milliseconds: 550);
  static const Curve wipeCurve = Cubic(.6, 0, .2, 1);

  // M7 squiggle
  static const Duration squiggle = Duration(milliseconds: 700);
  static const Curve squiggleCurve = Curves.easeOut;
  static const Duration squiggleDelay = Duration(milliseconds: 500);

  // M8 breathe
  static const Duration breathe = Duration(milliseconds: 2400);

  // M9 jelly
  static const Duration jelly = Duration(milliseconds: 180);
  static const Curve jellyCurve = Cubic(.3, 1.6, .5, 1);

  // M10 odometer
  static const Duration odometer = Duration(milliseconds: 900);
  static const Curve odometerCurve = Cubic(.2, .8, .2, 1);
  static const Duration odometerColumn = Duration(milliseconds: 80);
  static const Duration odometerDelay = Duration(milliseconds: 200);

  // M11 burst
  static const Duration burst = Duration(milliseconds: 900);
  static const Curve burstCurve = Cubic(.1, .7, .3, 1);
  static const Duration burstDelay = Duration(milliseconds: 150);

  // M12 wobble
  static const Duration wobble = Duration(milliseconds: 800);
  static const Curve wobbleCurve = Curves.easeOut;
  static const Duration wobbleStagger = Duration(milliseconds: 60);

  // M13 morph pill
  static const Duration pill = Duration(milliseconds: 350);
  static const Curve pillCurve = Cubic(.3, 1.3, .5, 1);
  static const Duration pillFirst = Duration(milliseconds: 450);

  // M14 peek sheet
  static const Duration sheetIn = Duration(milliseconds: 500);
  static const Duration sheetOut = Duration(milliseconds: 200);

  // M15 feedback
  static const Duration feedback = Duration(milliseconds: 360);

  // M16 drift: the common period of 11, 15 and 28 s
  static const Duration driftPeriod = Duration(seconds: 4620);

  // the side drawer (§5.8)
  static const Duration drawer = Duration(milliseconds: 450);
  static const Curve drawerCurve = Cubic(.2, .8, .2, 1);
}
