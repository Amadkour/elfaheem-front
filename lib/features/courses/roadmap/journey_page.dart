// lib/features/courses/roadmap/journey_page.dart
//
// The student's learning path (D-120, D-309; redesign Stu1Discover?screen=journey, S-A2): the home journey card's
// page, personal accounts only (docs/guides/roadmap.md).
//
//   next      "خطوتك الجاية": the next course on the dark area card, its teacher and progress, and the page's ONE
//             forward button (كمّل الخطوة / ابدأ الخطوة → the course)
//   steps     "خطوات المسار" with "2 of 6 done": a rail of nodes (a tick when done, the number otherwise; the current
//             one in the forward colours) and one card per step with its tag (خلّصتها · الحين · الجاية); a step
//             opens its course
//   more      My interests (the interests sheet) · Suggested for you (RecommendationsPage), each behind its switch
//
// Data: [initial] is the home's own `journey` block (/me/home carries the steps since D-309), so the page draws at
// once with NO call; GET /api/v1/me/journey only on pull-to-refresh, after the interests change, or when the block
// came without steps (an older server) / no block was handed over (a deep link). From 840 px the steps and the side
// column (next step, interests) sit side by side.
library;

import 'package:flutter_education_app/features/guest/sa_hero_page.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter/material.dart';

import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppFill;
import 'package:flutter_education_app/utils/widget/app_navigator.dart' show AppNavigator;
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/courses/roadmap/recommendations.dart' show RecommendationsPage, showInterestsSheet;
import 'package:flutter_education_app/features/courses/roadmap/roadmap_api.dart';
import 'package:flutter_education_app/features/courses/roadmap/roadmap_path.dart';

/// "Continue" for a course the student is in, "Start" for one they have not begun.
String journeyActionLabel(Journey j) => j.next.kind == 'continue' ? t('متابعة', 'Continue') : t('ابدأ', 'Start');

/// Where the student is in a course: "In progress · 40 %" / "Not started yet" / "Completed".
String journeyStepState(RmCourse c) => switch (c.state) {
      RmState.completed => t('مكتمل', 'Completed'),
      RmState.inProgress => t('قيد الدراسة · ${c.progress.round()}٪', 'In progress · ${c.progress.round()} %'),
      _ => t('لم تبدأه بعد', 'Not started yet'),
    };

/// Whether the page can draw [j] without asking the server (it carries the whole path).
bool journeyComplete(Journey? j) => j != null && j.steps.isNotEmpty;

class JourneyPage extends StatefulWidget {
  const JourneyPage({super.key, this.api = const RoadmapApi(), this.initial});

  final RoadmapApi api;

  /// The home's journey block: drawn at once, no call while it carries its steps.
  final Journey? initial;

  @override
  State<JourneyPage> createState() => _JourneyPageState();
}

class _JourneyPageState extends State<JourneyPage> {
  Journey? _j;
  bool _loaded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _j = widget.initial;
    if (journeyComplete(_j)) {
      _loaded = true;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final j = await widget.api.journey();
      if (mounted) setState(() => (_j = j, _loaded = true));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loaded = roadmapHiddenError(e);
        // a failed refresh keeps the path on screen; only an empty page says so
        _error = _loaded || _j != null ? null : t('تعذّر تحميل رحلتك', 'Could not load your journey');
      });
      if (_j != null && !roadmapHiddenError(e)) showAppNotice(t('تعذّر التحديث', 'Could not refresh'), error: true);
    }
  }

  Future<void> _interests() async {
    final saved = await showInterestsSheet(context);
    if (saved == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final j = _j;
    final recsOn = !roadmapOff(kRoadmapRecsKey);
    return BasePage(
      key: const ValueKey(kRoadmapJourneyKey),
      appBar: ScreenAppBar(title: t('مساري التعليمي', 'My learning path')),
      child: SaHeroPage(area: AppArea.learn, kicker: 'sa_journey_kicker'.tr, title: 'sa_journey_title'.tr, squiggle: 'sa_journey_squiggle'.tr, child: AppRefresh(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.xl),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: AppWidth.content.max),
                child: j != null
                    ? JourneyContent(
                        journey: j,
                        onOpenCourse: (c) => AppNavigator.openCourse(c.id),
                        onPickInterests: recsOn ? _interests : null,
                        onMoreForYou: recsOn
                            ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RecommendationsPage()))
                            : null,
                      )
                    : _error != null
                        ? AppEmpty(icon: Icons.cloud_off_rounded, title: _error!, actionLabel: t('إعادة المحاولة', 'Retry'), onAction: _load)
                        : _loaded
                            ? AppEmpty(
                                icon: Icons.route_rounded,
                                title: t('لا مسار بعد', 'No path yet'),
                                message: t('أكمل دورة أو اختر اهتماماتك ليظهر طريقك هنا.', 'Complete a course or pick your interests and your way shows here.'),
                                actionLabel: recsOn ? t('اختر اهتماماتك', 'Pick your interests') : null,
                                onAction: recsOn ? _interests : null,
                              )
                            : const AppListSkeleton(items: 4),
              ),
            ),
          ],
        ),
      )),
    );
  }
}

/// The page's content from plain values (redesign Stu1Discover?screen=journey, S-A2).
///
///   phone   the next step (a dark card with the ONE forward button) · "The path's steps" (a rail of numbered nodes,
///           each step a card) · My interests and More for you
///   wide    the steps on the start side; the next step, My interests and More for you beside them
class JourneyContent extends StatelessWidget {
  const JourneyContent({super.key, required this.journey, required this.onOpenCourse, this.onPickInterests, this.onMoreForYou});

  final Journey journey;
  final ValueChanged<RmCourse> onOpenCourse;
  final VoidCallback? onPickInterests, onMoreForYou;

  /// From this width the steps and the side column sit side by side.
  static const double twoColumnsFrom = 840;

  @override
  Widget build(BuildContext context) {
    final j = journey;
    final next = _JourneyNextCard(journey: j, onOpen: () => onOpenCourse(j.next));
    final steps = _JourneyStepsCard(journey: j, onOpen: onOpenCourse);
    final more = onPickInterests == null && onMoreForYou == null
        ? null
        : _JourneyMoreCard(onPickInterests: onPickInterests, onMoreForYou: onMoreForYou);
    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth >= twoColumnsFrom) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 3, child: steps),
          const SizedBox(width: AppSpace.lg),
          Expanded(
            flex: 2,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              next,
              if (more != null) ...[AppSpace.gapLg, more],
            ]),
          ),
        ]);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        next,
        AppSpace.gapLg,
        steps,
        if (more != null) ...[AppSpace.gapLg, more],
      ]);
    });
  }
}

/// The next step on the dark area card: "Your next step" · the course · teacher and where they are · the bar · the
/// page's one forward button.
class _JourneyNextCard extends StatelessWidget {
  const _JourneyNextCard({required this.journey, required this.onOpen});

  final Journey journey;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final co = journey.next;
    final meta = [if ((co.teacherName ?? '').isNotEmpty) co.teacherName!, _journeyWhere(co)].join('، ');
    return AppCard(
      variant: AppCardVariant.dark,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // start-aligned: each text box hugs its words, so the contrast check reads them on the gradient
        Text('sa_journey_next'.tr,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: c.onHeroMuted, fontWeight: FontWeight.w600)),
        AppSpace.gapXs,
        Semantics(
          header: true,
          child: Text(co.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.headline(context).copyWith(color: c.onHero)),
        ),
        AppSpace.gapXs,
        Text(meta, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.onHeroMuted)),
        AppSpace.gapMd,
        SizedBox(width: double.infinity, child: _HotBar(value: co.progress / 100, track: c.heroGlass)),
        AppSpace.gapMd,
        AppButton.hot(
          key: const ValueKey('journey.continue'),
          label: co.kind == 'continue' ? 'sa_journey_continue'.tr : 'sa_journey_start'.tr,
          expand: true,
          onPressed: onOpen,
        ),
      ]),
    );
  }
}

/// A thin bar in the forward gradient (the step's progress).
class _HotBar extends StatelessWidget {
  const _HotBar({required this.value, required this.track});

  final double value;
  final Color track;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(AppRadius.pill);
    return ExcludeSemantics(
      child: SizedBox(
        height: AppSpace.xs,
        child: DecoratedBox(
          decoration: BoxDecoration(color: track, borderRadius: r),
          child: AppFill(
            value: value.clamp(0.0, 1.0),
            builder: (context, v) => FractionallySizedBox(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: v.clamp(0.0, 1.0),
              heightFactor: 1,
              child: DecoratedBox(decoration: BoxDecoration(gradient: context.colors.kit.hotButton, borderRadius: r)),
            ),
          ),
        ),
      ),
    );
  }
}

/// "The path's steps" with "2 of 6 done": one row per step, a rail of nodes on the start side.
class _JourneyStepsCard extends StatelessWidget {
  const _JourneyStepsCard({required this.journey, required this.onOpen});

  final Journey journey;
  final ValueChanged<RmCourse> onOpen;

  @override
  Widget build(BuildContext context) {
    final j = journey;
    final stops = j.steps.isEmpty ? [RoadmapStop(j.next, RoadmapStopRole.here)] : journeyStops(j);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _CardHead(
          title: 'sa_journey_steps'.tr,
          action: j.total > 0
              ? AppStatusBadge(
                  label: 'sa_journey_done_of'.tr.replaceAll('{done}', '${j.done}').replaceAll('{total}', '${j.total}'),
                  tone: AppTone.success,
                )
              : null,
        ),
        for (var i = 0; i < stops.length; i++)
          _StepRow(
            stop: stops[i],
            number: i + 1,
            last: i == stops.length - 1,
            first: i == 0,
            prevDone: i > 0 && stops[i - 1].role == RoadmapStopRole.taken,
            onTap: () => onOpen(stops[i].course),
          ),
      ]),
    );
  }
}

/// One step: its node on the rail (a tick when done, its number otherwise) and its card.
class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.stop,
    required this.number,
    required this.first,
    required this.last,
    required this.prevDone,
    required this.onTap,
  });

  final RoadmapStop stop;
  final int number;
  final bool first, last, prevDone;
  final VoidCallback onTap;

  static const double _node = 48;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final kit = c.kit;
    final co = stop.course;
    final done = stop.role == RoadmapStopRole.taken && co.done;
    final taken = stop.role == RoadmapStopRole.taken;
    final here = stop.role == RoadmapStopRole.here;
    final (String tag, AppTone tone) = taken
        ? ('sa_journey_done'.tr, AppTone.success)
        : here
            ? ('sa_journey_now'.tr, AppTone.brand)
            : (last ? 'sa_journey_last'.tr : 'sa_journey_upcoming'.tr, AppTone.neutral);
    final teacher = co.teacherName ?? '';
    final state = taken
        ? 'sa_journey_done'.tr
        : here
            ? _journeyWhere(co)
            : 'sa_journey_not_started'.tr;
    final meta = [if (teacher.isNotEmpty) teacher, state].join('، ');
    final radius = BorderRadius.circular(AppRadius.tile);
    final card = Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: here ? null : (taken ? c.cardBg : kit.well),
        gradient: here ? LinearGradient(colors: [c.cardBg, kit.hotTone.tint]) : null,
        borderRadius: radius,
        border: Border.all(color: here ? kit.hotB : kit.line, width: AppBorder.strong),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        // the tag hugs the end; on a narrow card (320 px, large text) it drops under the words
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: AppSpace.xs,
          runSpacing: AppSpace.xs,
          children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(co.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.tileTitle(context)),
              const SizedBox(height: AppSpace.xxs),
              Text(meta, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
            ]),
            AppStatusBadge(label: tag, tone: tone),
          ],
        ),
        if (here) ...[
          AppSpace.gapSm,
          _HotBar(value: co.progress / 100, track: kit.track),
        ],
      ]),
    );
    final Widget node;
    if (done || taken) {
      node = _Node(fill: kit.ok.color, child: Icon(Icons.check_rounded, size: AppIconSize.md, color: c.onHero));
    } else if (here) {
      node = _Node(
        gradient: kit.hotButton,
        ring: kit.hotTone.tint,
        child: Text('$number', style: AppType.label(context).copyWith(color: kit.hotFg, fontWeight: FontWeight.w600)),
      );
    } else {
      node = _Node(
        fill: kit.track,
        child: Text('$number', style: AppType.label(context).copyWith(color: c.textMedium, fontWeight: FontWeight.w600)),
      );
    }
    return Semantics(
      button: true,
      label: '${'sa_journey_step'.tr.replaceAll('{n}', '$number')}: ${co.name}, $tag',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              width: _node + AppSpace.xs,
              child: CustomPaint(
                painter: _RailPainter(
                  top: first ? null : (prevDone ? kit.ok.color : kit.lock),
                  bottom: last ? null : (taken ? kit.ok.color : kit.lock),
                  topDashed: !prevDone,
                  bottomDashed: !taken,
                ),
                child: Center(child: node),
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Padding(padding: const EdgeInsets.symmetric(vertical: AppSpace.xs), child: card),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Node extends StatelessWidget {
  const _Node({required this.child, this.fill, this.gradient, this.ring});

  final Widget child;
  final Color? fill;
  final Gradient? gradient;
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: _StepRow._node,
      height: _StepRow._node,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        gradient: gradient,
        shape: BoxShape.circle,
        border: Border.all(color: ring ?? c.cardBg, width: AppBorder.focus),
        boxShadow: AppShadow.card(context),
      ),
      child: child,
    );
  }
}

/// The rail between two nodes: solid in the done colour up to the last finished step, dashed after it.
class _RailPainter extends CustomPainter {
  _RailPainter({this.top, this.bottom, this.topDashed = false, this.bottomDashed = false});

  final Color? top, bottom;
  final bool topDashed, bottomDashed;

  void _line(Canvas canvas, Offset a, Offset b, Color color, bool dashed) {
    final p = Paint()
      ..color = color
      ..strokeWidth = AppBorder.focus * 2
      ..strokeCap = StrokeCap.round;
    if (!dashed) {
      canvas.drawLine(a, b, p);
      return;
    }
    const dash = 6.0, gap = 6.0;
    for (var y = a.dy; y < b.dy; y += dash + gap) {
      canvas.drawLine(Offset(a.dx, y), Offset(a.dx, (y + dash).clamp(a.dy, b.dy)), p);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2, mid = size.height / 2;
    if (top != null) _line(canvas, Offset(x, 0), Offset(x, mid), top!, topDashed);
    if (bottom != null) _line(canvas, Offset(x, mid), Offset(x, size.height), bottom!, bottomDashed);
  }

  @override
  bool shouldRepaint(_RailPainter old) =>
      old.top != top || old.bottom != bottom || old.topDashed != topDashed || old.bottomDashed != bottomDashed;
}

/// A card's head: the title (section) and its tag or link hugging the end.
class _CardHead extends StatelessWidget {
  const _CardHead({required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.sm),
        // a Wrap: the tag hugs the end, and drops under the title when both do not fit (320 px, large text)
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpace.sm,
          runSpacing: AppSpace.xs,
          children: [
            Semantics(header: true, child: Text(title, style: AppType.section(context))),
            ?action,
          ],
        ),
      );
}

/// "My interests" (edit → the interests sheet) and "More courses for you" (the recommendations page).
class _JourneyMoreCard extends StatelessWidget {
  const _JourneyMoreCard({this.onPickInterests, this.onMoreForYou});

  final VoidCallback? onPickInterests, onMoreForYou;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _CardHead(
          title: 'sa_journey_interests'.tr,
          action: onPickInterests == null
              ? null
              : AppButton.ghost(
                  key: const ValueKey('journey.interests'),
                  label: 'sa_journey_edit'.tr,
                  icon: Icons.edit_outlined,
                  size: AppButtonSize.sm,
                  onPressed: onPickInterests,
                ),
        ),
        Text('sa_journey_interests_sub'.tr, style: AppType.meta(context)),
        if (onMoreForYou != null) ...[
          AppSpace.gapSm,
          AppTile(
            key: const ValueKey('journey.more'),
            icon: Icons.auto_awesome_rounded,
            title: 'sa_journey_recs'.tr,
            subtitle: 'sa_journey_recs_sub'.tr,
            trailing: Icon(Icons.chevron_right_rounded, size: AppIconSize.md, color: context.colors.textMedium),
            onTap: onMoreForYou,
          ),
        ],
      ]),
    );
  }
}

/// The path as one segment per course: done in emerald, the current one in ink (it fills once, AppFill), the rest
/// on the [rest] track; without steps (an older server) a plain bar.
class JourneyTrack extends StatelessWidget {
  const JourneyTrack({super.key, required this.journey, this.height = 6, this.rest});

  final Journey journey;
  final double height;

  /// The colour of the steps ahead (the warm hairline by default; a block passes a tint of its ink).
  final Color? rest;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final done = c.primary;
    final track = rest ?? c.divider;
    final steps = journey.steps;
    final radius = BorderRadius.circular(height);
    Widget bar(Color color, double fill) => SizedBox(
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(color: track, borderRadius: radius),
        child: AppFill(
          value: fill,
          builder: (context, v) => FractionallySizedBox(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: v.clamp(0.0, 1.0),
            heightFactor: 1,
            child: DecoratedBox(decoration: BoxDecoration(color: color, borderRadius: radius)),
          ),
        ),
      ),
    );
    if (steps.isEmpty || steps.length > 12) {
      return ExcludeSemantics(child: bar(done, journey.fraction.clamp(0.0, 1.0)));
    }
    return ExcludeSemantics(
      child: Row(
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpace.xxs),
            Expanded(
              child: steps[i].done
                  ? bar(done, 1)
                  : steps[i].current
                      ? bar(c.textDark, (steps[i].progress / 100).clamp(0.15, 1.0))
                      : bar(track, 0),
            ),
          ],
        ],
      ),
    );
  }
}

/// Where the student is in a step, in the design's words: "خلّصتها" · "خلّصت 64٪" · "ما بدأتها".
String _journeyWhere(RmCourse c) => switch (c.state) {
      RmState.completed => 'sa_journey_done'.tr,
      RmState.inProgress => 'sa_journey_progress'.tr.replaceAll('{n}', '${c.progress.round()}'),
      _ => 'sa_journey_not_started'.tr,
    };
