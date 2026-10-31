import 'package:flutter/material.dart';

import '../../config/theme/theme_config_provider.dart';
import '../../design/app_contrast.dart';
import '../../design/app_tokens.dart';
import 'app_loading_indicator.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';

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
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    // A button with no onPressed (or enable:false) must LOOK disabled, not just ignore taps.
    final disabled = !widget.enable || widget.onPressed == null;

    // `width: double.infinity` throws when the parent gives UNBOUNDED width (e.g. a button placed
    // directly in a Row) — that is what produced the "RenderBox was not laid out" cascade inside the
    // user-detail bottom sheet. Fill the width only when it is bounded; otherwise size to the content.
    final c = context.colors;
    // The brand fill is the primary gradient (D-136); a caller's own colour (success, danger …) stays flat. A
    // disabled button is a flat neutral well with readable muted text (L10: white on a pale half-transparent
    // gradient was unreadable).
    final off = disabled && !widget.isLoading;
    final own = widget.background;
    final brand = own == null || own == c.primary;
    final ink = off ? c.textMedium : c.onHero;
    final r = BorderRadius.circular(10);
    final motion = AppMotion.of(context);
    // keyboard focus: a crisp ring outside the button (a page-coloured gap, then the brand colour at 3:1)
    final ring = ensureContrast(c.primary, [c.background], min: 3);
    final shadows = <BoxShadow>[
      if (_focused && !off) ...[
        BoxShadow(color: c.background, spreadRadius: 2),
        BoxShadow(color: ring, spreadRadius: 4),
      ],
      if (!off && !_pressed) ...(brand ? c.primaryButtonShadow : [BoxShadow(color: own.withValues(alpha: 0.28), blurRadius: 14, offset: const Offset(0, 5))]),
    ];
    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        width: constraints.hasBoundedWidth ? double.infinity : null,
        height: 52,
        child: Semantics(
          button: true,
          enabled: !off,
          child: AnimatedContainer(
            duration: motion.fast,
            curve: AppMotion.curve,
            decoration: BoxDecoration(
              color: off ? c.inputBg : (brand ? null : own),
              gradient: off || !brand ? null : (_pressed ? c.primaryGradientPressed : c.primaryGradient),
              borderRadius: r,
              border: off ? Border.all(color: c.divider) : null,
              boxShadow: shadows,
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: r,
                onTap: widget.isLoading || disabled ? null : widget.onPressed,
                onHighlightChanged: (v) => setState(() => _pressed = v),
                onFocusChange: (v) => setState(() => _focused = v),
                splashColor: c.onHero.withValues(alpha: 0.14),
                highlightColor: Colors.transparent,
                hoverColor: c.onHero.withValues(alpha: 0.06),
                focusColor: c.onHero.withValues(alpha: 0.08),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: widget.isLoading
                      ? Center(child: AppLoadingIndicator(showLogo: false, size: 50, ringColor: ink))
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            if (widget.icon != null && widget.iconBefore) ...[
                              Padding(
                                padding: const EdgeInsets.fromLTRB(5.0, 0, 5, 2),
                                child: Icon(widget.icon, color: ink, size: 18),
                              ),
                            ],
                            Flexible(
                              child: Text(
                                widget.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: AppFonts.family,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: ink,
                                ),
                              ),
                            ),
                            if (widget.icon != null && !widget.iconBefore) ...[
                              const SizedBox(width: 6),
                              Icon(widget.icon, color: ink, size: 18),
                            ],
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
