// lib/features/teacher/sessions/live/annotation/draw_input_prefs.dart
//
// How this DEVICE draws (D-093), the same on a shared screen's annotation and on the whiteboard:
//   stylusOnly  only a stylus / S Pen / Apple Pencil draws; a finger scrolls and zooms the board (and never draws on
//               a shared screen). Off by default; remembered on the device (SharedPreferences). The first time a stylus
//               touches a board, the board offers it once.
// Never sent: each device decides how its own fingers behave.
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DrawInputPrefs {
  DrawInputPrefs._();

  static const _kKey = 'live.draw.stylus_only';

  /// Only a stylus draws here; fingers pan / zoom.
  static final ValueNotifier<bool> stylusOnly = ValueNotifier<bool>(false);

  /// A stylus has touched a board in this run (the board offers "Stylus only" once).
  static bool stylusSeen = false;

  /// The offer was shown (or answered) in this run.
  static bool offered = false;

  static bool _loaded = false;

  /// Reads the saved choice (once per run; a failing store keeps the default).
  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      stylusOnly.value = p.getBool(_kKey) ?? false;
    } catch (_) {}
  }

  static Future<void> setStylusOnly(bool on) async {
    offered = true;
    if (stylusOnly.value == on) return;
    stylusOnly.value = on;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kKey, on);
    } catch (_) {}
  }
}
