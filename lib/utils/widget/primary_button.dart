import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../config/theme/theme_config_provider.dart';
import 'app_loading_indicator.dart';

class PrimaryButton extends StatelessWidget {
  final bool isLoading;
  final bool enable;
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
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: GestureDetector(
        onTap: isLoading || !enable ? null : onPressed,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            gradient: context.colors.accentGradient,
            borderRadius: BorderRadius.circular(10),
            boxShadow: context.colors.primaryShadow,
          ),
          child: isLoading
              ? AppLoadingIndicator(showLogo: false, size: 50)
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  textDirection: iconBefore
                      ? TextDirection.ltr
                      : TextDirection.rtl,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontFamily: 'tajawal',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (icon != null) Icon(icon, color: Colors.white, size: 18),
                  ],
                ),
        ),
      ),
    );
  }
}
