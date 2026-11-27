// lib/features/home/student/home_continue.dart — the student home's two editorial blocks (D-613, the Warm Editorial
// theme), drawn from the same /me/home payload as the rest of the page (no call of their own):
//
//   StudentContinueBlock   "Continue learning": the ONE course to pick up now (homeContinueCourse: the first of
//                          homeCourseFocus that is not finished) on the emerald block — the primary subject of a
//                          learner's home. Cover · course name in the editorial headline · its next lecture · the
//                          progress as a filling bar and a rolling figure (AppFill + AppOdometer) · ONE Continue
//                          button. It leans under the pointer (AppTilt.subtle) and presses in on touch. The course
//                          list under it leaves this course out (StudentCourseSummary.featuredId).
//   StudentFreeDayBlock    a day with nothing on it: the sky (schedule) block — "No classes today" · what comes next
//                          and when · Full timetable — instead of a folded, empty "Today" section.
//
// Plain values in, callbacks out (layout-tested in test/ui/student_home_layout_test.dart).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/home/me_home.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';
import 'package:flutter_education_app/features/calendar/calendar_models.dart' show CalEvent;
import 'package:flutter_education_app/features/home/student/home_event_rows.dart';
import 'package:flutter_education_app/utils/widget/app_network_image.dart';

/// The home kit's side inset (its sections, header and cards sit 20 px from the page edge): the student's own blocks
/// line up with them.
const double kStudentHomeInset = AppSpace.md + AppSpace.xxs;

/// The course the "Continue learning" block offers: the first course of [homeCourseFocus] that is not finished, or
/// null (no course, or every course done). Pure.
MeCourseProgress? homeContinueCourse(List<MeCourseProgress> all, {List<CalEvent> events = const [], DateTime? nowUtc}) =>
    homeCourseFocus(all, events: events, nowUtc: nowUtc).where((x) => x.progress < 100).firstOrNull;

/// "Continue learning" — the course to pick up now, on the emerald block.
class StudentContinueBlock extends StatelessWidget {
  const StudentContinueBlock({super.key, required this.course, required this.line, this.onOpen});

  final MeCourseProgress course;

  /// Where the student is: the next lecture and when ([homeNextLectureLine]).
  final String line;

  /// The block and its button → the course.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final title = course.name(AppConfig.lang);
    final pct = course.progress.clamp(0, 100).round();
    return RepaintBoundary(
      child: AppTilt.subtle(
        radius: AppRadius.block,
        enabled: onOpen != null,
        // D-1100: the queue card is the home's ONE highlighted card; this block stays the emerald tint
        child: AppBlock(
          key: const ValueKey('student_home.continue'),
          tone: AppBlockTone.emerald,
          onTap: onOpen,
          semanticLabel: '${'home_s_continue'.tr}: $title. $line. $pct% ${'complete_label'.tr}',
          child: LayoutBuilder(builder: (context, box) {
            final wide = box.maxWidth >= 560;
            final head = _ContinueHead(course: course, title: title, line: line, cover: wide ? null : AppTouch.primary);
            final progress = _ContinueProgress(courseId: course.courseId, percent: pct);
            final button = AppButton.primary(
              key: const ValueKey('student_home.continue.button'),
              label: 'continue'.tr,
              icon: Icons.play_arrow_rounded,
              onPressed: onOpen,
            );
            if (wide) {
              // a desktop column: the course on the start side, where it stands and the button on the end side
              return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                AppTiltLayer(child: _Cover(url: course.imageUrl, size: AppTouch.min * 2)),
                AppSpace.gapLg,
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [head, AppSpace.gapLg, progress.bar])),
                AppSpace.gapXl,
                Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [progress.figure, AppSpace.gapSm, button]),
              ]);
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              head,
              AppSpace.gapLg,
              progress.bar,
              AppSpace.gapSm,
              // the figure and the button share a line while they fit, else the button takes its own
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [progress.figure, button],
              ),
            ]);
          }),
        ),
      ),
    );
  }
}

/// Cover · "Continue learning" · the course name (editorial headline) · the next lecture line.
class _ContinueHead extends StatelessWidget {
  const _ContinueHead({required this.course, required this.title, required this.line, required this.cover});

  final MeCourseProgress course;
  final String title, line;
  /// The cover's size at the end of the head (a phone); null = no cover here (the wide row draws it first).
  final double? cover;

  @override
  Widget build(BuildContext context) {
    final ink = AppBlock.colorsOf(context);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('home_s_continue'.tr, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: ink.muted)),
          const SizedBox(height: AppSpace.xxs),
          Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.headline(context).copyWith(color: ink.ink)),
          const SizedBox(height: AppSpace.xs),
          Text(line, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.body(context).copyWith(color: ink.muted)),
        ]),
      ),
      if (cover != null) ...[
        AppSpace.gapMd,
        // the cover sits a little deeper than the block when it leans (AppTiltLayer)
        AppTiltLayer(child: _Cover(url: course.imageUrl, size: cover!)),
      ],
    ]);
  }
}

/// The course picture, or a drawn book on a paper plate when the course has none.
class _Cover extends StatelessWidget {
  const _Cover({required this.url, required this.size});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = AppBlock.colorsOf(context);
    final radius = BorderRadius.circular(AppRadius.control);
    final has = url != null && url!.isNotEmpty;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: c.cardBg, borderRadius: radius),
        clipBehavior: Clip.antiAlias,
        child: has
            ? AppNetworkImage(url: url!, width: size, height: size, fit: BoxFit.cover, borderRadius: BorderRadius.zero)
            : Icon(Icons.auto_stories_rounded, size: AppIconSize.lg, color: ink.accentInk(c.primary)),
      ),
    );
  }
}

/// The progress as a bar that fills and a figure whose digits roll (the block's key number).
class _ContinueProgress {
  const _ContinueProgress({required this.courseId, required this.percent});

  final int courseId, percent;

  Widget get bar => _ProgressBar(value: percent / 100);

  Widget get figure => Builder(builder: (context) {
        final ink = AppBlock.colorsOf(context);
        return Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          AppOdometer('$percent%', memoryKey: 'student_home.continue.$courseId', style: AppType.figureLarge(context).copyWith(color: ink.ink)),
          const SizedBox(width: AppSpace.xs),
          Flexible(
            child: Text('complete_label'.tr, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: ink.muted)),
          ),
        ]);
      });
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = AppBlock.colorsOf(context);
    final radius = BorderRadius.circular(AppRadius.pill);
    return ExcludeSemantics(
      child: SizedBox(
        height: AppSpace.xs,
        child: DecoratedBox(
          decoration: BoxDecoration(color: ink.ink.withValues(alpha: 0.1), borderRadius: radius),
          child: AppFill(
            value: value.clamp(0.0, 1.0),
            builder: (context, v) => Align(
              alignment: AlignmentDirectional.centerStart,
              child: FractionallySizedBox(
                widthFactor: v,
                heightFactor: 1,
                child: DecoratedBox(decoration: BoxDecoration(color: ink.accentInk(c.primary), borderRadius: radius)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A day with nothing on it: the sky (schedule) block with what comes next and the timetable.
class StudentFreeDayBlock extends StatelessWidget {
  const StudentFreeDayBlock({super.key, this.next, this.onOpenNext, this.onTimetable});

  /// The next class of the coming days (/me/home's first upcoming row), or null.
  final CalEvent? next;
  final VoidCallback? onOpenNext;
  final VoidCallback? onTimetable;

  @override
  Widget build(BuildContext context) {
    final e = next;
    // what comes next on one line, when on its own (a date never wraps away from its time)
    final line = e == null ? 'sv_home_s_free_hint'.tr : 'home_next_lecture'.tr.replaceAll('{n}', e.title);
    final when = e == null ? null : '${AppTime.date(e.start, pattern: 'EEE d MMM')} · ${AppTime.time(e.start)}';
    return AppBlock(
      key: const ValueKey('student_home.free_day'),
      tone: AppBlockTone.sage,
      onTap: e == null ? onTimetable : onOpenNext,
      child: Builder(builder: (context) {
        final ink = AppBlock.colorsOf(context);
        final c = context.colors;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: AppTouch.min,
              height: AppTouch.min,
              decoration: BoxDecoration(color: c.cardBg, borderRadius: BorderRadius.circular(AppRadius.control)),
              child: Icon(Icons.event_available_rounded, size: AppIconSize.lg, color: ink.accentInk(c.primary)),
            ),
            AppSpace.gapMd,
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('home_no_classes_today'.tr, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context).copyWith(color: ink.ink)),
                const SizedBox(height: AppSpace.xxs),
                Text(line, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.body(context).copyWith(color: ink.muted)),
                if (when != null)
                  Text(when, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: ink.ink, fontWeight: FontWeight.w600)),
              ]),
            ),
          ]),
          if (onTimetable != null) ...[
            AppSpace.gapMd,
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppButton.secondary(
                label: 'home_full_timetable'.tr,
                icon: Icons.calendar_month_rounded,
                size: AppButtonSize.sm,
                onPressed: onTimetable,
              ),
            ),
          ],
        ]);
      }),
    );
  }
}
