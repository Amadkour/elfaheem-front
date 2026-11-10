// lib/utils/widget/primary_button.dart
//
// The older full-width primary button (auth, forms, sheets). It wears the kit's primary look (system.md §4): a solid
// emerald fill with the on-hero ink, radius 14, 56 high (a phone's hero action), the label at 15 · 600, a 0.97 press
// (parked under Reduce motion), the kit's crisp 2 px focus ring outside the button. [background] paints a caller's
// own colour (success, danger …) as a solid fill. isLoading keeps the width and shows the brand ring; a disabled
// button is a flat neutral well with muted ink. New screens use AppButton.primary.
library;

import 'package:flutter/material.dart';

import '../../config/theme/theme_config_provider.dart';
import '../../design/app_buttons.dart' show appFocusRing, appKeyboardFocus;
import '../../design/app_motion_kit.dart' show AppEase, AppPressScale;
import '../../design/app_tokens.dart';
import 'app_loading_indicator.dart';

class PrimaryButton extends StatefulWidget {
  final bool isLoading;
  final bool enable;
  final Color? background;
  final bool iconBefore;
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  const PrimaryButton({
    super.key,
    required this.isLoading,
    required this.label,
    this.icon,
    this.onPressed,
    this.enable = true,
    this.iconBefore = false,
    this.background,
  });

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
  bool _pressed = false;
  bool _hover = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    // A button with no onPressed (or enable:false) must LOOK disabled, not just ignore taps.
    final disabled = !widget.enable || widget.onPressed == null;
    final c = context.colors;
    final off = disabled && !widget.isLoading;
    final active = !off && !widget.isLoading;
    final own = widget.background ?? c.primary;
    final deep = own == c.primary ? c.primaryDark : Color.lerp(own, c.textDark, 0.35)!;
    final ink = off ? c.textMedium : c.onHero;
    final fill = off
        ? c.inputBg
        : _pressed && active
            ? Color.lerp(own, deep, 0.5)
            : _hover && active
                ? Color.lerp(own, deep, 0.22)
                : own;
    final r = AppRadius.controlAll;
    final motion = AppMotion.of(context);
    final style = AppType.row(context).copyWith(fontSize: 15, fontWeight: FontWeight.w600, color: ink, height: 1.2);
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.icon != null && widget.iconBefore) ...[
          Icon(widget.icon, color: ink, size: AppIconSize.md),
          const SizedBox(width: AppSpace.xs),
        ],
        Flexible(child: Text(widget.label, maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false, style: style)),
        if (widget.icon != null && !widget.iconBefore) ...[
          const SizedBox(width: AppSpace.xs),
          Icon(widget.icon, color: ink, size: AppIconSize.md),
        ],
      ],
    );
    // `width: double.infinity` throws when the parent gives UNBOUNDED width (a button placed directly in a Row):
    // fill the width only when it is bounded; otherwise size to the content.
    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        width: constraints.hasBoundedWidth ? double.infinity : null,
        height: AppTouch.primary,
        child: Semantics(
          button: true,
          enabled: active,
          label: widget.label,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: r,
              onTap: active ? widget.onPressed : null,
              onHighlightChanged: (v) => setState(() => _pressed = v),
              onHover: (v) => setState(() => _hover = v),
              onFocusChange: (v) => setState(() => _focused = v),
              splashFactory: NoSplash.splashFactory,
              highlightColor: Colors.transparent,
              hoverColor: Colors.transparent,
              focusColor: Colors.transparent,
              mouseCursor: active ? SystemMouseCursors.click : SystemMouseCursors.basic,
              child: AppPressScale(
                scale: 0.97,
                enabled: active,
                child: AnimatedContainer(
                  duration: motion.fast,
                  curve: AppEase.out,
                  decoration: BoxDecoration(
                    color: fill,
                    borderRadius: r,
                    border: off ? Border.all(color: c.divider, width: AppBorder.hairline) : null,
                    boxShadow: _focused && active && appKeyboardFocus() ? appFocusRing(context) : null,
                  ),
                  padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpace.lg),
                  // the label keeps its place under the ring, so the width never jumps
                  child: Stack(alignment: Alignment.center, children: [
                    AnimatedOpacity(opacity: widget.isLoading ? 0 : 1, duration: motion.fast, child: content),
                    if (widget.isLoading)
                      AppLoadingIndicator(showLogo: false, size: AppTouch.primary - AppSpace.xs, ringColor: ink),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
