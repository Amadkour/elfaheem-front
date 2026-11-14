// shared/session/components/session_shared_widgets.dart
//
// Micro-widgets shared across SessionMaterialCard sub-components.
// No provider dependency — purely presentational. They wear the editorial kit: paper surfaces on warm hairlines,
// the kit's text roles, radius by hierarchy (chip 10 · control 14 · sheet 28), 48 px targets.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_buttons.dart';
import 'package:flutter_education_app/design/app_inputs.dart' show appFieldDecoration, appFieldTextStyle, AppFieldLabel;
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppPopIn, AppPressScale;
import 'package:flutter_education_app/design/app_tokens.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Confirm / form dialog (follows the app's direction; the name is historical)
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
    final c = context.colors;
    final danger = confirmColor == c.danger;
    return Directionality(
      textDirection: AppConfig.lang == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      child: AppPopIn(
        child: AlertDialog(
          backgroundColor: c.cardBg,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sheet)),
          titlePadding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.lg, AppSpace.lg, 0),
          contentPadding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.xs),
          actionsPadding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.sm, AppSpace.lg, AppSpace.lg),
          title: Text(title, style: AppType.headline(context)),
          content: DefaultTextStyle.merge(style: AppType.body(context), child: content),
          actions: [
            AppButton.ghost(label: 'cancel'.tr, onPressed: onCancel),
            danger
                ? AppButton.danger(label: confirmLabel, onPressed: onConfirm)
                : AppButton.primary(label: confirmLabel, onPressed: onConfirm),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Labelled text field: the kit's label above a warm well
// ─────────────────────────────────────────────────────────────────────────────

class SessionField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final TextInputType? keyboardType;

  const SessionField({
    super.key,
    required this.ctrl,
    required this.label,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppFieldLabel(label),
        TextField(
          controller: ctrl,
          keyboardType: keyboardType,
          style: appFieldTextStyle(context),
          decoration: appFieldDecoration(context),
        ),
      ],
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
    final c = context.colors;
    final tone = isLive ? c.danger : c.primary;
    final tint = isLive ? c.dangerTint : c.primaryTint;
    final ink = c.blockAccentInk(tone, Color.alphaBlend(tint, c.cardBg));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: 2),
      decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (isLive) ...[
          // a vector dot, never the emoji in the old badge text
          Container(width: AppSpace.xs - 2, height: AppSpace.xs - 2, decoration: BoxDecoration(color: tone, shape: BoxShape.circle)),
          const SizedBox(width: AppSpace.xxs),
        ],
        Flexible(
          child: Text(
            isLive ? 'live'.tr : 'recorded_badge'.tr,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.overline(context).copyWith(color: ink),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small type label (material type): the type's colour as a faint tint, its ink lifted to AA
// ─────────────────────────────────────────────────────────────────────────────

class SessionPill extends StatelessWidget {
  final String label;
  final Color color;

  const SessionPill(this.label, this.color, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tint = Color.alphaBlend(color.withValues(alpha: 0.10), c.cardBg);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs - 2, vertical: 1),
      decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(AppRadius.chip - 4)),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppType.overline(context).copyWith(color: c.blockAccentInk(color, tint)),
      ),
    );
  }
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
    final c = context.colors;
    final bg = filled
        ? color
        : outlined
        ? Colors.transparent
        : Color.alphaBlend(color.withValues(alpha: 0.09), c.cardBg);

    final textColor = filled ? c.onHero : c.blockAccentInk(color, outlined ? c.cardBg : bg);

    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: AppPressScale(
        enabled: !loading && onTap != null,
        child: Material(
          color: bg,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.controlAll,
            side: filled ? BorderSide.none : BorderSide(color: color.withValues(alpha: 0.40), width: AppBorder.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: loading ? null : onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppSpace.xl + AppSpace.xxs),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                child: loading
                    ? AppLoadingIndicator(ringColor: textColor, showLogo: false, size: AppIconSize.lg)
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, size: AppIconSize.sm, color: textColor),
                          const SizedBox(width: AppSpace.xs - 2),
                          Flexible(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: textColor),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
