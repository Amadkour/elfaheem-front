// lib/features/shared/roadmap/journey_page.dart
//
// The student's learning path (D-120, redesigned D-309): the home journey card's page.
//
//   summary   "Your learning path" · the field · "Continue your journey in <field>" · the path as segments ·
//             "2 of 3 done · 67 %" · the next step with the page's ONE primary button (Continue / Start → the course)
//   path      "The whole path": what they took · the next step ("Your next step") · what follows (RoadmapPathView);
//             a course opens its page
//   more      My interests (the interests sheet) · More courses for you (RecommendationsPage), each behind its switch
//
// Data: [initial] is the home's own `journey` block (/me/home carries the steps since D-309), so the page draws at
// once with NO call; GET /api/v1/me/journey only on pull-to-refresh, after the interests change, or when the block
// came without steps (an older server) / no block was handed over (a deep link). Narrow and wide: one centred column
// (max 760) so a desktop window never stretches the path across the screen.
//
// Warm Editorial: the summary is the page's one block (peach, learning) with the title in the editorial serif, the
// path's segments (done emerald, the current one ink) and the next step on a paper card holding the ONE primary
// button; "The whole path" is an editorial section under it.
library;

import 'package:flutter/material.dart';

import '../../../config/theme/theme_config_provider.dart';
import '../../../design/app_kit.dart';
import '../../../design/app_motion_kit.dart' show AppFill;
import '../../../utils/widget/app_navigator.dart' show AppNavigator;
import '../../../utils/widget/app_bar.dart';
import '../../../utils/widget/base_page.dart';
import '../../admin/admin_common.dart' show t;
import 'recommendations.dart' show RecommendationsPage, showInterestsSheet;
import 'roadmap_api.dart';
import 'roadmap_path.dart';

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
      child: AppRefresh(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.xl),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: AppWidth.reading.max),
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
                                message: t('أكمل كورساً أو اختر اهتماماتك ليظهر طريقك هنا.', 'Complete a course or pick your interests and your way shows here.'),
                                actionLabel: recsOn ? t('اختر اهتماماتك', 'Pick your interests') : null,
                                onAction: recsOn ? _interests : null,
                              )
                            : const AppListSkeleton(items: 4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The page's content from plain values.
class JourneyContent extends StatelessWidget {
  const JourneyContent({super.key, required this.journey, required this.onOpenCourse, this.onPickInterests, this.onMoreForYou});

  final Journey journey;
  final ValueChanged<RmCourse> onOpenCourse;
  final VoidCallback? onPickInterests, onMoreForYou;

  @override
  Widget build(BuildContext context) {
    final j = journey;
    final field = j.field?.name ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppBlock(
          tone: AppBlockTone.peach,
          hero: true,
          child: Builder(builder: (context) {
            final b = AppBlock.colorsOf(context);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.route_rounded, size: AppIconSize.md, color: b.muted),
                    const SizedBox(width: AppSpace.xs),
                    Expanded(
                      child: Text(t('مسارك التعليمي', 'Your learning path'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: b.muted)),
                    ),
                    if (field.isNotEmpty)
                      ConstrainedBox(constraints: const BoxConstraints(maxWidth: 180), child: AppStatusBadge(label: field)),
                  ],
                ),
                AppSpace.gapXs,
                Semantics(
                  header: true,
                  child: Text(j.title, style: AppType.headline(context).copyWith(color: b.ink)),
                ),
                AppSpace.gapMd,
                JourneyTrack(journey: j, height: AppSpace.xs, rest: b.ink.withValues(alpha: 0.12)),
                const SizedBox(height: AppSpace.xs),
                Text(
                  '${j.doneLine} · ${(j.fraction * 100).round()} %',
                  style: AppType.label(context).copyWith(color: b.muted, fontFeatures: const [FontFeature.tabularFigures()]),
                ),
                if (j.source == 'interest') ...[
                  AppSpace.gapXs,
                  Text(
                    t('اقتراح من اهتماماتك والكورسات التي أكملتها.', 'Suggested from your interests and the courses you completed.'),
                    style: AppType.body(context).copyWith(color: b.muted),
                  ),
                ],
                AppSpace.gapLg,
                _NextBox(journey: j, onOpen: () => onOpenCourse(j.next)),
              ],
            );
          }),
        ),
        Padding(
          padding: AppSpace.sectionHead,
          child: Semantics(header: true, child: Text(t('المسار كاملاً', 'The whole path'), style: AppType.section(context))),
        ),
        RoadmapPathView(
          stops: j.steps.isEmpty ? [RoadmapStop(j.next, RoadmapStopRole.here)] : journeyStops(j),
          hereLabel: t('خطوتك التالية', 'Your next step'),
          onTap: onOpenCourse,
        ),
        if (onPickInterests != null || onMoreForYou != null) ...[
          AppSpace.gapLg,
          Wrap(
            spacing: AppSpace.xs,
            runSpacing: AppSpace.xs,
            children: [
              if (onPickInterests != null)
                AppButton.secondary(
                  key: const ValueKey('journey.interests'),
                  label: t('اهتماماتي', 'My interests'),
                  icon: Icons.favorite_border_rounded,
                  size: AppButtonSize.sm,
                  onPressed: onPickInterests,
                ),
              if (onMoreForYou != null)
                AppButton.ghost(
                  key: const ValueKey('journey.more'),
                  label: t('كورسات مقترحة لك', 'More courses for you'),
                  icon: Icons.auto_awesome_rounded,
                  size: AppButtonSize.sm,
                  onPressed: onMoreForYou,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// The next step with the page's one primary action.
class _NextBox extends StatelessWidget {
  const _NextBox({required this.journey, required this.onOpen});

  final Journey journey;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final co = journey.next;
    final label = co.kind == 'continue' ? t('أكمل', 'Continue') : t('خطوتك التالية', 'Your next step');
    final meta = [journeyStepState(co), if ((co.teacherName ?? '').isNotEmpty) co.teacherName!].join(' · ');
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(fontWeight: FontWeight.w500)),
        const SizedBox(height: AppSpace.xxs / 2),
        Text(co.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
        const SizedBox(height: AppSpace.xxs / 2),
        Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
      ],
    );
    final button = AppButton.primary(
      key: const ValueKey('journey.continue'),
      label: journeyActionLabel(journey),
      trailingIcon: Icons.arrow_forward_rounded,
      onPressed: onOpen,
    );
    // the next step on paper inside the block: the one card that holds the page's primary action
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: c.cardBg,
        border: Border.all(color: c.divider, width: AppBorder.hairline),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: LayoutBuilder(builder: (context, box) {
        // phone: the button under the text, full width; wider: beside it
        if (box.maxWidth < 420) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [text, AppSpace.gapSm, button]);
        }
        return Row(children: [Expanded(child: text), AppSpace.gapSm, button]);
      }),
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
