// lib/features/parent/parent_report_widgets.dart
// Visual building blocks of the parent report (no chart package needed):
//   PlScoreRing · PlSection · PlKpi · PlTrendChart · PlInsightTile · PlBarRow · PlWeekdayStrip
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import 'parent_widgets.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

// ── colours by meaning ────────────────────────────────────────────────────────
Color plTierColor(BuildContext context, String tier) {
  final c = context.colors;
  switch (tier) {
    case 'excellent':
      return c.success;
    case 'good':
      return c.primary;
    case 'fair':
      return c.warning;
    case 'attention':
      return c.danger;
    default:
      return Colors.grey;
  }
}

Color plLevelColor(BuildContext context, String level) {
  final c = context.colors;
  return level == 'good' ? c.success : (level == 'warn' ? c.warning : c.primary);
}

IconData plLevelIcon(String level) =>
    level == 'good' ? Icons.check_circle_rounded : (level == 'warn' ? Icons.warning_amber_rounded : Icons.info_rounded);

/// Percent colour: green ≥ 75, blue ≥ 50, orange ≥ 30, red below.
Color plPctColor(BuildContext context, num v) {
  final c = context.colors;
  return v >= 75 ? c.success : (v >= 50 ? c.primary : (v >= 30 ? c.warning : c.danger));
}

// ═════════════════════════════════════════════════════════════════════════════
//  Score ring
// ═════════════════════════════════════════════════════════════════════════════
class PlScoreRing extends StatelessWidget {
  const PlScoreRing({super.key, required this.value, required this.color, this.size = 96, this.light = false});

  final num value;
  final Color color;
  final double size;
  final bool light; // drawn on a coloured background

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: Stack(alignment: Alignment.center, children: [
          CustomPaint(
            size: Size.square(size),
            painter: _RingPainter(value.toDouble().clamp(0, 100) / 100, color, light ? Colors.white24 : color.withAlpha(35)),
          ),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${value.round()}',
                style: TextStyle(fontSize: size * 0.30, fontWeight: FontWeight.w900, color: light ? Colors.white : color)),
            Text('/100', style: TextStyle(fontSize: size * 0.12, color: light ? context.colors.onHeroMuted : context.colors.textLight)),
          ]),
        ]),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.t, this.color, this.track);

  final double t;
  final Color color, track;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.11;
    final rect = Offset(stroke / 2, stroke / 2) & Size(size.width - stroke, size.height - stroke);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, base..color = track);
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * t, false, base..color = color);
  }

  @override
  bool shouldRepaint(covariant _RingPainter o) => o.t != t || o.color != color || o.track != track;
}

// ═════════════════════════════════════════════════════════════════════════════
//  Section card with a one-line plain explanation
// ═════════════════════════════════════════════════════════════════════════════
class PlSection extends StatelessWidget {
  const PlSection({super.key, required this.icon, required this.title, this.hint, required this.child, this.trailing});

  final IconData icon;
  final String title;
  final String? hint;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PlCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(color: c.primary.withAlpha(28), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: c.primary),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: c.h2.copyWith(fontSize: 15))),
          if (trailing != null) trailing!,
        ]),
        if (hint != null) ...[
          const SizedBox(height: 6),
          Text(hint!, style: c.caption.copyWith(fontSize: 12, height: 1.4)),
        ],
        const SizedBox(height: 12),
        child,
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  KPI tile  (big number · what it means · change vs previous period)
// ═════════════════════════════════════════════════════════════════════════════
class PlKpi extends StatelessWidget {
  const PlKpi({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.sub,
    this.color,
    this.delta,
    this.higherIsBetter = true,
    this.deltaSuffix = '',
  });

  final IconData icon;
  final String label, value;
  final String? sub;
  final Color? color;
  final num? delta; // current - previous
  final bool higherIsBetter;
  final String deltaSuffix;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = color ?? c.primary;
    Widget? chip;
    if (delta != null && delta != 0) {
      final up = delta! > 0;
      final good = up == higherIsBetter;
      final dc = good ? c.success : c.danger;
      chip = Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: dc.withAlpha(30), borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 12, color: dc),
          Text('${delta!.abs().round()}$deltaSuffix', style: TextStyle(fontSize: 11, color: dc, fontWeight: FontWeight.w800)),
        ]),
      );
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: col.withAlpha(20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: col.withAlpha(45)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 18, color: col),
          const Spacer(),
          if (chip != null) chip,
        ]),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(value, style: c.h2.copyWith(fontSize: 22, color: col)),
        ),
        const SizedBox(height: 2),
        Text(label, style: c.h2.copyWith(fontSize: 12.5)),
        if (sub != null) Text(sub!, style: c.caption.copyWith(fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Insight row
// ═════════════════════════════════════════════════════════════════════════════
class PlInsightTile extends StatelessWidget {
  const PlInsightTile({super.key, required this.level, required this.text});

  final String level, text;

  @override
  Widget build(BuildContext context) {
    final col = plLevelColor(context, level);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: col.withAlpha(22),
        borderRadius: BorderRadius.circular(12),
        border: BorderDirectional(start: BorderSide(color: col, width: 4)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(plLevelIcon(level), size: 18, color: col),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5, height: 1.4))),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Horizontal bar row  (label · bar · value)
// ═════════════════════════════════════════════════════════════════════════════
class PlBarRow extends StatelessWidget {
  const PlBarRow({super.key, required this.icon, required this.label, required this.fraction, required this.value, this.color, this.highlight = false});

  final IconData icon;
  final String label, value;
  final double fraction; // 0..1
  final Color? color;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = color ?? c.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Icon(icon, size: 18, color: highlight ? col : context.colors.textLight),
        const SizedBox(width: 8),
        SizedBox(width: 78, child: Text(label, style: TextStyle(fontSize: 12.5, fontWeight: highlight ? FontWeight.w800 : FontWeight.w500))),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: fraction.clamp(0.0, 1.0).toDouble(),
              minHeight: 10,
              color: highlight ? col : col.withAlpha(120),
              backgroundColor: col.withAlpha(25),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(width: 34, child: Text(value, textAlign: TextAlign.end, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Weekday strip (7 squares whose colour = activity)
// ═════════════════════════════════════════════════════════════════════════════
const _dayAr = ['إثنين', 'ثلاثاء', 'أربعاء', 'خميس', 'جمعة', 'سبت', 'أحد'];
const _dayEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _monAr = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
const _monEn = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String plDayName(int weekday0) => (plIsAr ? _dayAr : _dayEn)[weekday0 % 7]; // Monday = 0

class PlWeekdayStrip extends StatelessWidget {
  const PlWeekdayStrip({super.key, required this.counts, required this.weekStart});

  final List<int> counts; // Monday = 0
  final int weekStart;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final maxV = counts.fold<int>(0, (a, b) => a > b ? a : b);
    final order = [for (var i = 0; i < 7; i++) (weekStart + i) % 7];
    return Row(children: [
      for (final d in order)
        Expanded(
          child: Column(children: [
            Container(
              height: 36,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: counts[d] == 0 || maxV == 0 ? c.primary.withAlpha(18) : c.primary.withAlpha(60 + (170 * counts[d] / maxV).round()),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(counts[d] == 0 ? '' : '${counts[d]}',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: counts[d] / (maxV == 0 ? 1 : maxV) > 0.5 ? Colors.white : c.primary)),
            ),
            const SizedBox(height: 4),
            Text(plDayName(d), style: const TextStyle(fontSize: 10), maxLines: 1, overflow: TextOverflow.clip),
          ]),
        ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Trend chart (bars) — last 7 days / 6 weeks / 6 months
// ═════════════════════════════════════════════════════════════════════════════
class PlTrendChart extends StatefulWidget {
  const PlTrendChart({super.key, required this.unit, required this.points});

  final String unit; // day | week | month
  final List<Map<String, dynamic>> points;

  @override
  State<PlTrendChart> createState() => _PlTrendChartState();
}

class _PlTrendChartState extends State<PlTrendChart> {
  String _metric = 'minutes';

  String _label(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    switch (widget.unit) {
      case 'day':
        return plDayName(d.weekday - 1);
      case 'month':
        return (plIsAr ? _monAr : _monEn)[d.month - 1];
      default:
        return '${d.day}/${d.month}';
    }
  }

  String _fmt(num v) {
    if (_metric == 'minutes') return v >= 60 ? '${(v / 60).toStringAsFixed(v % 60 == 0 ? 0 : 1)}${'pl_h'.tr}' : '${v.round()}';
    if (_metric == 'exam_avg') return '${v.round()}%';
    return '${v.round()}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final vals = [for (final p in widget.points) (p[_metric] as num?)];
    final maxV = vals.fold<num>(0, (a, b) => b != null && b > a ? b : a);
    final top = _metric == 'exam_avg' ? 100 : (maxV == 0 ? 1 : maxV);
    const maxH = 96.0;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, children: [
        for (final m in const ['minutes', 'activities', 'exam_avg'])
          ChoiceChip(
            visualDensity: VisualDensity.compact,
            label: Text('pl_trend_$m'.tr, style: const TextStyle(fontSize: 12)),
            selected: _metric == m,
            onSelected: (_) => setState(() => _metric = m),
          ),
      ]),
      const SizedBox(height: 12),
      SizedBox(
        height: maxH + 44,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var i = 0; i < widget.points.length; i++)
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Text(vals[i] == null ? '–' : _fmt(vals[i]!), style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 350),
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  height: vals[i] == null ? 3 : 3 + (maxH - 3) * (vals[i]! / top).clamp(0.0, 1.0),
                  decoration: BoxDecoration(
                    color: i == widget.points.length - 1 ? c.primary : c.primary.withAlpha(95),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 4),
                Text(_label('${widget.points[i]['label']}'),
                    style: TextStyle(fontSize: 10, fontWeight: i == widget.points.length - 1 ? FontWeight.w800 : FontWeight.w400),
                    maxLines: 1,
                    overflow: TextOverflow.clip),
              ]),
            ),
        ]),
      ),
    ]);
  }
}
