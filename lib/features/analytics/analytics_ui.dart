// lib/features/analytics/analytics_ui.dart
// The analytics design system — shared by the student analytics (hub, course report, profile), the teacher
// analytics hub and the parent reports, so every role sees ONE product.
// (Was student_analytics_widgets.dart; that file now re-exports this one.)
// Every colour comes from the theme (context.colors) — light and dark mode both work.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import 'package:flutter_education_app/features/data_lab/data_lab_models.dart';
import 'package:flutter_education_app/features/analytics/analytics_summary.dart' show anIsolate;
import 'package:flutter_education_app/design/app_gradients.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show appMotionOff, AppEase;

String get anFont => AppFonts.display;

TextStyle anText(double size, {FontWeight w = FontWeight.w500, Color? c, double? h}) =>
    TextStyle(fontFamily: anFont, fontSize: size, fontWeight: w, color: c, height: h);

/// Translation with an English fallback while a key is not in the language file yet.
String anTr(String key, String fallback) {
  final v = key.tr;
  return (v.isEmpty || v == key) ? fallback : v;
}

/// Translates [key] and fills `{name}` placeholders.
String anFmt(String key, Map<String, Object?> params, [String? fallback]) {
  var out = fallback == null ? key.tr : anTr(key, fallback);
  params.forEach((k, v) => out = out.replaceAll('{$k}', '$v'));
  return out;
}

/// Green / amber / red for a 0–100 value.
Color anScoreColor(BuildContext context, double? v) {
  final c = context.colors;
  if (v == null) return c.textLight;
  if (v >= 75) return c.success;
  if (v >= 50) return c.warning;
  return c.danger;
}

String anLevel(double v) => v >= 85
    ? 'sa_level_excellent'.tr
    : v >= 70
    ? 'sa_level_very_good'.tr
    : v >= 50
    ? 'sa_level_good'.tr
    : 'sa_level_needs_follow_up'.tr;

String anPct(double? v) => v == null ? '–' : '${v.round()}%';

/// One warm sentence about the strongest / weakest area (progress, attendance, exams).
String anInsightSentence(double? prog, double? att, double? ex, {required bool mine}) {
  final m = <String, double>{
    if (prog != null) 'dl_progress'.tr: prog,
    if (att != null) 'dl_attendance'.tr: att,
    if (ex != null) 'dl_exams'.tr: ex,
  };
  if (m.isEmpty) return 'dl_insight_empty'.tr;
  final best = m.entries.reduce((a, b) => a.value >= b.value ? a : b);
  final worst = m.entries.reduce((a, b) => a.value <= b.value ? a : b);
  if (m.length == 1 || best.key == worst.key || worst.value >= 75) {
    return (mine ? 'dl_insight_great_me' : 'dl_insight_great_other').tr.replaceAll('{a}', best.key);
  }
  return '${(mine ? 'dl_insight_best_me' : 'dl_insight_best_other').tr.replaceAll('{a}', best.key)} '
      '${'dl_insight_focus'.tr.replaceAll('{a}', worst.key)}';
}

// ── surfaces ─────────────────────────────────────────────────────────────────

class AnCard extends StatelessWidget {
  const AnCard({super.key, required this.child, this.padding = AppSpace.card, this.margin, this.onTap, this.borderColor});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = AppRadius.cardAll;
    // paper (D-612): the card surface on a warm hairline, no resting shadow
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: r,
        border: Border.all(color: borderColor ?? c.divider, width: borderColor == null ? AppBorder.hairline : AppBorder.strong),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: r,
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
      ),
    );
  }
}

class AnSectionTitle extends StatelessWidget {
  const AnSectionTitle(this.title, {super.key, this.icon, this.subtitle, this.trailing});

  final String title;
  final IconData? icon;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.xxs / 2, AppSpace.lg, AppSpace.xxs / 2, AppSpace.sm),
      child: Row(children: [
        if (icon != null) ...[
          Icon(icon, size: AppIconSize.sm, color: c.textMedium),
          const SizedBox(width: AppSpace.xs),
        ],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
            if (subtitle != null) Text(subtitle!, style: AppType.meta(context)),
          ]),
        ),
        ?trailing,
      ]),
    );
  }
}

// ── gauges ───────────────────────────────────────────────────────────────────

/// Animated ring. [onColor] = drawn on the gradient hero (white), otherwise coloured by the score.
class AnRing extends StatelessWidget {
  const AnRing({super.key, required this.value, this.size = 84, this.stroke = 8, this.label, this.onColor = false, this.color});

  final double? value;
  final double size, stroke;
  final String? label;
  final bool onColor;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = onColor ? context.colors.onHero : (color ?? anScoreColor(context, value));
    final track = onColor ? context.colors.onHero.withValues(alpha: 0.18) : col.withValues(alpha: 0.13);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      TweenAnimationBuilder<double>(
        tween: Tween(begin: appMotionOff(context) ? ((value ?? 0) / 100).clamp(0.0, 1.0) : 0, end: ((value ?? 0) / 100).clamp(0.0, 1.0)),
        duration: appMotionOff(context) ? Duration.zero : const Duration(milliseconds: 900),
        curve: AppEase.out,
        builder: (_, v, __) => SizedBox(
          width: size,
          height: size,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox.expand(child: CircularProgressIndicator(value: 1, strokeWidth: stroke, color: track)),
            SizedBox.expand(
              child: CircularProgressIndicator(value: v, strokeWidth: stroke, strokeCap: StrokeCap.round, color: col),
            ),
            Text(value == null ? '–' : '${(v * 100).round()}%',
                style: anText(size * 0.22, w: FontWeight.w800, c: onColor ? context.colors.onHero : c.textDark)),
          ]),
        ),
      ),
      if (label != null) ...[
        const SizedBox(height: AppSpace.xs),
        Text(label!, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: AppType.meta(context).copyWith(color: onColor ? context.colors.onHeroMuted : c.textMedium)),
      ],
    ]);
  }
}

/// Bar with an optional marker (class average) on the same scale.
class AnBar extends StatelessWidget {
  const AnBar({super.key, required this.value, this.max = 100, this.height = 8, this.color, this.marker});

  final double? value;
  final double max, height;
  final Color? color;
  final double? marker;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final m = max == 0 ? 100.0 : max;
    final pct = value == null ? 0.0 : (value! / m).clamp(0.0, 1.0);
    final col = color ?? anScoreColor(context, value == null ? null : value! / m * 100);
    return LayoutBuilder(builder: (_, box) {
      final w = box.maxWidth;
      return SizedBox(
        height: height + 6,
        child: Stack(alignment: AlignmentDirectional.centerStart, children: [
          Container(height: height, decoration: BoxDecoration(color: col.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(height))),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: appMotionOff(context) ? pct : 0, end: pct),
            duration: appMotionOff(context) ? Duration.zero : const Duration(milliseconds: 700),
            curve: AppEase.out,
            builder: (_, t, __) => Container(
              width: w * t,
              height: height,
              decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(height)),
            ),
          ),
          if (marker != null)
            PositionedDirectional(
              start: (w * (marker! / m).clamp(0.0, 1.0)) - 1,
              child: Container(width: 2.5, height: height + 6, decoration: BoxDecoration(color: c.textDark.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(2))),
            ),
        ]),
      );
    });
  }
}

// ── hero pieces (on the primary gradient) ───────────────────────────────────

BoxDecoration anHeroDecoration(BuildContext context, {bool roundAll = false}) {
  final c = context.colors;
  return BoxDecoration(
    gradient: AppGradients.blend(context),
    borderRadius: roundAll ? BorderRadius.circular(c.radiusLarge) : const BorderRadius.vertical(bottom: Radius.circular(32)),
    boxShadow: c.primaryShadow,
  );
}

class AnGlassIcon extends StatelessWidget {
  const AnGlassIcon({super.key, required this.icon, required this.onTap, this.tooltip});

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final b = Material(
      color: context.colors.onHero.withValues(alpha: 0.16),
      shape: CircleBorder(side: BorderSide(color: context.colors.heroGlassBorder)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: AppTouch.min, height: AppTouch.min, child: Icon(icon, color: context.colors.onHero, size: AppIconSize.md)),
      ),
    );
    return tooltip == null ? b : Tooltip(message: tooltip!, child: b);
  }
}

class AnHeroStat extends StatelessWidget {
  const AnHeroStat({super.key, required this.icon, required this.value, required this.label, this.onTap});

  final IconData icon;
  final String value, label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Material(
      color: context.colors.heroGlass,
      borderRadius: AppRadius.cardAll,
      child: InkWell(
        borderRadius: AppRadius.cardAll,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.sm, horizontal: AppSpace.xs),
          decoration: BoxDecoration(
            borderRadius: AppRadius.cardAll,
            border: Border.all(color: context.colors.heroGlassBorder, width: AppBorder.hairline),
          ),
          child: Column(children: [
            Icon(icon, color: context.colors.onHero, size: AppIconSize.md),
            const SizedBox(height: AppSpace.xs),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value, maxLines: 1, style: AppType.figure(context).copyWith(color: context.colors.onHero)),
            ),
            const SizedBox(height: AppSpace.xxs / 2),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.overline(context).copyWith(color: context.colors.onHeroMuted, letterSpacing: 0, fontWeight: FontWeight.w500)),
          ]),
        ),
      ),
    ),
  );
}

/// A soft pill on the hero ("Very good", "My full profile" …).
class AnGlassPill extends StatelessWidget {
  const AnGlassPill({super.key, required this.label, this.icon, this.onTap});

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: context.colors.onHero.withValues(alpha: 0.16),
    shape: StadiumBorder(side: BorderSide(color: context.colors.heroGlassBorder)),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: AppIconSize.sm, color: context.colors.onHero), const SizedBox(width: AppSpace.xs)],
          Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: context.colors.onHero, fontWeight: FontWeight.w600))),
          if (onTap != null) ...[const SizedBox(width: AppSpace.xxs), Icon(Icons.chevron_right_rounded, size: AppIconSize.sm, color: context.colors.onHero)],
        ]),
      ),
    ),
  );
}

// ── small pieces ─────────────────────────────────────────────────────────────

class AnChip extends StatelessWidget {
  const AnChip({super.key, required this.icon, required this.label, required this.color, this.onTap, this.badge});

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    // the label reads at AA on its tint (gold / success / warning are never small text as they are)
    final ink = appInk(context, color);
    return Material(
      color: appTintOn(context, color),
      shape: StadiumBorder(side: BorderSide(color: color.withValues(alpha: 0.25), width: AppBorder.hairline)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: onTap == null ? 0 : AppTouch.min - AppSpace.xs),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: AppIconSize.xs, color: ink),
              const SizedBox(width: AppSpace.xxs + AppSpace.xxs / 2),
              Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: ink, fontWeight: FontWeight.w600))),
              if (badge != null && badge! > 0) ...[
                const SizedBox(width: AppSpace.xxs + AppSpace.xxs / 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs - AppSpace.xxs / 2, vertical: AppSpace.xxs / 4),
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(AppRadius.pill)),
                  child: Text('$badge', style: AppType.overline(context).copyWith(color: context.colors.onHero, letterSpacing: 0)),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class AnTag extends StatelessWidget {
  const AnTag(this.label, this.color, {super.key, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final ink = appInk(context, color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs / 2),
      decoration: BoxDecoration(color: appTintOn(context, color), borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: AppIconSize.xs, color: ink), const SizedBox(width: AppSpace.xxs)],
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: AppType.overline(context).copyWith(color: ink, letterSpacing: 0)),
        ),
      ]),
    );
  }
}

class AnEmpty extends StatelessWidget {
  const AnEmpty({super.key, required this.icon, required this.title, this.sub, this.action});

  final IconData icon;
  final String title;
  final String? sub;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: AppWidth.form.max),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AppStatePlate(icon: icon, size: 104),
            AppSpace.gapLg,
            Text(title, textAlign: TextAlign.center, style: AppType.section(context)),
            if (sub != null) ...[
              AppSpace.gapXs,
              Text(sub!, textAlign: TextAlign.center, style: AppType.body(context)),
            ],
            if (action != null) ...[AppSpace.gapLg, action!],
          ]),
        ),
      ),
    );
  }
}

class AnErrorRetry extends StatelessWidget {
  const AnErrorRetry({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return AnEmpty(
      icon: Icons.wifi_off_rounded,
      title: anTr('an_error_title', 'Something went wrong'),
      sub: message,
      action: AppButton.primary(label: 'retry'.tr, icon: Icons.refresh_rounded, onPressed: onRetry),
    );
  }
}

// ── analytics-profile pieces (Data Lab) ─────────────────────────────────────

/// One mark the teacher published: value, bar with the class average marker, and a kind sentence.
class AnMarkRow extends StatelessWidget {
  const AnMarkRow({super.key, required this.col, this.teacherMode = false});

  final DlProfileColumn col;
  final bool teacherMode;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final n = dlNum(col.value);
    final mx = col.maxValue == 0 ? 100.0 : col.maxValue;
    final pct = n == null ? null : n / mx * 100;
    final avg = col.classAvg;
    final diff = (n != null && avg != null) ? n - avg : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(col.label, style: AppType.row(context))),
        if (teacherMode && !col.visibleToStudents)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: Tooltip(message: 'dl_hidden_from_student'.tr, child: Icon(Icons.visibility_off_rounded, size: AppIconSize.sm, color: c.textLight)),
          ),
        Text(dlFmt(col.value), style: AppType.figure(context).copyWith(color: col.isNumber ? appInk(context, anScoreColor(context, pct)) : c.textDark)),
        if (col.isNumber && n != null) Text(' / ${dlFmt(mx)}', style: AppType.meta(context)),
      ]),
      if (col.isNumber && n != null) ...[
        AppSpace.gapXs,
        AnBar(value: n, max: mx, marker: avg),
        if (avg != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xxs),
            child: Row(children: [
              Flexible(child: Text('${'dl_class_avg'.tr}: ${dlFmt(avg)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context))),
              AppSpace.gapXs,
              if (diff != null && diff.abs() >= 0.5) ...[
                const Spacer(),
                Icon(diff > 0 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                    size: AppIconSize.xs, color: appInk(context, diff > 0 ? c.success : c.warning)),
                const SizedBox(width: AppSpace.xxs / 2),
                Flexible(
                  child: Text(
                    diff > 0
                        ? '${dlFmt(diff)} ${anTr('an_above_avg', 'above average')}'
                        : '${dlFmt(-diff)} ${anTr('an_below_avg', 'below average')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: appInk(context, diff > 0 ? c.success : c.warning)),
                  ),
                ),
              ],
            ]),
          ),
      ],
    ]);
  }
}

/// "You vs the class" for progress, attendance and exams — only the lines the teacher shares a class average for.
class AnVsClassCard extends StatelessWidget {
  const AnVsClassCard({super.key, required this.rows, this.bare = false});

  /// (label, mine 0–100, class average 0–100)
  final List<(String, double?, double?)> rows;

  /// Without its own card (when it sits inside another card).
  final bool bare;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shown = rows.where((r) => r.$2 != null && r.$3 != null).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    // as shown (whole points): level with the class is neither above nor below (M5)
    final above = shown.where((r) => r.$2!.round() > r.$3!.round()).length;
    final below = shown.where((r) => r.$2!.round() < r.$3!.round()).length;
    final body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          above == 0 && below == 0
              ? anTr('an_vs_all_level', 'Level with the class average — keep going.')
              : above == shown.length
              ? anTr('an_vs_all_above', 'Above the class average everywhere — wonderful work! 🌟')
              : above == 0
              ? anTr('an_vs_all_below', 'Below the class average for now — a little extra effort will close the gap.')
              : anTr('an_vs_mixed', 'Ahead of the class in some areas, with room to grow in others.'),
          style: AppType.body(context),
        ),
        for (final r in shown) ...[
          AppSpace.gapSm,
          Row(children: [
            Expanded(child: Text(r.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context))),
            Text(anPct(r.$2), style: AppType.bodyStrong(context).copyWith(color: appInk(context, anScoreColor(context, r.$2)))),
            Text('  ·  ${anTr('an_class', 'class')} ${anIsolate(anPct(r.$3))}', style: AppType.meta(context)),
          ]),
          const SizedBox(height: AppSpace.xxs + AppSpace.xxs / 2),
          AnBar(value: r.$2, marker: r.$3, height: AppSpace.xs),
        ],
        AppSpace.gapXs,
        Row(children: [
          Container(width: 2.5, height: AppSpace.sm, color: c.textDark.withValues(alpha: 0.6)),
          const SizedBox(width: AppSpace.xs),
          Flexible(child: Text(anTr('an_marker_hint', 'the line marks the class average'), style: AppType.meta(context))),
        ]),
      ]);
    return bare ? body : AnCard(child: body);
  }
}

class AnFlagTile extends StatelessWidget {
  const AnFlagTile({super.key, required this.icon, required this.color, required this.value, required this.label, this.onTap});

  final IconData icon;
  final Color color;
  final int value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ink = appInk(context, color);
    return Material(
      color: appTintOn(context, color),
      borderRadius: AppRadius.cardAll,
      child: InkWell(
        borderRadius: AppRadius.cardAll,
        onTap: onTap,
        child: Padding(
          padding: AppSpace.card,
          child: Row(children: [
            Icon(icon, color: ink, size: AppIconSize.lg),
            AppSpace.gapSm,
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$value', style: AppType.figure(context).copyWith(color: ink)),
                Text(label, style: AppType.meta(context)),
              ]),
            ),
            if (onTap != null) Icon(Icons.chevron_right_rounded, color: ink, size: AppIconSize.md),
          ]),
        ),
      ),
    );
  }
}

/// Round avatar: photo, or the first letter on a tinted circle.
class AnAvatar extends StatelessWidget {
  const AnAvatar({super.key, required this.name, this.url, this.size = 40, this.color, this.onColor = false});

  final String name;
  final String? url;
  final double size;
  final Color? color;

  /// Drawn on the gradient hero (white circle, coloured letter).
  final bool onColor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final letter = name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
    final tone = AppBlockColors.of(context, AppBlockTone.forKey(name));
    final col = color ?? c.primary;
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: onColor ? context.colors.onHero : (color == null ? tone.surface : col.withValues(alpha: 0.14)),
      ),
      child: Text(letter, style: anText(size * 0.42, w: FontWeight.w600, c: color == null && !onColor ? tone.ink : appInk(context, col))),
    );
    if (url == null || url!.isEmpty) return fallback;
    return ClipOval(
      child: SizedBox(width: size, height: size, child: Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback)),
    );
  }
}

/// A student who needs attention: name, the low numbers, tap → the analytics profile.
class AnAttentionChip extends StatelessWidget {
  const AnAttentionChip({super.key, required this.name, this.subtitle, this.attendance, this.exams, required this.onTap});

  final String name;
  final String? subtitle;
  final double? attendance, exams;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget metric(IconData icon, double? v, double limit) {
      final low = v != null && v < limit;
      final ink = low ? appInk(context, c.danger) : c.textMedium;
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: AppIconSize.xs, color: ink),
        const SizedBox(width: AppSpace.xxs),
        Text(anPct(v), style: AppType.meta(context).copyWith(color: ink, fontWeight: FontWeight.w600)),
      ]);
    }

    return Material(
      color: c.cardBg,
      borderRadius: AppRadius.cardAll,
      child: InkWell(
        borderRadius: AppRadius.cardAll,
        onTap: onTap,
        child: Container(
          width: 196,
          padding: const EdgeInsets.all(AppSpace.sm),
          decoration: BoxDecoration(
            borderRadius: AppRadius.cardAll,
            border: Border.all(color: c.warning.withValues(alpha: 0.35), width: AppBorder.hairline),
          ),
          child: Row(children: [
            AnAvatar(name: name, size: 38),
            AppSpace.gapSm,
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
                if (subtitle != null)
                  Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                const SizedBox(height: AppSpace.xxs),
                Row(children: [
                  Flexible(child: metric(Icons.event_available_rounded, attendance, 60)),
                  AppSpace.gapSm,
                  Flexible(child: metric(Icons.bar_chart_rounded, exams, 50)),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
