// lib/features/courses/roadmap/roadmap_path.dart
//
// The roadmap drawn as ONE vertical path (D-120), plain values only (test/ui/roadmap_layout_test.dart):
//
//   ●  Completed            the courses the student took before (done ✓ / in progress ◐ with its bar)
//   │  Python 1
//   ◉  You are here         the course (tinted card) — the journey page: the next step
//   │  Python 2
//   ②  Step 2               the next courses in order, each with its prerequisites ("Needs  ✓ Python 1  ○ SQL")
//      Python 3
//
// A node and its card share one row; the rail is drawn by the node so a card can grow (two-line names, chips)
// without breaking the line. The teacher's view shows drafts ("Draft") and no states.
//
// Warm Editorial: the walked part of the line and a completed stop are emerald, "You are here" is ink on its node
// and the path's one block (emerald: the page's subject), the stops ahead are paper with their step number; course
// names are editorial section headings; a stop presses in under the finger.
library;

import 'package:flutter/material.dart';

import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_contrast.dart' show ensureContrast;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppPressScale;
import 'package:flutter_education_app/utils/widget/app_network_image.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/courses/course_price_tag.dart' show coursePriceLabel;
import 'package:flutter_education_app/features/courses/course_space/course_space_parts.dart' show CourseProgressBar;
import 'package:flutter_education_app/features/courses/roadmap/roadmap_api.dart';

enum RoadmapStopRole { taken, here, next }

class RoadmapStop {
  const RoadmapStop(this.course, this.role);

  final RmCourse course;
  final RoadmapStopRole role;
}

/// The stops of a course's roadmap: previous · the course · next.
List<RoadmapStop> roadmapStops(Roadmap r) => [
  for (final c in r.previous) RoadmapStop(c, RoadmapStopRole.taken),
  RoadmapStop(r.course, RoadmapStopRole.here),
  for (final c in r.next) RoadmapStop(c, RoadmapStopRole.next),
];

/// The stops of a journey: what came before the current step · the current step · what comes after it.
List<RoadmapStop> journeyStops(Journey j) {
  final at = j.steps.indexWhere((s) => s.current);
  return [
    for (var i = 0; i < j.steps.length; i++)
      RoadmapStop(
        j.steps[i],
        i == at ? RoadmapStopRole.here : (at >= 0 && i > at ? RoadmapStopRole.next : RoadmapStopRole.taken),
      ),
  ];
}

class RoadmapPathView extends StatelessWidget {
  const RoadmapPathView({super.key, required this.stops, this.onTap, this.staff = false, this.hereLabel});

  final List<RoadmapStop> stops;
  final ValueChanged<RmCourse>? onTap;

  /// The owner's view: drafts are marked, no student states.
  final bool staff;

  /// The current stop's caption; default "You are here".
  final String? hereLabel;

  @override
  Widget build(BuildContext context) {
    var step = 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < stops.length; i++)
          _StopRow(
            stop: stops[i],
            step: stops[i].role == RoadmapStopRole.next ? ++step : null,
            first: i == 0,
            last: i == stops.length - 1,
            lineInDone: i > 0 && _doneish(stops[i - 1]),
            lineOutDone: _doneish(stops[i]),
            staff: staff,
            hereLabel: hereLabel,
            onTap: onTap,
          ),
      ],
    );
  }

  static bool _doneish(RoadmapStop s) => s.role == RoadmapStopRole.taken && s.course.done;
}

class _StopRow extends StatelessWidget {
  const _StopRow({
    required this.stop,
    required this.step,
    required this.first,
    required this.last,
    required this.lineInDone,
    required this.lineOutDone,
    required this.staff,
    required this.hereLabel,
    required this.onTap,
  });

  final RoadmapStop stop;
  final int? step;
  final bool first, last, lineInDone, lineOutDone, staff;
  final String? hereLabel;
  final ValueChanged<RmCourse>? onTap;

  static const double _rail = 36;
  static const double _node = 28;
  static const double _nodeTop = 18;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final here = stop.role == RoadmapStopRole.here;
    final tap = here || onTap == null ? null : () => onTap!(stop.course);
    // "You are here" is the path's one block (emerald: the subject of the page); the other stops are paper
    final emerald = AppBlockColors.of(context, AppBlockTone.emerald);
    final radius = BorderRadius.circular(AppRadius.card);
    final body = Padding(
      padding: const EdgeInsets.all(AppSpace.sm),
      child: _StopBody(stop: stop, step: step, staff: staff, hereLabel: hereLabel, tappable: tap != null),
    );
    // the card sizes the row; the rail is stretched beside it (no IntrinsicHeight: the card holds LayoutBuilders)
    return Stack(
      children: [
        Padding(
          padding: EdgeInsetsDirectional.only(start: _rail + AppSpace.xs, bottom: last ? 0 : AppSpace.sm),
          child: AppPressScale(
            enabled: tap != null,
            child: Material(
              color: here ? emerald.surface : c.cardBg,
              shape: RoundedRectangleBorder(
                borderRadius: radius,
                side: BorderSide(
                  color: here ? (emerald.border ?? Color.lerp(emerald.surface, c.textDark, 0.14)!) : c.divider,
                  width: AppBorder.hairline,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(onTap: tap, child: body),
            ),
          ),
        ),
        PositionedDirectional(
          start: 0,
          top: 0,
          bottom: 0,
          width: _rail,
          child: Stack(
            children: [
              if (!first)
                PositionedDirectional(start: _rail / 2 - 1, top: 0, height: _nodeTop, child: _Line(done: lineInDone)),
              if (!last)
                PositionedDirectional(start: _rail / 2 - 1, top: _nodeTop + _node, bottom: 0, child: _Line(done: lineOutDone)),
              PositionedDirectional(
                start: (_rail - _node) / 2,
                top: _nodeTop,
                child: ExcludeSemantics(child: _Node(stop: stop, step: step, staff: staff)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The path's line: emerald where it has been walked, the warm hairline ahead.
class _Line extends StatelessWidget {
  const _Line({required this.done});

  final bool done;

  @override
  Widget build(BuildContext context) => Container(
    width: AppBorder.focus,
    decoration: BoxDecoration(
      color: done ? context.colors.success.withValues(alpha: 0.6) : context.colors.divider,
      borderRadius: BorderRadius.circular(1),
    ),
  );
}

/// A stop's node: emerald with a check when done, ink at "You are here", a paper disc with the step's number
/// ahead (its edge emerald while the student is in it).
class _Node extends StatelessWidget {
  const _Node({required this.stop, required this.step, required this.staff});

  final RoadmapStop stop;
  final int? step;
  final bool staff;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = stop.course.state;
    final Color fill, border, ink;
    Widget? child;
    IconData? icon;
    switch (stop.role) {
      case RoadmapStopRole.here:
        fill = c.textDark;
        border = c.textDark;
        ink = c.background;
        icon = Icons.place_rounded;
      case RoadmapStopRole.taken when staff:          // the owner's view: a course that comes before, no state
        fill = c.cardBg;
        border = c.divider;
        ink = c.textMedium;
        icon = Icons.flag_outlined;
      case RoadmapStopRole.taken:
        final done = s == RmState.completed;
        fill = done ? c.success : c.cardBg;
        border = done ? c.success : c.primary;
        ink = done ? appInkOnFill(context, c.success) : appInk(context, c.primary);
        icon = done ? Icons.check_rounded : Icons.timelapse_rounded;
      case RoadmapStopRole.next:
        final done = !staff && s == RmState.completed;
        fill = done ? c.success : c.cardBg;
        border = done ? c.success : (!staff && s == RmState.inProgress ? c.primary : c.divider);
        ink = done ? appInkOnFill(context, c.success) : c.textMedium;
        if (done) {
          icon = Icons.check_rounded;
        } else {
          child = Text(
            '${step ?? ''}',
            style: AppType.meta(context).copyWith(
              fontWeight: FontWeight.w600,
              color: ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          );
        }
    }
    return Container(
      width: _StopRow._node,
      height: _StopRow._node,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: fill, shape: BoxShape.circle, border: Border.all(color: border, width: AppBorder.strong)),
      child: child ?? Icon(icon, size: AppIconSize.sm, color: ink),
    );
  }
}

class _StopBody extends StatelessWidget {
  const _StopBody({required this.stop, required this.step, required this.staff, required this.hereLabel, required this.tappable});

  final RoadmapStop stop;
  final int? step;
  final bool staff, tappable;
  final String? hereLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final co = stop.course;
    final here = stop.role == RoadmapStopRole.here;
    // on the emerald block the captions keep AA against the block, on paper against the card
    final surface = here ? AppBlockColors.of(context, AppBlockTone.emerald).surface : c.cardBg;
    final muted = ensureContrast(c.textMedium, [surface]);
    final (caption, captionColor) = _caption(context);
    final meta = [
      if (co.level != null && co.level!.isNotEmpty) roadmapLevelLabel(co.level),
      if (here && !staff && co.state == RmState.inProgress) t('${co.progress.round()}٪ مكتمل', '${co.progress.round()}% done'),
      if (!staff && stop.role == RoadmapStopRole.next && co.state == RmState.notStarted)
        co.isFree || co.finalPrice <= 0 ? t('مجاني', 'Free') : coursePriceLabel(co.currency, co.finalPrice),
    ].join(' · ');
    final showBar = !staff && co.state == RmState.inProgress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Thumb(url: co.imageUrl),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (here)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs / 2),
                      decoration: BoxDecoration(color: c.textDark, borderRadius: BorderRadius.circular(AppRadius.pill)),
                      child: Text(
                        caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: c.background),
                      ),
                    )
                  else
                    Text(
                      caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.meta(context).copyWith(
                        fontWeight: FontWeight.w500,
                        color: captionColor == null ? muted : appInkOn(context, captionColor, surface),
                      ),
                    ),
                  const SizedBox(height: AppSpace.xxs),
                  Text(co.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: AppSpace.xxs / 2),
                    Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: muted)),
                  ],
                ],
              ),
            ),
            if (tappable) ...[
              const SizedBox(width: AppSpace.xxs),
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.sm + 2),
                child: Icon(Icons.chevron_right_rounded, size: AppIconSize.md, color: c.textLight),
              ),
            ],
          ],
        ),
        if (showBar) ...[
          const SizedBox(height: AppSpace.sm - 2),
          CourseProgressBar(value: co.progress / 100, height: AppSpace.xxs + 1, color: c.primary),
        ],
        if (co.prerequisites.isNotEmpty) ...[
          const SizedBox(height: AppSpace.sm - 2),
          _Prereqs(items: co.prerequisites, staff: staff, on: surface),
        ],
      ],
    );
  }

  /// The caption above the name and its tone (null = the muted ink).
  (String, Color?) _caption(BuildContext context) {
    final c = context.colors;
    final co = stop.course;
    switch (stop.role) {
      case RoadmapStopRole.here:
        return (hereLabel ?? t('أنت هنا', 'You are here'), null);
      case RoadmapStopRole.taken when staff:
        return (t('يأتي قبله', 'Comes before'), null);
      case RoadmapStopRole.taken:
        return co.state == RmState.completed
            ? (t('مكتمل', 'Completed'), c.success)
            : (t('قيد الدراسة · ${co.progress.round()}٪', 'In progress · ${co.progress.round()}%'), c.primary);
      case RoadmapStopRole.next:
        if (staff && !co.isPublished) return (t('الخطوة $step · مسودة', 'Step $step · Draft'), c.warning);
        return switch (staff ? null : co.state) {
          RmState.completed => (t('الخطوة $step · مكتمل', 'Step $step · Completed'), c.success),
          RmState.inProgress => (t('الخطوة $step · ${co.progress.round()}٪', 'Step $step · ${co.progress.round()}%'), c.primary),
          _ => (t('الخطوة $step', 'Step $step'), null),
        };
    }
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final u = url;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: SizedBox(
        width: AppTouch.min,
        height: AppTouch.min,
        child: u == null
            ? ColoredBox(
                color: c.inputBg,
                child: Icon(Icons.menu_book_rounded, size: AppIconSize.md, color: c.textLight),
              )
            : AppNetworkImage(url: u, width: AppTouch.min, height: AppTouch.min, fit: BoxFit.cover, borderRadius: BorderRadius.zero),
      ),
    );
  }
}

class _Prereqs extends StatelessWidget {
  const _Prereqs({required this.items, required this.staff, required this.on});

  final List<RmPrereq> items;
  final bool staff;

  /// The card's surface.
  final Color on;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final okFill = appTintOn(context, c.success, surface: on);
    return Wrap(
      spacing: AppSpace.xs - 2,
      runSpacing: AppSpace.xs - 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(t('يتطلب', 'Needs'), style: AppType.meta(context).copyWith(fontWeight: FontWeight.w500, color: ensureContrast(c.textMedium, [on]))),
        for (final p in items)
          Semantics(
            label: staff
                ? p.name
                : (p.done == true ? t('${p.name}: مكتمل', '${p.name}: done') : t('${p.name}: لم يكتمل بعد', '${p.name}: not done yet')),
            excludeSemantics: true,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 220),
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs),
              decoration: BoxDecoration(
                color: p.done == true ? okFill : c.inputBg,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    staff ? Icons.link_rounded : (p.done == true ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded),
                    size: AppIconSize.xs,
                    color: p.done == true ? appInkOn(context, c.success, okFill) : c.textMedium,
                  ),
                  const SizedBox(width: AppSpace.xxs),
                  Flexible(
                    child: Text(
                      p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.meta(context).copyWith(fontWeight: FontWeight.w500, color: c.textDark),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
