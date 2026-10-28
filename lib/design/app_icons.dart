// lib/design/app_icons.dart
//
// Material icons that point somewhere but do NOT mirror themselves in a right-to-left layout.
//
// Flutter mirrors an icon in Arabic only when its IconData says `matchTextDirection: true`. arrow_back / forward,
// chevron_left / right, arrow_*_ios, navigate_*, send, open_in_new … already do (so never pick one of them by
// language: that flips them twice). The icons below do not, so in Arabic "log out" pointed into the app and a
// "reply" arrow pointed the wrong way. These are the same glyphs with the flag set; use them instead of the
// Icons.* names (they are const, so `const Icon(DirIcons.logout)` still works and the icon font tree-shaker
// keeps the code points).
//
// CupertinoIcons: use `CupertinoIcons.back` / `CupertinoIcons.forward` (they mirror), not `chevron_back` /
// `chevron_forward` (same glyphs, they do not).
library;

import 'package:flutter/widgets.dart';

abstract final class DirIcons {
  static const IconData logout = IconData(0xf88b, fontFamily: 'MaterialIcons', matchTextDirection: true);
  static const IconData login = IconData(0xf88a, fontFamily: 'MaterialIcons', matchTextDirection: true);
  static const IconData exitToApp = IconData(0xf71e, fontFamily: 'MaterialIcons', matchTextDirection: true);

  /// The "child of" / "nested under" arrow: points from the start side into the item.
  static const IconData subArrowLeft = IconData(0xf01e9, fontFamily: 'MaterialIcons', matchTextDirection: true);
  static const IconData subArrowRight = IconData(0xf01ea, fontFamily: 'MaterialIcons', matchTextDirection: true);

  /// "Goes up / out to" (escalated, follow-up question): leans toward the reading direction's end.
  static const IconData northEast = IconData(0xf0019, fontFamily: 'MaterialIcons', matchTextDirection: true);
  static const IconData arrowOutward = IconData(0xf087d, fontFamily: 'MaterialIcons', matchTextDirection: true);
}
