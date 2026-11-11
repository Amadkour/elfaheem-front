// lib/features/student/analysis/analytics_editorial.dart
//
// The Warm Editorial pieces of the two Analytics tabs (the student's and the instructor's), which the shared summary
// layout (shared/analytics/analytics_summary_ui.dart) takes as plain widgets:
//
//   AnalyticsMasthead(title:, subtitle:, actions:)   the editorial page title in ink on the canvas, one line under it,
//                                                    the chrome as paper plates (under a shell's bar the title is
//                                                    already above: only the line and the actions stay)
//   AnalyticsHeroBlock(headline:, rings:, …)         THE memorable element of the page: a tinted hero block (peach for
//                                                    a learner, sky for an instructor) with the activity rings, the
//                                                    overall figure counting up once, the one sentence in the
//                                                    editorial headline and the legend in the block's ink; it leans
//                                                    under the pointer (AppTilt) and the rings ride a parallax layer
//
// Plain values only, so the layout harness can pump them on their own.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppCountUp, AppPressScale, AppTilt, AppTiltLayer;
import 'package:flutter_education_app/design/app_shell_nav.dart' show ShellChrome;
import 'package:flutter_education_app/design/chrome_button.dart' show ChromeIconButton;

import '../../shared/analytics/analytics_summary_ui.dart';
import '../../shared/analytics/analytics_ui.dart' show anPct, anTr;

/// A header action of [AnalyticsMasthead]: a paper chrome plate with its tooltip.
class AnalyticsHeaderAction extends StatelessWidget {
  const AnalyticsHeaderAction({super.key, required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ChromeIconButton(icon: icon, label: tooltip, onTap: onTap);
}

/// The page's masthead: the editorial title, one line under it, the actions at the end.
class AnalyticsMasthead extends StatelessWidget {
  const AnalyticsMasthead({super.key, required this.title, this.subtitle, this.actions = const []});

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    // a tab's first page: the shell's bar above already says the title (D-551), so only the line under it remains
    final titled = !ShellChrome.ownsHeaderOf(context);
    final sub = subtitle;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.only(top: titled ? AppSpace.md : AppSpace.xs),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              if (titled)
                Semantics(
                  header: true,
                  child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.display(context)),
                ),
              if (sub != null && sub.isNotEmpty) ...[
                if (titled) const SizedBox(height: AppSpace.xxs),
                Text(
                  sub,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: titled ? AppType.body(context) : AppType.bodyStrong(context),
                ),
              ],
            ]),
          ),
          for (final a in actions) ...[AppSpace.gapXs, a],
        ]),
      ),
    );
  }
}

/// The hero of an Analytics tab: rings + overall figure + one sentence + the legend, on a tinted block.
class AnalyticsHeroBlock extends StatelessWidget {
  const AnalyticsHeroBlock({
    super.key,
    required this.headline,
    required this.rings,
    this.overall,
    this.overallLabel,
    this.footer,
    this.tone = AppBlockTone.peach,
    this.memoryKey = 'analytics.overall',
  });

  final String headline;
  final List<AnRingSpec> rings;
  final double? overall;

  /// Under the overall figure (default "Overall").
  final String? overallLabel;

  /// Under the legend, parted by a hairline (e.g. "My full analytics profile").
  final Widget? footer;

  /// Peach for a learner (progress), sky for an instructor (the role homes' convention).
  final AppBlockTone tone;

  /// Remembers the overall figure, so a revisit never counts up from zero again.
  final String memoryKey;

  /// From this width the sentence and the legend sit beside the rings.
  static const double _wideFrom = 600;

  /// Under this width the rings stack above the legend.
  static const double _stackUnder = 300;

  /// The rings' diameter by the room the block has.
  static double _ringSize(double width) => width >= 520 ? 168 : (width >= 330 ? 128 : 108);

  /// The overall figure fills this share of the rings' inner space.
  static const double _centerShare = 0.46;

  @override
  Widget build(BuildContext context) {
    return AppTilt(
      radius: AppRadius.block,
      glare: true,
      touchTilt: false,
      child: AppBlock(
        tone: tone,
        hero: true,
        child: Builder(builder: (context) {
          final b = AppBlock.colorsOf(context);
          return LayoutBuilder(builder: (context, box) {
            final w = box.maxWidth;
            final size = _ringSize(w);
            final label = overallLabel ?? anTr('an2_overall', 'Overall');
            final lone = rings.length == 1;
            final ringsW = AppTiltLayer(
              depth: 1.4,
              child: Semantics(
                label: '$label ${anPct(overall)}',
                child: AnActivityRings(
                  size: size,
                  values: [for (final r in rings) r.value],
                  colors: [for (final r in rings) anMetricColor(context, r.metric)],
                  center: ExcludeSemantics(
                    child: SizedBox(
                      width: size * _centerShare,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: AppCountUp(
                            anPct(overall),
                            memoryKey: memoryKey,
                            style: AppType.figureLarge(context).copyWith(color: b.ink),
                          ),
                        ),
                        Text(
                          lone ? (overallLabel ?? anMetricLabel(rings.first.metric)) : label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: AppType.meta(context).copyWith(color: b.muted),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            );
            final title = Semantics(
              header: true,
              child: Text(
                headline,
                style: (w >= _wideFrom ? AppType.headline(context) : AppType.pageTitle(context)).copyWith(color: b.ink),
              ),
            );
            final Widget body;
            if (lone) {
              // a lone ring already says its figure in the middle: no legend, the sentence beside it
              body = Row(children: [
                ringsW,
                SizedBox(width: w >= _wideFrom ? AppSpace.xl : AppSpace.md),
                Expanded(child: title),
              ]);
            } else if (w >= _wideFrom) {
              body = Row(children: [
                ringsW,
                AppSpace.gapXl,
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    title,
                    AppSpace.gapLg,
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      for (var i = 0; i < rings.length; i++) ...[
                        if (i > 0) AppSpace.gapMd,
                        Expanded(child: _LegendRow(spec: rings[i])),
                      ],
                    ]),
                  ]),
                ),
              ]);
            } else {
              final legend = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var i = 0; i < rings.length; i++) ...[
                  if (i > 0) AppSpace.gapSm,
                  _LegendRow(spec: rings[i]),
                ],
              ]);
              body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                title,
                AppSpace.gapLg,
                if (w < _stackUnder) ...[
                  Center(child: ringsW),
                  AppSpace.gapMd,
                  legend,
                ] else
                  Row(children: [
                    ringsW,
                    SizedBox(width: w >= 520 ? AppSpace.xl : AppSpace.lg),
                    Expanded(child: legend),
                  ]),
              ]);
            }
            return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              body,
              if (footer != null) ...[
                AppSpace.gapMd,
                Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: b.border ?? b.faint.withValues(alpha: 0.3)),
                const SizedBox(height: AppSpace.xxs),
                footer!,
              ],
            ]);
          });
        }),
      ),
    );
  }
}

/// One metric of the legend in the block's ink: its colour as a short rule, the name, the figure, "vs class".
class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.spec});

  final AnRingSpec spec;

  /// The colour rule beside the metric.
  static const double _rule = 3;

  @override
  Widget build(BuildContext context) {
    final b = AppBlock.colorsOf(context);
    final col = anMetricColor(context, spec.metric);
    final d = spec.delta;
    final sem = StringBuffer('${anMetricLabel(spec.metric)} ${anPct(spec.value)}');
    if (d != null) {
      final sign = d >= 0.5 ? '+' : (d <= -0.5 ? '−' : '±');
      sem.write(', $sign${d.abs().round()} ${anTr('an2_vs_class', 'vs class')}');
    }
    return Semantics(
      label: sem.toString(),
      container: true,
      child: ExcludeSemantics(
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              width: _rule,
              decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(AppRadius.pill)),
            ),
            AppSpace.gapSm,
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(anMetricLabel(spec.metric),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: b.muted)),
                Wrap(
                  spacing: AppSpace.xs,
                  runSpacing: AppSpace.xxs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      anPct(spec.value),
                      style: AppType.figure(context).copyWith(
                        color: b.ink,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (d != null) AnDeltaChip(delta: d),
                  ],
                ),
                if (spec.detail != null)
                  Text(spec.detail!,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: b.faint)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// A course's mark: its cover when it has one, else a small tile in the course's own block tone (the same tone
/// wherever the course appears).
class AnalyticsCourseMark extends StatelessWidget {
  const AnalyticsCourseMark({super.key, required this.courseId, this.imageUrl, this.size = AppTouch.min});

  final int courseId;
  final String? imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final b = AppBlockColors.of(context, AppBlockTone.forKey('course:$courseId'));
    final tile = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: b.surface,
        borderRadius: AppRadius.controlAll,
        border: b.border == null ? null : Border.all(color: b.border!, width: AppBorder.hairline),
      ),
      child: Icon(Icons.menu_book_rounded, size: AppIconSize.lg, color: b.ink),
    );
    final url = imageUrl;
    if (url == null || url.isEmpty) return tile;
    return ClipRRect(
      borderRadius: AppRadius.controlAll,
      child: Image.network(url, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, _, _) => tile),
    );
  }
}

/// One quiet fact under a title: a small icon and its words.
class AnalyticsFact extends StatelessWidget {
  const AnalyticsFact({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: AppIconSize.xs, color: context.colors.textLight),
        const SizedBox(width: AppSpace.xxs),
        Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context))),
      ]);
}

/// A shortcut of a course card (attendance, exams, marks, banks): a quiet well with a tinted icon, the name in ink
/// and an optional count. 48 px high, presses in.
class AnalyticsShortcut extends StatelessWidget {
  const AnalyticsShortcut({super.key, required this.icon, required this.label, required this.color, this.onTap, this.badge});

  final IconData icon;
  final String label;

  /// The icon's tone (never the label's: the label stays in ink).
  final Color color;
  final VoidCallback? onTap;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final n = badge ?? 0;
    return AppPressScale(
      enabled: onTap != null,
      child: Material(
        color: c.inputBg,
        borderRadius: AppRadius.controlAll,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouch.min),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm, AppSpace.xxs, AppSpace.sm, AppSpace.xxs),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: AppIconSize.sm, color: appInkOn(context, color, c.inputBg)),
                const SizedBox(width: AppSpace.xs),
                Flexible(
                  child: Text(label,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: c.textDark)),
                ),
                if (n > 0) ...[
                  const SizedBox(width: AppSpace.xs),
                  AppCountBadge(count: n, tone: AppTone.neutral),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
