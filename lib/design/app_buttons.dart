// lib/design/app_buttons.dart
//
// The buttons of the design system (system.md §4, Warm Editorial):
//
//   AppButton.primary(label: 'save'.tr, onPressed: save, busy: saving)   solid emerald: the ONE main action of a screen
//   AppButton.secondary(...)  paper with an ink hairline     AppButton.tonal(...)   emerald tint, emerald ink
//   AppButton.ghost(...)      text only, primary ink         AppButton.danger(...)  danger fill (dangerOutline: paper + danger hairline)
//   AppIconButton(icon: Icons.edit, tooltip: 'edit'.tr, onPressed: …, badge: 3)
//   AppButtonRow(primary: …, secondary: [...])   the primary at the END in both directions, wraps at 320 px
//
// Geometry: sizes sm / md / lg are 40 / 48 / 56 high (sm keeps a 48 high hit area; lg is a phone's hero action),
// radius 14 (AppRadius.control), 24 px horizontal padding (16 on sm), the label at 15 · 600 (13 on sm), icon 20.
// A press scales to 0.97 (AppPressScale, parked under Reduce motion); keyboard focus draws a crisp 2 px ring OUTSIDE
// the button, a canvas-coloured gap between. busy draws a spinner over the label, which stays laid out, so the
// button never changes width; taps are ignored (no double submit). A disabled filled button is a flat neutral well
// with muted ink (no washed-out brand colour); the unfilled variants fade to 45 %. The label is one line (ellipsis).
// Colour (D-649): primary is the brand gradient primary → primary_dark on a soft primary-tinted shadow (a press
// deepens it); accent is the gold highlight CTA (accent2 → lighter, dark ink), sparingly; danger is the solid red;
// secondary, tonal and ghost stay flat.
library;

import 'package:flutter/material.dart';

import '../config/theme/theme_config_provider.dart';
import 'app_badges.dart';
import 'app_charts.dart' show appInk;
import 'app_contrast.dart' show ensureContrast;
import 'app_gradients.dart' show AppBrandLayer, AppBrandLabel, AppBrandSpan, AppGradientIcon;
import 'app_motion_kit.dart';
import 'app_tokens.dart';

enum AppButtonVariant { primary, secondary, tonal, ghost, danger, accent }

enum AppButtonSize { sm, md, lg }

double _heightOf(AppButtonSize s) => switch (s) {
      AppButtonSize.sm => 40,
      AppButtonSize.md => AppTouch.min,
      AppButtonSize.lg => AppTouch.primary,
    };

/// The focus ring every control in the kit draws OUTSIDE itself on keyboard focus: a 2 px gap in the surface colour,
/// then a 2 px line in [ring] (crisp — no blur). Painted as box shadows so it costs no layout and works on any shape.
List<BoxShadow> appFocusRing(BuildContext context, {Color? ring, Color? gap}) {
  final c = context.colors;
  return [
    BoxShadow(color: ring ?? ensureContrast(c.primary, [c.background, c.cardBg], min: 3), spreadRadius: AppBorder.focus * 2),
    BoxShadow(color: gap ?? c.background, spreadRadius: AppBorder.focus),
  ];
}

/// True while focus came from the keyboard (a tap must not light a ring).
bool appKeyboardFocus() => FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

class AppButton extends StatefulWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.trailingIcon,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.md,
    this.busy = false,
    this.expand = false,
    this.tooltip,
    this.dangerOutline = false,
  });

  const AppButton.primary({
    Key? key,
    required String label,
    required VoidCallback? onPressed,
    IconData? icon,
    IconData? trailingIcon,
    AppButtonSize size = AppButtonSize.md,
    bool busy = false,
    bool expand = false,
    String? tooltip,
  }) : this(
            key: key,
            label: label,
            onPressed: onPressed,
            icon: icon,
            trailingIcon: trailingIcon,
            size: size,
            busy: busy,
            expand: expand,
            tooltip: tooltip);

  /// The accent / premium button (D-649): a gold gradient with a dark ink, for a HIGHLIGHT call to action only — Go
  /// live on the hero, Upgrade, a featured offer. At most one per screen; the main action stays [AppButton.primary].
  const AppButton.accent({
    Key? key,
    required String label,
    required VoidCallback? onPressed,
    IconData? icon,
    IconData? trailingIcon,
    AppButtonSize size = AppButtonSize.md,
    bool busy = false,
    bool expand = false,
    String? tooltip,
  }) : this(
            key: key,
            label: label,
            onPressed: onPressed,
            icon: icon,
            trailingIcon: trailingIcon,
            variant: AppButtonVariant.accent,
            size: size,
            busy: busy,
            expand: expand,
            tooltip: tooltip);

  const AppButton.secondary({
    Key? key,
    required String label,
    required VoidCallback? onPressed,
    IconData? icon,
    IconData? trailingIcon,
    AppButtonSize size = AppButtonSize.md,
    bool busy = false,
    bool expand = false,
    String? tooltip,
  }) : this(
            key: key,
            label: label,
            onPressed: onPressed,
            icon: icon,
            trailingIcon: trailingIcon,
            variant: AppButtonVariant.secondary,
            size: size,
            busy: busy,
            expand: expand,
            tooltip: tooltip);

  const AppButton.tonal({
    Key? key,
    required String label,
    required VoidCallback? onPressed,
    IconData? icon,
    IconData? trailingIcon,
    AppButtonSize size = AppButtonSize.md,
    bool busy = false,
    bool expand = false,
    String? tooltip,
  }) : this(
            key: key,
            label: label,
            onPressed: onPressed,
            icon: icon,
            trailingIcon: trailingIcon,
            variant: AppButtonVariant.tonal,
            size: size,
            busy: busy,
            expand: expand,
            tooltip: tooltip);

  const AppButton.ghost({
    Key? key,
    required String label,
    required VoidCallback? onPressed,
    IconData? icon,
    IconData? trailingIcon,
    AppButtonSize size = AppButtonSize.md,
    bool busy = false,
    bool expand = false,
    String? tooltip,
  }) : this(
            key: key,
            label: label,
            onPressed: onPressed,
            icon: icon,
            trailingIcon: trailingIcon,
            variant: AppButtonVariant.ghost,
            size: size,
            busy: busy,
            expand: expand,
            tooltip: tooltip);

  const AppButton.danger({
    Key? key,
    required String label,
    required VoidCallback? onPressed,
    IconData? icon,
    IconData? trailingIcon,
    AppButtonSize size = AppButtonSize.md,
    bool busy = false,
    bool expand = false,
    String? tooltip,
    bool dangerOutline = false,
  }) : this(
            key: key,
            label: label,
            onPressed: onPressed,
            icon: icon,
            trailingIcon: trailingIcon,
            variant: AppButtonVariant.danger,
            size: size,
            busy: busy,
            expand: expand,
            tooltip: tooltip,
            dangerOutline: dangerOutline);

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final IconData? trailingIcon;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final bool busy;
  final bool expand;
  final String? tooltip;

  /// danger only: paper with a danger hairline and danger ink instead of the solid fill.
  final bool dangerOutline;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  /// Where the label sits, so the brand fill keeps its cream end past it (D-650 r2).
  final _span = AppBrandSpan();
  bool _pressed = false;
  bool _hover = false;
  bool _focus = false;

  bool get _enabled => widget.onPressed != null && !widget.busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final v = widget.variant;
    final outlineDanger = v == AppButtonVariant.danger && widget.dangerOutline;
    final filled = (v == AppButtonVariant.primary || v == AppButtonVariant.danger || v == AppButtonVariant.accent) && !outlineDanger;
    final h = _heightOf(widget.size);
    final sm = widget.size == AppButtonSize.sm;
    final disabled = widget.onPressed == null && !widget.busy;
    final lit = _enabled && (_pressed || _hover);
    final down = _enabled && _pressed;

    // the ink of an unfilled button: the primary (or the danger) made readable on the open mode's surface (appInk —
    // a deep emerald is fine on paper, far too dark on a dark card); a tonal button sits on its own translucent
    // tint over the card or the page or a tinted bar, so its ink is checked over every one of those
    final tonalInk = ensureContrast(appInk(context, c.primary), [
      for (final base in [c.cardBg, c.background]) ...[
        Color.alphaBlend(c.primaryTint, base),
        Color.alphaBlend(c.primaryTint, Color.alphaBlend(c.primaryTint, base)),
        Color.alphaBlend(Color.lerp(c.primaryTint, c.primary, 0.12)!, base),
      ],
    ]);
    final brand = AppBrandLayer.of(context);
    Color ink = switch (v) {
      AppButtonVariant.primary => brand.buttonInk,
      AppButtonVariant.accent => brand.goldInk,
      AppButtonVariant.danger => outlineDanger ? appInk(context, c.danger) : c.onHero,
      AppButtonVariant.secondary => c.textDark,
      AppButtonVariant.tonal => tonalInk,
      AppButtonVariant.ghost => appInk(context, c.primary),
    };
    if (disabled && filled) ink = c.textMedium;

    Color? fill;
    Gradient? gradient;
    var brandFill = false;
    List<BoxShadow>? shadow;
    BoxBorder? border;
    final inkHairline = Color.lerp(c.divider, c.textDark, 0.35)!;
    final hover = _hover && _enabled;
    switch (v) {
      case AppButtonVariant.primary:
        // D-650 r2: primary → cream past the label (AppBrandFill) on a soft primary-tinted shadow; hover and press deepen it
        brandFill = true;
        shadow = AppBrandLayer.buttonShadow(context, pressed: down);
      case AppButtonVariant.accent:
        gradient = AppBrandLayer.gold(context, hover: hover, pressed: down);
        shadow = AppBrandLayer.goldShadow(context, pressed: down);
      case AppButtonVariant.danger:
        if (outlineDanger) {
          fill = lit ? c.dangerTint : c.cardBg;
          border = Border.all(color: appInk(context, c.danger), width: AppBorder.strong);
        } else {
          fill = down ? Color.lerp(c.danger, c.textDark, 0.22) : _hover && _enabled ? Color.lerp(c.danger, c.textDark, 0.1) : c.danger;
        }
      case AppButtonVariant.secondary:
        fill = down ? Color.lerp(c.cardBg, c.textDark, 0.08) : lit ? Color.lerp(c.cardBg, c.textDark, 0.04) : c.cardBg;
        border = Border.all(color: down ? c.textDark : inkHairline, width: AppBorder.hairline);
      case AppButtonVariant.tonal:
        fill = down ? Color.lerp(c.primaryTint, c.primary, 0.14) : lit ? Color.lerp(c.primaryTint, c.primary, 0.06) : c.primaryTint;
      case AppButtonVariant.ghost:
        fill = down ? Color.lerp(c.primaryTint, c.primary, 0.06) : lit ? c.primaryTint : null;
    }
    if (disabled && filled) {
      // a flat neutral well: the brand colour is never washed out (an unreadable half-transparent fill)
      fill = c.inputBg;
      gradient = null;
      brandFill = false;
      shadow = null;
      border = Border.all(color: c.divider, width: AppBorder.hairline);
    }

    final style = AppType.row(context).copyWith(
      color: ink,
      fontWeight: FontWeight.w600,
      fontSize: sm ? 13 : 15,
      height: 1.2,
    );
    final radius = AppRadius.controlAll;
    final motion = AppMotion.of(context);

    final spinner = SizedBox(
      width: AppIconSize.md,
      height: AppIconSize.md,
      child: CircularProgressIndicator(strokeWidth: 2.2, color: ink),
    );

    // the label row hugs its glyphs (AppBrandLabel measures it); a full-width button centres it in the width
    Widget content = AppBrandLabel(
      span: _span,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.icon != null) ...[
            Icon(widget.icon, size: AppIconSize.md, color: ink),
            const SizedBox(width: AppSpace.xs),
          ],
          Flexible(child: Text(widget.label, maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false, style: style)),
          if (widget.trailingIcon != null) ...[
            const SizedBox(width: AppSpace.xs),
            Icon(widget.trailingIcon, size: AppIconSize.md, color: ink),
          ],
        ],
      ),
    );
    if (widget.expand) {
      content = Row(mainAxisAlignment: MainAxisAlignment.center, children: [Flexible(child: content)]);
    }

    // busy: the label keeps its place (invisible) under the spinner, so the width never jumps
    final body = Stack(alignment: Alignment.center, children: [
      AnimatedOpacity(opacity: widget.busy ? 0 : 1, duration: motion.fast, curve: AppEase.out, child: content),
      if (widget.busy) spinner,
    ]);

    Widget visual = AnimatedContainer(
      duration: motion.fast,
      curve: AppEase.out,
      height: h,
      decoration: brandFill
          ? AppBrandLayer.buttonFill(
              context,
              hover: hover,
              pressed: down,
              span: _span,
              borderRadius: radius,
              boxShadow: _focus && _enabled && appKeyboardFocus() ? appFocusRing(context) : shadow,
            )
          : BoxDecoration(
              color: gradient == null ? fill : null,
              gradient: gradient,
              borderRadius: radius,
              border: border,
              boxShadow: _focus && _enabled && appKeyboardFocus()
                  ? appFocusRing(context, ring: v == AppButtonVariant.danger ? appInk(context, c.danger) : null)
                  : shadow,
            ),
      padding: EdgeInsetsDirectional.symmetric(horizontal: sm ? AppSpace.md : AppSpace.lg),
      child: body,
    );

    Widget out = InkWell(
      onTap: _enabled ? widget.onPressed : null,
      onHighlightChanged: (v) => setState(() => _pressed = v),
      onHover: (v) => setState(() => _hover = v),
      onFocusChange: (v) => setState(() => _focus = v),
      borderRadius: radius,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      focusColor: Colors.transparent,
      mouseCursor: _enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppTouch.min, minWidth: AppTouch.min),
        child: Center(
          widthFactor: widget.expand ? null : 1,
          child: AppPressScale(scale: 0.97, enabled: _enabled, child: visual),
        ),
      ),
    );

    out = Opacity(opacity: disabled && !filled ? 0.45 : 1, child: Material(type: MaterialType.transparency, child: out));
    out = Semantics(
      button: true,
      enabled: _enabled,
      label: widget.label,
      excludeSemantics: true,
      onTap: _enabled ? widget.onPressed : null,
      child: out,
    );
    if (widget.tooltip != null) out = Tooltip(message: widget.tooltip!, child: out);
    return widget.expand ? SizedBox(width: double.infinity, child: out) : out;
  }
}

enum AppIconButtonVariant { standard, tonal, filled }

/// An icon-only button: a 40 px square (radius 10, concentric with the 48 px hit area at 14) — standard draws the
/// icon alone, tonal on the emerald tint, filled on the solid primary. [tooltip] is required: it is the tooltip and
/// the screen reader label.
class AppIconButton extends StatefulWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.variant = AppIconButtonVariant.standard,
    this.badge = 0,
    this.busy = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final AppIconButtonVariant variant;

  /// A count drawn on the top-end corner (0 = none).
  final int badge;
  final bool busy;

  @override
  State<AppIconButton> createState() => _AppIconButtonState();
}

class _AppIconButtonState extends State<AppIconButton> {
  bool _hover = false;
  bool _focus = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = widget.onPressed != null && !widget.busy;
    final filled = widget.variant == AppIconButtonVariant.filled;
    final tonal = widget.variant == AppIconButtonVariant.tonal;
    final lit = enabled && (_hover || _pressed);
    final ink = filled
        ? c.onHero
        : tonal
            ? ensureContrast(appInk(context, c.primary), [Color.alphaBlend(c.primaryTint, c.cardBg)])
            : lit
                ? c.textDark
                : c.textMedium;
    // D-649: filled wears the brand gradient, tonal (a primary action's icon chip) a subtle tint gradient at rest
    final Gradient? gradient = filled && enabled
        ? null
        : tonal && !lit
            ? AppBrandLayer.iconTint(context)
            : null;
    final Color? fill = filled
        ? c.primary
        : tonal
            ? (lit ? Color.lerp(c.primaryTint, c.primary, 0.08) : c.primaryTint)
            : (lit ? c.inputBg : null);
    final motion = AppMotion.of(context);
    final visual = AnimatedContainer(
      duration: motion.fast,
      curve: AppEase.out,
      width: AppTouch.min - AppSpace.xs,
      height: AppTouch.min - AppSpace.xs,
      alignment: Alignment.center,
      // D-650 r2: filled wears the brand fill, its cream end past the centred glyph
      decoration: filled && enabled
          ? AppBrandLayer.buttonFill(
              context,
              hover: lit && !_pressed,
              pressed: _pressed,
              content: AppIconSize.lg,
              borderRadius: AppRadius.chipAll,
              boxShadow: _focus && appKeyboardFocus() ? appFocusRing(context) : null,
            )
          : BoxDecoration(
              color: gradient == null ? fill : null,
              gradient: gradient,
              borderRadius: AppRadius.chipAll,
              boxShadow: _focus && enabled && appKeyboardFocus() ? appFocusRing(context) : null,
            ),
      child: widget.busy
          ? SizedBox(
              width: AppIconSize.md,
              height: AppIconSize.md,
              child: CircularProgressIndicator(strokeWidth: 2.2, color: ink))
          // D-650: a tonal (primary action) chip's glyph wears the green → gold family at rest
          : tonal && enabled && !lit
              ? AppGradientIcon(widget.icon, size: AppIconSize.lg, on: [for (final b in [c.cardBg, c.background]) Color.alphaBlend(c.primaryTint, b)])
              : Icon(widget.icon, size: AppIconSize.lg, color: ink),
    );
    Widget out = SizedBox(
      width: AppTouch.min,
      height: AppTouch.min,
      child: InkWell(
        onTap: enabled ? widget.onPressed : null,
        onHighlightChanged: (v) => setState(() => _pressed = v),
        onHover: (v) => setState(() => _hover = v),
        onFocusChange: (v) => setState(() => _focus = v),
        borderRadius: AppRadius.controlAll,
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        mouseCursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: Center(
          child: AppPressScale(
            scale: 0.94,
            enabled: enabled,
            child: widget.badge > 0 ? AppCountBadge(count: widget.badge, child: visual) : visual,
          ),
        ),
      ),
    );
    out = Opacity(
        opacity: widget.onPressed == null && !widget.busy ? 0.45 : 1,
        child: Material(type: MaterialType.transparency, child: out));
    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: widget.badge > 0 ? '${widget.tooltip}, ${appCountText(widget.badge)}' : widget.tooltip,
        excludeSemantics: true,
        onTap: enabled ? widget.onPressed : null,
        child: out,
      ),
    );
  }
}

/// A primary action with its secondary ones. The primary sits at the END in both directions (secondaries first in
/// the children order, which is start-to-end). Wraps onto more lines when the width runs out, so 320 px never overflows.
class AppButtonRow extends StatelessWidget {
  const AppButtonRow({super.key, required this.primary, this.secondary = const []});

  final Widget primary;
  final List<Widget> secondary;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.end,
      runAlignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpace.sm,
      runSpacing: AppSpace.xs,
      children: [...secondary, primary],
    );
  }
}
