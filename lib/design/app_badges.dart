// lib/design/app_badges.dart
//
// Status and count badges of the design system (Warm Editorial, system.md §2: a full pill, the label flexes,
// success = emerald, achievements = gold, and a tone is never small text on its own tint as it comes — it is
// darkened, lifted in dark mode, until it reads).
//
//   AppStatusBadge(label: 'Active', tone: AppTone.success, dot: true)   a full pill on an opaque warm tint
//   AppStatusBadge(label: 'Top mark', tone: AppTone.gold)                achievements, streaks, top marks only
//   AppCountBadge(count: 150)                                            "99+" bubble (danger by default)
//   AppCountBadge(count: 3, child: Icon(Icons.notifications))            the bubble over the child's top-end corner
//
//   appTintOn(context, tone)        the opaque tint of a tone over the card surface (badges, delta chips, icon boxes)
//   appInkOn(context, tone, tint)   the tone as TEXT on that tint, at WCAG AA (hue kept)
//
// Colours come from `context.colors` only.
library;

import 'package:flutter/material.dart';

import '../config/theme/theme_config_provider.dart';
import 'app_contrast.dart';
import 'app_motion_kit.dart';
import 'app_tokens.dart';

/// The meaning a badge carries. [gold] is reserved (system.md §2): streaks, achievements and top marks, never a
/// decoration; [success] is emerald: done, correct, active.
enum AppTone { neutral, info, success, warning, danger, brand, gold }

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
    AppTone.gold => c.accent2,
  };
}

/// The opaque tint of [tone] laid over [surface] (the card surface by default): a translucent wash would change
/// with whatever sits under it, an opaque one keeps the same ink contrast on a card, the canvas or a block.
Color appTintOn(BuildContext context, Color tone, {Color? surface}) {
  final c = context.colors;
  return Color.alphaBlend(tone.withValues(alpha: c.isDark ? 0.24 : 0.14), surface ?? c.cardBg);
}

/// [tone] as TEXT (or an icon) on [tint]: the same hue, darkened — lifted in dark mode — until it reads at AA.
/// Gold, success and warning are only 2.9 – 4.3:1 on their own tints as they come (system.md §2).
Color appInkOn(BuildContext context, Color tone, Color tint) => ensureContrast(tone, [tint]);

/// The ink on a SOLID tone fill (a count bubble, a filled chip): whichever of the on-hero ink, the text ink and the
/// canvas reads best on it (in dark mode the text ink is light, so a light fill takes the dark canvas).
Color appInkOnFill(BuildContext context, Color fill) {
  final c = context.colors;
  var best = c.onHero;
  var bestRatio = contrastRatio(best, fill);
  for (final candidate in [c.textDark, c.background]) {
    final r = contrastRatio(candidate, fill);
    if (r > bestRatio) {
      best = candidate;
      bestRatio = r;
    }
  }
  return best;
}

/// The soft, opaque background of a tone.
Color appToneTint(BuildContext context, AppTone tone) {
  final c = context.colors;
  return switch (tone) {
    AppTone.neutral => Color.alphaBlend(c.textMedium.withValues(alpha: c.isDark ? 0.20 : 0.10), c.cardBg),
    _ => appTintOn(context, appToneColor(context, tone)),
  };
}

/// Text colour on [appToneTint]: the tone itself where it reads, else pulled until it does (hue kept).
Color appToneInk(BuildContext context, AppTone tone) {
  final c = context.colors;
  if (tone == AppTone.neutral) return c.textDark;
  return appInkOn(context, appToneColor(context, tone), appToneTint(context, tone));
}

/// A full status pill. The label flexes (ellipsis), never clips; a badge is read, not pressed, so it keeps its
/// own small height and the row around it provides the 48 px target when it is tappable.
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

  /// A leading coloured dot (the raw tone: a fill, not text).
  final bool dot;

  /// 20 px high instead of 24.
  final bool dense;

  static const double _height = 24;
  static const double _heightDense = 20;
  static const double _dot = 6;

  @override
  Widget build(BuildContext context) {
    final ink = appToneInk(context, tone);
    final style = (dense ? AppType.overline(context) : AppType.meta(context))
        .copyWith(color: ink, fontWeight: FontWeight.w600, letterSpacing: 0, height: 1.2);
    return Container(
      constraints: BoxConstraints(minHeight: dense ? _heightDense : _height),
      padding: EdgeInsetsDirectional.symmetric(horizontal: dense ? AppSpace.xs : AppSpace.sm, vertical: AppSpace.xxs / 2),
      decoration: BoxDecoration(color: appToneTint(context, tone), borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: AppIconSize.xs, color: ink),
          const SizedBox(width: AppSpace.xxs),
        ] else if (dot) ...[
          Container(
            width: _dot,
            height: _dot,
            decoration: BoxDecoration(color: appToneColor(context, tone), shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpace.xxs + _dot / 3),
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

  /// The bubble's smallest size: a circle for one digit, a stadium past that.
  static const double _size = 20;

  /// How far the bubble hangs over the child's corner.
  static const double _overhang = 6;

  @override
  Widget build(BuildContext context) {
    final hidden = count <= 0 && !showZero;
    final c = context.colors;
    final fill = appToneColor(context, tone);
    final bubble = hidden
        ? const SizedBox.shrink()
        : Semantics(
            label: semanticLabel ?? appCountText(count),
            excludeSemantics: true,
            // a count that changes pops once (D-581)
            child: AppBump(
              trigger: count,
              child: Container(
                constraints: const BoxConstraints(minWidth: _size, minHeight: _size),
                padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpace.xxs + 2),
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  // the ring that lifts it off the child is the surface it sits on, not a hairline
                  border: child == null ? null : Border.all(color: c.cardBg, width: AppBorder.focus),
                ),
                // shrink-wrapped around the centred figure (a Container with `alignment` would fill a Wrap's run)
                child: Center(
                  widthFactor: 1,
                  heightFactor: 1,
                  child: Text(
                    appCountText(count),
                    maxLines: 1,
                    style: AppType.overline(context).copyWith(color: appInkOnFill(context, fill), letterSpacing: 0, height: 1.1),
                  ),
                ),
              ),
            ),
          );
    if (child == null) return bubble;
    return Stack(clipBehavior: Clip.none, children: [
      child!,
      if (!hidden) PositionedDirectional(top: -_overhang, end: -_overhang, child: bubble),
    ]);
  }
}
