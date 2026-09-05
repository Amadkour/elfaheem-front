// shared/session/components/session_shared_widgets.dart
//
// Micro-widgets shared across SessionMaterialCard sub-components.
// No provider dependency — purely presentational.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';

import '../../../../../config/app_config.dart';
import '../../../../../config/theme/app_theme.dart';
import '../../../../../config/theme/theme_config_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// RTL themed AlertDialog wrapper
// ─────────────────────────────────────────────────────────────────────────────

class RtlDialog extends StatelessWidget {
  final String title;
  final Widget content;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;
  final String confirmLabel;
  final Color confirmColor;

  const RtlDialog({
    super.key,
    required this.title,
    required this.content,
    required this.onCancel,
    required this.onConfirm,
    required this.confirmLabel,
    required this.confirmColor,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        backgroundColor: context.colors.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: context.colors.h3),
        content: content,
        actions: [
          TextButton(
            onPressed: onCancel,
            child: Text(
              'cancel'.tr,
              style: TextStyle(
                  fontFamily: 'bahji', color: context.colors.textMedium),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: confirmColor,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: onConfirm,
            child: Text(
              confirmLabel,
              style: const TextStyle(
                fontFamily: 'bahji',
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Labelled text field (RTL-friendly)
// ─────────────────────────────────────────────────────────────────────────────

class SessionField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;

  const SessionField({
    super.key,
    required this.ctrl,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      style: context.colors.body,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: context.colors.caption,
        filled: true,
        fillColor: context.colors.background,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
              color: context.colors.textLight.withValues(alpha: 0.2)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
              color: context.colors.textLight.withValues(alpha: 0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: context.colors.primary),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Type pill (live / recorded badge on card header)
// ─────────────────────────────────────────────────────────────────────────────

class SessionTypePill extends StatelessWidget {
  final bool isLive;

  const SessionTypePill({super.key, required this.isLive});

  @override
  Widget build(BuildContext context) {
    final c = isLive ? context.colors.danger : context.colors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isLive ? 'live_badge'.tr : 'recorded_badge'.tr,
        style: context.colors.caption
            .copyWith(color: c, fontWeight: FontWeight.w700),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small colour pill (material type label)
// ─────────────────────────────────────────────────────────────────────────────

class SessionPill extends StatelessWidget {
  final String label;
  final Color color;

  const SessionPill(this.label, this.color, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'bahji',
            fontSize: 9,
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable action button (attendance / exams / live controls)
// ─────────────────────────────────────────────────────────────────────────────

class SessionActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool filled;
  final bool outlined;
  final bool loading;

  const SessionActionBtn({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
     this.onTap,
    this.filled = false,
    this.outlined = false,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = filled
        ? color
        : outlined
            ? Colors.transparent
            : color.withValues(alpha: 0.09);

    final textColor = filled ? Colors.white : color;

    return GestureDetector(
      onTap:loading? null:onTap,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: color.withValues(alpha: 0.40), width: 1.2),
          boxShadow: filled
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.30),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ]
              : null,
        ),
        child:loading?AppLoadingIndicator(ringColor: textColor,showLogo: false,size: 25,): Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: textColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'tajawal',
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: textColor,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
