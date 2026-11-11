// lib/design/chrome_button.dart
// The one look of the small action buttons in the app's chrome — the desktop / tablet top bar (calendar, assistant,
// bell), the home header (Meet now, calendar, bell on phones) and the page headers: never a loud orange / red fill
// (M7). A button finds out by itself where it sits: inside [ChromeBar] (the forest home hero, a hero band) it is a
// translucent cream plate on it; anywhere else it is a GHOST on the canvas (D-630: seven white boxed chips along a
// top bar were noise) — no plate, no border, the ink icon, a soft ink tint on hover / press and the focus ring.
//
//   ChromeIconButton(icon: Icons.event_rounded, label: 'my_calendar'.tr, onTap: …, badge: 3)
//   ChromePlate(onTap: …, child: Icon(…))     the bare plate (AppBackButton is one with the back arrow)
//   ChromeGhost(child: …)                      the buttons inside draw as GHOSTS: no plate and no hairline until
//                                              hovered / pressed, the count a small dot-sized pill (the desktop top
//                                              bar and the sidebar header, D-631)
//
// Every button is a real button for screen readers and the keyboard (Semantics + focus + Enter / Space), with a
// tooltip, keeps a 48 × 48 target around a 40 × 40 plate, and presses with a little depth (zero under Reduce
// motion).
library;

import 'package:flutter/material.dart';

import '../config/theme/theme_config_provider.dart';
import 'app_gradients.dart' show AppBrandLayer, AppGradientIcon;
import 'app_tokens.dart';

/// Marks its subtree as the shell's top bar (the hero-coloured band): [ChromeIconButton]s inside it draw as glass.
class ChromeBar extends InheritedWidget {
  const ChromeBar({super.key, required super.child});

  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<ChromeBar>() != null;

  @override
  bool updateShouldNotify(ChromeBar oldWidget) => false;
}

/// Marks its subtree as a surface whose chrome buttons are ghosts (the shell's paper top bar, D-631).
class ChromeGhost extends InheritedWidget {
  const ChromeGhost({super.key, required super.child});

  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<ChromeGhost>() != null;

  @override
  bool updateShouldNotify(ChromeGhost oldWidget) => false;
}

/// The floating chrome card (D-648, the Spike-style shell): the sidebar, the top bar and every pushed page's header
/// are one white rounded card on the canvas — the card surface, the card radius, a whisper of shadow (a hairline in
/// dark mode, where a shadow does not show) and no rule under it. Its own [Material] carries the ink of the buttons
/// inside, and the chrome buttons inside draw as ghosts ([ChromeGhost]).
///
///   ChromeCard(margin: EdgeInsets.all(AppSpace.lg), child: Row(…))
class ChromeCard extends StatelessWidget {
  const ChromeCard({super.key, required this.child, this.margin = EdgeInsets.zero, this.height, this.padding});

  final Widget child;

  /// The inset from the window / the neighbouring chrome (the page gutter).
  final EdgeInsetsGeometry margin;

  /// A fixed height (the shell's top bar); null = the child's.
  final double? height;
  final EdgeInsetsGeometry? padding;

  /// The bar height every floating top bar shares: a touch target with its breathing room.
  static const double barHeight = AppTouch.min + AppSpace.md;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(AppRadius.card);
    Widget body = ChromeGhost(child: child);
    if (padding != null) body = Padding(padding: padding!, child: body);
    if (height != null) body = SizedBox(height: height, child: body);
    return Padding(
      padding: margin,
      child: DecoratedBox(
        decoration: BoxDecoration(borderRadius: radius, boxShadow: AppElevation.of(context, 1)),
        child: Material(
          color: c.cardBg,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: c.isDark ? BorderSide(color: c.divider, width: AppBorder.hairline) : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: body,
        ),
      ),
    );
  }
}

/// "9+" style count for the small badges.
String chromeBadgeText(int n) => n > 99 ? '99+' : '$n';

/// The chip itself: a 40 × 40 plate centred in a 48 × 48 target, a ghost on the canvas (transparent until hovered /
/// pressed) or glass on a hero ([onHero], or inside a [ChromeBar]), with the press depth of the kit and a focus ring.
class ChromePlate extends StatefulWidget {
  const ChromePlate({super.key, required this.child, required this.onTap, this.onHero, this.onHighlightChanged});

  final Widget child;
  final VoidCallback? onTap;

  /// Glass on a hero surface; null reads the nearest [ChromeBar].
  final bool? onHero;
  final ValueChanged<bool>? onHighlightChanged;

  /// The plate inside the target.
  static const double size = AppTouch.min - AppSpace.xs;

  /// The plate's surface and ink where it sits (a ghost's plate and border are transparent).
  static ({Color plate, Color border, Color ink}) colorsOf(BuildContext context, {required bool onHero}) {
    final c = context.colors;
    if (onHero) return (plate: c.heroGlass, border: c.heroGlassBorder, ink: c.onHero);
    // off a hero every button is a ghost (D-630); on the shell's paper bar ([ChromeGhost], D-631) its ink is the quieter one
    return (plate: Colors.transparent, border: Colors.transparent, ink: ChromeGhost.of(context) ? c.textMedium : c.textDark);
  }

  /// The colour a count badge is ringed with so it parts from what is under it.
  static Color badgeRing(BuildContext context, {required bool onHero}) =>
      onHero ? colorsOf(context, onHero: true).plate : context.colors.background;

  @override
  State<ChromePlate> createState() => _ChromePlateState();
}

class _ChromePlateState extends State<ChromePlate> {
  bool _down = false;
  bool _focused = false;

  void _press(bool down) {
    if (_down != down) setState(() => _down = down);
    widget.onHighlightChanged?.call(down);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final onHero = widget.onHero ?? ChromeBar.of(context);
    final k = ChromePlate.colorsOf(context, onHero: onHero);
    // hover / press: a soft wash of the ink (the ghost has no plate of its own to darken)
    final wash = k.ink.withValues(alpha: c.isDark || onHero ? 0.14 : 0.08);
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
              side: _focused
                  ? BorderSide(color: onHero ? k.ink : c.primary, width: AppBorder.focus)
                  : BorderSide(color: k.border, width: AppBorder.hairline),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.onTap,
              onHighlightChanged: _press,
              onFocusChange: (f) => setState(() => _focused = f),
              hoverColor: wash,
              highlightColor: wash,
              splashColor: wash,
              focusColor: wash,
              mouseCursor: widget.onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
              child: SizedBox.square(
                dimension: ChromePlate.size,
                // a button with nothing to do looks it on purpose: the ink at the disabled emphasis, never a faint
                // look-alike of an enabled one (a busy button's spinner keeps its own ink)
                child: IconTheme.merge(
                  data: IconThemeData(color: widget.onTap == null ? k.ink.withValues(alpha: 0.38) : k.ink, size: AppIconSize.md),
                  child: widget.child,
                ),
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
                // D-650 r3: the glyph wears the brand family, matched to the plate it sits on
                : AppGradientIcon(icon, on: onBar
                    ? [for (final s in [AppBrandLayer.of(context).sidebar.first, c.blockForest]) Color.alphaBlend(k.plate, s)]
                    : [c.cardBg, c.background]),
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
                    // a count on the shell's paper bar rings itself with the paper, elsewhere with what is under it
                    border: Border.all(color: ChromeGhost.of(context) && !onBar ? c.cardBg : ChromePlate.badgeRing(context, onHero: onBar), width: AppBorder.strong),
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
