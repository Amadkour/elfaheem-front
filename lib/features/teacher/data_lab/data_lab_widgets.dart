// lib/features/teacher/data_lab/data_lab_widgets.dart
// Small reusable building blocks of the Data Lab (all colours come from the app theme).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import 'data_lab_models.dart';

/// Translation with a friendly English fallback while a key is not in the language files yet.
String dlTr(String key, String fallback) {
  final v = key.tr;
  return (v.isEmpty || v == key) ? fallback : v;
}

TextStyle dlText(double size, {FontWeight w = FontWeight.w500, Color? c, double? h}) =>
    TextStyle(fontFamily: 'tajawal', fontSize: size, fontWeight: w, color: c, height: h);

/// Traffic-light colour for a 0–100 value, taken from the active theme.
Color dlScoreColor(BuildContext context, double? v) {
  final c = context.colors;
  if (v == null) return c.textLight;
  if (v >= 75) return c.success;
  if (v >= 50) return c.warning;
  return c.danger;
}

/// Rounded card used by every block of the Data Lab.
class DlCard extends StatelessWidget {
  const DlCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.margin, this.onTap});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = BorderRadius.circular(c.radiusLarge - 4);
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: r,
        border: Border.all(color: c.divider),
        boxShadow: c.cardShadow,
      ),
      child: ClipRRect(
        borderRadius: r,
        child: Material(
          color: Colors.transparent,
          child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
        ),
      ),
    );
  }
}

/// Gradient header of the page: a friendly title and up to three numbers.
class DlHero extends StatelessWidget {
  const DlHero({super.key, required this.title, required this.subtitle, required this.icon, this.stats = const []});

  final String title, subtitle;
  final IconData icon;
  final List<DlHeroStat> stats;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(c.radiusLarge),
        gradient: LinearGradient(
          colors: [c.primary, c.primaryDark],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        boxShadow: c.primaryShadow,
      ),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: dlText(20, w: FontWeight.w800, c: Colors.white)),
              const SizedBox(height: 4),
              Text(subtitle, style: dlText(12.5, c: Colors.white70, h: 1.5)),
            ]),
          ),
          const SizedBox(width: 12),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white24),
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
        ]),
        if (stats.isNotEmpty) ...[
          const SizedBox(height: 16),
          Row(children: [
            for (var i = 0; i < stats.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: stats[i]),
            ],
          ]),
        ],
      ]),
    );
  }
}

class DlHeroStat extends StatelessWidget {
  const DlHeroStat({super.key, required this.icon, required this.value, required this.label});

  final IconData icon;
  final String value, label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white12),
    ),
    child: Column(children: [
      Icon(icon, color: Colors.white, size: 18),
      const SizedBox(height: 4),
      Text(value, style: dlText(17, w: FontWeight.w800, c: Colors.white)),
      Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: dlText(10.5, c: Colors.white70)),
    ]),
  );
}

/// Tinted pill button (Import / Export / New column …).
class DlActionPill extends StatelessWidget {
  const DlActionPill({super.key, required this.icon, required this.label, required this.onTap, this.color});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = color ?? c.primary;
    final off = onTap == null;
    return Opacity(
      opacity: off ? 0.45 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: col.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: col.withValues(alpha: 0.28)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 18, color: col),
              const SizedBox(width: 7),
              // Flexible: a long label (or a big text scale on a phone) ellipsizes instead of overflowing.
              Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: dlText(12.5, w: FontWeight.w800, c: col))),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A thin progress bar with a value, coloured by how good the number is.
class DlBar extends StatelessWidget {
  const DlBar({super.key, required this.value, this.max = 100, this.height = 7, this.color, this.marker});

  final double? value;
  final double max;
  final double height;
  final Color? color;

  /// Optional marker (class average), same scale as [value].
  final double? marker;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pct = value == null ? 0.0 : (value! / (max == 0 ? 100 : max)).clamp(0.0, 1.0);
    final col = color ?? dlScoreColor(context, value == null ? null : value! / (max == 0 ? 100 : max) * 100);
    return LayoutBuilder(builder: (_, box) {
      final w = box.maxWidth;
      return SizedBox(
        height: height + 6,
        child: Stack(alignment: AlignmentDirectional.centerStart, children: [
          Container(
            height: height,
            decoration: BoxDecoration(color: c.divider.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(height)),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            height: height,
            width: w * pct,
            decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(height)),
          ),
          if (marker != null)
            PositionedDirectional(
              start: (w * (marker! / (max == 0 ? 100 : max)).clamp(0.0, 1.0)) - 1,
              child: Container(width: 2, height: height + 6, color: c.textDark.withValues(alpha: 0.55)),
            ),
        ]),
      );
    });
  }
}

/// Round gauge, e.g. progress 72 %.
class DlRing extends StatelessWidget {
  const DlRing({super.key, required this.value, required this.label, this.size = 86, this.color});

  final double? value;
  final String label;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = color ?? dlScoreColor(context, value);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: size,
        height: size,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: ((value ?? 0) / 100).clamp(0.0, 1.0)),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          builder: (_, t, __) => CustomPaint(
            painter: _RingPainter(t, col, c.divider),
            child: Center(
              child: Text(value == null ? '–' : '${value!.round()}%',
                  style: dlText(size * 0.22, w: FontWeight.w800, c: c.textDark)),
            ),
          ),
        ),
      ),
      const SizedBox(height: 6),
      Text(label, textAlign: TextAlign.center, style: dlText(11.5, w: FontWeight.w600, c: c.textMedium)),
    ]);
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.t, this.color, this.track);

  final double t;
  final Color color, track;

  @override
  void paint(Canvas canvas, Size s) {
    final stroke = s.width * 0.115;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, s.width - stroke, s.height - stroke);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, base..color = track.withValues(alpha: 0.7));
    if (t > 0) canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * t, false, base..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.t != t || o.color != color || o.track != track;
}

/// Round avatar with the first letter when there is no photo.
class DlAvatar extends StatelessWidget {
  const DlAvatar({super.key, required this.name, this.url, this.size = 40});

  final String name;
  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: [c.primary.withValues(alpha: 0.24), c.primary.withValues(alpha: 0.10)]),
      ),
      child: Text(name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase(),
          style: dlText(size * 0.42, w: FontWeight.w800, c: c.primary)),
    );
    if (url == null || url!.isEmpty) return fallback;
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback),
      ),
    );
  }
}

/// Small coloured label ("Temporary", "Waiting for the student" …).
class DlTag extends StatelessWidget {
  const DlTag(this.label, this.color, {super.key, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.28)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      if (icon != null) ...[Icon(icon, size: 11, color: color), const SizedBox(width: 3)],
      Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: dlText(10.5, w: FontWeight.w700, c: color))),
    ]),
  );
}

/// Section title used inside sheets and the profile.
class DlSectionTitle extends StatelessWidget {
  const DlSectionTitle(this.title, {super.key, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: dlText(15, w: FontWeight.w800, c: c.textDark)),
            if (subtitle != null) Text(subtitle!, style: dlText(11.5, c: c.textMedium, h: 1.4)),
          ]),
        ),
        ?trailing,
      ]),
    );
  }
}

/// Primary filled button of the Data Lab sheets.
class DlPrimaryButton extends StatelessWidget {
  const DlPrimaryButton({super.key, required this.label, required this.onPressed, this.icon, this.busy = false});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: c.primary,
          disabledBackgroundColor: c.primary.withValues(alpha: 0.35),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        onPressed: busy ? null : onPressed,
        child: busy
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
            : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (icon != null) ...[Icon(icon, size: 19), const SizedBox(width: 8)],
          Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: dlText(14.5, w: FontWeight.w800, c: Colors.white))),
        ]),
      ),
    );
  }
}

/// Plain text field in the app's look (no dependency on the admin widgets).
class DlField extends StatelessWidget {
  const DlField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.keyboard,
    this.maxLines = 1,
    this.onChanged,
    this.ltr = false,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final TextInputType? keyboard;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final bool ltr;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    OutlineInputBorder b(Color col, [double w = 1]) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: col, width: w));
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboard,
        maxLines: maxLines,
        onChanged: onChanged,
        textDirection: ltr ? TextDirection.ltr : null,
        style: dlText(14, c: c.textDark),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: dlText(13, c: c.textMedium),
          hintStyle: dlText(13, c: c.textLight),
          filled: true,
          fillColor: c.inputBg,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: b(c.divider),
          enabledBorder: b(c.divider),
          focusedBorder: b(c.primary, 1.6),
        ),
      ),
    );
  }
}

/// Selectable chip (single or multi select).
class DlChoiceChip extends StatelessWidget {
  const DlChoiceChip({super.key, required this.label, required this.selected, required this.onTap, this.icon});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? c.primary : c.inputBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? c.primary : c.divider),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 16, color: selected ? Colors.white : c.textMedium), const SizedBox(width: 6)],
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: dlText(12.5, w: FontWeight.w700, c: selected ? Colors.white : c.textDark)),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Premium building blocks (all colours from the theme)
// ─────────────────────────────────────────────────────────────────────────────

/// Compact number pill: icon · value · label. Used in the sheet's header.
class DlStatChip extends StatelessWidget {
  const DlStatChip({super.key, required this.icon, required this.value, required this.label, this.color, this.tooltip});

  final IconData icon;
  final String value, label;
  final Color? color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = color ?? c.primary;
    final chip = Container(
      padding: const EdgeInsetsDirectional.fromSTEB(8, 6, 12, 6),
      decoration: BoxDecoration(
        color: col.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: col.withValues(alpha: 0.18)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(color: col.withValues(alpha: 0.16), shape: BoxShape.circle),
          child: Icon(icon, size: 14, color: col),
        ),
        const SizedBox(width: 7),
        Text(value, style: dlText(13, w: FontWeight.w800, c: c.textDark)),
        const SizedBox(width: 5),
        Text(label, style: dlText(11.5, w: FontWeight.w600, c: c.textMedium)),
      ]),
    );
    return tooltip == null ? chip : Tooltip(message: tooltip!, child: chip);
  }
}

/// Soft pulsing placeholder while the first page loads (no package needed).
class DlShimmer extends StatefulWidget {
  const DlShimmer({super.key, required this.child});

  final Widget child;

  @override
  State<DlShimmer> createState() => _DlShimmerState();
}

class _DlShimmerState extends State<DlShimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween<double>(begin: 0.45, end: 1).animate(CurvedAnimation(parent: _a, curve: Curves.easeInOut)),
    child: widget.child,
  );
}

class DlSkeletonBox extends StatelessWidget {
  const DlSkeletonBox({super.key, this.width, this.height = 12, this.radius = 8});

  final double? width;
  final double height, radius;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: context.colors.divider.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

/// The shape of the sheet while it loads: calmer than a spinner, and the page does not jump when data arrives.
class DlSheetSkeleton extends StatelessWidget {
  const DlSheetSkeleton({super.key, this.rows = 9, this.columns = 4});

  final int rows, columns;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DlShimmer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
        children: [
          Row(children: [
            const DlSkeletonBox(width: 120, height: 30, radius: 10),
            for (var j = 0; j < columns; j++) ...[const SizedBox(width: 12), const Expanded(child: DlSkeletonBox(height: 30, radius: 10))],
          ]),
          const SizedBox(height: 14),
          for (var i = 0; i < rows; i++)
            Container(
              height: 48,
              decoration: BoxDecoration(border: Border(top: BorderSide(color: c.divider.withValues(alpha: 0.5)))),
              child: Row(children: [
                const DlSkeletonBox(width: 26, height: 26, radius: 13),
                const SizedBox(width: 10),
                DlSkeletonBox(width: 70.0 + (i * 23) % 40, height: 11),
                const SizedBox(width: 24),
                for (var j = 0; j < columns; j++) ...[
                  const SizedBox(width: 12),
                  Expanded(child: Center(child: DlSkeletonBox(width: 26.0 + (i + j) * 7 % 20, height: 11))),
                ],
              ]),
            ),
        ],
      ),
    );
  }
}

/// Five bars: how the class is spread over 0–20 %, 20–40 % … 80–100 % of the full mark.
class DlHistogram extends StatelessWidget {
  const DlHistogram({super.key, required this.buckets, this.height = 74});

  final List<int> buckets;
  final double height;

  static const _labels = ['0–20', '20–40', '40–60', '60–80', '80–100'];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final top = buckets.fold<int>(0, (m, e) => e > m ? e : m);
    return Directionality(
      textDirection: TextDirection.ltr, // a scale always reads low → high
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < 5; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(i < buckets.length ? '${buckets[i]}' : '0', style: dlText(11, w: FontWeight.w800, c: c.textDark)),
              const SizedBox(height: 3),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: top == 0 || i >= buckets.length ? 0 : buckets[i] / top),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
                builder: (_, t, __) => Container(
                  height: 4 + (height - 4) * t,
                  decoration: BoxDecoration(
                    color: dlScoreColor(context, i * 20.0 + 10).withValues(alpha: 0.85),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(7), bottom: Radius.circular(3)),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(_labels[i], maxLines: 1, style: dlText(9.5, c: c.textLight)),
            ]),
          ),
        ],
      ]),
    );
  }
}

/// A calm, tinted message block (tips, warnings, "locked" notes …).
class DlBanner extends StatelessWidget {
  const DlBanner({super.key, required this.icon, required this.text, this.color, this.action});

  final IconData icon;
  final String text;
  final Color? color;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = color ?? c.primary;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: col.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: col.withValues(alpha: 0.22)),
      ),
      child: Row(children: [
        Icon(icon, size: 19, color: col),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: dlText(12, w: FontWeight.w600, c: c.textDark, h: 1.45))),
        ?action,
      ]),
    );
  }
}

/// "3 min ago" / "yesterday" / a date — friendly time for the history.
String dlAgo(DateTime? t) {
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return dlTr('dl_ago_now', 'just now');
  if (d.inMinutes < 60) return '${d.inMinutes} ${dlTr('dl_ago_min', 'min ago')}';
  if (d.inHours < 24) return '${d.inHours} ${dlTr('dl_ago_hours', 'h ago')}';
  if (d.inDays == 1) return dlTr('dl_ago_yesterday', 'yesterday');
  if (d.inDays < 7) return '${d.inDays} ${dlTr('dl_ago_days', 'days ago')}';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)}';
}

// ─────────────────────────────────────────────────────────────────────────────
// Column style colours
// ─────────────────────────────────────────────────────────────────────────────

/// A style colour: a theme name (follows the app theme and dark mode) or '#RRGGBB'.
Color? dlStyleColor(BuildContext context, String? token) {
  if (token == null || token.isEmpty) return null;
  final c = context.colors;
  switch (token) {
    case 'primary':
      return c.primary;
    case 'success':
      return c.success;
    case 'warning':
      return c.warning;
    case 'danger':
      return c.danger;
    case 'purple':
      return c.purple;
    case 'accent':
      return c.accent;
    case 'accent2':
      return c.accent2;
  }
  if (token.startsWith('#') && token.length == 7) {
    final v = int.tryParse(token.substring(1), radix: 16);
    if (v != null) return Color(0xFF000000 | v);
  }
  return null;
}

/// Red → amber → green for 0 → 50 → 100 (the colour scale of a column).
Color dlScaleColor(BuildContext context, double pct) {
  final c = context.colors;
  final t = (pct / 100).clamp(0.0, 1.0);
  return t < 0.5 ? Color.lerp(c.danger, c.warning, t * 2)! : Color.lerp(c.warning, c.success, (t - 0.5) * 2)!;
}

/// Text alignment of a style value ('start' | 'center' | 'end').
TextAlign dlTextAlign(String? a) => switch (a) {
  'start' => TextAlign.start,
  'end' => TextAlign.end,
  _ => TextAlign.center,
};

AlignmentDirectional dlAlignment(String? a) => switch (a) {
  'start' => AlignmentDirectional.centerStart,
  'end' => AlignmentDirectional.centerEnd,
  _ => AlignmentDirectional.center,
};

/// A row of colour swatches (+ "none"). [value] is the selected token.
class DlSwatches extends StatelessWidget {
  const DlSwatches({super.key, required this.value, required this.onChanged, this.allowNone = true, this.size = 30});

  final String? value;
  final ValueChanged<String?> onChanged;
  final bool allowNone;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget dot(String? token) {
      final col = dlStyleColor(context, token);
      final on = value == token;
      return InkWell(
        customBorder: const CircleBorder(),
        onTap: () => onChanged(token),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: col ?? c.inputBg,
            border: Border.all(color: on ? c.textDark : c.divider, width: on ? 2.4 : 1),
          ),
          child: col == null
              ? Icon(Icons.format_color_reset_rounded, size: size * 0.55, color: c.textMedium)
              : (on ? Icon(Icons.check_rounded, size: size * 0.6, color: Colors.white) : null),
        ),
      );
    }

    return Wrap(spacing: 8, runSpacing: 8, children: [
      if (allowNone) dot(null),
      for (final t in dlStyleColors) dot(t),
    ]);
  }
}
