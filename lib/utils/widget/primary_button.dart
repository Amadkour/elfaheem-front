import 'package:flutter/material.dart';

import '../../config/theme/theme_config_provider.dart';
import 'app_loading_indicator.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';

class PrimaryButton extends StatelessWidget {
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
  Widget build(BuildContext context) {
    // A button with no onPressed (or enable:false) must LOOK disabled, not just ignore taps.
    final disabled = !enable || onPressed == null;

    // `width: double.infinity` throws when the parent gives UNBOUNDED width (e.g. a button placed
    // directly in a Row) — that is what produced the "RenderBox was not laid out" cascade inside the
    // user-detail bottom sheet. Fill the width only when it is bounded; otherwise size to the content.
    final c = context.colors;
    // Calm brand fill (M22: the old primary → accent gradient read olive → green). A disabled button is a flat
    // neutral well with readable muted text (L10: white on a pale half-transparent gradient was unreadable).
    final off = disabled && !isLoading;
    final fill = off ? c.inputBg : (background ?? c.primary);
    final ink = off ? c.textMedium : c.onHero;
    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        width: constraints.hasBoundedWidth ? double.infinity : null,
        height: 52,
        child: Semantics(
          button: true,
          enabled: !off,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: isLoading || disabled ? null : onPressed,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(10),
                border: off ? Border.all(color: c.divider) : null,
                boxShadow: off ? null : c.primaryShadow,
              ),
              child: isLoading
                  ? AppLoadingIndicator(showLogo: false, size: 50)
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (icon != null && iconBefore ) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(5.0,0,5,2),
                            child: Icon(icon, color: ink, size: 18),
                          ),
                        ],
                        Flexible(
                          child: Text(
                            label,
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
                        if (icon != null && !iconBefore ) ...[
                          const SizedBox(width: 6),
                          Icon(icon, color: ink, size: 18),
                        ],
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
