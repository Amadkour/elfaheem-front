// lib/features/teacher/sessions/live/widgets/live_palette.dart
//
// The live classroom's colours, derived from the LIVE app theme (the one the super admin sets), so the room,
// pre-join and controls look like the rest of the app instead of a separate neon palette.
// The room stays dark (video needs it) — but it is a deep shade of YOUR primary colour.
// RoomPage / PreJoin call LivePalette.sync(context) at the top of build(); before the first sync the theme
// defaults (AppTheme) are used.
//
// Participant colours: every person gets ONE stable hue derived from their name (`hueFor`), so the same
// student is the same colour on every device, in every tile and in the recording. The gradient
// (`avatarGradient`) is what initials sit on; `avatarColor` is the mid tone used for rings, glows and tints.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/app_theme.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

class LivePalette {
  LivePalette._();
  static ThemeConfigProvider? _t;

  static void sync(BuildContext context) => _t = context.colors;

  static Color get _primaryDark => _t?.primaryDark ?? AppTheme.primaryDark;
  static Color _deep(double a) => Color.alphaBlend(Colors.black.withValues(alpha: a), _primaryDark);

  static Color get bg => _deep(0.86);
  static Color get surface => _deep(0.78);
  static Color get surfaceHi => _deep(0.68);
  static Color get accent => _t?.primaryLight ?? AppTheme.primaryLight;   // was neon cyan
  static Color get accent2 => _t?.purple ?? AppTheme.purple;               // was neon indigo
  static Color get success => _t?.success ?? AppTheme.success;             // was neon mint
  static Color get danger => _t?.danger ?? AppTheme.danger;                // was neon rose / rec red
  static Color get warning => _t?.warning ?? AppTheme.warning;             // was amber / orange

  // ── Text and glass tokens on the dark room backdrop ────────────────────────
  // White at fixed alphas: the room is always dark (a deep shade of the primary), so these read in both
  // app themes — the theme only changes the hue underneath them.
  static const Color textHigh = Color(0xFFFFFFFF);
  static const Color textMid = Color(0xB3FFFFFF);
  static const Color textLow = Color(0x66FFFFFF);
  static const Color glass = Color(0x1AFFFFFF);
  static const Color glassBorder = Color(0x30FFFFFF);
  static const Color scrim = Color(0x99000000);

  // ── Per-participant colour ─────────────────────────────────────────────────

  /// Stable hue (0 ≤ h < 360) for a participant name. Case and surrounding spaces are ignored, so
  /// "Ahmed" and " ahmed " agree. The hash stays below 2^53, so web (JS numbers) and mobile agree too.
  static double hueFor(String name) {
    final s = name.trim().toLowerCase();
    if (s.isEmpty) return HSLColor.fromColor(accent).hue;
    var h = 7;
    for (final c in s.codeUnits) {
      h = (h * 31 + c) % 1000003;
    }
    // Spread neighbouring names apart (golden-angle step) instead of landing on adjacent hues.
    return (h * 137.508) % 360;
  }

  /// The mid tone of a participant's colour: rings, glows, tints.
  static Color avatarColor(String name) =>
      HSLColor.fromAHSL(1, hueFor(name), 0.58, 0.47).toColor();

  /// The deep end of the gradient (hue nudged by 34°, darker).
  static Color avatarColorDeep(String name) =>
      HSLColor.fromAHSL(1, (hueFor(name) + 34) % 360, 0.62, 0.30).toColor();

  /// The gradient initials sit on.
  static LinearGradient avatarGradient(String name) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [avatarColor(name), avatarColorDeep(name)],
      );
}
