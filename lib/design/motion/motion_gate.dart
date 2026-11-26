// lib/design/motion/motion_gate.dart
//
// The one question every one-shot move of the motion library asks before it plays (KIT_SPEC §4.2, §4.3): motion
// allowed, a student area (for the playful moves), not played yet on this route, and granted by the screen's budget.
library;

import 'package:flutter/widgets.dart';

import '../app_area.dart';
import '../app_motion_kit.dart' show appMotionOff, appPlayOnce;
import 'motion_budget.dart';

/// True when the move of [kind] keyed [key] may play now. [playfulOnly]: refused outside an area scope (teacher,
/// parent, admin, organization screens draw the end state). [once]: plays once per route for `key`.
bool motionMayPlay(BuildContext context, MotionKind kind, String key, {bool playfulOnly = true, bool once = true}) {
  if (appMotionOff(context)) return false;
  if (playfulOnly && !AppAreaScope.playful(context)) return false;
  if (once && !appPlayOnce(context, '$key:${kind.name}')) return false;
  final budget = AppMotionBudget.maybeOf(context);
  return budget == null || budget.claimEntry(kind);
}

/// Piecewise-linear [values] over [stops] (both the same length, stops rising from 0 to 1) at [t].
double motionKeyframes(double t, List<double> stops, List<double> values) {
  if (t <= stops.first) return values.first;
  for (var i = 1; i < stops.length; i++) {
    if (t <= stops[i]) {
      final k = (t - stops[i - 1]) / (stops[i] - stops[i - 1]);
      return values[i - 1] + (values[i] - values[i - 1]) * k;
    }
  }
  return values.last;
}

const double kDeg = 3.141592653589793 / 180;
