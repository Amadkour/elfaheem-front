// lib/design/chrome_button.dart
// The one look of the small action buttons in the app's chrome — the desktop / tablet top bar (calendar, assistant,
// bell), the home header (Meet now, calendar, bell on phones) and the page headers: a paper chip in ink (D-612),
// never a loud orange / red fill (M7). A button finds out by itself where it sits: inside [ChromeBar] (the shell's
// top bar, drawn in the hero colour) it is glass on the bar; anywhere else it is a paper chip — the card surface
// with a warm hairline — on the canvas.
//
//   ChromeIconButton(icon: Icons.event_rounded, label: 'my_calendar'.tr, onTap: …, badge: 3)
//   ChromePlate(onTap: …, child: Icon(…))     the bare plate (AppBackButton is one with the back arrow)
//
// Every button is a real button for screen readers and the keyboard (Semantics + focus + Enter / Space), with a
// tooltip, keeps a 48 × 48 target around a 40 × 40 plate, and presses with a little depth (zero under Reduce
// motion).
library;

import 'package:flutter/material.dart';

import '../config/theme/theme_config_provider.dart';
import 'app_tokens.dart';

/// Marks its subtree as the shell's top bar (the hero-coloured band): [ChromeIconButton]s inside it draw as glass.
class ChromeBar extends InheritedWidget {
  const ChromeBar({super.key, required super.child});

  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<ChromeBar>() != null;

  @override
  bool updateShouldNotify(ChromeBar oldWidget) => false;
}

/// "9+" style count for the small badges.
String chromeBadgeText(int n) => n > 99 ? '99+' : '$n';

/// The chip itself: a 40 × 40 plate centred in a 48 × 48 target, paper on the canvas (card surface + hairline) or
/// glass on a hero band ([onHero], or inside a [ChromeBar]), with the press depth of the kit.
class ChromePlate extends StatefulWidget {
  const ChromePlate({super.key, required this.child, required this.onTap, this.onHero, this.onHighlightChanged});

  final Widget child;
  final VoidCallback? onTap;

  /// Glass on a hero surface; null reads the nearest [ChromeBar].
  final bool? onHero;
  final ValueChanged<bool>? onHighlightChanged;

  /// The plate inside the target.
  static const double size = AppTouch.min - AppSpace.xs;

  /// The plate's surface and ink where it sits.
  static ({Color plate, Color border, Color ink}) colorsOf(BuildContext context, {required bool onHero}) {
    final c = context.colors;
    return onHero
        ? (plate: c.heroGlass, border: c.heroGlassBorder, ink: c.onHero)
        : (plate: c.cardBg, border: c.divider, ink: c.textDark);
  }

  @override
  State<ChromePlate> createState() => _ChromePlateState();
}

class _ChromePlateState extends State<ChromePlate> {
  bool _down = false;

  void _press(bool down) {
    if (_down != down) setState(() => _down = down);
    widget.onHighlightChanged?.call(down);
  }

  @override
  Widget build(BuildContext context) {
    final onHero = widget.onHero ?? ChromeBar.of(context);
    final k = ChromePlate.colorsOf(context, onHero: onHero);
    return SizedBox(
      width: AppTouch.min,
      height: AppTouch.min,
      child: Center(
        child: AnimatedScale(
          scale: _down ? 0.94 : 1,
          duration: AppMotion.of(context).fast,
          curve: AppMotion.curve,
          child: Material(
            color: k.plate,
            shape: RoundedRectangleBorder(
              borderRadius: AppRadius.chipAll,
              side: BorderSide(color: k.border, width: AppBorder.hairline),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.onTap,
              onHighlightChanged: _press,
              mouseCursor: widget.onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
              child: SizedBox.square(
                dimension: ChromePlate.size,
                child: IconTheme.merge(data: IconThemeData(color: k.ink, size: AppIconSize.md), child: widget.child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

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

  /// How far the count pill sits in from the plate's corner.
  static const double _badgeInset = 2;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final onBar = ChromeBar.of(context);
    final k = ChromePlate.colorsOf(context, onHero: onBar);
    final semantic = badge > 0 ? '$label, ${chromeBadgeText(badge)}' : label;
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: semantic,
        child: ChromePlate(
          onHero: onBar,
          onTap: busy ? null : onTap,
          child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
            busy
                ? SizedBox.square(
                    dimension: AppIconSize.sm,
                    child: CircularProgressIndicator(strokeWidth: AppBorder.focus, color: k.ink),
                  )
                : Icon(icon),
            if (badge > 0)
              PositionedDirectional(
                top: _badgeInset,
                end: _badgeInset,
                child: Container(
                  constraints: const BoxConstraints(minWidth: AppIconSize.sm, minHeight: AppIconSize.sm),
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.danger,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: Border.all(color: k.plate, width: AppBorder.strong),
                  ),
                  child: ExcludeSemantics(
                    child: Text(
                      chromeBadgeText(badge),
                      maxLines: 1,
                      style: AppType.overline(context).copyWith(color: c.onHero, height: 1.2, letterSpacing: 0),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
