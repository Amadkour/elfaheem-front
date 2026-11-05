// lib/design/app_buttons.dart
//
// The buttons of the design system.
//
//   AppButton.primary(label: 'save'.tr, onPressed: save, busy: saving)   brand gradient: the ONE main action of a screen
//   AppButton.secondary(...)  outlined, primary ink        AppButton.tonal(...)  primaryTint fill
//   AppButton.ghost(...)      text only                    AppButton.danger(...) danger fill (dangerOutline: true = lighter)
//   AppIconButton(icon: Icons.edit, tooltip: 'edit'.tr, onPressed: …, badge: 3)
//   AppButtonRow(primary: …, secondary: [...])   the primary at the END in both directions, wraps at 320 px
//
// Sizes sm / md / lg are 40 / 48 / 56 high; sm still has a 48 high hit area. busy swaps the icon for a spinner and
// ignores taps (no double submit). A disabled button is 45 % opaque without ripple. The label is one line (ellipsis).
library;

import 'package:flutter/material.dart';

import '../config/theme/theme_config_provider.dart';
import 'app_badges.dart';
import 'app_charts.dart' show appInk;
import 'app_gradients.dart';
import 'app_tokens.dart';

enum AppButtonVariant { primary, secondary, tonal, ghost, danger }

enum AppButtonSize { sm, md, lg }

double _heightOf(AppButtonSize s) => switch (s) {
      AppButtonSize.sm => 40,
      AppButtonSize.md => AppTouch.min,
      AppButtonSize.lg => AppTouch.primary,
    };

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

  /// danger only: an outlined button with danger ink instead of the solid fill.
  final bool dangerOutline;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _pressed = false;
  bool _hover = false;
  bool _focus = false;

  bool get _enabled => widget.onPressed != null && !widget.busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final v = widget.variant;
    final outlineDanger = v == AppButtonVariant.danger && widget.dangerOutline;
    final filled = (v == AppButtonVariant.primary || v == AppButtonVariant.danger) && !outlineDanger;
    final h = _heightOf(widget.size);
    final disabled = widget.onPressed == null && !widget.busy;

    // text / icon ink of an unfilled button: the primary made readable on the open mode's surface (appInk — the raw
    // indigo is about 1.6:1 on a dark card); fills and borders keep the raw tone
    final Color ink = filled
        ? c.onHero
        : outlineDanger
            ? c.danger
            : appInk(context, c.primary);
    final fs = switch (widget.size) {
      AppButtonSize.sm => 13.0,
      AppButtonSize.md => 14.0,
      AppButtonSize.lg => 16.0,
    };
    final style = AppType.row(context).copyWith(color: ink, fontWeight: FontWeight.w600, fontSize: fs, height: 1.2);

    final radius = BorderRadius.circular(h >= AppTouch.primary ? AppRadius.card : AppRadius.card - 2);
    final lit = _enabled && (_pressed || _hover);

    Gradient? gradient;
    Color? fill;
    BoxBorder? border;
    switch (v) {
      case AppButtonVariant.primary:
        gradient = _pressed && _enabled ? AppGradients.brandPressed(context) : AppGradients.brand(context);
      case AppButtonVariant.danger:
        if (outlineDanger) {
          fill = lit ? c.dangerTint : null;
          border = Border.all(color: c.danger, width: AppBorder.strong);
        } else {
          fill = _pressed && _enabled ? Color.lerp(c.danger, c.textDark, 0.18) : c.danger;
        }
      case AppButtonVariant.secondary:
        fill = lit ? c.primaryTint : null;
        border = Border.all(color: c.primary, width: AppBorder.strong);
      case AppButtonVariant.tonal:
        fill = lit ? Color.lerp(c.primaryTint, c.primary, 0.12) : c.primaryTint;
      case AppButtonVariant.ghost:
        fill = lit ? c.primaryTint : null;
    }

    final spinner = SizedBox(
      width: AppIconSize.md,
      height: AppIconSize.md,
      child: CircularProgressIndicator(strokeWidth: 2.2, color: ink),
    );

    final content = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.busy) ...[
          spinner,
          const SizedBox(width: AppSpace.xs),
        ] else if (widget.icon != null) ...[
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

    Widget visual = DecoratedBox(
      decoration: BoxDecoration(
        gradient: gradient,
        color: fill,
        borderRadius: radius,
        border: border,
        boxShadow: v == AppButtonVariant.primary && !disabled ? c.primaryButtonShadow : null,
      ),
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          gradient: v == AppButtonVariant.primary ? c.primaryGloss : null,
          borderRadius: radius,
        ),
        child: SizedBox(
          height: h,
          child: Padding(
            padding: EdgeInsetsDirectional.symmetric(
                horizontal: widget.size == AppButtonSize.sm ? AppSpace.md : AppSpace.lg - 4),
            child: content,
          ),
        ),
      ),
    );
    if (_focus && _enabled) {
      visual = DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: c.primary, width: AppBorder.focus),
        ),
        child: visual,
      );
    }

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
        child: Center(widthFactor: widget.expand ? null : 1, child: visual),
      ),
    );

    out = Opacity(opacity: disabled ? 0.45 : 1, child: Material(type: MaterialType.transparency, child: out));
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

/// An icon-only button. [tooltip] is required: it is the tooltip and the screen reader label.
class AppIconButton extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = onPressed != null && !busy;
    final filled = variant == AppIconButtonVariant.filled;
    final ink = filled ? c.onHero : appInk(context, c.primary); // readable on a dark card too (see AppButton)
    final visual = Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: filled ? AppGradients.brand(context) : null,
        color: variant == AppIconButtonVariant.tonal ? c.primaryTint : null,
        borderRadius: BorderRadius.circular(AppRadius.card - 2),
        boxShadow: filled && enabled ? c.primaryButtonShadow : null,
      ),
      child: busy
          ? SizedBox(
              width: AppIconSize.md,
              height: AppIconSize.md,
              child: CircularProgressIndicator(strokeWidth: 2.2, color: ink))
          : Icon(icon, size: AppIconSize.lg, color: variant == AppIconButtonVariant.standard ? c.textMedium : ink),
    );
    Widget out = SizedBox(
      width: AppTouch.min,
      height: AppTouch.min,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Center(child: badge > 0 ? AppCountBadge(count: badge, child: visual) : visual),
      ),
    );
    out = Opacity(
        opacity: onPressed == null && !busy ? 0.45 : 1, child: Material(type: MaterialType.transparency, child: out));
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: badge > 0 ? '$tooltip, ${appCountText(badge)}' : tooltip,
        excludeSemantics: true,
        onTap: enabled ? onPressed : null,
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
