// lib/features/shared/analytics/analytics_summary_ui.dart
// The presentational half of the Analytics tabs (student and instructor). Every widget takes plain values, reads no
// provider and makes no request, so the layout harness and the visual renders pump them directly.
//
//   AnSummaryLayout   the page: header · hero · stat tiles · "For you" · the course chart · compact lists
//                     phone: one column (16 gutters, 16 between blocks) · wide (>= 960): hero | For you, the tiles
//                     across, chart | lists — capped at 1200 and centred
//   AnPageHeader      large title + one line + trailing actions (refresh for mouse users, a link)
//   AnSummaryHero     the headline: concentric rings (progress · attendance · exams, Apple-Fitness style), the
//                     overall figure in the middle, ONE sentence, and a legend with "+6 vs class" per ring
//   AnActivityRings   the rings themselves (CustomPaint, animated once; a lone ring when only one figure exists)
//   AnStatTiles       3–4 count tiles (AppTrendTile) — 2 per row on a phone, one row on wide
//   AnInsightCard     up to three plain-language nudges, each with an action
//   AnSegmented       the segmented control (iOS style)
//   AnCourseBars      one horizontal bar per course for the chosen metric, the class average as a tick, the first
//                     5 + "Show all"
//   AnCompactList     a titled card of slim rows: the first 3 + "Show all (n)" that unfolds in place
//   AnExamRow · AnPersonRow   rows for the compact lists
//   AnSummarySkeleton the page's shape while it loads (shimmer, no spinner)
//
// Colours: the three metrics keep ONE categorical slot each across rings, legend and bars (appChartPalette 0 · 1 ·
// 2 — colour follows the entity); status colours (success / warning / danger) only mark state, always with an icon
// or a word. Text wears text tokens. Layout test: test/ui/analytics_summary_layout_test.dart.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import 'analytics_summary.dart';
import 'analytics_ui.dart' show anPct, anTr, anFmt;

/// The metric's colour (the same in the rings, the legend and the bars).
Color anMetricColor(BuildContext context, AnMetric m) => appChartPalette(context)[switch (m) {
      AnMetric.progress => 0,
      AnMetric.attendance => 1,
      AnMetric.exams => 2,
    }];

IconData anMetricIcon(AnMetric m) => switch (m) {
      AnMetric.progress => Icons.route_rounded,
      AnMetric.attendance => Icons.event_available_rounded,
      AnMetric.exams => Icons.quiz_rounded,
    };

String anMetricLabel(AnMetric m) => switch (m) {
      AnMetric.progress => anTr('dl_progress', 'Progress'),
      AnMetric.attendance => anTr('dl_attendance', 'Attendance'),
      AnMetric.exams => anTr('dl_exams', 'Exams'),
    };

/// From here the page has two columns (chart | For you + lists); from [kAnWide] wider gutters.
const double kAnTwoColumns = 720;
const double kAnWide = 960;

// ─────────────────────────────────────────────────────────────────────────────
// Surface
// ─────────────────────────────────────────────────────────────────────────────

class AnSurface extends StatelessWidget {
  const AnSurface({super.key, required this.child, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.divider.withValues(alpha: 0.7), width: 0.8),
        boxShadow: c.cardShadow,
      ),
      child: child,
    );
  }
}

class _CardTitle extends StatelessWidget {
  const _CardTitle(this.title, {this.trailing, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(16, w: FontWeight.w800, c: c.textDark)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(12, c: c.textMedium, h: 1.35)),
          ],
        ]),
      ),
      if (trailing != null) const SizedBox(width: 12),
      ?trailing,
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Page layout
// ─────────────────────────────────────────────────────────────────────────────

class AnSummaryLayout extends StatelessWidget {
  const AnSummaryLayout({
    super.key,
    required this.header,
    required this.hero,
    this.tiles,
    this.insights,
    this.chart,
    this.lists = const [],
  });

  final Widget header, hero;
  final Widget? tiles, insights, chart;
  final List<Widget> lists;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= kAnTwoColumns;
      const gap = SizedBox(height: 16, width: 16);
      if (!wide) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            header,
            gap,
            hero,
            if (tiles != null) ...[gap, tiles!],
            if (insights != null) ...[gap, insights!],
            if (chart != null) ...[gap, chart!],
            for (final l in lists) ...[gap, l],
          ]),
        );
      }
      final side = [?insights, ...lists];
      final pad = box.maxWidth >= kAnWide ? 32.0 : 24.0;
      return Align(
        alignment: AlignmentDirectional.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Padding(
            padding: EdgeInsets.fromLTRB(pad, 16, pad, 40),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              header,
              const SizedBox(height: 24),
              hero,
              if (tiles != null) ...[gap, tiles!],
              gap,
              if (chart == null)
                for (var i = 0; i < side.length; i++) ...[if (i > 0) gap, side[i]]
              else
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 7, child: chart!),
                  if (side.isNotEmpty) ...[
                    gap,
                    Expanded(
                      flex: 5,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        for (var i = 0; i < side.length; i++) ...[if (i > 0) gap, side[i]],
                      ]),
                    ),
                  ],
                ]),
            ]),
          ),
        ),
      );
    });
  }
}

class AnPageHeader extends StatelessWidget {
  const AnPageHeader({super.key, required this.title, this.subtitle, this.actions = const []});

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(28, w: FontWeight.w800, c: c.textDark, h: 1.15)),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(13.5, c: c.textMedium, h: 1.35)),
              ],
            ]),
          ),
          ...actions,
        ]),
      ),
    );
  }
}

/// A round 48×48 icon button for the header (refresh for mouse users …).
class AnHeaderIcon extends StatelessWidget {
  const AnHeaderIcon({super.key, required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: c.cardBg,
        shape: CircleBorder(side: BorderSide(color: c.divider)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 48, height: 48, child: Icon(icon, size: 21, color: c.textMedium)),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero
// ─────────────────────────────────────────────────────────────────────────────

class AnRingSpec {
  const AnRingSpec({required this.metric, required this.value, this.delta, this.detail});

  final AnMetric metric;
  final double? value;

  /// You minus the class, in points (null = no class figure).
  final double? delta;

  /// A small line under the value ("38 of 44 sessions").
  final String? detail;
}

class AnActivityRings extends StatelessWidget {
  const AnActivityRings({super.key, required this.values, required this.colors, this.size = 140, this.center});

  /// 0–100 each, outermost first; null draws the empty track.
  final List<double?> values;
  final List<Color> colors;
  final double size;
  final Widget? center;

  @override
  Widget build(BuildContext context) {
    final track = context.colors.isDark ? 0.20 : 0.14;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (_, t, child) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingsPainter(values: values, colors: colors, t: t, trackAlpha: track),
          child: Center(child: child),
        ),
      ),
      child: center,
    );
  }
}

class _RingsPainter extends CustomPainter {
  _RingsPainter({required this.values, required this.colors, required this.t, required this.trackAlpha});

  final List<double?> values;
  final List<Color> colors;
  final double t, trackAlpha;

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    if (n == 0) return;
    final r0 = size.shortestSide / 2;
    final stroke = n == 1 ? r0 * 0.20 : r0 * 0.155;
    final gap = r0 * 0.04;
    final c = size.center(Offset.zero);
    for (var i = 0; i < n; i++) {
      final r = r0 - stroke / 2 - i * (stroke + gap);
      if (r <= stroke / 2) break;
      final rect = Rect.fromCircle(center: c, radius: r);
      final col = colors[i % colors.length];
      canvas.drawCircle(c, r, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = col.withValues(alpha: trackAlpha));
      final v = ((values[i] ?? 0) / 100).clamp(0.0, 1.0) * t;
      if (v <= 0) continue;
      canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * v, false, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = col);
    }
  }

  @override
  bool shouldRepaint(_RingsPainter o) => o.t != t || o.values != values || o.colors != colors || o.trackAlpha != trackAlpha;
}

class AnSummaryHero extends StatelessWidget {
  const AnSummaryHero({super.key, required this.headline, required this.rings, this.overall, this.overallLabel, this.footer});

  final String headline;
  final List<AnRingSpec> rings;
  final double? overall;
  final String? overallLabel;

  /// Under the legend (e.g. "My full analytics profile").
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AnSurface(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: LayoutBuilder(builder: (context, box) {
        final ringSize = box.maxWidth >= 520 ? 168.0 : (box.maxWidth >= 330 ? 132.0 : 112.0);
        final stack = box.maxWidth < 300;
        final ringsW = Semantics(
          label: '${overallLabel ?? anTr('an2_overall', 'Overall')} ${anPct(overall)}',
          child: AnActivityRings(
            size: ringSize,
            values: [for (final r in rings) r.value],
            colors: [for (final r in rings) anMetricColor(context, r.metric)],
            center: ExcludeSemantics(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(anPct(overall), style: appText(ringSize * 0.17, w: FontWeight.w800, c: c.textDark, h: 1.0)),
                const SizedBox(height: 2),
                Text(overallLabel ?? anTr('an2_overall', 'Overall'), style: appText(ringSize * 0.075 + 2, w: FontWeight.w600, c: c.textMedium)),
              ]),
            ),
          ),
        );
        final legend = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < rings.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _LegendRow(spec: rings[i]),
          ],
        ]);
        if (rings.length == 1) {
          // a lone ring already says its figure in the middle: no legend, the sentence beside it
          final small = box.maxWidth < 600 ? (box.maxWidth >= 330 ? 112.0 : 96.0) : 140.0;
          final lone = rings.first;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Semantics(
                label: '${overallLabel ?? anMetricLabel(lone.metric)} ${anPct(overall)}',
                child: AnActivityRings(
                  size: small,
                  values: [lone.value],
                  colors: [anMetricColor(context, lone.metric)],
                  center: ExcludeSemantics(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(anPct(overall), style: appText(small * 0.2, w: FontWeight.w800, c: c.textDark, h: 1.0)),
                      const SizedBox(height: 2),
                      Text(overallLabel ?? anMetricLabel(lone.metric), style: appText(11, w: FontWeight.w600, c: c.textMedium)),
                    ]),
                  ),
                ),
              ),
              SizedBox(width: box.maxWidth >= 600 ? 32 : 20),
              Expanded(child: Text(headline, style: appText(box.maxWidth >= 600 ? 21 : 17, w: FontWeight.w700, c: c.textDark, h: 1.4))),
            ]),
            if (footer != null) ...[const SizedBox(height: 16), footer!],
          ]);
        }
        if (box.maxWidth >= 600) {
          // wide: rings on the start, the sentence over a legend laid out across
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              ringsW,
              const SizedBox(width: 32),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(headline, style: appText(21, w: FontWeight.w700, c: c.textDark, h: 1.35)),
                  const SizedBox(height: 20),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (var i = 0; i < rings.length; i++) ...[
                      if (i > 0) const SizedBox(width: 16),
                      Expanded(child: _LegendRow(spec: rings[i])),
                    ],
                  ]),
                ]),
              ),
            ]),
            if (footer != null) ...[const SizedBox(height: 16), footer!],
          ]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(headline, style: appText(17.5, w: FontWeight.w700, c: c.textDark, h: 1.4)),
          const SizedBox(height: 20),
          if (stack) ...[Center(child: ringsW), const SizedBox(height: 16), legend]
          else
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              ringsW,
              SizedBox(width: box.maxWidth >= 520 ? 32 : 20),
              Expanded(child: legend),
            ]),
          if (footer != null) ...[const SizedBox(height: 16), footer!],
        ]);
      }),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.spec});

  final AnRingSpec spec;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = anMetricColor(context, spec.metric);
    final d = spec.delta;
    final sem = StringBuffer('${anMetricLabel(spec.metric)} ${anPct(spec.value)}');
    if (d != null) sem.write(', ${_signed(d)} ${anTr('an2_vs_class', 'vs class')}');
    return Semantics(
      label: sem.toString(),
      container: true,
      child: ExcludeSemantics(
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Container(width: 4, height: 36, decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(4))),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(anMetricLabel(spec.metric), maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12, w: FontWeight.w600, c: c.textMedium)),
              const SizedBox(height: 1),
              Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Text(anPct(spec.value), style: appText(19, w: FontWeight.w800, c: c.textDark, h: 1.15)),
                if (d != null) ...[
                  const SizedBox(width: 8),
                  Flexible(child: AnDeltaChip(delta: d)),
                ],
              ]),
              if (spec.detail != null)
                Text(spec.detail!, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(11, c: c.textLight)),
            ]),
          ),
        ]),
      ),
    );
  }
}

String _signed(double d) => '${d >= 0.5 ? '+' : (d <= -0.5 ? '−' : '±')}${d.abs().round()}';

/// "+6 vs class" — green up, red down, grey level; the arrow says it too.
class AnDeltaChip extends StatelessWidget {
  const AnDeltaChip({super.key, required this.delta, this.suffix});

  final double delta;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final up = delta >= 0.5, down = delta <= -0.5;
    final tone = up ? c.success : (down ? c.danger : c.textLight);
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: tone.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (!up && !down)
            Text(anTr('an2_same_as_class', 'Same as class'), style: appText(10.5, w: FontWeight.w700, c: c.textMedium))
          else ...[
            Icon(up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 11, color: appInk(context, tone)),
            const SizedBox(width: 2),
            Text(_signed(delta), textDirection: TextDirection.ltr, style: appText(11, w: FontWeight.w800, c: appInk(context, tone))),
            const SizedBox(width: 3),
            Text(suffix ?? anTr('an2_vs_class', 'vs class'), style: appText(10.5, w: FontWeight.w600, c: appInk(context, tone))),
          ],
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stat tiles
// ─────────────────────────────────────────────────────────────────────────────

class AnTileSpec {
  const AnTileSpec({required this.icon, required this.label, required this.value, this.color, this.onTap});
  final IconData icon;
  final String label, value;
  final Color? color;
  final VoidCallback? onTap;
}

class AnStatTiles extends StatelessWidget {
  const AnStatTiles({super.key, required this.tiles});

  final List<AnTileSpec> tiles;

  @override
  Widget build(BuildContext context) {
    final shown = tiles.take(4).toList();
    return LayoutBuilder(builder: (context, box) {
      final cols = box.maxWidth >= 640 ? shown.length : 2;
      const gap = 12.0;
      final w = (box.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(spacing: gap, runSpacing: gap, children: [
        for (final t in shown)
          SizedBox(
            width: w,
            child: AppTrendTile(label: t.label, value: t.value, icon: t.icon, color: t.color, onTap: t.onTap),
          ),
      ]);
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Insights
// ─────────────────────────────────────────────────────────────────────────────

class AnInsightRowData {
  const AnInsightRowData({required this.tone, required this.text, this.onTap});
  final AnTone tone;
  final String text;
  final VoidCallback? onTap;
}

class AnInsightCard extends StatelessWidget {
  const AnInsightCard({super.key, required this.title, required this.rows});

  final String title;
  final List<AnInsightRowData> rows;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AnSurface(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.auto_awesome_rounded, size: 18, color: appInk(context, c.primary)),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: appText(16, w: FontWeight.w800, c: c.textDark))),
        ]),
        const SizedBox(height: 8),
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) Divider(height: 1, thickness: 0.7, color: c.divider.withValues(alpha: 0.7), indent: 44),
          _InsightRow(row: rows[i]),
        ],
      ]),
    );
  }
}

class _InsightRow extends StatelessWidget {
  const _InsightRow({required this.row});

  final AnInsightRowData row;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (tone, icon) = switch (row.tone) {
      AnTone.warn => (c.warning, Icons.flag_rounded),
      AnTone.info => (c.primary, Icons.lightbulb_rounded),
      AnTone.good => (c.success, Icons.celebration_rounded),
    };
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: row.onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: tone.withValues(alpha: 0.13), shape: BoxShape.circle),
              child: Icon(icon, size: 16, color: appInk(context, tone)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(row.text, style: appText(13.5, w: FontWeight.w500, c: c.textDark, h: 1.45)),
              ),
            ),
            if (row.onTap != null) ...[
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 7),
                child: Icon(Icons.chevron_right_rounded, size: 20, color: c.textLight),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Segmented control
// ─────────────────────────────────────────────────────────────────────────────

class AnSegmented<T> extends StatelessWidget {
  const AnSegmented({super.key, required this.options, required this.value, required this.onChanged});

  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.isDark ? c.background : c.divider.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final (v, label) in options)
          Flexible(
            child: Semantics(
              button: true,
              selected: v == value,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(v),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: v == value ? c.cardBg : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: v == value
                        ? [BoxShadow(color: Colors.black.withValues(alpha: c.isDark ? 0.3 : 0.08), blurRadius: 6, offset: const Offset(0, 1))]
                        : null,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(label,
                        maxLines: 1,
                        style: appText(12.5, w: v == value ? FontWeight.w800 : FontWeight.w600, c: v == value ? c.textDark : c.textMedium)),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Course bars
// ─────────────────────────────────────────────────────────────────────────────

class AnBarRowData {
  const AnBarRowData({required this.title, required this.value, this.classValue, this.detail, this.flag = false, this.onTap});
  final String title;
  final double? value, classValue;

  /// Next to the value ("7/12").
  final String? detail;

  /// Needs attention (a small warning dot before the title, with its own label for screen readers).
  final bool flag;
  final VoidCallback? onTap;
}

class AnCourseBars extends StatelessWidget {
  const AnCourseBars({
    super.key,
    required this.title,
    required this.metric,
    required this.metrics,
    required this.onMetric,
    required this.rows,
    this.maxRows = 5,
    this.onShowAll,
    this.showAllLabel,
    this.youLabel,
  });

  final String title;
  final AnMetric metric;
  final List<AnMetric> metrics;
  final ValueChanged<AnMetric> onMetric;
  final List<AnBarRowData> rows;
  final int maxRows;
  final VoidCallback? onShowAll;
  final String? showAllLabel;
  final String? youLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = anMetricColor(context, metric);
    final shown = rows.take(maxRows).toList();
    final hasClass = shown.any((r) => r.classValue != null);
    final hasFlag = shown.any((r) => r.flag);
    return AnSurface(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: LayoutBuilder(builder: (context, box) {
        final seg = metrics.length > 1
            ? AnSegmented<AnMetric>(
                options: [for (final m in metrics) (m, anMetricLabel(m))],
                value: metric,
                onChanged: onMetric,
              )
            : null;
        final inline = seg != null && box.maxWidth >= 560;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _CardTitle(title, trailing: inline ? seg : null),
          if (seg != null && !inline) ...[const SizedBox(height: 12), seg],
          const SizedBox(height: 8),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(anTr('chart_no_data', 'No data yet'), textAlign: TextAlign.center, style: appText(13, c: c.textLight)),
            ),
          for (final r in shown) _BarRow(row: r, color: col),
          if (hasClass || hasFlag) ...[
            const SizedBox(height: 4),
            _BarsLegend(color: col, you: youLabel ?? anTr('an2_you', 'You'), classMark: hasClass, flag: hasFlag),
            const SizedBox(height: 4),
          ],
          if (onShowAll != null) ...[
            Divider(height: 16, thickness: 0.7, color: c.divider.withValues(alpha: 0.7)),
            AnShowAllRow(label: showAllLabel ?? anFmt('an2_show_all', {'n': rows.length}, 'Show all ({n})'), onTap: onShowAll!),
          ],
        ]);
      }),
    );
  }
}

class _BarRow extends StatelessWidget {
  const _BarRow({required this.row, required this.color});

  final AnBarRowData row;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final v = row.value;
    final sem = StringBuffer('${row.title}: ${anPct(v)}');
    if (row.classValue != null) sem.write(', ${anTr('an2_class_avg', 'Class average')} ${anPct(row.classValue)}');
    if (row.flag) sem.write(', ${anTr('an_needs_attention', 'Needs attention')}');
    return Semantics(
      label: sem.toString(),
      button: row.onTap != null,
      container: true,
      child: ExcludeSemantics(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: row.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                if (row.flag) ...[
                  Container(width: 7, height: 7, decoration: BoxDecoration(color: c.warning, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(row.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13.5, w: FontWeight.w700, c: c.textDark)),
                ),
                const SizedBox(width: 8),
                if (row.detail != null) ...[
                  Text(row.detail!, style: appText(11.5, c: c.textLight)),
                  const SizedBox(width: 8),
                ],
                Text(anPct(v), style: appText(14, w: FontWeight.w800, c: v == null ? c.textLight : c.textDark)),
              ]),
              const SizedBox(height: 8),
              _Bar(value: v, marker: row.classValue, color: color),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.value, required this.marker, required this.color});

  final double? value, marker;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pct = ((value ?? 0) / 100).clamp(0.0, 1.0);
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      return SizedBox(
        height: 14,
        child: Stack(alignment: AlignmentDirectional.centerStart, clipBehavior: Clip.none, children: [
          Container(height: 8, decoration: BoxDecoration(color: color.withValues(alpha: c.isDark ? 0.18 : 0.13), borderRadius: BorderRadius.circular(8))),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: pct),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (_, t, _) => Container(
              width: math.max(t > 0 ? 8 : 0, w * t),
              height: 8,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
            ),
          ),
          if (marker != null)
            PositionedDirectional(
              start: (w * (marker! / 100).clamp(0.0, 1.0) - 1.5).clamp(0.0, math.max(0.0, w - 3)),
              child: Container(
                width: 3,
                height: 14,
                decoration: BoxDecoration(
                  color: c.textDark.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(color: c.cardBg, width: 0.8),
                ),
              ),
            ),
        ]),
      );
    });
  }
}

class _BarsLegend extends StatelessWidget {
  const _BarsLegend({required this.color, required this.you, this.classMark = true, this.flag = false});

  final Color color;
  final String you;
  final bool classMark, flag;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Wrap(spacing: 16, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
      if (classMark) ...[
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 14, height: 8, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
          const SizedBox(width: 6),
          Text(you, style: appText(11.5, w: FontWeight.w600, c: c.textMedium)),
        ]),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 3, height: 12, decoration: BoxDecoration(color: c.textDark.withValues(alpha: 0.75), borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 6),
          Text(anTr('an2_class_avg', 'Class average'), style: appText(11.5, w: FontWeight.w600, c: c.textMedium)),
        ]),
      ],
      if (flag)
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: c.warning, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(anTr('an_needs_attention', 'Needs attention'), style: appText(11.5, w: FontWeight.w600, c: c.textMedium)),
        ]),
    ]);
  }
}

class AnShowAllRow extends StatelessWidget {
  const AnShowAllRow({super.key, required this.label, required this.onTap, this.expanded = false});

  final String label;
  final VoidCallback onTap;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: SizedBox(
        height: 44,
        child: Row(children: [
          Expanded(child: Text(label, style: appText(13.5, w: FontWeight.w700, c: appInk(context, c.primary)))),
          Icon(expanded ? Icons.keyboard_arrow_up_rounded : Icons.chevron_right_rounded, size: 20, color: appInk(context, c.primary)),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Compact lists
// ─────────────────────────────────────────────────────────────────────────────

/// A titled card of slim rows: the first [visible] and "Show all (n)", which unfolds the rest in place.
class AnCompactList extends StatefulWidget {
  const AnCompactList({super.key, required this.title, required this.rows, this.visible = 3, this.subtitle, this.empty});

  final String title;
  final String? subtitle;
  final List<Widget> rows;
  final int visible;

  /// Shown instead of rows when there are none (null hides the whole card).
  final String? empty;

  @override
  State<AnCompactList> createState() => _AnCompactListState();
}

class _AnCompactListState extends State<AnCompactList> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (widget.rows.isEmpty && widget.empty == null) return const SizedBox.shrink();
    final rows = _open ? widget.rows : widget.rows.take(widget.visible).toList();
    final more = widget.rows.length > widget.visible;
    return AnSurface(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _CardTitle(widget.title, subtitle: widget.subtitle),
        const SizedBox(height: 4),
        if (widget.rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(widget.empty!, textAlign: TextAlign.center, style: appText(13, c: c.textLight, h: 1.45)),
          ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: AlignmentDirectional.topStart,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Divider(height: 1, thickness: 0.7, color: c.divider.withValues(alpha: 0.7)),
              rows[i],
            ],
          ]),
        ),
        if (more) ...[
          Divider(height: 1, thickness: 0.7, color: c.divider.withValues(alpha: 0.7)),
          AnShowAllRow(
            expanded: _open,
            label: _open ? anTr('an2_show_less', 'Show less') : anFmt('an2_show_all', {'n': widget.rows.length}, 'Show all ({n})'),
            onTap: () => setState(() => _open = !_open),
          ),
        ] else
          const SizedBox(height: 8),
      ]),
    );
  }
}

/// One exam: name · course on the start, the score and Passed / Below pass on the end.
class AnExamRow extends StatelessWidget {
  const AnExamRow({super.key, required this.name, required this.course, required this.score, this.passed, this.onTap});

  final String name, course;
  final double? score;
  final bool? passed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = passed ?? (score != null && score! >= 50);
    final tone = p ? c.success : c.danger;
    final word = p ? anTr('an2_passed', 'Passed') : anTr('an2_below_pass', 'Below pass');
    return Semantics(
      label: '$name, $course: ${anPct(score)}, $word',
      button: onTap != null,
      container: true,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13.5, w: FontWeight.w700, c: c.textDark)),
                    const SizedBox(height: 2),
                    Text(course, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12, c: c.textMedium)),
                  ]),
                ),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(anPct(score), style: appText(15, w: FontWeight.w800, c: c.textDark)),
                  const SizedBox(height: 2),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(p ? Icons.check_circle_rounded : Icons.error_rounded, size: 12, color: appInk(context, tone)),
                    const SizedBox(width: 3),
                    Text(word, style: appText(11, w: FontWeight.w700, c: appInk(context, tone))),
                  ]),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// One student who needs attention: initial, name · course, and the low figures with their icon.
class AnPersonRow extends StatelessWidget {
  const AnPersonRow({super.key, required this.name, required this.course, this.attendance, this.exams, this.onTap});

  final String name, course;
  final double? attendance, exams;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final initial = name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
    Widget figure(IconData icon, double? v, double limit) {
      final low = v != null && v < limit;
      final ink = low ? appInk(context, c.danger) : c.textMedium;
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: ink),
        const SizedBox(width: 3),
        Text(anPct(v), style: appText(12, w: FontWeight.w800, c: ink)),
      ]);
    }

    return Semantics(
      label: '$name, $course. ${anMetricLabel(AnMetric.attendance)} ${anPct(attendance)}, ${anMetricLabel(AnMetric.exams)} ${anPct(exams)}',
      button: onTap != null,
      container: true,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: Text(initial, style: appText(14, w: FontWeight.w800, c: appInk(context, c.primary))),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13.5, w: FontWeight.w700, c: c.textDark)),
                    const SizedBox(height: 2),
                    Text(course, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12, c: c.textMedium)),
                  ]),
                ),
                const SizedBox(width: 8),
                figure(Icons.event_available_rounded, attendance, kAnLowAttendance),
                const SizedBox(width: 10),
                figure(Icons.quiz_rounded, exams, kAnLowExams),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Skeleton
// ─────────────────────────────────────────────────────────────────────────────

class AnSummarySkeleton extends StatelessWidget {
  const AnSummarySkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    Widget card(double h) => AnSurface(child: SizedBox(height: h));
    return AppShimmer(
      child: AnSummaryLayout(
        header: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(height: 8),
          AppSkeletonBox(width: 160, height: 26),
          SizedBox(height: 10),
          AppSkeletonBox(width: 220, height: 12),
        ]),
        hero: AnSurface(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const AppSkeletonBox(height: 16),
            const SizedBox(height: 8),
            const AppSkeletonBox(width: 180, height: 16),
            const SizedBox(height: 20),
            Row(children: [
              const AppSkeletonBox(width: 120, height: 120, radius: 60),
              const SizedBox(width: 20),
              Expanded(
                child: Column(children: [
                  for (var i = 0; i < 3; i++) ...[if (i > 0) const SizedBox(height: 14), const AppSkeletonBox(height: 28)],
                ]),
              ),
            ]),
          ]),
        ),
        tiles: AnStatTiles(tiles: [
          for (var i = 0; i < 4; i++) const AnTileSpec(icon: Icons.circle, label: ' ', value: ' '),
        ]),
        insights: card(140),
        chart: card(260),
      ),
    );
  }
}
