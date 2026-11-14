// lib/design/app_kpi.dart
//
// The stat card of the dashboards and the grid that lays them out (Warm Editorial, system.md §4 – §6).
//
//   AppKpiCard(label: 'Students', value: '1,240', icon: Icons.people_alt_rounded, delta: 0.12, spark: [...])
//   AppKpiCard(…, highlight: true)     the ONE key KPI of a page: a tinted block (peach by default, `tone:` picks
//                                      another), the figure rolls (AppOdometer) and the block leans a little under
//                                      the pointer (AppTilt.subtle)
//   AppKpiCard(…, loading: true)       skeleton of the same size
//   AppKpiGrid(children: [...])        1 column under 300 px, 2 on phones, 3 - 4 wide; equal heights per row
//
// The other cards are paper: the card surface on a warm hairline, no shadow (depth is tone first, D-612). `delta`
// is a fraction (0.12 = +12 %); `deltaGoodWhenUp: false` flips the colours for "lower is better" figures
// (absences, overdue). The whole card is one tappable (when `onTap` is given) read as "label: value".
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import 'app_badges.dart';
import 'app_bidi.dart';
import 'app_blocks.dart';
import 'app_charts.dart';
import 'app_gradients.dart' show AppGradientIcon;
import 'app_kit.dart' show AppShimmer, AppSkeletonBox;
import 'app_motion_kit.dart';
import 'app_responsive.dart';
import 'app_tokens.dart';

/// "+12%" / "-4.5%" for a fraction; one decimal under 10 %. Isolated left to right, so Arabic shows "+12%", never
/// "12%+".
String appDeltaText(double delta) {
  final p = delta.abs() * 100;
  final s = p >= 10 ? p.round().toString() : p.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
  final sign = delta > 0 ? '+' : (delta < 0 ? '-' : '');
  return ltrIsolate('$sign$s%');
}

class AppKpiCard extends StatelessWidget {
  const AppKpiCard({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.delta,
    this.deltaGoodWhenUp = true,
    this.deltaLabel,
    this.spark,
    this.footnote,
    this.onTap,
    this.highlight = false,
    this.tone,
    this.loading = false,
  });

  final String label;
  final String value;
  final IconData? icon;

  /// A fraction: 0.12 = +12 %.
  final double? delta;
  final bool deltaGoodWhenUp;

  /// Default: "vs previous period".
  final String? deltaLabel;
  final List<double>? spark;
  final String? footnote;
  final VoidCallback? onTap;

  /// The ONE key KPI of the page.
  final bool highlight;

  /// The block tone of a [highlight] card (default peach, the learning / progress tone). Gold and emerald carry
  /// meaning (system.md §2): gold for a streak or a top score, emerald for something completed.
  final AppBlockTone? tone;
  final bool loading;

  /// The sparkline's height inside the card.
  static const double _sparkHeight = 36;

  /// The skeleton's bones: the figure line and the meta line under it.
  static const double _boneFigureWidth = 96, _boneFigureHeight = 28;
  static const double _boneMetaWidth = 120, _boneMetaHeight = 14;

  @override
  Widget build(BuildContext context) {
    // the skeleton crossfades into the card (D-582)
    return AppSkeletonSwitch(loading: loading, child: loading ? _skeleton(context) : _card(context));
  }

  Widget _content(BuildContext context, {required Color ink, required Color muted, required Color surface, required Color accent}) {
    final c = context.colors;
    final d = delta;
    final iconBox = AppTouch.min - AppSpace.xs;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (icon != null)
            Container(
              width: iconBox,
              height: iconBox,
              decoration: BoxDecoration(
                color: highlight ? Color.lerp(surface, ink, 0.07) : appTintOn(context, c.primary),
                borderRadius: AppRadius.chipAll,
              ),
              // D-650: a plain card's chip glyph wears the green → gold family; the highlighted card keeps its ink
              child: highlight
                  ? Icon(icon, size: AppIconSize.lg, color: accent)
                  : AppGradientIcon(icon!, size: AppIconSize.lg, on: [Color.alphaBlend(appTintOn(context, c.primary), surface)]),
            ),
          if (icon != null) AppSpace.gapSm,
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: icon != null ? AppSpace.xxs : 0),
              child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: muted)),
            ),
          ),
        ]),
        const SizedBox(height: AppSpace.sm),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: highlight
              // the key figure of the page rolls (D-620); the others count up once and glide on a change (D-581)
              ? AppOdometer(value, memoryKey: 'kpi:$label', style: AppType.figureLarge(context).copyWith(color: ink))
              : AppCountUp(value, memoryKey: 'kpi:$label', style: AppType.figureLarge(context).copyWith(color: ink)),
        ),
        if (d != null) ...[
          const SizedBox(height: AppSpace.xs),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
            _DeltaChip(delta: d, goodWhenUp: deltaGoodWhenUp, surface: surface),
            Text(deltaLabel ?? 'ds_vs_previous'.tr, style: AppType.meta(context).copyWith(color: muted)),
          ]),
        ],
        if (footnote != null && footnote!.isNotEmpty) ...[
          const SizedBox(height: AppSpace.xs),
          Text(footnote!, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: muted)),
        ],
        if (spark != null && spark!.length > 1) ...[
          const SizedBox(height: AppSpace.sm),
          AppSparkline(spark!, color: accent, surface: surface, height: _sparkHeight, label: label),
        ],
      ],
    );
  }

  Widget _card(BuildContext context) {
    final c = context.colors;
    final semantic = '$label: $value';
    if (highlight) {
      final blockTone = tone ?? AppBlockTone.peach;
      final phone = MediaQuery.sizeOf(context).width < AppWidth.phoneMax;
      return Semantics(
        container: true,
        button: onTap != null,
        label: semantic,
        excludeSemantics: true,
        onTap: onTap,
        // the one key figure of a page leans a little under the pointer; touch gets press depth only (D-620)
        child: AppTilt.subtle(
          radius: AppRadius.block,
          child: AppBlock(
            tone: blockTone,
            padding: phone ? AppSpace.card : AppSpace.block,
            onTap: onTap,
            child: Builder(builder: (context) {
              final b = AppBlock.colorsOf(context);
              return _content(context,
                  ink: b.ink, muted: b.muted, surface: b.surface, accent: b.accentInk(c.primary));
            }),
          ),
        ),
      );
    }
    return Semantics(
      container: true,
      button: onTap != null,
      label: semantic,
      excludeSemantics: true,
      onTap: onTap,
      // a tappable card presses in (D-582); a resting card is white with one soft shadow (D-632)
      child: AppPressScale(
        enabled: onTap != null,
        child: AppLift(child: Material(
          color: c.cardBg,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.cardAll, side: AppShadow.cardEdge(context)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: AppSpace.card,
              child: SizedBox(
                width: double.infinity,
                child: _content(context, ink: c.textDark, muted: c.textMedium, surface: c.cardBg, accent: c.primary),
              ),
            ),
          ),
        )),
      ),
    );
  }

  Widget _skeleton(BuildContext context) {
    final c = context.colors;
    const iconBox = AppTouch.min - AppSpace.xs;
    return Semantics(
      label: 'ds_loading'.tr,
      container: true,
      excludeSemantics: true,
      child: AppShimmer(
        child: Container(
          width: double.infinity,
          padding: AppSpace.card,
          decoration: BoxDecoration(
            color: c.cardBg,
            borderRadius: AppRadius.cardAll,
            border: Border.fromBorderSide(AppShadow.cardEdge(context)),
            boxShadow: AppShadow.card(context),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const AppSkeletonBox(width: iconBox, height: iconBox, radius: AppRadius.chip),
              AppSpace.gapSm,
              const Expanded(child: AppSkeletonBox(height: AppSpace.sm)),
            ]),
            const SizedBox(height: AppSpace.sm),
            const AppSkeletonBox(width: _boneFigureWidth, height: _boneFigureHeight),
            const SizedBox(height: AppSpace.xs),
            const AppSkeletonBox(width: _boneMetaWidth, height: _boneMetaHeight),
          ]),
        ),
      ),
    );
  }
}

class _DeltaChip extends StatelessWidget {
  const _DeltaChip({required this.delta, required this.goodWhenUp, required this.surface});

  final double delta;
  final bool goodWhenUp;

  /// What the chip sits on (the card or the block), so its ink reaches AA on its own tint there.
  final Color surface;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final flat = delta == 0;
    final good = (delta > 0) == goodWhenUp;
    final tone = flat ? c.textMedium : (good ? c.success : c.danger);
    final bg = appTintOn(context, tone, surface: surface);
    final fg = flat ? c.textDark : appInkOn(context, tone, bg);
    return Container(
      key: ValueKey(flat ? 'kpi.delta.flat' : (good ? 'kpi.delta.good' : 'kpi.delta.bad')),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs / 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (!flat) Icon(delta > 0 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: AppIconSize.xs, color: fg),
        if (!flat) const SizedBox(width: AppSpace.xxs),
        Text(appDeltaText(delta), style: AppType.meta(context).copyWith(color: fg, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// A responsive grid of [AppKpiCard]s (or any tiles): 1 column under 300 px, 2 on phones, 3 from tablet width,
/// 4 from desktop width (never more than [maxColumns]). The cards of a row share the row's height.
class AppKpiGrid extends StatelessWidget {
  const AppKpiGrid({super.key, required this.children, this.maxColumns = 4});

  final List<Widget> children;
  final int maxColumns;

  static int columnsFor(double width, int maxColumns) {
    final n = width < 300
        ? 1
        : width < Breakpoints.mobile - 100
            ? 2
            : width < Breakpoints.desktop
                ? 3
                : width < 1100
                    ? 4
                    : 5; // only a grid that asks for five (maxColumns) gets it
    return math.max(1, math.min(n, maxColumns));
  }

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, box) {
      final cols = columnsFor(box.maxWidth, maxColumns);
      final rows = (children.length / cols).ceil();
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var r = 0; r < rows; r++) ...[
          if (r > 0) AppSpace.gapSm,
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < cols; i++) ...[
                if (i > 0) AppSpace.gapSm,
                Expanded(
                  // the grid is the page's one orchestrated entrance: the first tiles rise once (D-580)
                  child: r * cols + i < children.length
                      ? AppReveal(index: r * cols + i, group: 'kpi', child: children[r * cols + i])
                      : const SizedBox.shrink(),
                ),
              ],
            ]),
          ),
        ],
      ]);
    });
  }
}
