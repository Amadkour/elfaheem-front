// lib/features/courses/course_space/subject_lessons_page.dart
//
// "دروس المادة" (Stu1Learn screen=sessions, S-B): every step of the subject's path on one page. Plain values: the
// student's course screen pushes it and rebuilds it from its provider. The learn area's hero (kicker, title, one
// line), then one card: "مسارك في المادة" with its ring, the finished start folded into one row ("٥ دروس
// خلّصتها · اعرضها"), the live step with its "ادخل الحصة", the current step "كمّل", locked steps dashed.
library;

import 'package:flutter/material.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';
import 'package:flutter_education_app/features/courses/course_space/subject_space_parts.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';

/// How close to the end of the scroll the next page of lessons is asked for.
const double _kNearEnd = 400;

/// How many finished steps at the start fold into one row (the last of them stays visible).
int subjectFoldCount(List<SubjectStep> steps) {
  var n = 0;
  while (n < steps.length && steps[n].state == SubjectStepState.done) {
    n++;
  }
  return n >= 3 ? n - 1 : 0;
}

class SubjectLessonsPage extends StatefulWidget {
  const SubjectLessonsPage({
    super.key,
    required this.steps,
    required this.teacher,
    this.kicker,
    this.done = 0,
    this.total = 0,
    this.loading = false,
    this.loadingMore = false,
    this.onNearEnd,
    this.onBack,
    this.onRefresh,
  });

  final List<SubjectStep> steps;
  final String teacher;

  /// "الرياضيات، ثاني ثانوي".
  final String? kicker;
  final int done, total;
  final bool loading, loadingMore;
  final VoidCallback? onNearEnd;
  final VoidCallback? onBack;
  final Future<void> Function()? onRefresh;

  @override
  State<SubjectLessonsPage> createState() => _SubjectLessonsPageState();
}

class _SubjectLessonsPageState extends State<SubjectLessonsPage> {
  bool _unfolded = false;

  bool _onScroll(ScrollNotification n) {
    if (widget.onNearEnd != null && n.metrics.axis == Axis.vertical && n.metrics.pixels >= n.metrics.maxScrollExtent - _kNearEnd) {
      widget.onNearEnd!();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => AppAreaScope(
        area: AppArea.learn,
        child: Builder(builder: (context) {
          final width = MediaQuery.sizeOf(context).width;
          final gutter = AppSpace.gutter(width);
          final w = widget;
          Widget view = CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            slivers: [
              SliverToBoxAdapter(
                child: AppHeroOverlap(
                  hero: _hero(context),
                  body: Padding(
                    padding: EdgeInsets.symmetric(horizontal: gutter),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: AppWidth.reading.max),
                        child: w.loading && w.steps.isEmpty ? const AppCard(child: AppListSkeleton(items: 5)) : _card(context),
                      ),
                    ),
                  ),
                ),
              ),
              if (w.loadingMore)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpace.md),
                    child: Center(child: AppLoadingIndicator()),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpace.xl)),
            ],
          );
          view = NotificationListener<ScrollNotification>(onNotification: _onScroll, child: view);
          if (w.onRefresh != null) view = AppRefresh(onRefresh: w.onRefresh!, child: view);
          return Scaffold(backgroundColor: context.colors.background, body: view);
        }),
      );

  Widget _hero(BuildContext context) {
    final w = widget;
    return AppHero(
      kicker: w.kicker,
      title: 'sb_lessons_title'.tr,
      subtitle: w.total > 0
          ? sbFill('sb_lessons_sub', {'teacher': w.teacher, 'done': sbDigits(w.done), 'total': sbDigits(w.total)})
          : w.teacher,
      leading: w.onBack == null ? null : AppBackButton(onPressed: w.onBack, onHero: true),
      wipe: false,
    );
  }

  Widget _card(BuildContext context) {
    final w = widget;
    final c = context.colors;
    if (w.steps.isEmpty) {
      return AppCard(
        child: AppEmpty(
          icon: Icons.video_library_outlined,
          title: 'sb_lessons_empty_t'.tr,
          message: 'sb_lessons_empty'.tr,
        ),
      );
    }
    final fold = _unfolded ? 0 : subjectFoldCount(w.steps);
    final progress = w.total > 0 ? (w.done / w.total).clamp(0, 1).toDouble() : null;
    final rows = <Widget>[
      if (subjectFoldCount(w.steps) > 0) _FoldRow(count: subjectFoldCount(w.steps), open: _unfolded, onTap: () => setState(() => _unfolded = !_unfolded)),
      for (final s in w.steps.skip(fold)) SubjectStepRow(key: ValueKey('lessons_step_${s.id}'), step: s, showJoin: true),
    ];
    return AppCard(
      title: 'sb_subj_path'.tr,
      action: progress == null
          ? null
          : _CountAction(children: [
              AppProgressRing(value: progress, showPercent: false, size: AppIconSize.xl),
              const SizedBox(width: AppSpace.xs),
              Flexible(
                child: Text(sbFill('sb_subj_path_count', {'done': sbDigits(w.done), 'total': sbDigits(w.total)}),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.label(context).copyWith(color: c.kit.warmTone.ink, fontWeight: FontWeight.w600)),
              ),
            ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, r) in rows.indexed) ...[
            if (i > 0) const SizedBox(height: AppSpace.sm),
            AppFlipIn(index: i, group: 'subject_lessons', child: r),
          ],
        ],
      ),
    );
  }
}

/// "٥ دروس خلّصتها · اعرضها": the finished start in one dashed mint row.
class _FoldRow extends StatelessWidget {
  const _FoldRow({required this.count, required this.open, required this.onTap});

  final int count;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ok = context.colors.kit.ok;
    return Semantics(
      button: true,
      expanded: open,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.tile),
        child: Container(
          constraints: const BoxConstraints(minHeight: AppTouch.primary),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
          decoration: BoxDecoration(
            color: ok.tint.withValues(alpha: .5),
            borderRadius: BorderRadius.circular(AppRadius.tile),
            border: Border.all(color: ok.color.withValues(alpha: .5), width: AppBorder.strong),
          ),
          child: Row(children: [
            Container(
              width: AppDashSize.ringSm,
              height: AppDashSize.ringSm,
              decoration: BoxDecoration(color: ok.color, shape: BoxShape.circle),
              child: Icon(Icons.check_rounded, color: context.colors.onHero, size: AppIconSize.md),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Text(
                sbFill('sb_lessons_folded', {'n': sbLessons(count)}),
                style: AppType.tileTitle(context).copyWith(color: ok.ink),
              ),
            ),
            Flexible(
              child: Text((open ? 'sb_lessons_hide' : 'sb_lessons_show').tr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.label(context).copyWith(color: ok.ink, fontWeight: FontWeight.w600)),
            ),
            Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: ok.ink),
          ]),
        ),
      ),
    );
  }
}

/// A card head's count (ring + "1 من 24 درس"): at most 45 % of the card, so a long count never pushes the title out.
class _CountAction extends StatelessWidget {
  const _CountAction({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .45),
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      );
}
