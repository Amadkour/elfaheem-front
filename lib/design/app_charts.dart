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
// Colour (dataviz method, validated with its script on the default theme, light surface #FFFFFF and dark
// #1E2342): five categorical slots in a FIXED order — primary · accent2 (gold) · a teal derived from the primary
// hue (−60°) · purple · a rose derived from the primary hue (+90°) — each snapped into the mode's OKLab lightness
// band (light 0.45–0.72, dark 0.50–0.65) so a server theme stays legible in both modes. Series beyond five fold
// into "other" (textLight). success / warning / danger are STATUS colours and never series colours. Every chart
// is RTL-aware (the first category sits at the reading start), theme-aware (surface = cardBg, grid = divider,
// ink = text tokens) and carries a semantics label with its values.
// Layout test: test/ui/app_charts_layout_test.dart.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../config/theme/theme_config_provider.dart';

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

/// The categorical palette of the open theme (fixed order, see the header). Index past the end → "other".
List<Color> appChartPalette(BuildContext context) {
  final c = context.colors;
  final dark = c.isDark;
  final p = HSLColor.fromColor(c.primary);
  Color derived(double shift) =>
      p.withHue((p.hue + shift + 360) % 360).withSaturation(math.max(p.saturation, 0.55)).toColor();
  return [
    for (final x in [c.primary, c.accent2, derived(-60), c.purple, derived(90)]) chartSnapLightness(x, dark: dark),
  ];
}

Color _slot(BuildContext context, List<Color> palette, int i, Color? own) =>
    own ?? (i < palette.length ? palette[i] : context.colors.textLight);

String _tx(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

TextStyle _ink(Color color, {double size = 10.5, FontWeight w = FontWeight.w600}) =>
    TextStyle(fontFamily: 'tajawal', fontSize: size, fontWeight: w, color: color, height: 1.2);

double _niceMax(double v) {
  if (v <= 0) return 1;
  final e = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
  final m = v / e;
  final n = m <= 1 ? 1.0 : (m <= 2 ? 2.0 : (m <= 2.5 ? 2.5 : (m <= 5 ? 5.0 : 10.0)));
  return n * e;
}

// ─────────────────────────────────────────────────────────────────────────────
// Legend
// ─────────────────────────────────────────────────────────────────────────────

class AppLegend extends StatelessWidget {
  const AppLegend(this.entries, {super.key, this.alignment = WrapAlignment.start});
  final List<AppLegendEntry> entries;
  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Wrap(
      alignment: alignment,
      spacing: 14,
      runSpacing: 6,
      children: [
        for (final e in entries)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: e.color, borderRadius: BorderRadius.circular(3)),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(e.label,
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: _ink(c.textMedium, size: 12, w: FontWeight.w500)),
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
  const AppSparkline(this.values, {super.key, this.color, this.height = 36, this.fill = true, this.label});

  final List<double> values;
  final Color? color;
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
          child: CustomPaint(
            painter: _SparkPainter(
              values: values,
              color: col,
              surface: c.cardBg,
              fill: fill,
              rtl: Directionality.of(context) == TextDirection.rtl,
            ),
          ),
        ),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter({required this.values, required this.color, required this.surface, required this.fill, required this.rtl});
  final List<double> values;
  final Color color, surface;
  final bool fill, rtl;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || size.width <= 0 || size.height <= 0) return;
    final n = values.length;
    final lo = values.reduce(math.min);
    final hi = values.reduce(math.max);
    const pad = 5.0; // room for the end marker
    final w = size.width - pad * 2, h = size.height - pad * 2;
    Offset at(int i) {
      final t = n == 1 ? 1.0 : i / (n - 1);
      final x = pad + (rtl ? (1 - t) : t) * w;
      final y = hi == lo ? pad + h / 2 : pad + h - (values[i] - lo) / (hi - lo) * h;
      return Offset(x, y);
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
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    final end = at(n - 1);
    canvas.drawCircle(end, 6, Paint()..color = surface);   // the 2 px surface ring
    canvas.drawCircle(end, 4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparkPainter o) =>
      o.values != values || o.color != color || o.surface != surface || o.fill != fill || o.rtl != rtl;
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
            const SizedBox(height: 10),
          ],
          SizedBox(
            height: widget.height,
            width: double.infinity,
            child: empty
                ? Center(child: Text('chart_no_data'.tr, style: _ink(c.textLight, size: 12.5, w: FontWeight.w500)))
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
                        child: CustomPaint(
                          size: Size(box.maxWidth, box.maxHeight),
                          painter: _BarPainter(
                            series: widget.series,
                            labels: widget.labels,
                            colors: colors,
                            geo: geo,
                            hot: _hot,
                            surface: c.cardBg,
                            grid: c.divider,
                            ink: c.textLight,
                            inkStrong: c.textDark,
                            highlight: c.primary.withValues(alpha: 0.06),
                            format: widget.format,
                            textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                          ),
                        ),
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
    required this.ink,
    required this.inkStrong,
    required this.highlight,
    required this.format,
    required this.textDirection,
  });

  final List<AppChartSeries> series;
  final List<String> labels;
  final List<Color> colors;
  final _BarGeometry geo;
  final int? hot;
  final Color surface, grid, ink, inkStrong, highlight;
  final String Function(num) format;
  final TextDirection textDirection;

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
    final top = _niceMax(maxV);
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    final tickStyle = _ink(ink);

    // hot band
    if (hot != null) {
      final r = Rect.fromLTWH(geo.bandLeft(hot!), 0, geo.band, geo.baseline);
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(8)), Paint()..color = highlight);
    }

    // grid + ticks: 0 · ¼ · ½ · ¾ · max
    for (var k = 0; k <= 4; k++) {
      final v = top * k / 4;
      final y = geo.baseline - geo.plotH * k / 4;
      canvas.drawLine(Offset(geo.plotStart, y), Offset(geo.plotStart + geo.plotW, y), gridPaint);
      final tp = _text(format(v), tickStyle, maxWidth: _BarGeometry.axisW - 4);
      final x = geo.rtl ? size.width - tp.width : _BarGeometry.axisW - 4 - tp.width;
      tp.paint(canvas, Offset(x, y - tp.height / 2));
    }

    // bars
    for (var i = 0; i < labels.length; i++) {
      for (var s = 0; s < series.length; s++) {
        final v = _value(s, i);
        if (v <= 0) continue;
        final h = geo.plotH * (v / top);
        final x = geo.barLeft(i, s);
        final rect = Rect.fromLTWH(x, geo.baseline - h, geo.barW, h);
        final radius = Radius.circular(math.min(4, h));
        canvas.drawRRect(RRect.fromRectAndCorners(rect, topLeft: radius, topRight: radius), Paint()..color = colors[s]);
        if (hot == i) {
          final tp = _text(format(v), _ink(inkStrong, size: 10));
          final cx = x + geo.barW / 2 - tp.width / 2;
          final cy = geo.baseline - h - tp.height - 2;
          final bg = Rect.fromLTWH(cx - 3, cy - 1, tp.width + 6, tp.height + 2);
          canvas.drawRRect(RRect.fromRectAndRadius(bg, const Radius.circular(4)), Paint()..color = surface);
          tp.paint(canvas, Offset(cx, cy));
        }
      }
      // category label
      final tp = _text(labels[i], tickStyle, maxWidth: math.max(8, geo.band - 4));
      tp.paint(canvas, Offset(geo.bandLeft(i) + (geo.band - tp.width) / 2, geo.baseline + 4));
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
      o.ink != ink ||
      o.textDirection != textDirection;
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
        CustomPaint(
          size: Size(size, size),
          painter: _DonutPainter(
            values: [for (final p in parts) math.max(0.0, p.value)],
            colors: colors,
            surface: c.cardBg,
            track: c.divider,
            thickness: thickness,
            rtl: rtl,
          ),
        ),
        Padding(
          padding: EdgeInsets.all(thickness + 6),
          child: center ??
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  total > 0 ? format(total) : '—',
                  style: _ink(c.textDark, size: size * 0.18, w: FontWeight.w800),
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
          total > 0 ? '${parts[i].label} · ${(parts[i].value / total * 100).round()}%' : parts[i].label,
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
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [for (final e in entries) Padding(padding: const EdgeInsets.only(bottom: 6), child: AppLegend([e]))],
                ),
              ),
            ]);
          }
          return Column(mainAxisSize: MainAxisSize.min, children: [
            ring,
            const SizedBox(height: 10),
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
  });
  final List<double> values;
  final List<Color> colors;
  final Color surface, track;
  final double thickness;
  final bool rtl;

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
    final shown = values.where((v) => v > 0).length;
    final gap = shown > 1 ? 2.0 / r : 0.0;   // a 2 px surface gap between parts
    var start = -math.pi / 2;
    final dir = rtl ? -1.0 : 1.0;
    for (var i = 0; i < values.length; i++) {
      if (values[i] <= 0) continue;
      final sweep = values[i] / total * math.pi * 2;
      final drawn = math.max(0.0, sweep - gap);
      canvas.drawArc(rect, start + dir * gap / 2, dir * drawn, false, stroke..color = colors[i]);
      start += dir * sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter o) =>
      o.values != values || o.colors != colors || o.surface != surface || o.track != track || o.rtl != rtl;
}

// ─────────────────────────────────────────────────────────────────────────────
// Trend tile
// ─────────────────────────────────────────────────────────────────────────────

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

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = color ?? appChartPalette(context).first;
    final d = delta;
    final up = d != null && d > 0;
    final down = d != null && d < 0;
    final good = d == null || d == 0 ? null : (up == upIsGood);
    final deltaColor = good == null ? c.textLight : (good ? c.success : c.danger);
    final deltaText = d == null
        ? null
        : '${d > 0 ? '+' : ''}${d.abs() >= 100 || d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toStringAsFixed(1)}%';
    final hint = deltaHint ?? 'chart_vs_previous'.tr;
    final sem = StringBuffer('$label: $value');
    if (deltaText != null) sem.write(', $deltaText $hint');
    final body = Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(c.radiusLarge - 4),
        border: Border.all(color: c.divider),
        boxShadow: c.cardShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          if (icon != null) ...[Icon(icon, size: 16, color: col), const SizedBox(width: 6)],
          Expanded(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: _ink(c.textMedium, size: 12.5, w: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(value, maxLines: 1, style: _ink(c.textDark, size: 24, w: FontWeight.w800)),
            ),
          ),
          if (deltaText != null) ...[
            const SizedBox(width: 8),
            // scales down with the value on a very narrow tile instead of overflowing
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Tooltip(
                  message: hint,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration:
                        BoxDecoration(color: deltaColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(
                        up ? Icons.north_east_rounded : (down ? Icons.south_east_rounded : Icons.remove_rounded),
                        size: 12,
                        color: deltaColor,
                      ),
                      const SizedBox(width: 2),
                      Text(deltaText, style: _ink(deltaColor, size: 11, w: FontWeight.w700)),
                    ]),
                  ),
                ),
              ),
            ),
          ],
        ]),
        if (spark != null && spark!.length >= 2) ...[
          const SizedBox(height: 8),
          AppSparkline(spark!, color: col, height: 30, label: label),
        ],
      ]),
    );
    return Semantics(
      label: sem.toString(),
      button: onTap != null,
      container: true,
      child: ExcludeSemantics(
        child: onTap == null
            ? body
            : Material(
                color: Colors.transparent,
                child: InkWell(borderRadius: BorderRadius.circular(c.radiusLarge - 4), onTap: onTap, child: body),
              ),
      ),
    );
  }
}
