/// Custom reusable button widget (older screens): the kit's button geometry (48 high, radius 14, 24 px padding, the
/// label at 15 · 600, icon 20) on a FilledButton, so the theme paints the brand fill; [color] / [textColor] override
/// it. New screens use AppButton.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';

class CustomButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final Color? color;
  final Color? textColor;

  const CustomButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.icon,
    this.color,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: isLoading ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: textColor,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
        minimumSize: const Size(AppTouch.min, AppTouch.min),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.controlAll),
      ),
      child: isLoading
          ? const SizedBox(
              height: AppIconSize.md,
              width: AppIconSize.md,
              child: AppLoadingIndicator(showLogo: false, size: AppIconSize.md),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: AppIconSize.md),
                  const SizedBox(width: AppSpace.xs),
                ],
                Flexible(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.row(context).copyWith(fontSize: 15, fontWeight: FontWeight.w600, color: textColor),
                  ),
                ),
              ],
            ),
    );
  }
}
