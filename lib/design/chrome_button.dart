// lib/design/chrome_button.dart
// The one look of the small action buttons in the app's chrome — the desktop / tablet top bar (calendar, assistant,
// bell) and the home header (Meet now, calendar, bell on phones): a calm square in theme colours, never a loud
// orange / red fill (M7). A button finds out by itself where it sits: inside [ChromeBar] (the shell's top bar,
// drawn in the hero colour) it is glass on the bar; anywhere else it is a card-coloured square with a hairline.
//
//   ChromeIconButton(icon: Icons.event_rounded, label: 'my_calendar'.tr, onTap: …, badge: 3)
//
// Every button is a real button for screen readers and the keyboard (Semantics + focus + Enter / Space), with a
// tooltip, and keeps a 44 × 44 target.
library;

import 'package:flutter/material.dart';

import '../config/theme/theme_config_provider.dart';
import '../core/display/app_fonts.dart';

/// Marks its subtree as the shell's top bar (the hero-coloured band): [ChromeIconButton]s inside it draw as glass.
class ChromeBar extends InheritedWidget {
  const ChromeBar({super.key, required super.child});

  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<ChromeBar>() != null;

  @override
  bool updateShouldNotify(ChromeBar oldWidget) => false;
}

/// "9+" style count for the small badges.
String chromeBadgeText(int n) => n > 99 ? '99+' : '$n';

class ChromeIconButton extends StatelessWidget {
  const ChromeIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge = 0,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  /// A count drawn on the corner (0 = none); it is also read out after the label.
  final int badge;

  /// Shows a small spinner instead of the icon (and ignores taps).
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final onBar = ChromeBar.of(context);
    final bg = onBar ? c.heroGlass : c.cardBg;
    final ink = onBar ? c.onHero : c.textMedium;
    final border = onBar ? c.heroGlassBorder : c.divider;
    final semantic = badge > 0 ? '$label, ${chromeBadgeText(badge)}' : label;
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: semantic,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Material(
            color: bg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: border)),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: busy ? null : onTap,
              child: SizedBox.square(
                dimension: 44,
                child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
                  busy
                      ? SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: ink))
                      : Icon(icon, color: ink, size: 21),
                  if (badge > 0)
                    PositionedDirectional(
                      top: 6,
                      end: 5,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 16),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: c.danger,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: onBar ? c.primary : c.cardBg, width: 1.5),
                        ),
                        child: ExcludeSemantics(
                          child: Text(
                          chromeBadgeText(badge),
                          style: TextStyle(
                            fontFamily: AppFonts.family,
                            fontSize: 9.5,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                            color: c.onHero,
                          ),
                        ),
                        ),
                      ),
                    ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
