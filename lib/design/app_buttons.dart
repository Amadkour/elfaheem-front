// lib/design/app_buttons.dart
//
// The buttons of the design system (KIT_SPEC §5.4, the redesign kit):
//
//   AppButton.primary(label: 'save'.tr, onPressed: save, busy: saving)   the area set's button gradient: the ONE
//                             main action of a screen (one filled button above the fold on a student phone screen)
//   AppButton.hot(...)        the forward button (gold, dark ink): only for the action that moves the student on
//   AppButton.secondary(...)  card fill, the kit line, area ink    AppButton.tonal(...)   area tint, area ink
//   AppButton.ghost(...)      a link: text only, area ink          AppButton.danger(...)  danger fill (dangerOutline:
//                             card + the kit error ink and a darkened error-tint edge)
//   AppIconButton(icon: Icons.edit, tooltip: 'edit'.tr, onPressed: …, badge: 3)
//   AppButtonRow(primary: …, secondary: [...])   the primary at the END in both directions, wraps at 320 px
//
// Geometry: sizes sm / md / lg are 40 / 48 / 56 high (sm keeps a 48 high hit area; lg is a phone's hero action),
// a full pill (AppRadius.pill), 24 px horizontal padding (16 on sm), the label at 15 · 600 (13 on sm), icon 20.
// A press squashes (AppJelly, M9) on primary / hot / tonal / secondary, scales on ghost / danger; under a mouse a
// filled button rises 2 px. Keyboard focus draws a crisp 2 px ring in the kit partner OUTSIDE the button. busy draws
// a spinner over the label, which stays laid out, so the button never changes width; taps are ignored. A disabled
// filled button is a flat neutral well with muted ink; the unfilled variants fade to 45 %. The label is one line.
// Colour: every variant reads the nearest AppAreaScope (a student area or a role accent; none = home): primary the
// set's button gradient and `btnFg` on `AppShadow.button`; hot the kit's hot gradient and `hotFg`. `accent` is the
// old name of `hot`.
library;

import 'package:flutter/material.dart';

import '../config/theme/theme_config_provider.dart';
import 'app_badges.dart';
import 'app_charts.dart' show appInk;
import 'app_contrast.dart' show ensureContrast;
import 'app_area.dart';
import 'app_gradients.dart' show AppBrandLayer, AppGradientIcon;
import 'app_motion_kit.dart';
import 'app_tokens.dart';

enum AppButtonVariant {
  primary,
  secondary,
  tonal,
  ghost,
  danger,
  @Deprecated('Use AppButtonVariant.hot')
  accent,
  hot,
}

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

  /// The forward button (KIT_SPEC §5.4, P4): the kit's gold hot gradient with the deep ink, only for the action that
  /// moves the student forward. Same parameters as [AppButton.primary].
  const AppButton.hot({
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
            variant: AppButtonVariant.hot,
            size: size,
            busy: busy,
            expand: expand,
            tooltip: tooltip);

  /// The old name of [AppButton.hot]; draws exactly like it.
  @Deprecated('Use AppButton.hot')
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
            // ignore: deprecated_member_use_from_same_package
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
  bool _pressed = false;
  bool _hover = false;
  bool _focus = false;

  bool get _enabled => widget.onPressed != null && !widget.busy;

  AppButtonVariant get _variant =>
      // ignore: deprecated_member_use_from_same_package
      widget.variant == AppButtonVariant.accent ? AppButtonVariant.hot : widget.variant;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final kit = c.kit;
    final set = AppAreaScope.of(context);
    final v = _variant;
    final outlineDanger = v == AppButtonVariant.danger && widget.dangerOutline;
    final filled = (v == AppButtonVariant.primary || v == AppButtonVariant.danger || v == AppButtonVariant.hot) &&
        !outlineDanger;
    final h = _heightOf(widget.size);
    final sm = widget.size == AppButtonSize.sm;
    final disabled = widget.onPressed == null && !widget.busy;
    final lit = _enabled && (_pressed || _hover);
    final down = _enabled && _pressed;
    final hover = _hover && _enabled;
    final error = kit.error;

    Color ink = switch (v) {
      AppButtonVariant.primary => set.btnFg,
      AppButtonVariant.danger => outlineDanger ? error.color : c.onHero,
      AppButtonVariant.secondary || AppButtonVariant.tonal || AppButtonVariant.ghost => set.ink,
      _ => kit.hotFg,
    };
    if (disabled && filled) ink = c.textMedium;

    Color? fill;
    Gradient? gradient;
    List<BoxShadow>? shadow;
    BoxBorder? border;
    switch (v) {
      case AppButtonVariant.primary:
        gradient = set.button;
        shadow = down ? null : AppShadow.button(context, set.btnA);
      case AppButtonVariant.danger:
        if (outlineDanger) {
          fill = lit ? error.tint : c.cardBg;
          border = Border.all(color: Color.lerp(error.tint, error.color, .25)!, width: AppBorder.strong);
        } else {
          fill = down
              ? Color.lerp(c.dangerBase, c.textDark, 0.22)
              : hover
                  ? Color.lerp(c.dangerBase, c.textDark, 0.1)
                  : c.dangerBase;
        }
      case AppButtonVariant.secondary:
        fill = down ? Color.lerp(c.cardBg, set.tint, 0.6) : lit ? Color.lerp(c.cardBg, set.tint, 0.3) : c.cardBg;
        border = Border.all(color: lit ? Color.lerp(kit.line, set.ink, 0.3)! : kit.line, width: AppBorder.strong);
      case AppButtonVariant.tonal:
        fill = down ? Color.lerp(set.tint, set.a, 0.14) : lit ? Color.lerp(set.tint, set.a, 0.06) : set.tint;
      case AppButtonVariant.ghost:
        fill = down ? Color.lerp(set.tint, set.a, 0.06) : lit ? set.tint : null;
      default: // hot (and its old name, accent)
        gradient = kit.hotButton;
        shadow = down ? null : AppShadow.button(context, kit.hotB);
    }
    if (disabled && filled) {
      // a flat neutral well: the brand colour is never washed out (an unreadable half-transparent fill)
      fill = c.inputBg;
      gradient = null;
      shadow = null;
      border = Border.all(color: c.divider, width: AppBorder.hairline);
    }

    final style = AppType.row(context).copyWith(
      color: ink,
      fontWeight: FontWeight.w600,
      fontSize: sm ? 13 : 15,
      height: 1.2,
    );
    final radius = BorderRadius.circular(AppRadius.pill);
    final motion = AppMotion.of(context);

    final spinner = SizedBox(
      width: AppIconSize.md,
      height: AppIconSize.md,
      child: CircularProgressIndicator(strokeWidth: 2.2, color: ink),
    );

    Widget content = Row(
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
    );
    if (widget.expand) {
      content = Row(mainAxisAlignment: MainAxisAlignment.center, children: [Flexible(child: content)]);
    }

    // busy: the label keeps its place (invisible) under the spinner, so the width never jumps
    final body = Stack(alignment: Alignment.center, children: [
      AnimatedOpacity(opacity: widget.busy ? 0 : 1, duration: motion.fast, curve: AppEase.out, child: content),
      if (widget.busy) spinner,
    ]);

    final focusRing = _focus && _enabled && appKeyboardFocus()
        ? appFocusRing(context, ring: v == AppButtonVariant.danger ? error.color : kit.partner)
        : null;
    final rise = filled && hover && !down && !motion.off;
    final visual = AnimatedContainer(
      duration: motion.fast,
      curve: AppEase.out,
      height: h,
      transform: Matrix4.translationValues(0, rise ? -AppBorder.focus : 0, 0),
      decoration: BoxDecoration(
        color: gradient == null ? fill : null,
        gradient: gradient,
        borderRadius: radius,
        border: border,
        boxShadow: focusRing ?? shadow,
      ),
      padding: EdgeInsetsDirectional.symmetric(horizontal: sm ? AppSpace.md : AppSpace.lg),
      child: body,
    );

    final jelly = v == AppButtonVariant.primary ||
        v == AppButtonVariant.hot ||
        v == AppButtonVariant.tonal ||
        v == AppButtonVariant.secondary;
    final Widget pressed = jelly
        ? AppJelly(enabled: _enabled, wide: widget.expand, child: visual)
        : AppPressScale(scale: 0.97, enabled: _enabled, child: visual);

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
        child: Center(widthFactor: widget.expand ? null : 1, child: pressed),
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

/// An icon-only button in a 48 px hit area. Standard is the kit's round button (KIT_SPEC §5.4: a 42 px circle on the
/// card with a `kit.line` edge); [onHero] draws it 38 px on the hero glass with the on-hero ink (the phone top bar);
/// tonal (a 40 px square on the primary tint) and filled (on the brand fill) are unchanged. [tooltip] is required: it
/// is the tooltip and the screen reader label.
class AppIconButton extends StatefulWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.variant = AppIconButtonVariant.standard,
    this.badge = 0,
    this.busy = false,
    this.onHero = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final AppIconButtonVariant variant;

  /// On a hero / the phone top bar: 38 px glass with the on-hero ink (standard variant only).
  final bool onHero;

  /// The visual size of the round standard button on a hero (in its 48 px hit area).
  static const double heroSize = 38;

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
    final round = !filled && !tonal;
    final hero = round && widget.onHero;
    final ink = filled || hero
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
            : hero
                ? (lit ? Color.alphaBlend(c.heroGlass, c.heroGlass) : c.heroGlass)
                : (lit ? Color.alphaBlend(c.kit.well, c.cardBg) : c.cardBg);
    final motion = AppMotion.of(context);
    final side = hero ? AppIconButton.heroSize : round ? AppDashSize.glyph : AppTouch.min - AppSpace.xs;
    final visual = AnimatedContainer(
      duration: motion.fast,
      curve: AppEase.out,
      width: side,
      height: side,
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
              shape: round ? BoxShape.circle : BoxShape.rectangle,
              borderRadius: round ? null : AppRadius.chipAll,
              border: round
                  ? Border.all(color: hero ? c.heroGlassBorder : c.kit.line, width: AppBorder.strong)
                  : null,
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
              : Icon(widget.icon, size: round ? AppIconSize.md : AppIconSize.lg, color: ink),
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
