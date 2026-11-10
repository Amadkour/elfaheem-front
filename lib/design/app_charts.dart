// lib/design/app_charts.dart — chart primitives for every dashboard, pure CustomPaint, no package (D-063).
//
//   AppSparkline(values)                          a trend line (area wash at 10 %, end marker with a surface ring)
//   AppBarChart(series: [...], labels: [...])     grouped columns: <= 24 px thick, 4 px rounded caps square at the
//                                                 baseline, 2 px surface gap between bars, hairline grid, compact
//                                                 ticks (1K · 4.2M); tap / hover shows the group's values; a legend
//                                                 for >= 2 series (one series needs none — the title names it)
//   AppDonut(parts: [...])                        share of a whole: 2 px surface gaps, the total in the centre, legend
//   AppTrendTile(label:, value:, delta:, spark:)  a stat tile: value + signed delta (colour = direction × upIsGood)
//                                                 + a sparkline — the form for "one number and its trend"
//   AppLegend(entries)                            swatch + label; text wears text tokens, never the series colour
//   appChartPalette(context)                      the categorical slots, derived from the theme
//   appCompactNumber(1284) → "1.3K"               the figure format of tiles and ticks
//
// Colour (Warm Editorial, system.md §2, validated with the dataviz lightness script): five categorical slots in a
// FIXED order — the primary (emerald) · peach (`accent`) · sky (`accent3`) · gold (`accent2`) · the theme's purple —
// each snapped into the mode's OKLab lightness band (light 0.45–0.72, dark 0.50–0.65), so the pale block tints
// become readable series and a server theme stays legible in both modes. Series beyond five fold into "other"
// (textLight). success / warning / danger are STATUS colours and never series colours. Every chart draws in once
// (AppDrawIn, D-582), is RTL-aware (the first category sits at the reading start), theme-aware (surface = cardBg,
// grid = divider, ink = text tokens) and carries a semantics label with its values.
// Layout test: test/ui/app_charts_layout_test.dart.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_bidi.dart';
import 'package:flutter_education_app/design/app_icons.dart';
import 'app_badges.dart';
import 'app_motion_kit.dart';
import 'app_tokens.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data
// ─────────────────────────────────────────────────────────────────────────────

class AppChartSeries {
  const AppChartSeries(this.name, this.values, {this.color});
  final String name;
  final List<double> values;
  final Color? color;
}

class AppChartPart {
  const AppChartPart(this.label, this.value, {this.color});
  final String label;
  final double value;
  final Color? color;
}

class AppLegendEntry {
  const AppLegendEntry(this.label, this.color);
  final String label;
  final Color color;
}

// ─────────────────────────────────────────────────────────────────────────────
// Numbers and colour maths
// ─────────────────────────────────────────────────────────────────────────────

/// 1,284 → 1.3K · 4,200,000 → 4.2M · 12 → 12 · 3.456 → 3.5
String appCompactNumber(num v) {
  final a = v.abs().toDouble();
  final sign = v < 0 ? '-' : '';
  String f(double x, String s) {
    final t = x >= 10 ? x.toStringAsFixed(0) : x.toStringAsFixed(1);
    return (t.endsWith('.0') ? t.substring(0, t.length - 2) : t) + s;
  }

  if (a >= 1e9) return sign + f(a / 1e9, 'B');
  if (a >= 1e6) return sign + f(a / 1e6, 'M');
  if (a >= 1e3) return sign + f(a / 1e3, 'K');
  if (a == a.roundToDouble()) return sign + a.toInt().toString();
  return sign + a.toStringAsFixed(1);
}

/// OKLab lightness (0–1) of a colour — the measure the dataviz lightness band uses.
double oklabLightness(Color c) {
  double lin(double v) => v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  final r = lin(c.r), g = lin(c.g), b = lin(c.b);
  final l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b;
  final m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b;
  final s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b;
  double cb(double v) => v < 0 ? -math.pow(-v, 1 / 3).toDouble() : math.pow(v, 1 / 3).toDouble();
  return 0.2104542553 * cb(l) + 0.7936177850 * cb(m) - 0.0040720468 * cb(s);
}

/// Moves [c] (hue kept) until its OKLab lightness sits in the mode's band: light 0.45–0.72, dark 0.50–0.65.
Color chartSnapLightness(Color c, {required bool dark}) {
  final lo = dark ? 0.50 : 0.45;
  final hi = dark ? 0.65 : 0.72;
  var h = HSLColor.fromColor(c);
  for (var i = 0; i < 30; i++) {
    final l = oklabLightness(h.toColor());
    if (l < lo) {
      h = h.withLightness(math.min(1, h.lightness + 0.02));
    } else if (l > hi) {
      h = h.withLightness(math.max(0, h.lightness - 0.02));
    } else {
      break;
    }
  }
  return h.toColor();
}

/// A tone (primary, warning, a series colour …) drawn as TEXT or an icon on a card, made readable in the open
/// mode, hue kept: on a light surface it is darkened to OKLab L <= 0.53 (about 5:1 on white and still 4.5:1 on the
/// tone's own 12 % tint, where 0.56 gave 4.1 (WCAG text contrast guideline); the theme's
/// warning / success are 2–2.5:1 as they are), on a dark surface lifted to L >= 0.72 (the indigo primary is
/// 1.6:1 on the dark card). Fills, tints and borders keep the raw tone.
Color appInk(BuildContext context, Color tone) {
  final dark = context.colors.isDark;
  var h = HSLColor.fromColor(tone);
  for (var i = 0; i < 40; i++) {
    final l = oklabLightness(h.toColor());
    if (dark && l < 0.72) {
      h = h.withLightness(math.min(1, h.lightness + 0.02));
    } else if (!dark && l > 0.53) {
      h = h.withLightness(math.max(0, h.lightness - 0.02));
    } else {
      break;
    }
  }
  return h.toColor().withValues(alpha: tone.a);
}

/// The categorical palette of the open theme (fixed order, see the header): emerald · peach · sky · gold · purple,
/// each snapped into the lightness band so the pale block tints become series colours. Index past the end →
/// "other". A theme whose peach and gold land on the same hue is still told apart by lightness and saturation.
List<Color> appChartPalette(BuildContext context) {
  final c = context.colors;
  final dark = c.isDark;
  Color vivid(Color x) {
    // the block tints are desaturated pastels: a series needs at least a mid saturation to read as a colour
    final h = HSLColor.fromColor(x);
    return h.withSaturation(math.max(h.saturation, 0.55)).toColor();
  }

  return [
    for (final x in [c.primary, vivid(c.accent), vivid(c.accent3), c.accent2, c.purple]) chartSnapLightness(x, dark: dark),
  ];
}

Color _slot(BuildContext context, List<Color> palette, int i, Color? own) =>
    own ?? (i < palette.length ? palette[i] : context.colors.textLight);

String _tx(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

/// The small text of a chart (ticks, category labels, a legend): the overline role in [color].
TextStyle _tick(BuildContext context, Color color) =>
    AppType.overline(context).copyWith(color: color, letterSpacing: 0, height: 1.2);

double _niceMax(double v) {
  if (v <= 0) return 1;
  final e = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
  final m = v / e;
  final n = m <= 1 ? 1.0 : (m <= 2 ? 2.0 : (m <= 2.5 ? 2.5 : (m <= 5 ? 5.0 : 10.0)));
  return n * e;
}

/// The value axis of [maxV] as (top, steps): four quarter steps (0 · ¼ · ½ · ¾ · max), or, for counts
/// ([integer]), whole steps of 1 · 2 · 5 · 10 · 20 … — at most four, so 2 students read 0 · 1 · 2, never 0.5.
(double, int) chartAxis(double maxV, {bool integer = false}) {
  if (!integer) return (_niceMax(maxV), 4);
  if (maxV <= 0) return (1, 1);
  final want = maxV / 4;
  var step = 1.0;
  for (var e = 1.0; step < want; e *= 10) {
    step = want <= e ? e : (want <= 2 * e ? 2 * e : (want <= 5 * e ? 5 * e : 10 * e));
  }
  final steps = (maxV / step).ceil();
  return (step * steps, steps);
}

// ─────────────────────────────────────────────────────────────────────────────
// Legend
// ─────────────────────────────────────────────────────────────────────────────

class AppLegend extends StatelessWidget {
  const AppLegend(this.entries, {super.key, this.alignment = WrapAlignment.start});
  final List<AppLegendEntry> entries;
  final WrapAlignment alignment;

  /// The swatch: a small rounded square.
  static const double _swatch = 10;
  static const double _swatchRadius = 3;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Wrap(
      alignment: alignment,
      spacing: AppSpace.md,
      runSpacing: AppSpace.xs,
      children: [
        for (final e in entries)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: _swatch,
              height: _swatch,
              decoration: BoxDecoration(color: e.color, borderRadius: BorderRadius.circular(_swatchRadius)),
            ),
            const SizedBox(width: AppSpace.xs - 2),
            Flexible(
              child: Text(e.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.meta(context).copyWith(color: c.textMedium, fontWeight: FontWeight.w500)),
            ),
          ]),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sparkline
// ─────────────────────────────────────────────────────────────────────────────

class AppSparkline extends StatelessWidget {
  const AppSparkline(this.values, {super.key, this.color, this.surface, this.height = 36, this.fill = true, this.label});

  final List<double> values;
  final Color? color;

  /// What the line is drawn on (the end marker wears a ring of it): the card surface by default, a block's tint
  /// when the sparkline sits in a block.
  final Color? surface;
  final double height;
  final bool fill;

  /// What the line measures, for the semantics label.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = color ?? appChartPalette(context).first;
    final text = '${label ?? _tx('اتجاه', 'Trend')}: ${values.map(appCompactNumber).join(', ')}';
    return Semantics(
      label: text,
      container: true,
      child: ExcludeSemantics(
        child: SizedBox(
          height: height,
          width: double.infinity,
          // the line draws in from the reading start (D-582)
          child: AppDrawIn(
            builder: (context, t) => CustomPaint(
              painter: _SparkPainter(
                values: values,
                color: col,
                surface: surface ?? c.cardBg,
                fill: fill,
                rtl: Directionality.of(context) == TextDirection.rtl,
                t: t,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter({required this.values, required this.color, required this.surface, required this.fill, required this.rtl, this.t = 1});
  final List<double> values;
  final Color color, surface;
  final bool fill, rtl;

  /// Drawn so far, 0..1 from the reading start.
  final double t;

  static const double _stroke = 2;
  static const double _markerRing = 6;
  static const double _marker = 4;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || size.width <= 0 || size.height <= 0) return;
    final n = values.length;
    final lo = values.reduce(math.min);
    final hi = values.reduce(math.max);
    const pad = _markerRing - 1; // room for the end marker
    final w = size.width - pad * 2, h = size.height - pad * 2;
    Offset at(int i) {
      final t = n == 1 ? 1.0 : i / (n - 1);
      final x = pad + (rtl ? (1 - t) : t) * w;
      final y = hi == lo ? pad + h / 2 : pad + h - (values[i] - lo) / (hi - lo) * h;
      return Offset(x, y);
    }

    if (t < 1) {
      final shown = size.width * t;
      canvas.clipRect(rtl ? Rect.fromLTWH(size.width - shown, 0, shown, size.height) : Rect.fromLTWH(0, 0, shown, size.height));
    }
    final line = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < n; i++) {
      line.lineTo(at(i).dx, at(i).dy);
    }
    if (fill && n > 1) {
      final area = Path.from(line)
        ..lineTo(at(n - 1).dx, size.height)
        ..lineTo(at(0).dx, size.height)
        ..close();
      canvas.drawPath(area, Paint()..color = color.withValues(alpha: 0.10));
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    if (t < 1) return; // the end marker lands with the line
    final end = at(n - 1);
    canvas.drawCircle(end, _markerRing, Paint()..color = surface); // the 2 px surface ring
    canvas.drawCircle(end, _marker, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparkPainter o) =>
      o.values != values || o.color != color || o.surface != surface || o.fill != fill || o.rtl != rtl || o.t != t;
}

// ─────────────────────────────────────────────────────────────────────────────
// Bar chart
// ─────────────────────────────────────────────────────────────────────────────

class AppBarChart extends StatefulWidget {
  const AppBarChart({
    super.key,
    required this.series,
    required this.labels,
    this.height = 180,
    this.maxBarWidth = 24,
    this.title,
    this.showLegend,
    this.format = appCompactNumber,
    this.integerAxis = false,
  });

  final List<AppChartSeries> series;

  /// One per category (x position). Series values beyond the labels are ignored; missing ones count as 0.
  final List<String> labels;
  final double height;
  final double maxBarWidth;

  /// What the chart shows, for the semantics label (also the legend-less single-series case).
  final String? title;

  /// Default: a legend for two or more series.
  final bool? showLegend;
  final String Function(num value) format;

  /// The values are counts (students, papers): the axis ticks are whole numbers (0 · 1 · 2), never 0.3.
  final bool integerAxis;

  @override
  State<AppBarChart> createState() => _AppBarChartState();
}

class _AppBarChartState extends State<AppBarChart> {
  int? _hot;

  void _set(int? i) {
    if (i != _hot) setState(() => _hot = i);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final palette = appChartPalette(context);
    final colors = [for (var i = 0; i < widget.series.length; i++) _slot(context, palette, i, widget.series[i].color)];
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final empty = widget.labels.isEmpty ||
        widget.series.isEmpty ||
        widget.series.every((s) => s.values.every((v) => v <= 0));
    final legend = widget.showLegend ?? widget.series.length >= 2;
    final sem = StringBuffer(widget.title ?? _tx('رسم بياني', 'Chart'));
    for (var i = 0; i < widget.labels.length; i++) {
      sem.write('. ${widget.labels[i]}: ');
      sem.write([
        for (final s in widget.series)
          '${s.name} ${widget.format(i < s.values.length ? s.values[i] : 0)}',
      ].join(', '));
    }
    return Semantics(
      label: sem.toString(),
      container: true,
      child: ExcludeSemantics(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          if (legend && widget.series.isNotEmpty) ...[
            AppLegend([for (var i = 0; i < widget.series.length; i++) AppLegendEntry(widget.series[i].name, colors[i])]),
            const SizedBox(height: AppSpace.sm),
          ],
          SizedBox(
            height: widget.height,
            width: double.infinity,
            child: empty
                ? Center(child: Text('chart_no_data'.tr, style: AppType.meta(context).copyWith(color: c.textLight)))
                : LayoutBuilder(builder: (context, box) {
                    final geo = _BarGeometry(
                      width: box.maxWidth,
                      height: box.maxHeight,
                      groups: widget.labels.length,
                      bars: widget.series.length,
                      maxBarWidth: widget.maxBarWidth,
                      rtl: rtl,
                    );
                    return MouseRegion(
                      onHover: (e) => _set(geo.groupAt(e.localPosition.dx)),
                      onExit: (_) => _set(null),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (e) => _set(geo.groupAt(e.localPosition.dx)),
                        // the bars grow from the baseline (D-582)
                        child: AppDrawIn(builder: (context, t) => CustomPaint(
                          size: Size(box.maxWidth, box.maxHeight),
                          painter: _BarPainter(
                            t: t,
                            series: widget.series,
                            labels: widget.labels,
                            colors: colors,
                            geo: geo,
                            hot: _hot,
                            surface: c.cardBg,
                            grid: c.divider,
                            highlight: c.primary.withValues(alpha: 0.06),
                            tickStyle: _tick(context, c.textLight),
                            valueStyle: _tick(context, c.textDark),
                            format: widget.format,
                            textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                            integerAxis: widget.integerAxis,
                          ),
                        )),
                      ),
                    );
                  }),
          ),
        ]),
      ),
    );
  }
}

/// Where the bars go: shared by the painter and the hit test.
class _BarGeometry {
  _BarGeometry({
    required this.width,
    required this.height,
    required this.groups,
    required this.bars,
    required this.maxBarWidth,
    required this.rtl,
  });

  final double width, height, maxBarWidth;
  final int groups, bars;
  final bool rtl;

  static const axisW = 34.0;   // tick labels
  static const labelH = 18.0;  // category labels
  static const topPad = 14.0;  // value labels of the hot group
  static const gap = 2.0;      // surface gap between adjacent bars

  double get plotStart => rtl ? 0 : axisW;
  double get plotW => math.max(0, width - axisW);
  double get baseline => height - labelH;
  double get plotH => math.max(0, baseline - topPad);
  double get band => groups == 0 ? 0 : plotW / groups;

  double get barW {
    if (bars == 0) return 0;
    final w = (band * 0.72 - gap * (bars - 1)) / bars;
    return math.max(2, math.min(maxBarWidth, w));
  }

  /// Left edge of group [i]'s band (the first category sits at the reading start).
  double bandLeft(int i) => plotStart + (rtl ? groups - 1 - i : i) * band;

  /// Left edge of bar [b] of group [i].
  double barLeft(int i, int b) {
    final total = bars * barW + gap * (bars - 1);
    final start = bandLeft(i) + (band - total) / 2;
    final k = rtl ? bars - 1 - b : b;
    return start + k * (barW + gap);
  }

  int? groupAt(double x) {
    if (groups == 0 || x < plotStart || x > plotStart + plotW) return null;
    final k = ((x - plotStart) / band).floor().clamp(0, groups - 1);
    return rtl ? groups - 1 - k : k;
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.series,
    required this.labels,
    required this.colors,
    required this.geo,
    required this.hot,
    required this.surface,
    required this.grid,
    required this.highlight,
    required this.tickStyle,
    required this.valueStyle,
    required this.format,
    required this.textDirection,
    this.integerAxis = false,
    this.t = 1,
  });

  /// Grown so far (0..1).
  final double t;
  final List<AppChartSeries> series;
  final List<String> labels;
  final List<Color> colors;
  final _BarGeometry geo;
  final bool integerAxis;
  final int? hot;
  final Color surface, grid, highlight;
  final TextStyle tickStyle, valueStyle;
  final String Function(num) format;
  final TextDirection textDirection;

  /// The bars' rounded caps and the hot band's corners.
  static const double _cap = AppSpace.xxs;
  static const double _bandRadius = AppSpace.xs;

  double _value(int s, int i) => i < series[s].values.length ? series[s].values[i] : 0;

  TextPainter _text(String s, TextStyle style, {double? maxWidth}) {
    final tp = TextPainter(text: TextSpan(text: s, style: style), textDirection: textDirection, maxLines: 1, ellipsis: '…')
      ..layout(maxWidth: maxWidth ?? double.infinity);
    return tp;
  }

  @override
  void paint(Canvas canvas, Size size) {
    var maxV = 0.0;
    for (var s = 0; s < series.length; s++) {
      for (var i = 0; i < labels.length; i++) {
        maxV = math.max(maxV, _value(s, i));
      }
    }
    final (top, steps) = chartAxis(maxV, integer: integerAxis);
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = AppBorder.hairline;

    // hot band
    if (hot != null) {
      final r = Rect.fromLTWH(geo.bandLeft(hot!), 0, geo.band, geo.baseline);
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(_bandRadius)), Paint()..color = highlight);
    }

    // grid + ticks: 0 · ¼ · ½ · ¾ · max (whole steps for counts)
    for (var k = 0; k <= steps; k++) {
      final v = top * k / steps;
      final y = geo.baseline - geo.plotH * k / steps;
      canvas.drawLine(Offset(geo.plotStart, y), Offset(geo.plotStart + geo.plotW, y), gridPaint);
      final tp = _text(format(v), tickStyle, maxWidth: _BarGeometry.axisW - AppSpace.xxs);
      final x = geo.rtl ? size.width - tp.width : _BarGeometry.axisW - AppSpace.xxs - tp.width;
      tp.paint(canvas, Offset(x, y - tp.height / 2));
    }

    // bars
    for (var i = 0; i < labels.length; i++) {
      for (var s = 0; s < series.length; s++) {
        final v = _value(s, i);
        if (v <= 0) continue;
        final h = geo.plotH * (v / top) * t;
        if (h <= 0) continue;
        final x = geo.barLeft(i, s);
        final rect = Rect.fromLTWH(x, geo.baseline - h, geo.barW, h);
        final radius = Radius.circular(math.min(_cap, h));
        canvas.drawRRect(RRect.fromRectAndCorners(rect, topLeft: radius, topRight: radius), Paint()..color = colors[s]);
        if (hot == i && t >= 1) {
          final tp = _text(format(v), valueStyle);
          final cx = x + geo.barW / 2 - tp.width / 2;
          final cy = geo.baseline - h - tp.height - 2;
          final bg = Rect.fromLTWH(cx - 3, cy - 1, tp.width + 6, tp.height + 2);
          canvas.drawRRect(RRect.fromRectAndRadius(bg, const Radius.circular(_cap)), Paint()..color = surface);
          tp.paint(canvas, Offset(cx, cy));
        }
      }
      // category label
      final tp = _text(labels[i], tickStyle, maxWidth: math.max(8, geo.band - AppSpace.xxs));
      tp.paint(canvas, Offset(geo.bandLeft(i) + (geo.band - tp.width) / 2, geo.baseline + AppSpace.xxs));
    }
  }

  @override
  bool shouldRepaint(_BarPainter o) =>
      o.series != series ||
      o.labels != labels ||
      o.colors != colors ||
      o.hot != hot ||
      o.geo.width != geo.width ||
      o.geo.height != geo.height ||
      o.surface != surface ||
      o.grid != grid ||
      o.tickStyle != tickStyle ||
      o.textDirection != textDirection ||
      o.integerAxis != integerAxis ||
      o.t != t;
}

// ─────────────────────────────────────────────────────────────────────────────
// Donut
// ─────────────────────────────────────────────────────────────────────────────

class AppDonut extends StatelessWidget {
  const AppDonut({
    super.key,
    required this.parts,
    this.size = 120,
    this.thickness = 14,
    this.center,
    this.legend = true,
    this.title,
    this.format = appCompactNumber,
  });

  final List<AppChartPart> parts;
  final double size, thickness;

  /// Replaces the total in the centre.
  final Widget? center;
  final bool legend;
  final String? title;
  final String Function(num value) format;

  /// The centre figure's size as a share of the ring's diameter.
  static const double _centreScale = 0.18;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final palette = appChartPalette(context);
    final colors = [for (var i = 0; i < parts.length; i++) _slot(context, palette, i, parts[i].color)];
    final total = parts.fold<double>(0, (a, p) => a + math.max(0, p.value));
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final sem = StringBuffer(title ?? _tx('توزيع', 'Breakdown'));
    for (final p in parts) {
      sem.write('. ${p.label}: ${format(p.value)}');
      if (total > 0) sem.write(' (${(p.value / total * 100).round()}%)');
    }
    final ring = SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        // the ring sweeps in (D-582)
        AppDrawIn(
          builder: (context, t) => CustomPaint(
            size: Size(size, size),
            painter: _DonutPainter(
              values: [for (final p in parts) math.max(0.0, p.value)],
              colors: colors,
              surface: c.cardBg,
              track: c.divider,
              thickness: thickness,
              rtl: rtl,
              t: t,
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.all(thickness + AppSpace.xxs + 2),
          child: center ??
              FittedBox(
                fit: BoxFit.scaleDown,
                child: AppCountUp(
                  total > 0 ? format(total) : '—',
                  style: AppType.figureLarge(context).copyWith(fontSize: size * _centreScale),
                ),
              ),
        ),
      ]),
    );
    if (!legend || parts.isEmpty) {
      return Semantics(label: sem.toString(), container: true, child: ExcludeSemantics(child: ring));
    }
    final entries = [
      for (var i = 0; i < parts.length; i++)
        AppLegendEntry(
          // the percent reads left to right in Arabic too ("ناجح · 100%", not "%100"), as everywhere else in the app
          total > 0 ? '${parts[i].label} · ${ltrIsolate('${(parts[i].value / total * 100).round()}%')}' : parts[i].label,
          colors[i],
        ),
    ];
    return Semantics(
      label: sem.toString(),
      container: true,
      child: ExcludeSemantics(
        child: LayoutBuilder(builder: (context, box) {
          final sideBySide = box.maxWidth >= size + 150;
          if (sideBySide) {
            return Row(children: [
              ring,
              AppSpace.gapMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final e in entries) Padding(padding: const EdgeInsets.only(bottom: AppSpace.xs - 2), child: AppLegend([e])),
                  ],
                ),
              ),
            ]);
          }
          return Column(mainAxisSize: MainAxisSize.min, children: [
            ring,
            const SizedBox(height: AppSpace.sm),
            AppLegend(entries, alignment: WrapAlignment.center),
          ]);
        }),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.values,
    required this.colors,
    required this.surface,
    required this.track,
    required this.thickness,
    required this.rtl,
    this.t = 1,
  });
  final List<double> values;
  final List<Color> colors;
  final Color surface, track;
  final double thickness;
  final bool rtl;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.min(size.width, size.height) / 2 - thickness / 2;
    final rect = Rect.fromCircle(center: Offset(size.width / 2, size.height / 2), radius: r);
    final total = values.fold<double>(0, (a, v) => a + v);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.butt;
    if (total <= 0) {
      canvas.drawArc(rect, 0, math.pi * 2, false, stroke..color = track);
      return;
    }
    if (t < 1) {
      // the track shows under the sweep until the ring is whole
      canvas.drawArc(rect, 0, math.pi * 2, false, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness
        ..color = track);
    }
    final shown = values.where((v) => v > 0).length;
    final gap = shown > 1 ? 2.0 / r : 0.0;   // a 2 px surface gap between parts
    var start = -math.pi / 2;
    final dir = rtl ? -1.0 : 1.0;
    for (var i = 0; i < values.length; i++) {
      if (values[i] <= 0) continue;
      final sweep = values[i] / total * math.pi * 2 * t;
      final drawn = math.max(0.0, sweep - gap);
      canvas.drawArc(rect, start + dir * gap / 2, dir * drawn, false, stroke..color = colors[i]);
      start += dir * sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter o) =>
      o.values != values || o.colors != colors || o.surface != surface || o.track != track || o.rtl != rtl || o.t != t;
}

// ─────────────────────────────────────────────────────────────────────────────
// Trend tile
// ─────────────────────────────────────────────────────────────────────────────

/// A paper tile (the card surface on a warm hairline, no shadow) for "one number and its trend".
class AppTrendTile extends StatelessWidget {
  const AppTrendTile({
    super.key,
    required this.label,
    required this.value,
    this.delta,
    this.spark,
    this.upIsGood = true,
    this.icon,
    this.color,
    this.onTap,
    this.deltaHint,
  });

  /// Sentence case, no trailing colon.
  final String label;

  /// Already formatted (appCompactNumber, a percentage, a duration …).
  final String value;

  /// Signed change in percent vs the previous period (null = none). Its colour = direction × [upIsGood].
  final double? delta;
  final List<double>? spark;
  final bool upIsGood;
  final IconData? icon;
  final Color? color;
  final VoidCallback? onTap;

  /// Replaces "vs previous period" next to the delta.
  final String? deltaHint;

  /// The sparkline's height inside the tile.
  static const double _sparkHeight = 30;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = color ?? appChartPalette(context).first;
    final d = delta;
    final up = d != null && d > 0;
    final down = d != null && d < 0;
    final good = d == null || d == 0 ? null : (up == upIsGood);
    final deltaTone = good == null ? c.textMedium : (good ? c.success : c.danger);
    final deltaTint = appTintOn(context, deltaTone);
    final deltaInk = good == null ? c.textDark : appInkOn(context, deltaTone, deltaTint);
    final deltaText = d == null
        ? null
        : '${d > 0 ? '+' : ''}${d.abs() >= 100 || d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toStringAsFixed(1)}%';
    final hint = deltaHint ?? 'chart_vs_previous'.tr;
    final sem = StringBuffer('$label: $value');
    if (deltaText != null) sem.write(', $deltaText $hint');
    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          if (icon != null) ...[Icon(icon, size: AppIconSize.sm, color: appInk(context, col)), const SizedBox(width: AppSpace.xs - 2)],
          Expanded(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context)),
          ),
        ]),
        const SizedBox(height: AppSpace.xs - 2),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: AppCountUp(value, memoryKey: 'trend:$label', style: AppType.figureLarge(context)),
            ),
          ),
          if (deltaText != null) ...[
            const SizedBox(width: AppSpace.xs),
            // scales down with the value on a very narrow tile instead of overflowing
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Tooltip(
                  message: hint,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs - 2, vertical: AppSpace.xxs / 2),
                    decoration: BoxDecoration(color: deltaTint, borderRadius: BorderRadius.circular(AppRadius.pill)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(
                        up ? DirIcons.northEast : (down ? Icons.south_east_rounded : Icons.remove_rounded),
                        size: AppIconSize.xs - 2,
                        color: deltaInk,
                      ),
                      const SizedBox(width: AppSpace.xxs / 2),
                      // a signed figure reads left to right in Arabic too ("+40.7%", not "40.7%+")
                      Text(deltaText,
                          textDirection: TextDirection.ltr,
                          style: AppType.overline(context).copyWith(color: deltaInk, letterSpacing: 0)),
                    ]),
                  ),
                ),
              ),
            ),
          ],
        ]),
        if (spark != null && spark!.length >= 2) ...[
          const SizedBox(height: AppSpace.xs),
          AppSparkline(spark!, color: col, height: _sparkHeight, label: label),
        ],
      ]),
    );
    final shape = RoundedRectangleBorder(
      borderRadius: AppRadius.cardAll,
      side: BorderSide(color: c.divider, width: AppBorder.hairline),
    );
    return Semantics(
      label: sem.toString(),
      button: onTap != null,
      container: true,
      child: ExcludeSemantics(
        // a tappable tile presses in (D-582); at rest it is tone + hairline (D-612)
        child: AppPressScale(
          enabled: onTap != null,
          child: Material(
            color: c.cardBg,
            shape: shape,
            clipBehavior: Clip.antiAlias,
            child: onTap == null ? body : InkWell(onTap: onTap, child: body),
          ),
        ),
      ),
    );
  }
}
