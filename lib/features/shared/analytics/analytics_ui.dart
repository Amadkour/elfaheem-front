// lib/features/shared/analytics/analytics_ui.dart
// The analytics design system — shared by the student analytics (hub, course report, profile), the teacher
// analytics hub and the parent reports, so every role sees ONE product.
// (Was student_analytics_widgets.dart; that file now re-exports this one.)
// Every colour comes from the theme (context.colors) — light and dark mode both work.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import '../../teacher/data_lab/data_lab_models.dart';

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
  const AnCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.margin, this.onTap, this.borderColor});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = BorderRadius.circular(18);
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: r,
        border: Border.all(color: borderColor ?? c.divider.withValues(alpha: 0.6), width: borderColor == null ? 0.6 : 1),
        boxShadow: c.cardShadow,
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
      padding: const EdgeInsets.fromLTRB(2, 18, 2, 10),
      child: Row(children: [
        if (icon != null) ...[
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 16, color: c.primary),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: anText(15, w: FontWeight.w800, c: c.textDark)),
            if (subtitle != null) Text(subtitle!, style: anText(11.5, c: c.textMedium, h: 1.4)),
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
        tween: Tween(begin: 0, end: ((value ?? 0) / 100).clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
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
        const SizedBox(height: 6),
        Text(label!, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: anText(11.5, w: FontWeight.w600, c: onColor ? context.colors.onHeroMuted : c.textMedium)),
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
            tween: Tween(begin: 0, end: pct),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
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
    gradient: LinearGradient(
      colors: [c.primaryDark, c.primary],
      begin: AlignmentDirectional.topStart,
      end: AlignmentDirectional.bottomEnd,
    ),
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
        child: SizedBox(width: 40, height: 40, child: Icon(icon, color: context.colors.onHero, size: 19)),
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
      color: context.colors.onHero.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.colors.onHero.withValues(alpha: 0.18)),
          ),
          child: Column(children: [
            Icon(icon, color: context.colors.onHero, size: 19),
            const SizedBox(height: 6),
            Text(value, maxLines: 1, style: anText(16, w: FontWeight.w800, c: context.colors.onHero)),
            const SizedBox(height: 2),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: anText(10, c: context.colors.onHeroMuted)),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 15, color: context.colors.onHero), const SizedBox(width: 6)],
          Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: anText(12.5, w: FontWeight.w700, c: context.colors.onHero))),
          if (onTap != null) ...[const SizedBox(width: 4), Icon(Icons.chevron_right_rounded, size: 16, color: context.colors.onHero)],
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
  Widget build(BuildContext context) => Material(
    color: color.withValues(alpha: 0.08),
    shape: StadiumBorder(side: BorderSide(color: color.withValues(alpha: 0.25))),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: anText(11.5, w: FontWeight.w700, c: color))),
          if (badge != null && badge! > 0) ...[
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
              child: Text('$badge', style: anText(10, w: FontWeight.w800, c: context.colors.onHero)),
            ),
          ],
        ]),
      ),
    ),
  );
}

class AnTag extends StatelessWidget {
  const AnTag(this.label, this.color, {super.key, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      if (icon != null) ...[Icon(icon, size: 12, color: color), const SizedBox(width: 4)],
      Text(label, style: anText(11, w: FontWeight.w700, c: color)),
    ]),
  );
}

class AnEmpty extends StatelessWidget {
  const AnEmpty({super.key, required this.icon, required this.title, this.sub, this.action});

  final IconData icon;
  final String title;
  final String? sub;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [c.primary.withValues(alpha: 0.16), c.primary.withValues(alpha: 0.04)]),
            ),
            child: Icon(icon, size: 40, color: c.primary),
          ),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: anText(16, w: FontWeight.w800, c: c.textDark)),
          if (sub != null) ...[
            const SizedBox(height: 6),
            Text(sub!, textAlign: TextAlign.center, style: anText(13, c: c.textMedium, h: 1.55)),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
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
    final c = context.colors;
    return AnEmpty(
      icon: Icons.wifi_off_rounded,
      title: anTr('an_error_title', 'Something went wrong'),
      sub: message,
      action: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: c.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded),
        label: Text('retry'.tr, style: anText(13.5, w: FontWeight.w700, c: context.colors.onHero)),
      ),
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
        Expanded(child: Text(col.label, style: anText(13.5, w: FontWeight.w700, c: c.textDark))),
        if (teacherMode && !col.visibleToStudents)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: Tooltip(message: 'dl_hidden_from_student'.tr, child: Icon(Icons.visibility_off_rounded, size: 15, color: c.textLight)),
          ),
        Text(dlFmt(col.value), style: anText(16, w: FontWeight.w800, c: col.isNumber ? anScoreColor(context, pct) : c.textDark)),
        if (col.isNumber && n != null) Text(' / ${dlFmt(mx)}', style: anText(11.5, c: c.textLight)),
      ]),
      if (col.isNumber && n != null) ...[
        const SizedBox(height: 6),
        AnBar(value: n, max: mx, marker: avg),
        if (avg != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(children: [
              Text('${'dl_class_avg'.tr}: ${dlFmt(avg)}', style: anText(11, c: c.textLight)),
              const Spacer(),
              if (diff != null && diff.abs() >= 0.5)
                Text(
                  diff > 0
                      ? '▲ ${dlFmt(diff)} ${anTr('an_above_avg', 'above average')}'
                      : '▼ ${dlFmt(-diff)} ${anTr('an_below_avg', 'below average')}',
                  style: anText(11, w: FontWeight.w700, c: diff > 0 ? c.success : c.warning),
                ),
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
          style: anText(12.5, c: c.textMedium, h: 1.5),
        ),
        for (final r in shown) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: Text(r.$1, style: anText(12.5, w: FontWeight.w700, c: c.textDark))),
            Text(anPct(r.$2), style: anText(13, w: FontWeight.w800, c: anScoreColor(context, r.$2))),
            Text('  ·  ${anTr('an_class', 'class')} ${anPct(r.$3)}', style: anText(11.5, c: c.textLight)),
          ]),
          const SizedBox(height: 5),
          AnBar(value: r.$2, marker: r.$3, height: 7),
        ],
        const SizedBox(height: 8),
        Row(children: [
          Container(width: 2.5, height: 12, color: c.textDark.withValues(alpha: 0.6)),
          const SizedBox(width: 6),
          Text(anTr('an_marker_hint', 'the line marks the class average'), style: anText(10.5, c: c.textLight)),
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
  Widget build(BuildContext context) => Material(
    color: color.withValues(alpha: 0.10),
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: color.withValues(alpha: 0.25))),
        child: Row(children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$value', style: anText(20, w: FontWeight.w800, c: color)),
              Text(label, style: anText(11, c: context.colors.textMedium, h: 1.3)),
            ]),
          ),
          if (onTap != null) Icon(Icons.chevron_right_rounded, color: color),
        ]),
      ),
    ),
  );
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
    final col = color ?? c.primary;
    final letter = name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: onColor ? context.colors.onHero : col.withValues(alpha: 0.14)),
      child: Text(letter, style: anText(size * 0.42, w: FontWeight.w800, c: col)),
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
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: low ? c.danger : c.textLight),
        const SizedBox(width: 3),
        Text(anPct(v), style: anText(11, w: FontWeight.w800, c: low ? c.danger : c.textMedium)),
      ]);
    }

    return Material(
      color: c.cardBg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: 196,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.warning.withValues(alpha: 0.35)),
          ),
          child: Row(children: [
            AnAvatar(name: name, size: 38, color: c.warning),
            const SizedBox(width: 9),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: anText(13, w: FontWeight.w800, c: c.textDark)),
                if (subtitle != null)
                  Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: anText(10.5, c: c.textLight)),
                const SizedBox(height: 3),
                Row(children: [
                  metric(Icons.event_available_rounded, attendance, 60),
                  const SizedBox(width: 10),
                  metric(Icons.bar_chart_rounded, exams, 50),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
