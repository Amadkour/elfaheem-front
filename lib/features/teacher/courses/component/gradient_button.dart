// ─────────────────────────────────────────────────────────────────────────────
// gradient_button.dart
// ─────────────────────────────────────────────────────────────────────────────

// FIX: removed unused `dart:math` import that caused an analysis warning.
import 'package:flutter/material.dart';

import '../../../../config/theme/app_theme.dart';
import '../../../../config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';

class GradientButton extends StatelessWidget {
  final String label;
  final bool isLoading;
  final bool enable;
  final VoidCallback? onTap;

  const GradientButton({
    super.key,
    required this.label,
    required this.isLoading,
    this.onTap,
    this.enable = true,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: isLoading || !enable ? null : onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      height: 50,
      decoration: BoxDecoration(
        gradient:
        enable ? context.colors.primaryGradient : context.colors.disableGradient,
        borderRadius: BorderRadius.circular(10),
        boxShadow: enable ? context.colors.primaryShadow : null,
      ),
      child: Center(
        child: isLoading
            ? const SizedBox(
            width: 20,
            height: 20,
            child: AppLoadingIndicator()): Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 14,
            fontFamily: 'bahji',
          ),
        ),
      ),
    ),
  );
}