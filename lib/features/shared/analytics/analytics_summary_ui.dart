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
// Colours: the three metrics keep ONE colour each across rings, legend and bars (anMetricColors: the primary, then
// palette slots kept 70° of OKLCH hue apart — colour follows the entity); status colours (success / warning / danger) only mark state, always with an icon
// or a word. Text wears text tokens. Layout test: test/ui/analytics_summary_layout_test.dart.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';
import 'package:flutter_education_app/design/chrome_button.dart' show ChromeIconButton;

import 'analytics_summary.dart';
import 'analytics_ui.dart' show anPct, anTr, anFmt;
import 'package:flutter_education_app/design/app_shell_nav.dart' show ShellChrome;

/// The metric's colour (the same in the rings, the legend, the bars and the tiles).
Color anMetricColor(BuildContext context, AnMetric m) => anMetricColors(context)[m.index];

/// The three metric colours, in [AnMetric] order. Progress is the theme's primary (palette slot 0). Attendance and
/// exams take, in the palette's own order (peach · sage · gold · terracotta, then hues derived from the primary at
/// +120° / −120° / +150° as a last resort), the first colour whose OKLCH hue sits at least [_kMetricHueGap] away from
/// the colours already taken (D-632: the theme's tones come first, so an emerald theme draws emerald · gold ·
/// terracotta, not a violet from the primary +120°). A fixed slot 2 made a teal or green primary (the Normal and Green presets) draw progress
/// and exams in two greens; the Blue preset keeps indigo · gold · teal. Every candidate sits in the mode's lightness
/// band (chartSnapLightness), so the three read in light and dark.
List<Color> anMetricColors(BuildContext context) =>
    anDistinctColors(appChartPalette(context), dark: context.colors.isDark, n: 3);

/// A fourth colour for a tile that sits beside the three metric tiles (students, saved to review …), kept apart from
/// them the same way.
Color anSpareColor(BuildContext context) =>
    anDistinctColors(appChartPalette(context), dark: context.colors.isDark, n: 4).last;

/// The pure half of [anMetricColors]: [n] colours from [palette] (appChartPalette, slot 0 = the primary) and the
/// hues derived from its primary, each [_kMetricHueGap] of OKLCH hue away from the ones before when possible.
@visibleForTesting
List<Color> anDistinctColors(List<Color> palette, {required bool dark, int n = 3}) {
  final p = HSLColor.fromColor(palette[0]);
  Color derived(double shift) => chartSnapLightness(
      p.withHue((p.hue + shift + 360) % 360).withSaturation(math.max(p.saturation, 0.55)).toColor(),
      dark: dark);
  // the theme's own tones first; a hue derived from the primary only when none of them is even [_kMetricMinGap]
  // apart (D-632: an emerald primary +120° is a violet the theme never chose)
  final own = palette.skip(1).toList();
  final spare = [derived(120), derived(-120), derived(150)];
  final taken = [palette[0]];
  (Color?, double) pick(List<Color> from) {
    Color? best;
    var bestGap = -1.0;
    for (final x in from) {
      if (taken.contains(x)) continue;
      final gap = taken.map((t) => _hueGap(x, t)).reduce(math.min);
      if (gap >= _kMetricHueGap) return (x, gap);
      if (gap > bestGap) {
        best = x;
        bestGap = gap;
      }
    }
    return (best, bestGap);
  }

  while (taken.length < n) {
    final (ownBest, ownGap) = pick(own);
    taken.add(ownBest != null && ownGap >= _kMetricMinGap ? ownBest : (pick(spare).$1 ?? ownBest)!);
  }
  return taken;
}

/// The smallest OKLCH hue distance (degrees) that keeps two metric colours apart at a glance (with the lightness
/// band, 45° tells gold from terracotta; D-632).
const double _kMetricHueGap = 45;

/// Below this hue distance a theme tone is no longer told apart even with the lightness band, and a derived hue
/// takes the slot.
const double _kMetricMinGap = 20;

/// OKLCH hue distance between [a] and [b] in degrees (0–180); 0 when either is nearly grey (no usable hue).
@visibleForTesting
double anHueGap(Color a, Color b) => _hueGap(a, b);

double _hueGap(Color a, Color b) {
  final (ca, ha) = _oklch(a);
  final (cb, hb) = _oklch(b);
  if (ca < 0.04 || cb < 0.04) return 0;
  final d = (ha - hb).abs() % 360;
  return d > 180 ? 360 - d : d;
}

/// OKLCH chroma and hue (degrees) of [col].
(double, double) _oklch(Color col) {
  double lin(double v) => v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  final r = lin(col.r), g = lin(col.g), b = lin(col.b);
  double cbrt(double v) => v < 0 ? -math.pow(-v, 1 / 3).toDouble() : math.pow(v, 1 / 3).toDouble();
  final l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
  final m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
  final s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
  final aa = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s;
  final bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s;
  return (math.sqrt(aa * aa + bb * bb), (math.atan2(bb, aa) * 180 / math.pi + 360) % 360);
}

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

/// Paper (D-612): the card surface on a warm hairline, radius `card`, no resting shadow — the hero is the block.
class AnSurface extends StatelessWidget {
  const AnSurface({super.key, required this.child, this.padding = AppSpace.card});

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
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: c.divider, width: AppBorder.hairline),
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
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
          if (subtitle != null) ...[
            const SizedBox(height: AppSpace.xxs),
            Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
          ],
        ]),
      ),
      if (trailing != null) AppSpace.gapSm,
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
      const gap = AppSpace.gapMd;
      if (!wide) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.xl),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            header,
            AppSpace.gapLg,
            hero,
            if (tiles != null) ...[gap, tiles!],
            if (insights != null) ...[gap, insights!],
            if (chart != null) ...[gap, chart!],
            for (final l in lists) ...[gap, l],
          ]),
        );
      }
      final side = [?insights, ...lists];
      final pad = box.maxWidth >= kAnWide ? AppSpace.xl : AppSpace.lg;
      return Align(
        alignment: AlignmentDirectional.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: AppWidth.wide.max),
          child: Padding(
            padding: EdgeInsets.fromLTRB(pad, AppSpace.md, pad, AppSpace.xxl),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              header,
              AppSpace.gapLg,
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
    // a tab's first page: the shell's bar above already says it (D-551), so only the line under the title remains here
    final titled = !ShellChrome.ownsHeaderOf(context);
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.only(top: AppSpace.xs),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (titled) Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.pageTitle(context)),
              if (subtitle != null) ...[
                if (titled) const SizedBox(height: AppSpace.xxs),
                Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.body(context)),
              ],
            ]),
          ),
          ...actions,
        ]),
      ),
    );
  }
}

/// The header's icon button (refresh for mouse users …): the kit's paper chrome plate in a 48 px target.
class AnHeaderIcon extends StatelessWidget {
  const AnHeaderIcon({super.key, required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ChromeIconButton(icon: icon, label: tooltip, onTap: onTap);
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
    final track = context.colors.isDark ? 0.22 : 0.16;
    // the rings draw in once with the hero's entrance; still under Reduce motion
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: appMotionOff(context) ? 1 : 0, end: 1),
      duration: appMotionOff(context) ? Duration.zero : const Duration(milliseconds: 900),
      curve: AppEase.out,
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
    // The screen's one memorable thing (system.md §1): a peach hero block — the sentence in the editorial headline,
    // the rings drawing in once, the overall figure rolling to its value — that leans toward a mouse (AppTilt).
    return AppTilt(
      radius: AppRadius.block,
      child: AppBlock(
        hero: true,
        child: LayoutBuilder(builder: (context, box) => _body(context, box)),
      ),
    );
  }

  Widget _figure(BuildContext context, double ringSize, String label, {required bool lone}) {
    final b = AppBlock.colorsOf(context);
    return ExcludeSemantics(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        AppCountUp(anPct(overall),
            roll: true,
            memoryKey: 'an.hero.overall',
            textDirection: TextDirection.ltr,
            style: AppType.figureLarge(context).copyWith(color: b.ink, fontSize: ringSize * (lone ? 0.2 : 0.17), height: 1)),
        const SizedBox(height: AppSpace.xxs),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: b.muted)),
      ]),
    );
  }

  Widget _body(BuildContext context, BoxConstraints box) {
    final b = AppBlock.colorsOf(context);
    final wide = box.maxWidth >= 600;
    final title = AppType.headline(context).copyWith(color: b.ink);
    final ringSize = box.maxWidth >= 520 ? 168.0 : (box.maxWidth >= 330 ? 132.0 : 112.0);
    final stack = box.maxWidth < 300;
    final ringsW = Semantics(
      label: '${overallLabel ?? anTr('an2_overall', 'Overall')} ${anPct(overall)}',
      child: AnActivityRings(
        size: ringSize,
        values: [for (final r in rings) r.value],
        colors: [for (final r in rings) anMetricColor(context, r.metric)],
        center: _figure(context, ringSize, overallLabel ?? anTr('an2_overall', 'Overall'), lone: false),
      ),
    );
    final legend = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < rings.length; i++) ...[
        if (i > 0) const SizedBox(height: AppSpace.sm),
        _LegendRow(spec: rings[i]),
      ],
    ]);
    final foot = footer == null ? const <Widget>[] : [AppSpace.gapLg, footer!];
    if (rings.length == 1) {
      // a lone ring already says its figure in the middle: no legend, the sentence beside it
      final small = wide ? 140.0 : (box.maxWidth >= 330 ? 112.0 : 96.0);
      final lone = rings.first;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Semantics(
            label: '${overallLabel ?? anMetricLabel(lone.metric)} ${anPct(overall)}',
            child: AnActivityRings(
              size: small,
              values: [lone.value],
              colors: [anMetricColor(context, lone.metric)],
              center: _figure(context, small, overallLabel ?? anMetricLabel(lone.metric), lone: true),
            ),
          ),
          wide ? AppSpace.gapXl : AppSpace.gapLg,
          Expanded(child: Text(headline, style: title)),
        ]),
        ...foot,
      ]);
    }
    if (wide) {
      // wide: rings on the start, the sentence over a legend laid out across
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          ringsW,
          AppSpace.gapXl,
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(headline, style: title),
              AppSpace.gapLg,
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (var i = 0; i < rings.length; i++) ...[
                  if (i > 0) AppSpace.gapMd,
                  Expanded(child: _LegendRow(spec: rings[i])),
                ],
              ]),
            ]),
          ),
        ]),
        ...foot,
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(headline, style: title),
      AppSpace.gapLg,
      if (stack) ...[Center(child: ringsW), AppSpace.gapMd, legend]
      else
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          ringsW,
          box.maxWidth >= 520 ? AppSpace.gapXl : AppSpace.gapLg,
          Expanded(child: legend),
        ]),
      ...foot,
    ]);
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.spec});

  final AnRingSpec spec;

  @override
  Widget build(BuildContext context) {
    final b = AppBlock.colorsOf(context);
    final col = anMetricColor(context, spec.metric);
    final d = spec.delta;
    final sem = StringBuffer('${anMetricLabel(spec.metric)} ${anPct(spec.value)}');
    if (d != null) sem.write(', ${_signed(d)} ${anTr('an2_vs_class', 'vs class')}');
    return Semantics(
      label: sem.toString(),
      container: true,
      child: ExcludeSemantics(
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          // the metric's colour, as a short rule — the same colour as its ring
          Container(width: AppSpace.xxs, height: AppSpace.xl, decoration: BoxDecoration(color: col, borderRadius: AppRadius.chipAll)),
          AppSpace.gapSm,
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(anMetricLabel(spec.metric), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: b.muted)),
              Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Text(anPct(spec.value), textDirection: TextDirection.ltr, style: AppType.figure(context).copyWith(color: b.ink)),
                if (d != null) ...[
                  AppSpace.gapXs,
                  Flexible(child: AnDeltaChip(delta: d, onBlock: true)),
                ],
              ]),
              if (spec.detail != null)
                Text(spec.detail!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: b.muted)),
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
  const AnDeltaChip({super.key, required this.delta, this.suffix, this.onBlock = false});

  final double delta;
  final String? suffix;

  /// Sits on a tinted block (the hero): the ink is lifted to read on the block's surface at AA, and the pill turns
  /// paper so a green or red tint never sits on peach.
  final bool onBlock;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final b = onBlock ? AppBlock.colorsOf(context) : null;
    final up = delta >= 0.5, down = delta <= -0.5;
    final tone = up ? c.success : (down ? c.danger : c.textLight);
    final ink = b != null ? b.accentInk(tone) : appInk(context, tone);
    final style = AppType.overline(context).copyWith(color: ink, letterSpacing: 0);
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs / 2),
        decoration: BoxDecoration(
          color: b != null ? c.cardBg.withValues(alpha: 0.7) : tone.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (!up && !down)
            Text(anTr('an2_same_as_class', 'Same as class'), style: style.copyWith(color: b?.muted ?? c.textMedium))
          else ...[
            Icon(up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: AppIconSize.xs, color: ink),
            const SizedBox(width: AppSpace.xxs / 2),
            Text(_signed(delta), textDirection: TextDirection.ltr, style: style),
            const SizedBox(width: AppSpace.xxs),
            Text(suffix ?? anTr('an2_vs_class', 'vs class'), style: style.copyWith(fontWeight: FontWeight.w500)),
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
      const gap = AppSpace.sm;
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
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.xs),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.auto_awesome_rounded, size: AppIconSize.sm, color: c.textMedium),
          AppSpace.gapXs,
          Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.section(context))),
        ]),
        AppSpace.gapXs,
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: c.divider, indent: AppSpace.xl + AppSpace.sm),
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
      borderRadius: AppRadius.controlAll,
      onTap: row.onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppTouch.min),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: AppSpace.xl,
              height: AppSpace.xl,
              decoration: BoxDecoration(color: appTintOn(context, tone), shape: BoxShape.circle),
              child: Icon(icon, size: AppIconSize.sm, color: appInk(context, tone)),
            ),
            AppSpace.gapSm,
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpace.xxs + AppSpace.xxs / 2),
                child: Text(row.text, style: AppType.row(context)),
              ),
            ),
            if (row.onTap != null) ...[
              AppSpace.gapXs,
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.xxs),
                child: Icon(Icons.chevron_right_rounded, size: AppIconSize.md, color: c.textLight),
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

/// The metric switch: the kit's pill track ([AppTabs], the chosen pill solid primary). Keeps its typed API.
class AnSegmented<T> extends StatelessWidget {
  const AnSegmented({super.key, required this.options, required this.value, required this.onChanged});

  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final i = options.indexWhere((o) => o.$1 == value);
    return AppTabs(
      items: [for (final (_, label) in options) AppTabItem(label)],
      index: i < 0 ? 0 : i,
      onChanged: (k) => onChanged(options[k].$1),
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
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.xs),
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
          if (seg != null && !inline) ...[AppSpace.gapSm, seg],
          AppSpace.gapXs,
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.lg),
              child: Text(anTr('chart_no_data', 'No data yet'), textAlign: TextAlign.center, style: AppType.meta(context)),
            ),
          for (final r in shown) _BarRow(row: r, color: col),
          if (hasClass || hasFlag) ...[
            const SizedBox(height: AppSpace.xxs),
            _BarsLegend(color: col, you: youLabel ?? anTr('an2_you', 'You'), classMark: hasClass, flag: hasFlag),
            const SizedBox(height: AppSpace.xxs),
          ],
          if (onShowAll != null) ...[
            Divider(height: AppSpace.md, thickness: AppBorder.hairline, color: c.divider),
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
          borderRadius: AppRadius.controlAll,
          onTap: row.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                if (row.flag) ...[
                  Container(width: AppSpace.xs, height: AppSpace.xs, decoration: BoxDecoration(color: c.warning, shape: BoxShape.circle)),
                  const SizedBox(width: AppSpace.xs),
                ],
                Expanded(
                  child: Text(row.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
                ),
                AppSpace.gapXs,
                if (row.detail != null) ...[
                  Text(row.detail!, style: AppType.meta(context)),
                  AppSpace.gapXs,
                ],
                Text(anPct(v), textDirection: TextDirection.ltr, style: AppType.bodyStrong(context).copyWith(
                    color: v == null ? c.textLight : c.textDark, fontFeatures: const [FontFeature.tabularFigures()])),
              ]),
              AppSpace.gapXs,
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
          Container(height: AppSpace.xs, decoration: BoxDecoration(color: color.withValues(alpha: c.isDark ? 0.18 : 0.13), borderRadius: BorderRadius.circular(AppRadius.pill))),
          AppFill(
            value: pct,
            builder: (_, t) => Container(
              width: math.max(t > 0 ? AppSpace.xs : 0, w * t),
              height: AppSpace.xs,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(AppRadius.pill)),
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
    final label = AppType.meta(context);
    return Wrap(spacing: AppSpace.md, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
      if (classMark) ...[
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: AppIconSize.xs, height: AppSpace.xs, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(AppRadius.pill))),
          const SizedBox(width: AppSpace.xs),
          Text(you, style: label),
        ]),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 3, height: AppSpace.sm, decoration: BoxDecoration(color: c.textDark.withValues(alpha: 0.75), borderRadius: BorderRadius.circular(AppRadius.pill))),
          const SizedBox(width: AppSpace.xs),
          Text(anTr('an2_class_avg', 'Class average'), style: label),
        ]),
      ],
      if (flag)
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: AppSpace.xs, height: AppSpace.xs, decoration: BoxDecoration(color: c.warning, shape: BoxShape.circle)),
          const SizedBox(width: AppSpace.xs),
          Text(anTr('an_needs_attention', 'Needs attention'), style: label),
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
    final ink = appInk(context, c.primary);
    return InkWell(
      borderRadius: AppRadius.controlAll,
      onTap: onTap,
      child: SizedBox(
        height: AppTouch.min,
        child: Row(children: [
          Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: ink, fontWeight: FontWeight.w600))),
          Icon(expanded ? Icons.keyboard_arrow_up_rounded : Icons.chevron_right_rounded, size: AppIconSize.md, color: ink),
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
    final rule = Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: c.divider);
    return AnSurface(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.xs),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _CardTitle(widget.title, subtitle: widget.subtitle),
        const SizedBox(height: AppSpace.xxs),
        if (widget.rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.lg),
            child: Text(widget.empty!, textAlign: TextAlign.center, style: AppType.meta(context)),
          ),
        AnimatedSize(
          duration: AppMotion.of(context).base,
          curve: AppEase.out,
          alignment: AlignmentDirectional.topStart,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) rule,
              rows[i],
            ],
          ]),
        ),
        if (more) ...[
          rule,
          AnShowAllRow(
            expanded: _open,
            label: _open ? anTr('an2_show_less', 'Show less') : anFmt('an2_show_all', {'n': widget.rows.length}, 'Show all ({n})'),
            onTap: () => setState(() => _open = !_open),
          ),
        ] else
          AppSpace.gapXs,
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
          borderRadius: AppRadius.controlAll,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouch.primary),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
                    const SizedBox(height: AppSpace.xxs / 2),
                    Text(course, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                  ]),
                ),
                AppSpace.gapSm,
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(anPct(score), textDirection: TextDirection.ltr, style: AppType.figure(context)),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(p ? Icons.check_circle_rounded : Icons.error_rounded, size: AppIconSize.xs, color: appInk(context, tone)),
                    const SizedBox(width: AppSpace.xxs),
                    Text(word, style: AppType.meta(context).copyWith(color: appInk(context, tone), fontWeight: FontWeight.w600)),
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
        Icon(icon, size: AppIconSize.xs, color: ink),
        const SizedBox(width: AppSpace.xxs),
        Text(anPct(v), textDirection: TextDirection.ltr, style: AppType.meta(context).copyWith(color: ink, fontWeight: FontWeight.w600)),
      ]);
    }

    return Semantics(
      label: '$name, $course. ${anMetricLabel(AnMetric.attendance)} ${anPct(attendance)}, ${anMetricLabel(AnMetric.exams)} ${anPct(exams)}',
      button: onTap != null,
      container: true,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.controlAll,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouch.primary),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
              child: Row(children: [
                // the initial on the student's own stable tone (peach / sky), never the reserved emerald
                Builder(builder: (context) {
                  final tone = AppBlockColors.of(context, AppBlockTone.forKey(name));
                  return Container(
                    width: AppSpace.xxl * 0.75,
                    height: AppSpace.xxl * 0.75,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: tone.surface, shape: BoxShape.circle),
                    child: Text(initial, style: AppType.bodyStrong(context).copyWith(color: tone.ink)),
                  );
                }),
                AppSpace.gapSm,
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
                    const SizedBox(height: AppSpace.xxs / 2),
                    Text(course, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                  ]),
                ),
                AppSpace.gapXs,
                figure(Icons.event_available_rounded, attendance, kAnLowAttendance),
                AppSpace.gapSm,
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
          SizedBox(height: AppSpace.xs),
          AppSkeletonBox(width: 160, height: AppSpace.lg),
          SizedBox(height: AppSpace.sm),
          AppSkeletonBox(width: 220, height: AppSpace.sm),
        ]),
        // the hero's shape: a block, not a card
        hero: AppBlock(
          hero: true,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const AppSkeletonBox(height: AppSpace.lg),
            AppSpace.gapXs,
            const AppSkeletonBox(width: 180, height: AppSpace.lg),
            AppSpace.gapLg,
            Row(children: [
              const AppSkeletonBox(width: 120, height: 120, radius: 60),
              AppSpace.gapLg,
              Expanded(
                child: Column(children: [
                  for (var i = 0; i < 3; i++) ...[if (i > 0) AppSpace.gapSm, const AppSkeletonBox(height: AppSpace.xl)],
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
