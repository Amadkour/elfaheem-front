// lib/features/parent/parent_report_widgets.dart
// Visual building blocks of the parent report, in the Warm Editorial kit (no chart package):
//   PlScoreRing      the score as a ring that fills once; on the report's hero its figure rolls (AppOdometer)
//   PlSection        a paper card with an editorial title and one plain line under it
//   PlKpi            a paper figure card: icon well · change vs the previous period · figure (counts up) · label
//   PlTrendChart     the period's trend on the kit's AppBarChart, the metric picked with AppTabs
//   PlInsightTile    one finding: a tone well and the sentence
//   PlBarRow         label · bar (fills once) · value
//   PlWeekdayStrip   seven day squares whose depth is the activity
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_bidi.dart' show ltrIsolate;
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppCountUp, AppOdometer, AppFill;

import '../../config/app_config.dart';
import 'parent_widgets.dart';

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
      return c.textLight;
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

/// An icon in a soft round well of its tone (opaque tint, the icon at AA on it).
class PlToneWell extends StatelessWidget {
  const PlToneWell({super.key, required this.icon, required this.tone, this.surface, this.size = PlToneWell.standard});

  final IconData icon;
  final Color tone;

  /// What the well sits on (the card by default).
  final Color? surface;
  final double size;

  static const double standard = AppTouch.min - AppSpace.sm;

  @override
  Widget build(BuildContext context) {
    final tint = appTintOn(context, tone, surface: surface);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
      child: Icon(icon, size: AppIconSize.sm, color: appInkOn(context, tone, tint)),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Score ring
// ═════════════════════════════════════════════════════════════════════════════
class PlScoreRing extends StatelessWidget {
  const PlScoreRing({super.key, required this.value, required this.color, this.size = 96, this.light = false, this.memoryKey});

  final num value;
  final Color color;
  final double size;

  /// Drawn inside a block: the arc in the block's accent ink, the figure in its ink, the track its faint ink.
  final bool light;

  /// Set on the report's key ring: its figure rolls like an odometer from the value it showed last.
  final String? memoryKey;

  static const double _stroke = 0.1;

  /// From this size the ring also says "/100" under the figure.
  static const double _withScale = AppTouch.primary + AppSpace.lg;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = light ? AppBlock.colorsOf(context) : null;
    final arc = ink == null ? color : ink.accentInk(color);
    final track = ink == null ? appTintOn(context, color) : Color.alphaBlend(ink.faint.withValues(alpha: 0.22), ink.surface);
    final figureStyle = AppType.figureLarge(context).copyWith(fontSize: size * 0.3, height: 1, color: ink?.ink ?? appInk(context, color));
    final figure = memoryKey == null
        ? AppCountUp('${value.round()}', style: figureStyle)
        : AppOdometer('${value.round()}', memoryKey: memoryKey, style: figureStyle);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        // the arc fills once from 0 and glides on a change
        AppFill(
          value: value.toDouble().clamp(0, 100) / 100,
          builder: (_, t) => CustomPaint(size: Size.square(size), painter: _RingPainter(t, arc, track, _stroke)),
        ),
        Padding(
          padding: EdgeInsets.all(size * _stroke * 1.6),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              figure,
              if (size >= _withScale)
                Text('/100', textDirection: TextDirection.ltr, style: AppType.meta(context).copyWith(color: ink?.muted ?? c.textLight)),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.t, this.color, this.track, this.strokeShare);

  final double t, strokeShare;
  final Color color, track;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * strokeShare;
    final rect = Offset(stroke / 2, stroke / 2) & Size(size.width - stroke, size.height - stroke);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, base..color = track);
    if (t > 0) canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * t, false, base..color = color);
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
    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpace.md),
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.md + AppSpace.xxs),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Semantics(header: true, child: Text(title, style: AppType.section(context))),
          ),
          ?trailing,
          Padding(
            padding: const EdgeInsetsDirectional.only(start: AppSpace.xs, top: AppSpace.xxs),
            child: Icon(icon, size: AppIconSize.md, color: c.textLight),
          ),
        ]),
        if (hint != null) ...[
          const SizedBox(height: AppSpace.xxs),
          Text(hint!, style: AppType.meta(context).copyWith(height: 1.45)),
        ],
        const SizedBox(height: AppSpace.md),
        child,
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  KPI tile  (figure · what it means · change vs previous period)
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
    if (delta != null && delta!.round() != 0) {
      final up = delta! > 0;
      final good = up == higherIsBetter;
      chip = AppStatusBadge(
        label: ltrIsolate('${up ? '+' : '-'}${delta!.abs().round()}$deltaSuffix'),
        tone: good ? AppTone.success : AppTone.danger,
        icon: up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
        dense: true,
      );
    }
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          PlToneWell(icon: icon, tone: col),
          const SizedBox(width: AppSpace.xs),
          if (chip != null)
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FittedBox(fit: BoxFit.scaleDown, child: chip),
              ),
            ),
        ]),
        const SizedBox(height: AppSpace.sm),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: AppCountUp(value, memoryKey: 'parent.report.$label', style: AppType.figureLarge(context).copyWith(color: appInk(context, col))),
        ),
        const SizedBox(height: AppSpace.xxs),
        Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
        if (sub != null)
          Text(sub!, style: AppType.meta(context).copyWith(height: 1.4), maxLines: 2, overflow: TextOverflow.ellipsis),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        PlToneWell(icon: plLevelIcon(level), tone: plLevelColor(context, level)),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpace.xxs + AppBorder.focus),
            child: Text(text, style: AppType.row(context).copyWith(height: 1.5)),
          ),
        ),
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

  static const double _labelWidth = AppSpace.xxxl + AppSpace.md;
  static const double _valueWidth = AppSpace.xl + AppSpace.xs;
  static const double _bar = AppSpace.xs + AppBorder.focus;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = color ?? c.primary;
    final fill = highlight ? col : Color.alphaBlend(col.withValues(alpha: 0.45), c.cardBg);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs + AppBorder.hairline),
      child: Row(children: [
        Icon(icon, size: AppIconSize.sm, color: highlight ? appInk(context, col) : c.textLight),
        const SizedBox(width: AppSpace.xs),
        SizedBox(
          width: _labelWidth,
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: AppType.label(context).copyWith(color: c.textDark, fontWeight: highlight ? FontWeight.w600 : FontWeight.w400)),
        ),
        Expanded(
          child: LayoutBuilder(builder: (context, box) {
            return Container(
              height: _bar,
              alignment: AlignmentDirectional.centerStart,
              decoration: BoxDecoration(color: appTintOn(context, col), borderRadius: BorderRadius.circular(AppRadius.pill)),
              child: AppFill(
                value: fraction.clamp(0.0, 1.0).toDouble(),
                builder: (_, v) => Container(
                  width: box.maxWidth * v,
                  height: _bar,
                  decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(AppRadius.pill)),
                ),
              ),
            );
          }),
        ),
        const SizedBox(width: AppSpace.xs),
        SizedBox(
          width: _valueWidth,
          child: Text(value, textAlign: TextAlign.end, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: AppType.label(context).copyWith(color: c.textDark, fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()])),
        ),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Weekday strip (7 squares whose depth = activity)
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

  static const double _cell = AppSpace.xl + AppSpace.xxs;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final maxV = counts.fold<int>(0, (a, b) => a > b ? a : b);
    final order = [for (var i = 0; i < 7; i++) (weekStart + i) % 7];
    return Row(children: [
      for (final d in order)
        Expanded(
          child: Builder(builder: (context) {
            final share = maxV == 0 ? 0.0 : counts[d] / maxV;
            // the depth of the primary over the card: an empty day is the input well, the busiest the full primary
            final fill = counts[d] == 0 ? c.inputBg : Color.alphaBlend(c.primary.withValues(alpha: 0.2 + 0.8 * share), c.cardBg);
            return Column(children: [
              Container(
                height: _cell,
                margin: const EdgeInsets.symmetric(horizontal: AppBorder.focus),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(AppRadius.chip)),
                child: counts[d] == 0
                    ? null
                    : Text('${counts[d]}', style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: appInkOnFill(context, fill))),
              ),
              const SizedBox(height: AppSpace.xxs),
              Text(plDayName(d), style: AppType.overline(context).copyWith(fontWeight: FontWeight.w400, letterSpacing: 0), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]);
          }),
        ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Trend chart (bars) — last 7 days / 6 weeks / 6 months, on the kit's AppBarChart
// ═════════════════════════════════════════════════════════════════════════════
class PlTrendChart extends StatefulWidget {
  const PlTrendChart({super.key, required this.unit, required this.points});

  final String unit; // day | week | month
  final List<Map<String, dynamic>> points;

  @override
  State<PlTrendChart> createState() => _PlTrendChartState();
}

class _PlTrendChartState extends State<PlTrendChart> {
  static const _metrics = ['minutes', 'activities', 'exam_avg'];
  String _metric = 'minutes';

  static const double _height = AppSpace.xxxl * 2 + AppSpace.lg;

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
    final vals = [for (final p in widget.points) ((p[_metric] as num?) ?? 0).toDouble()];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AppTabs(
        expand: true,
        items: [for (final m in _metrics) AppTabItem('pl_trend_$m'.tr)],
        index: _metrics.indexOf(_metric),
        onChanged: (i) => setState(() => _metric = _metrics[i]),
      ),
      const SizedBox(height: AppSpace.md),
      // a new metric draws its bars in again (the key restarts the draw-in)
      KeyedSubtree(
        key: ValueKey(_metric),
        child: AppBarChart(
          series: [AppChartSeries('pl_trend_$_metric'.tr, vals, color: context.colors.primary)],
          labels: [for (final p in widget.points) _label('${p['label']}')],
          height: _height,
          title: 'pl_trend_$_metric'.tr,
          format: _fmt,
          integerAxis: _metric == 'activities',
        ),
      ),
    ]);
  }
}
