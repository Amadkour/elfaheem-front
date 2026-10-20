// lib/features/teacher/sessions/live/widgets/live_palette.dart
//
// The live classroom's colours, derived from the LIVE app theme (the one the super admin sets), so the room,
// pre-join and controls look like the rest of the app instead of a separate neon palette.
// The room stays dark (video needs it) — but it is a deep shade of YOUR primary colour.
// RoomPage / PreJoin call LivePalette.sync(context) at the top of build(); before the first sync the theme
// defaults (AppTheme) are used.
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
}
