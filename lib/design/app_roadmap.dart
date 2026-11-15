// lib/design/app_roadmap.dart
//
// The connected roadmap (Institutions v2 phase 5, D-994): ONE drawing for "where am I, what is next" — the admin's
// institution roadmap, the student's journey, a head's path through a request. It speaks the course roadmap's
// language (RoadmapPathView, lib/features/courses/roadmap/roadmap_path.dart): a rail of round nodes joined by a
// line, the walked part emerald, the stops ahead paper.
//
//   AppRoadmap        connected nodes. Vertical on phones; horizontal on a wide box (≥ 720) when there are at most
//                     six nodes. Each node is done ✓ / current ● / to do (its number) / warn !, said by icon, colour
//                     AND a caption ("Done", "Needs attention"), never by colour alone. The "next" node (given, else
//                     the first current → warn → to do) is the path's one block (emerald) with its action button;
//                     the nodes after it are quieter. The walked line fills in once (AppFill: still under Reduce
//                     motion). Every node reads "Step 2 of 5, Departments, Done" to a screen reader.
//   AppStatusPath     the compact submitted → reviewed → decided line of one request (three dots, labels, times).
//   appRoadmapNextIndex · appRoadmapHorizontal · appRoadmapNodeLabel · appStatusPathLabel   pure (tested)
//
// Tests: test/org/institutions_v2_p5_test.dart (states, semantics, layout harness).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import 'app_badges.dart' show appInkOn, appInkOnFill, appTintOn;
import 'app_blocks.dart';
import 'app_buttons.dart';
import 'app_charts.dart' show appInk;
import 'app_contrast.dart' show ensureContrast;
import 'app_motion_kit.dart' show AppFill;
import 'app_tokens.dart';

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

enum AppRoadmapState { done, current, todo, warn }

/// The words of a state (drawn beside its colour and icon).
String appRoadmapStateLabel(AppRoadmapState s) => switch (s) {
      AppRoadmapState.done => _t('مكتمل', 'Done'),
      AppRoadmapState.current => _t('جارٍ الآن', 'In progress'),
      AppRoadmapState.todo => _t('لم يبدأ', 'To do'),
      AppRoadmapState.warn => _t('يحتاج انتباهاً', 'Needs attention'),
    };

class AppRoadmapNode {
  const AppRoadmapNode({
    required this.title,
    this.state = AppRoadmapState.todo,
    this.subtitle,
    this.caption,
    this.actionLabel,
    this.onAction,
    this.onTap,
    this.id,
  });

  final String title;
  final AppRoadmapState state;

  /// One or two lines under the title (the why, a count); shown on the next node, and on every node unless dense.
  final String? subtitle;

  /// Replaces the state's word in the caption line (e.g. "Due Tue 18 Nov"); the state is still read out.
  final String? caption;

  /// The next node's button; null = none.
  final String? actionLabel;
  final VoidCallback? onAction;

  /// The whole node opens something (every node, not only the next one).
  final VoidCallback? onTap;

  /// For keys: `roadmap.node.<id>`, `roadmap.action.<id>`.
  final String? id;
}

/// The node the roadmap highlights: the first current, else the first warn, else the first to do; null = all done.
int? appRoadmapNextIndex(List<AppRoadmapNode> nodes) {
  for (final s in const [AppRoadmapState.current, AppRoadmapState.warn, AppRoadmapState.todo]) {
    final i = nodes.indexWhere((n) => n.state == s);
    if (i >= 0) return i;
  }
  return null;
}

/// A wide box lays at most six nodes out in a row.
bool appRoadmapHorizontal(double width, int count) => count > 0 && count <= 6 && width >= AppRoadmap.wideFrom;

/// "Step 2 of 5, Departments, Done, 3 units have no head" — what a screen reader says for one node.
String appRoadmapNodeLabel(AppRoadmapNode n, int index, int count, {bool next = false}) => [
      _t('الخطوة ${index + 1} من $count', 'Step ${index + 1} of $count'),
      n.title,
      appRoadmapStateLabel(n.state),
      if (next) _t('الخطوة التالية', 'Next step'),
      if ((n.caption ?? '').isNotEmpty) n.caption!,
      if ((n.subtitle ?? '').isNotEmpty) n.subtitle!,
    ].join(_sep);

String get _sep => AppConfig.lang == 'ar' ? '، ' : ', ';

class AppRoadmap extends StatelessWidget {
  const AppRoadmap({
    super.key,
    required this.nodes,
    this.next,
    this.axis,
    this.dense = false,
    this.quietAfterNext = true,
    this.label,
  });

  /// From this box width a short roadmap is drawn in a row.
  static const double wideFrom = 720;

  final List<AppRoadmapNode> nodes;

  /// The highlighted node; null → [appRoadmapNextIndex]. -1 = none.
  final int? next;

  /// Forces a direction; null = by width ([appRoadmapHorizontal]).
  final Axis? axis;

  /// Home cards: one line per node; only the next one keeps its subtitle.
  final bool dense;

  /// The nodes after the next one are drawn quieter.
  final bool quietAfterNext;

  /// The whole path's name for a screen reader (e.g. "Institution roadmap: 2 of 5 done").
  final String? label;

  @override
  Widget build(BuildContext context) {
    if (nodes.isEmpty) return const SizedBox.shrink();
    final at = next == null ? appRoadmapNextIndex(nodes) : (next! < 0 ? null : next);
    final done = nodes.where((n) => n.state == AppRoadmapState.done).length;
    return Semantics(
      container: true,
      label: label ?? _t('$done من ${nodes.length} مكتملة', '$done of ${nodes.length} done'),
      child: LayoutBuilder(builder: (context, box) {
        final horizontal = axis == null ? appRoadmapHorizontal(box.maxWidth, nodes.length) : axis == Axis.horizontal;
        return horizontal
            ? _Horizontal(nodes: nodes, at: at, quiet: quietAfterNext, dense: dense)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < nodes.length; i++)
                    _VRow(
                      node: nodes[i],
                      index: i,
                      count: nodes.length,
                      next: i == at,
                      quiet: quietAfterNext && at != null && i > at && nodes[i].state == AppRoadmapState.todo,
                      dense: dense,
                      lineIn: i == 0 ? null : nodes[i - 1].state == AppRoadmapState.done,
                      lineOut: i == nodes.length - 1 ? null : nodes[i].state == AppRoadmapState.done,
                    ),
                ],
              );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Parts
// ─────────────────────────────────────────────────────────────────────────────

const double _node = AppIconSize.lg + AppSpace.xxs; // 28
const double _rail = AppSpace.xl + AppSpace.xxs; // 36

/// The path's line: emerald where it has been walked (filled in once), the warm hairline ahead.
class _Line extends StatelessWidget {
  const _Line({required this.done, required this.axis});
  final bool done;
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final v = axis == Axis.vertical;
    return Container(
      width: v ? AppBorder.focus : null,
      height: v ? null : AppBorder.focus,
      decoration: BoxDecoration(color: c.divider, borderRadius: BorderRadius.circular(AppBorder.hairline)),
      child: done
          ? AppFill(
              value: 1,
              builder: (context, f) => FractionallySizedBox(
                alignment: v ? AlignmentDirectional.topCenter : AlignmentDirectional.centerStart,
                heightFactor: v ? f : 1,
                widthFactor: v ? 1 : f,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                      color: c.success.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(AppBorder.hairline)),
                ),
              ),
            )
          : null,
    );
  }
}

/// A node: emerald ✓ done, ink ● current, amber ! warn, a paper disc with its number ahead.
class _Dot extends StatelessWidget {
  const _Dot({required this.state, required this.number, this.next = false, this.quiet = false});
  final AppRoadmapState state;
  final int number;
  final bool next, quiet;
  static const double size = _node;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final Color fill, border, ink;
    IconData? icon;
    switch (state) {
      case AppRoadmapState.done:
        fill = c.success;
        border = c.success;
        ink = appInkOnFill(context, c.success);
        icon = Icons.check_rounded;
      case AppRoadmapState.current:
        fill = c.textDark;
        border = c.textDark;
        ink = c.background;
        icon = Icons.my_location_rounded;
      case AppRoadmapState.warn:
        fill = appTintOn(context, c.warning, surface: c.cardBg);
        border = c.warning;
        ink = appInkOn(context, c.warning, fill);
        icon = Icons.priority_high_rounded;
      case AppRoadmapState.todo:
        fill = c.cardBg;
        border = next ? c.primary : c.divider;
        ink = quiet ? c.textLight : c.textMedium;
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: fill, shape: BoxShape.circle, border: Border.all(color: border, width: AppBorder.strong)),
      child: icon != null
          ? Icon(icon, size: size >= _node ? AppIconSize.sm : AppIconSize.xs, color: ink)
          : Text(
              '$number',
              style: AppType.meta(context).copyWith(
                fontWeight: FontWeight.w600,
                color: ensureContrast(ink, [fill]),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
    );
  }
}

/// The caption's words and tone.
(String, Color?) _captionOf(BuildContext context, AppRoadmapNode n, bool next) {
  final c = context.colors;
  final word = (n.caption ?? '').isNotEmpty ? n.caption! : appRoadmapStateLabel(n.state);
  return switch (n.state) {
    AppRoadmapState.done => (word, c.success),
    AppRoadmapState.warn => (word, c.warning),
    AppRoadmapState.current => (word, c.primary),
    AppRoadmapState.todo => (word, null),
  };
}

/// The next node's block: "Next" pill, title, why, the button.
class _NextBlock extends StatelessWidget {
  const _NextBlock({required this.node, required this.dense});
  final AppRoadmapNode node;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final b = AppBlockColors.of(context, AppBlockTone.emerald);
    final (caption, tone) = _captionOf(context, node, true);
    return Material(
      color: b.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.cardAll,
        side: BorderSide(color: b.border ?? Color.lerp(b.surface, c.textDark, 0.14)!, width: AppBorder.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: node.onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.sm),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs / 2),
                decoration: BoxDecoration(color: c.textDark, borderRadius: BorderRadius.circular(AppRadius.pill)),
                child: Text(_t('التالي', 'Next'),
                    maxLines: 1, style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: c.background)),
              ),
              Text(caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.meta(context).copyWith(
                      fontWeight: FontWeight.w500, color: tone == null ? b.muted : appInkOn(context, tone, b.surface))),
            ]),
            const SizedBox(height: AppSpace.xxs),
            Text(node.title,
                maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context).copyWith(color: b.ink)),
            if ((node.subtitle ?? '').isNotEmpty) ...[
              const SizedBox(height: AppSpace.xxs),
              Text(node.subtitle!,
                  maxLines: dense ? 2 : 3, overflow: TextOverflow.ellipsis, style: AppType.body(context).copyWith(color: b.muted)),
            ],
            if (node.actionLabel != null && node.onAction != null) ...[
              const SizedBox(height: AppSpace.sm),
              AppButton.primary(
                key: ValueKey('roadmap.action.${node.id ?? node.title}'),
                label: node.actionLabel!,
                trailingIcon: Icons.arrow_forward_rounded,
                onPressed: node.onAction,
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

/// A plain node's words: caption, title, subtitle.
class _NodeText extends StatelessWidget {
  const _NodeText({required this.node, required this.quiet, required this.dense, this.center = false});
  final AppRoadmapNode node;
  final bool quiet, dense, center;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (caption, tone) = _captionOf(context, node, false);
    final muted = ensureContrast(c.textMedium, [c.cardBg]);
    final align = center ? TextAlign.center : TextAlign.start;
    final titleStyle = (quiet || dense ? AppType.row(context) : AppType.bodyStrong(context))
        .copyWith(color: quiet ? muted : c.textDark);
    final captionLine = Text(caption,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: align,
        style: AppType.meta(context).copyWith(
            fontWeight: FontWeight.w500, color: tone == null ? muted : appInk(context, tone)));
    return Column(
      crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!center) captionLine,
        Text(node.title, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: align, style: titleStyle),
        if (center) captionLine,
        if (!dense && !quiet && (node.subtitle ?? '').isNotEmpty) ...[
          const SizedBox(height: AppSpace.xxs / 2),
          Text(node.subtitle!,
              maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: align, style: AppType.meta(context).copyWith(color: muted)),
        ],
      ],
    );
  }
}

/// One node of the vertical path: the rail (line in · dot · line out) beside the node's words or block.
class _VRow extends StatelessWidget {
  const _VRow({
    required this.node,
    required this.index,
    required this.count,
    required this.next,
    required this.quiet,
    required this.dense,
    required this.lineIn,
    required this.lineOut,
  });

  final AppRoadmapNode node;
  final int index, count;
  final bool next, quiet, dense;

  /// null = no line (first / last node); true = walked.
  final bool? lineIn, lineOut;

  @override
  Widget build(BuildContext context) {
    final dotTop = next ? AppSpace.sm : (dense ? AppSpace.xs + AppSpace.xxs / 2 : AppSpace.sm);
    final gap = dense ? AppSpace.xxs : AppSpace.xs;
    final label = appRoadmapNodeLabel(node, index, count, next: next);
    final Widget body = next
        ? Semantics(container: true, label: label, child: _NextBlock(node: node, dense: dense))
        : Semantics(
            container: true,
            button: node.onTap != null,
            label: label,
            excludeSemantics: true,
            onTap: node.onTap,
            child: InkWell(
              borderRadius: AppRadius.cardAll,
              onTap: node.onTap,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: dense ? AppTouch.min - AppSpace.xxs : AppTouch.min),
                child: Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(AppSpace.xs, dense ? AppSpace.xxs : AppSpace.xs, AppSpace.xs, dense ? AppSpace.xxs : AppSpace.xs),
                  child: Row(children: [
                    Expanded(child: _NodeText(node: node, quiet: quiet, dense: dense)),
                    if (node.onTap != null)
                      Icon(Icons.chevron_right_rounded, size: AppIconSize.md, color: context.colors.textLight),
                  ]),
                ),
              ),
            ),
          );
    return Stack(
      key: ValueKey('roadmap.node.${node.id ?? index}'),
      children: [
        Padding(
          padding: EdgeInsetsDirectional.only(start: _rail + AppSpace.xxs, bottom: lineOut == null ? 0 : gap),
          child: body,
        ),
        PositionedDirectional(
          start: 0,
          top: 0,
          bottom: 0,
          width: _rail,
          child: ExcludeSemantics(
            child: Stack(children: [
              if (lineIn != null)
                PositionedDirectional(start: _rail / 2 - AppBorder.hairline, top: 0, height: dotTop, child: _Line(done: lineIn!, axis: Axis.vertical)),
              if (lineOut != null)
                PositionedDirectional(
                    start: _rail / 2 - AppBorder.hairline, top: dotTop + _node, bottom: 0, child: _Line(done: lineOut!, axis: Axis.vertical)),
              PositionedDirectional(
                start: (_rail - _node) / 2,
                top: dotTop,
                child: _Dot(state: node.state, number: index + 1, next: next, quiet: quiet),
              ),
            ]),
          ),
        ),
      ],
    );
  }
}

/// The row form: every node a column (dot on the line, its title under it), the next node's block below the row.
class _Horizontal extends StatelessWidget {
  const _Horizontal({required this.nodes, required this.at, required this.quiet, required this.dense});
  final List<AppRoadmapNode> nodes;
  final int? at;
  final bool quiet, dense;

  @override
  Widget build(BuildContext context) {
    final n = nodes.length;
    final nextNode = at == null ? null : nodes[at!];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < n; i++)
          Expanded(
            key: ValueKey('roadmap.node.${nodes[i].id ?? i}'),
            child: Semantics(
              container: true,
              button: nodes[i].onTap != null,
              label: appRoadmapNodeLabel(nodes[i], i, n, next: i == at),
              excludeSemantics: true,
              onTap: nodes[i].onTap,
              child: InkWell(
                borderRadius: AppRadius.cardAll,
                onTap: nodes[i].onTap,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: AppTouch.min),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.xs),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(
                        height: _node,
                        child: Row(children: [
                          Expanded(child: i == 0 ? const SizedBox.shrink() : _Line(done: nodes[i - 1].state == AppRoadmapState.done, axis: Axis.horizontal)),
                          _Dot(
                            state: nodes[i].state,
                            number: i + 1,
                            next: i == at,
                            quiet: quiet && at != null && i > at! && nodes[i].state == AppRoadmapState.todo,
                          ),
                          Expanded(child: i == n - 1 ? const SizedBox.shrink() : _Line(done: nodes[i].state == AppRoadmapState.done, axis: Axis.horizontal)),
                        ]),
                      ),
                      const SizedBox(height: AppSpace.xs),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs),
                        child: _NodeText(
                          node: nodes[i],
                          quiet: quiet && at != null && i > at! && nodes[i].state == AppRoadmapState.todo,
                          dense: true,
                          center: true,
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
      ]),
      if (nextNode != null && (nextNode.actionLabel != null || (nextNode.subtitle ?? '').isNotEmpty)) ...[
        const SizedBox(height: AppSpace.xs),
        Semantics(
          container: true,
          label: appRoadmapNodeLabel(nextNode, at!, n, next: true),
          child: _NextBlock(node: nextNode, dense: dense),
        ),
      ],
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  AppStatusPath
// ─────────────────────────────────────────────────────────────────────────────

class AppStatusStop {
  const AppStatusStop(this.label, {this.at});
  final String label;

  /// When it was reached, already formatted (AppTime); null = not yet / unknown.
  final String? at;
}

/// "Status: Reviewed, 2 of 3" — the whole line for a screen reader.
String appStatusPathLabel(List<AppStatusStop> stops, int reached) {
  if (stops.isEmpty) return '';
  final r = reached.clamp(-1, stops.length - 1);
  if (r < 0) return _t('الحالة: لم يبدأ', 'Status: not started');
  final at = stops[r].at;
  return _t('الحالة: ${stops[r].label}$_sep${r + 1} من ${stops.length}${at == null ? '' : '$_sep$at'}',
      'Status: ${stops[r].label}, ${r + 1} of ${stops.length}${at == null ? '' : ', $at'}');
}

/// The compact path of one request: submitted → reviewed → decided. Reached stops are emerald ✓, the one being
/// worked on is ringed, the rest are hairline circles; each label sits under its dot.
class AppStatusPath extends StatelessWidget {
  const AppStatusPath({super.key, required this.stops, required this.reached, this.semanticPrefix});

  /// The request path's three stops in the app's words; [times] are the formatted times of each (null = not yet).
  factory AppStatusPath.request({Key? key, required int reached, List<String?> times = const [], String? semanticPrefix}) {
    String? at(int i) => i < times.length ? times[i] : null;
    return AppStatusPath(
      key: key,
      reached: reached,
      semanticPrefix: semanticPrefix,
      stops: [
        AppStatusStop(_t('قُدِّم', 'Submitted'), at: at(0)),
        AppStatusStop(_t('قيد المراجعة', 'Reviewed'), at: at(1)),
        AppStatusStop(_t('صدر القرار', 'Decided'), at: at(2)),
      ],
    );
  }

  final List<AppStatusStop> stops;

  /// The last stop reached (0-based); -1 = none yet.
  final int reached;

  /// Read before the status (the request's title).
  final String? semanticPrefix;

  @override
  Widget build(BuildContext context) {
    if (stops.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    final n = stops.length;
    final r = reached.clamp(-1, n - 1);
    const dot = AppIconSize.md;
    Widget dotOf(int i) {
      final done = i <= r;
      final working = i == r + 1;
      return Container(
        width: dot,
        height: dot,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: done ? c.success : c.cardBg,
          shape: BoxShape.circle,
          border: Border.all(color: done ? c.success : (working ? c.primary : c.divider), width: AppBorder.strong),
        ),
        child: done
            ? Icon(Icons.check_rounded, size: AppIconSize.xs, color: appInkOnFill(context, c.success))
            : (working
                ? Container(
                    width: AppSpace.xs - AppSpace.xxs / 2,
                    height: AppSpace.xs - AppSpace.xxs / 2,
                    decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle))
                : null),
      );
    }

    final muted = ensureContrast(c.textMedium, [c.cardBg]);
    Widget labelOf(int i) {
      final align = i == 0 ? TextAlign.start : (i == n - 1 ? TextAlign.end : TextAlign.center);
      final s = stops[i];
      return Column(
        crossAxisAlignment: i == 0 ? CrossAxisAlignment.start : (i == n - 1 ? CrossAxisAlignment.end : CrossAxisAlignment.center),
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(s.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: align,
              style: AppType.meta(context).copyWith(
                  fontWeight: i == r ? FontWeight.w600 : FontWeight.w500, color: i <= r ? c.textDark : muted)),
          if (s.at != null && i <= r)
            Text(s.at!, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: align, style: AppType.meta(context).copyWith(color: muted)),
        ],
      );
    }

    final label = appStatusPathLabel(stops, r);
    return Semantics(
      label: semanticPrefix == null ? label : '$semanticPrefix$_sep$label',
      excludeSemantics: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          for (var i = 0; i < n; i++) ...[
            dotOf(i),
            if (i < n - 1)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs),
                  child: _Line(done: i < r, axis: Axis.horizontal),
                ),
              ),
          ],
        ]),
        const SizedBox(height: AppSpace.xxs),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < n; i++) Expanded(child: labelOf(i)),
        ]),
      ]),
    );
  }
}
