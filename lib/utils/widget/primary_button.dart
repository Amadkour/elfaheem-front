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
    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        width: constraints.hasBoundedWidth ? double.infinity : null,
        height: 52,
        child: Opacity(
          opacity: disabled && !isLoading ? 0.5 : 1,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: isLoading || disabled ? null : onPressed,
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: background,
                gradient: background != null
                    ? null
                    : context.colors.accentGradient,
                borderRadius: BorderRadius.circular(10),
                boxShadow: context.colors.primaryShadow,
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
                            child: Icon(icon, color: Colors.white, size: 18),
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
                              color: Colors.white,
                            ),
                          ),
                        ),
                        if (icon != null && !iconBefore ) ...[
                          const SizedBox(width: 6),
                          Icon(icon, color: Colors.white, size: 18),
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
