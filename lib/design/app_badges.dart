// lib/design/app_badges.dart
//
// Status and count badges of the design system (the redesign kit, KIT_SPEC §5.5 / §5.10: a full pill, the label
// flexes; each tone is a kit role with its tint and its ink, which pass AA on each other by construction).
//
//   tone      tint / ink
//   neutral   kit.track / textMedium        info   kit.primaryTone      success  kit.ok      warning  kit.warn
//   danger    kit.live                      brand  the area set's tone  gold     kit.warmTone
//
//   AppStatusBadge(label: 'Active', tone: AppTone.success, dot: true)   a full pill on an opaque warm tint
//   AppStatusBadge(label: 'Top mark', tone: AppTone.gold)                achievements, streaks, top marks only
//   AppStatusBadge(label: 'Physics', subject: 'physics')                 a subject's / an accent's tint and ink
//                   (danger and gold always wear a glyph, appToneGlyph: never colour alone, D-862)
//   AppCountBadge(count: 150)                                            "99+" bubble (danger by default)
//   AppCountBadge(count: 3, child: Icon(Icons.notifications))            the bubble over the child's top-end corner
//
//   appTintOn(context, tone)        the opaque tint of a tone over the card surface (badges, delta chips, icon boxes)
//   appInkOn(context, tone, tint)   the tone as TEXT on that tint, at WCAG AA (hue kept)
//   appWashOn(context, tone)        the quiet wash of a tone behind a LARGE surface (a note, a selected card, D-728)
//
// Colours come from `context.colors` only.
library;

import 'package:flutter/material.dart';

import '../config/theme/theme_config_provider.dart';
import '../core/app_digits.dart';
import 'app_area.dart';
import 'app_contrast.dart';
import 'app_subject_colors.dart' show subjectKeyFor;
import 'app_motion_kit.dart';
import 'app_tokens.dart';

/// The meaning a badge carries. [gold] is reserved (system.md §2): streaks, achievements and top marks, never a
/// decoration; [success] is emerald: done, correct, active.
enum AppTone { neutral, info, success, warning, danger, brand, gold }

/// The kit tone (colour, tint, ink) of [tone] (KIT_SPEC §5.5).
KitTone appKitTone(BuildContext context, AppTone tone) {
  final c = context.colors;
  final kit = c.kit;
  return switch (tone) {
    AppTone.neutral => KitTone(c.textMedium, kit.track, c.textMedium),
    AppTone.info => kit.primaryTone,
    AppTone.success => kit.ok,
    AppTone.warning => kit.warn,
    AppTone.danger => kit.live,
    AppTone.brand => AppAreaScope.of(context).tone,
    AppTone.gold => kit.warmTone,
  };
}

/// The solid colour of a tone (icons, dots, fills).
Color appToneColor(BuildContext context, AppTone tone) => appKitTone(context, tone).color;

/// The glyph a tone always carries, so its meaning never rests on colour alone (D-862): an error / failed state wears
/// the error mark, an achievement (gold: top mark, streak) the trophy. Null for the other tones.
IconData? appToneGlyph(AppTone tone) => switch (tone) {
      AppTone.danger => Icons.error_outline_rounded,
      AppTone.gold => Icons.emoji_events_rounded,
      _ => null,
    };

/// [appToneGlyph] for a chip that takes a raw colour: the danger or accent2 family of the theme (ink or base).
IconData? appColorGlyph(BuildContext context, Color color) {
  final c = context.colors;
  final v = color.withValues(alpha: 1).toARGB32();
  if (v == c.danger.toARGB32() || v == c.dangerBase.toARGB32()) return appToneGlyph(AppTone.danger);
  if (v == c.accent2.toARGB32() || v == c.accent2Base.toARGB32()) return appToneGlyph(AppTone.gold);
  return null;
}

/// The colour of a SOLID [tone] fill under a label (a count bubble): the server's own status tones
/// (`successBase` …), so a dark-mode bubble keeps the same deep red and white figure as in light mode, where
/// [appToneColor] gives the dark-mode INK, lifted for text and icons (D-740).
Color appToneFill(BuildContext context, AppTone tone) {
  final kit = context.colors.kit;
  return switch (tone) {
    // a count badge: white digits at 4.62:1 (P11), never the lighter live colour
    AppTone.danger => kit.liveFill,
    _ => appToneColor(context, tone),
  };
}

/// The opaque tint of [tone] laid over [surface] (the card surface by default): a translucent wash would change
/// with whatever sits under it, an opaque one keeps the same ink contrast on a card, the canvas or a block.
Color appTintOn(BuildContext context, Color tone, {Color? surface}) {
  final c = context.colors;
  return Color.alphaBlend(tone.withValues(alpha: c.isDark ? 0.24 : 0.14), surface ?? c.cardBg);
}

/// The quiet wash of [tone] behind a LARGE surface: a note, a selected card or row, a sheet's header band (D-728).
/// Light mode is 5 % laid opaque on the card white (the tint of a badge, 14 %, read as a heavy green slab across a whole
/// card, and a translucent wash let the sage canvas through), so the border, the icon and the ink carry the meaning;
/// dark mode keeps the old translucent strength. Like [ThemeConfigProvider.primaryWash].
Color appWashOn(BuildContext context, Color tone) {
  final c = context.colors;
  return c.isDark ? tone.withValues(alpha: 0.14) : Color.alphaBlend(tone.withValues(alpha: 0.05), c.cardBg);
}

/// [tone] as TEXT (or an icon) on [tint]: the same hue, darkened — lifted in dark mode — until it reads at AA.
/// Gold, success and warning are only 2.9 – 4.3:1 on their own tints as they come (system.md §2).
Color appInkOn(BuildContext context, Color tone, Color tint) => appInkOnTint(tone, tint, dark: context.colors.isDark);

/// The ratio a tone's ink aims for on its own tint in dark mode. Light ink on a dark tint loses more to anti-aliasing
/// than dark ink on a light one: an ink computed at exactly 4.5:1 measured 3.9:1 as drawn at 11 px (a pill's label),
/// so dark mode keeps a margin above AA. Light mode aims at AA itself.
const double kDarkInkOnTint = 5.5;

/// [appInkOn] without a context: [tone] moved (hue kept) until it reaches AA on [tint], [kDarkInkOnTint] when [dark].
Color appInkOnTint(Color tone, Color tint, {required bool dark}) =>
    ensureContrast(tone, [tint], min: dark ? kDarkInkOnTint : kWcagAaText);

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
Color appToneTint(BuildContext context, AppTone tone) => appKitTone(context, tone).tint;

/// Text colour on [appToneTint] (the kit's ink, AA on its tint).
Color appToneInk(BuildContext context, AppTone tone) => appKitTone(context, tone).ink;

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
    this.accent,
    this.subject,
  });

  final String label;
  final AppTone tone;

  /// An accent's tint and ink; wins over [tone].
  final AppAccent? accent;

  /// A subject (slug or name, see `subjectKeyFor`): its tint and ink; wins over [tone] and [accent].
  final String? subject;

  /// A leading icon (wins over [dot]). Danger and gold fall back to their own glyph ([appToneGlyph], D-862).
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
    final kit = context.colors.kit;
    final KitTone t = subject != null
        ? kit.subject(subjectKeyFor(subject)).tone
        : accent != null
            ? kit.accent(accent!)
            : appKitTone(context, tone);
    final ink = t.ink;
    final icon = this.icon ?? (subject == null && accent == null ? appToneGlyph(tone) : null);
    final style = AppType.overline(context).copyWith(color: ink, fontWeight: FontWeight.w600, letterSpacing: 0, height: 1.2);
    return Container(
      constraints: BoxConstraints(minHeight: dense ? _heightDense : _height),
      padding: EdgeInsetsDirectional.symmetric(horizontal: dense ? AppSpace.xs : AppSpace.sm, vertical: AppSpace.xxs / 2),
      decoration: BoxDecoration(color: t.tint, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: AppIconSize.xs, color: ink),
          const SizedBox(width: AppSpace.xxs),
        ] else if (dot) ...[
          Container(
            width: _dot,
            height: _dot,
            decoration: BoxDecoration(color: t.color, shape: BoxShape.circle),
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
    this.ringColor,
  });

  final int count;
  final AppTone tone;

  /// The ring that lifts the bubble off its child (default: the card surface).
  final Color? ringColor;

  /// The widget the bubble is laid over (top-end, directional). Null = the bare bubble.
  final Widget? child;
  final bool showZero;
  final String? semanticLabel;

  /// The bubble's smallest size over a child (a circle for one digit, a stadium past that); bare, it is [_sizeBare].
  static const double _size = 18;
  static const double _sizeBare = 22;

  /// How far the bubble hangs over the child's corner.
  static const double _overhang = 6;

  @override
  Widget build(BuildContext context) {
    final hidden = count <= 0 && !showZero;
    final c = context.colors;
    final kit = c.kit;
    // danger: the live fill with white digits (P11); gold: the warm tint and ink; others: the tone's tint and ink
    final (Color fill, Color ink) = switch (tone) {
      AppTone.danger => (kit.liveFill, c.onHero),
      AppTone.gold => (kit.warmTone.tint, kit.warmTone.ink),
      _ => (appToneTint(context, tone), appToneInk(context, tone)),
    };
    final min = child == null ? _sizeBare : _size;
    final Widget bubble = hidden
        ? const SizedBox.shrink()
        : Semantics(
            label: semanticLabel ?? appCountText(count),
            excludeSemantics: true,
            // a count that changes pops once (D-581)
            child: AppBump(
              trigger: count,
              child: Container(
                constraints: BoxConstraints(minWidth: min, minHeight: min),
                padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpace.xxs + 2),
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  // the ring that lifts it off the child is the surface it sits on, not a hairline
                  border: child == null ? null : Border.all(color: ringColor ?? c.cardBg, width: AppBorder.focus),
                ),
                // shrink-wrapped around the centred figure (a Container with `alignment` would fill a Wrap's run)
                child: Center(
                  widthFactor: 1,
                  heightFactor: 1,
                  child: Text(
                    appDigits(appCountText(count)),
                    maxLines: 1,
                    style: AppType.overline(context).copyWith(color: ink, letterSpacing: 0, height: 1.1),
                  ),
                ),
              ),
            ),
          );
    // it lands with a slap under a student area (M4, tilt 0); elsewhere it is simply there
    final shown = hidden ? bubble : AppSlap(tilt: 0, delay: AppMotionSpec.slapDelay, child: bubble);
    if (child == null) return shown;
    return Stack(clipBehavior: Clip.none, children: [
      child!,
      if (!hidden) PositionedDirectional(top: -_overhang, end: -_overhang, child: shown),
    ]);
  }
}
