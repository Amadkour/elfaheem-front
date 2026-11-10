// lib/design/app_kpi.dart
//
// The stat card of the dashboards and the grid that lays them out.
//
//   AppKpiCard(label: 'Students', value: '1,240', icon: Icons.people_alt_rounded, delta: 0.12, spark: [...])
//   AppKpiCard(…, highlight: true)     the ONE key KPI of a page: brand gradient surface, on-hero ink
//   AppKpiCard(…, loading: true)       skeleton of the same size
//   AppKpiGrid(children: [...])        1 column under 360 px, 2 on phones, 3 - 4 wide; equal heights per row
//
// `delta` is a fraction (0.12 = +12 %); `deltaGoodWhenUp: false` flips the colours for "lower is better" figures
// (absences, overdue). The whole card is one tappable (when `onTap` is given) read as "label: value".
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import 'app_bidi.dart';
import 'app_gradients.dart';
import 'app_kit.dart';
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
  final bool loading;

  @override
  Widget build(BuildContext context) {
    // the skeleton crossfades into the card (D-582)
    return AppSkeletonSwitch(loading: loading, child: loading ? _skeleton(context) : _card(context));
  }

  Widget _card(BuildContext context) {
    final c = context.colors;
    final ink = highlight ? c.onHero : c.textDark;
    final muted = highlight ? c.onHeroMuted : c.textMedium;
    final d = delta;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (icon != null)
            Container(
              width: AppTouch.min - AppSpace.xs,
              height: AppTouch.min - AppSpace.xs,
              decoration: BoxDecoration(
                color: highlight ? c.heroGlass : c.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.chip),
              ),
              child: Icon(icon, size: AppIconSize.lg, color: highlight ? c.onHero : c.primary),
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
          // counts up the first time, glides on a change (D-581)
          child: AppCountUp(value, memoryKey: 'kpi:$label', style: AppType.figureLarge(context).copyWith(color: ink)),
        ),
        if (d != null) ...[
          const SizedBox(height: AppSpace.xs),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
            _DeltaChip(delta: d, goodWhenUp: deltaGoodWhenUp, onHero: highlight),
            Text(deltaLabel ?? 'ds_vs_previous'.tr, style: AppType.meta(context).copyWith(color: muted)),
          ]),
        ],
        if (footnote != null && footnote!.isNotEmpty) ...[
          const SizedBox(height: AppSpace.xs),
          Text(footnote!, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: muted)),
        ],
        if (spark != null && spark!.length > 1) ...[
          const SizedBox(height: AppSpace.sm),
          AppSparkline(spark!, color: highlight ? c.onHero : c.primary, height: 36, label: label),
        ],
      ],
    );

    final semantic = '$label: $value';
    if (highlight) {
      return Semantics(
        container: true,
        button: onTap != null,
        label: semantic,
        excludeSemantics: true,
        onTap: onTap,
        // the one key figure of a page: depth with a soft glare (D-583)
        child: AppTilt(
          radius: AppRadius.block,
          glare: true,
          child: _tapWrap(
            context,
            radius: AppRadius.block,
            child: AppGradientSurface(padding: AppSpace.card, radius: AppRadius.block, child: content),
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
      child: AppTilt(
        radius: AppRadius.card,
        maxTilt: 3,
        child: _tapWrap(
        context,
        radius: AppRadius.card,
        child: Container(
          width: double.infinity,
          padding: AppSpace.card,
          decoration: BoxDecoration(
            color: c.cardBg,
            borderRadius: AppRadius.cardAll,
            border: Border.all(color: c.divider, width: AppBorder.hairline),
            boxShadow: AppElevation.of(context, 1),
          ),
          child: content,
        ),
      ),
      ),
    );
  }

  /// The ink ripple sits on top of the card (a Stack, so it also shows over the gradient).
  Widget _tapWrap(BuildContext context, {required double radius, required Widget child}) {
    if (onTap == null) return child;
    return Stack(fit: StackFit.passthrough, children: [
      child,
      Positioned.fill(
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(borderRadius: BorderRadius.circular(radius), onTap: onTap),
        ),
      ),
    ]);
  }

  Widget _skeleton(BuildContext context) {
    final c = context.colors;
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
            border: Border.all(color: c.divider, width: AppBorder.hairline),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const AppSkeletonBox(width: AppTouch.min - AppSpace.xs, height: AppTouch.min - AppSpace.xs, radius: AppRadius.chip),
              AppSpace.gapSm,
              const Expanded(child: AppSkeletonBox(height: 12)),
            ]),
            const SizedBox(height: AppSpace.sm),
            const AppSkeletonBox(width: 96, height: 28),
            const SizedBox(height: AppSpace.xs),
            const AppSkeletonBox(width: 120, height: 14),
          ]),
        ),
      ),
    );
  }
}

class _DeltaChip extends StatelessWidget {
  const _DeltaChip({required this.delta, required this.goodWhenUp, required this.onHero});

  final double delta;
  final bool goodWhenUp;
  final bool onHero;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final flat = delta == 0;
    final good = (delta > 0) == goodWhenUp;
    final tone = flat ? c.textMedium : (good ? c.success : c.danger);
    final fg = onHero ? c.onHero : tone;
    final bg = onHero ? c.heroGlass : tone.withValues(alpha: 0.12);
    return Container(
      key: ValueKey(flat ? 'kpi.delta.flat' : (good ? 'kpi.delta.good' : 'kpi.delta.bad')),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.chip)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (!flat) Icon(delta > 0 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: AppIconSize.xs, color: fg),
        if (!flat) const SizedBox(width: AppSpace.xxs),
        Text(appDeltaText(delta), style: AppType.meta(context).copyWith(color: fg, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// A responsive grid of [AppKpiCard]s (or any tiles): 1 column under 360 px, 2 on phones, 3 from tablet width,
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
