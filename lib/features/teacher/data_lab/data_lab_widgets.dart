// lib/features/shared/data_lab/data_lab_widgets.dart
// Small reusable building blocks of the Data Lab (all colours come from the app theme).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

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
              Text(label, style: dlText(12.5, w: FontWeight.w800, c: col)),
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
      Text(label, style: dlText(10.5, w: FontWeight.w700, c: color)),
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
          Text(label, style: dlText(14.5, w: FontWeight.w800, c: Colors.white)),
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
