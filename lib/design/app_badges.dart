// lib/design/app_badges.dart
//
// Status and count badges of the design system.
//
//   AppStatusBadge(label: 'Active', tone: AppTone.success, dot: true)   a small rounded pill
//   AppCountBadge(count: 150)                                           "99+" bubble (danger by default)
//   AppCountBadge(count: 3, child: Icon(Icons.notifications))           the bubble over the child's top-end corner
//
// Colours come from `context.colors` only. The ink of a status badge is the tone colour pulled toward the text colour,
// so it stays readable on its own tint in light and dark mode.
library;

import 'package:flutter/material.dart';

import '../config/theme/theme_config_provider.dart';
import 'app_tokens.dart';

enum AppTone { neutral, info, success, warning, danger, brand }

/// The solid colour of a tone (icons, dots, fills).
Color appToneColor(BuildContext context, AppTone tone) {
  final c = context.colors;
  return switch (tone) {
    AppTone.neutral => c.textMedium,
    AppTone.info => c.charcoal,
    AppTone.success => c.success,
    AppTone.warning => c.warning,
    AppTone.danger => c.danger,
    AppTone.brand => c.primary,
  };
}

/// The soft background of a tone.
Color appToneTint(BuildContext context, AppTone tone) {
  final c = context.colors;
  return switch (tone) {
    AppTone.neutral => c.textMedium.withValues(alpha: c.isDark ? 0.20 : 0.12),
    AppTone.info => c.blueTint,
    AppTone.success => c.successTint,
    AppTone.warning => c.warning.withValues(alpha: c.isDark ? 0.22 : 0.14),
    AppTone.danger => c.danger.withValues(alpha: c.isDark ? 0.22 : 0.10),
    AppTone.brand => c.primaryTint,
  };
}

/// Text colour on [appToneTint]: the tone pulled toward the text colour (dark on light, light on dark).
Color appToneInk(BuildContext context, AppTone tone) {
  final c = context.colors;
  if (tone == AppTone.neutral) return c.textDark;
  // orange is the lightest hue: it needs more ink to reach 4.5:1 on its own tint
  return Color.lerp(appToneColor(context, tone), c.textDark, tone == AppTone.warning ? 0.6 : 0.4)!;
}

/// A small rounded status pill.
class AppStatusBadge extends StatelessWidget {
  const AppStatusBadge({
    super.key,
    required this.label,
    this.tone = AppTone.neutral,
    this.icon,
    this.dot = false,
    this.dense = false,
  });

  final String label;
  final AppTone tone;

  /// A leading icon (wins over [dot]).
  final IconData? icon;

  /// A leading coloured dot.
  final bool dot;

  /// 20 px high instead of 24.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final ink = appToneInk(context, tone);
    final style = AppType.meta(context).copyWith(
      color: ink,
      fontWeight: FontWeight.w600,
      fontSize: dense ? 11 : 12,
      height: 1.2,
    );
    return Container(
      constraints: BoxConstraints(minHeight: dense ? 20 : 24),
      padding: EdgeInsetsDirectional.symmetric(horizontal: dense ? AppSpace.xs : AppSpace.sm, vertical: 2),
      decoration: BoxDecoration(color: appToneTint(context, tone), borderRadius: BorderRadius.circular(AppRadius.sheet)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: AppIconSize.xs, color: ink),
          const SizedBox(width: AppSpace.xxs),
        ] else if (dot) ...[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: appToneColor(context, tone), shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
        ],
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: style)),
      ]),
    );
  }
}

/// "99+" style text for a count.
String appCountText(int n) => n > 99 ? '99+' : '$n';

/// A numeric count bubble; with a [child] it sits over the child's top-end corner.
class AppCountBadge extends StatelessWidget {
  const AppCountBadge({
    super.key,
    required this.count,
    this.tone = AppTone.danger,
    this.child,
    this.showZero = false,
    this.semanticLabel,
  });

  final int count;
  final AppTone tone;

  /// The widget the bubble is laid over (top-end, directional). Null = the bare bubble.
  final Widget? child;
  final bool showZero;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final hidden = count <= 0 && !showZero;
    final c = context.colors;
    final bubble = hidden
        ? const SizedBox.shrink()
        : Semantics(
            label: semanticLabel ?? appCountText(count),
            excludeSemantics: true,
            child: Container(
              constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
              padding: const EdgeInsetsDirectional.symmetric(horizontal: 6),
              alignment: AlignmentDirectional.center,
              decoration: BoxDecoration(
                color: appToneColor(context, tone),
                borderRadius: BorderRadius.circular(AppRadius.sheet),
                border: child == null ? null : Border.all(color: c.cardBg, width: AppBorder.focus),
              ),
              child: Text(
                appCountText(count),
                maxLines: 1,
                style: AppType.overline(context).copyWith(color: c.onHero, height: 1.1),
              ),
            ),
          );
    if (child == null) return bubble;
    return Stack(clipBehavior: Clip.none, children: [
      child!,
      if (!hidden) PositionedDirectional(top: -6, end: -6, child: bubble),
    ]);
  }
}
