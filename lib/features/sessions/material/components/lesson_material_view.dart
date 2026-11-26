// lib/features/sessions/material/components/lesson_material_view.dart
//
// The student's lesson content (Stu1Learn material, exam=retry): plain values only, so the layout harness and the
// goldens pump it at every size.
//
//   LessonVideoCard      the lesson's video in the area's gradient: play disc (M8), "شرح الدرس", length and where
//                        the student stopped, a progress line and ONE white "كمّل المشاهدة" / "شغّل الدرس"
//   LessonMaterialTile   a file of the lesson: tinted icon box by kind, title, kind + size; a done check or a
//                        download ring at the top end
//   LessonQuizCard       the lesson quiz: its state (ready · try again · passed · waiting · closed · no tries left),
//                        one line, the forward button and what is left
//   LessonMaterialView   the paper card holding the video and a 2-column grid of files (M1 flip-in), then the quiz
library;

import 'package:flutter/material.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/kit_palette.dart' show AppAccent, KitTone;
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_digits.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_responsive.dart' show Breakpoints;
import 'package:flutter_education_app/design/app_motion_kit.dart';

/// What a file is, for its colour and icon.
enum LessonFileKind { pdf, doc, image, link, video, recorded, recording, cards }

/// "١٢:٣٠" (or "1:02:33").
String lessonClock(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return appDigits(h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s');
}

/// "٣٨ دقيقة"
String lessonMinutes(int n) => appDigits(countText(n,
    ar1: 'دقيقة', ar2: 'دقيقتين', arFew: '{n} دقايق', arMany: '{n} دقيقة', en1: '1 minute', en: '{n} minutes'));

// ─────────────────────────────────────────────────────────────────────────────
// Video
// ─────────────────────────────────────────────────────────────────────────────

class LessonVideoData {
  const LessonVideoData({this.minutes, this.stoppedAt, this.progress, this.onPlay, this.title});

  /// Null: "شرح الدرس".
  final String? title;
  final int? minutes;

  /// Where the student stopped last time (null: not started).
  final Duration? stoppedAt;

  /// 0..1 (null: none drawn).
  final double? progress;
  final VoidCallback? onPlay;
}

class LessonVideoCard extends StatelessWidget {
  const LessonVideoCard({super.key, required this.data});

  final LessonVideoData data;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final set = AppAreaScope.of(context);
    final started = data.stoppedAt != null && data.stoppedAt! > Duration.zero;
    final meta = [
      if (data.minutes != null && data.minutes! > 0) 'sb_learn_video_len'.tr.replaceAll('{len}', lessonMinutes(data.minutes!)),
      if (started) 'sb_learn_video_stopped'.tr.replaceAll('{at}', lessonClock(data.stoppedAt!)),
    ].join(AppConfig.lang == 'ar' ? '، ' : ', ');
    final wide = MediaQuery.sizeOf(context).width >= Breakpoints.mobile;
    final button = _WhitePill(
      label: started ? 'sb_learn_video_continue'.tr : 'sb_learn_video_play'.tr,
      ink: set.ink,
      onTap: data.onPlay,
    );
    final disc = AppBreathe(
      color: c.onHero,
      child: Container(
        width: AppDashSize.disc,
        height: AppDashSize.disc,
        decoration: BoxDecoration(shape: BoxShape.circle, color: c.cardBg),
        child: Icon(Icons.play_arrow_rounded, color: c.kit.live.color, size: AppIconSize.xl, textDirection: TextDirection.ltr),
      ),
    );
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(data.title ?? 'sb_learn_video_title'.tr,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.section(context).copyWith(color: c.onHero)),
        if (meta.isNotEmpty)
          Text(meta, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.onHeroMuted)),
        if (data.progress != null) ...[
          AppSpace.gapXs,
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: data.progress!.clamp(0.0, 1.0),
              minHeight: AppSpace.xxs + AppSpace.xxs / 2,
              color: c.onHero,
              backgroundColor: c.heroGlass,
            ),
          ),
        ],
      ],
    );
    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpace.md),
        decoration: BoxDecoration(
          gradient: set.button,
          borderRadius: BorderRadius.circular(AppRadius.block),
          boxShadow: AppShadow.button(context, set.btnB),
        ),
        child: wide
            ? Row(children: [
                disc,
                AppSpace.gapMd,
                Expanded(child: text),
                AppSpace.gapMd,
                button,
              ])
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [disc, AppSpace.gapMd, Expanded(child: text)]),
                AppSpace.gapMd,
                button,
              ]),
      ),
    );
  }
}

class _WhitePill extends StatelessWidget {
  const _WhitePill({required this.label, required this.ink, this.onTap});

  final String label;
  final Color ink;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppJelly(
      child: Semantics(
        button: true,
        child: Material(
          color: c.cardBg,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.primary),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
                child: Center(
                  widthFactor: 1,
                  child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.colors.button.copyWith(color: ink)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Files
// ─────────────────────────────────────────────────────────────────────────────

class LessonFileData {
  const LessonFileData({
    required this.kind,
    required this.title,
    this.meta,
    this.done = false,
    this.downloading,
    this.onTap,
    this.trailing,
    this.footer,
  });

  final LessonFileKind kind;
  final String title;
  final String? meta;
  final bool done;

  /// 0..1 while the file comes to the device.
  final double? downloading;
  final VoidCallback? onTap;

  /// A small action at the top end in place of the check (the offline mark of a video).
  final Widget? trailing;

  /// Under the text (the stars once someone rated, "rate it").
  final Widget? footer;
}

KitTone lessonFileTone(BuildContext context, LessonFileKind k) {
  final kit = context.colors.kit;
  return switch (k) {
    LessonFileKind.pdf => kit.error,
    LessonFileKind.doc => kit.accent(AppAccent.sun),
    LessonFileKind.image => kit.accent(AppAccent.mint),
    LessonFileKind.link => kit.accent(AppAccent.grape),
    LessonFileKind.video || LessonFileKind.recorded => kit.accent(AppAccent.sky),
    LessonFileKind.recording => kit.live,
    LessonFileKind.cards => kit.accent(AppAccent.pink),
  };
}

IconData lessonFileIcon(LessonFileKind k) => switch (k) {
      LessonFileKind.pdf => Icons.description_outlined,
      LessonFileKind.doc => Icons.article_outlined,
      LessonFileKind.image => Icons.image_outlined,
      LessonFileKind.link => Icons.link_rounded,
      LessonFileKind.video => Icons.smart_display_outlined,
      LessonFileKind.recorded => Icons.videocam_outlined,
      LessonFileKind.recording => Icons.fiber_manual_record_rounded,
      LessonFileKind.cards => Icons.style_outlined,
    };

class LessonMaterialTile extends StatelessWidget {
  const LessonMaterialTile({super.key, required this.data});

  final LessonFileData data;

  static const double minHeight = AppDashSize.courseTile / 2 + AppSpace.lg;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final kit = c.kit;
    final tone = lessonFileTone(context, data.kind);
    final mark = data.downloading != null
        ? SizedBox.square(
            dimension: AppIconSize.lg,
            child: CircularProgressIndicator(
              value: data.downloading!.clamp(0.0, 1.0),
              strokeWidth: AppSpace.xxs,
              color: kit.hotB,
              backgroundColor: kit.track,
            ),
          )
        : data.trailing ??
            (data.done
                ? Container(
                    width: AppIconSize.lg,
                    height: AppIconSize.lg,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: kit.ok.color),
                    child: Icon(Icons.check_rounded, size: AppIconSize.sm, color: c.onHero, semanticLabel: 'completed'.tr),
                  )
                : null);
    final tile = Material(
      color: kit.well,
      borderRadius: BorderRadius.circular(AppRadius.tile),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: data.onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: minHeight),
          padding: const EdgeInsets.all(AppSpace.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.tile),
            border: Border.all(color: kit.line, width: AppBorder.strong),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppIconBox(icon: lessonFileIcon(data.kind), tone: tone, size: AppTouch.min),
                  const Spacer(),
                  ?mark,
                ],
              ),
              AppSpace.gapSm,
              Text(data.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.tileTitle(context)),
              if (data.meta != null && data.meta!.isNotEmpty) ...[
                const SizedBox(height: AppSpace.xxs),
                Text(data.meta!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
              ],
              ?data.footer,
            ],
          ),
        ),
      ),
    );
    return Semantics(button: data.onTap != null, child: AppJelly(wide: true, child: tile));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quiz
// ─────────────────────────────────────────────────────────────────────────────

enum LessonQuizState { start, retry, passed, waiting, closed, none }

class LessonQuizData {
  const LessonQuizData({
    required this.state,
    this.questions = 0,
    this.minutes,
    this.score,
    this.left,
    this.onOpen,
  });

  final LessonQuizState state;
  final int questions;
  final int? minutes;

  /// The best score, 0..100.
  final double? score;

  /// Tries left (null: unlimited / not known).
  final int? left;

  /// The button (start, try again, see answers …); null leaves it out.
  final VoidCallback? onOpen;
}

String _tries(int n) => appDigits(countText(n,
    ar1: 'محاولة وحدة', ar2: 'محاولتين', arFew: '{n} محاولات', arMany: '{n} محاولة', en1: '1 try', en: '{n} tries'));

String _questions(int n) => appDigits(countText(n,
    ar1: 'سؤال واحد', ar2: 'سؤالين', arFew: '{n} أسئلة', arMany: '{n} سؤال', en1: '1 question', en: '{n} questions'));

class LessonQuizCard extends StatelessWidget {
  const LessonQuizCard({super.key, required this.data});

  final LessonQuizData data;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final kit = c.kit;
    final score = data.score == null ? '' : appDigits('${data.score!.round()}%');
    final (KitTone tone, IconData icon, String tag, String line, String? cta, bool hot, String? left) = switch (data.state) {
      LessonQuizState.start => (
          kit.accent(AppAccent.grape),
          Icons.assignment_turned_in_outlined,
          'sb_learn_quiz_ready'.tr,
          [
            if (data.questions > 0) _questions(data.questions),
            if (data.minutes != null && data.minutes! > 0) lessonMinutes(data.minutes!),
          ].join(AppConfig.lang == 'ar' ? '، ' : ', '),
          'sb_learn_quiz_start'.tr,
          true,
          data.left == null ? null : 'sb_learn_quiz_left'.tr.replaceAll('{n}', _tries(data.left!)),
        ),
      LessonQuizState.retry => (
          kit.warmTone,
          Icons.replay_rounded,
          'sb_learn_quiz_failed'.tr,
          'sb_learn_quiz_close'.tr.replaceAll('{score}', score),
          'sb_learn_quiz_retry'.tr,
          true,
          data.left == null ? null : 'sb_learn_quiz_left'.tr.replaceAll('{n}', _tries(data.left!)),
        ),
      LessonQuizState.passed => (
          kit.ok,
          Icons.check_rounded,
          'sb_learn_quiz_passed'.tr,
          'sb_learn_quiz_passed_line'.tr.replaceAll('{score}', score),
          'sb_learn_quiz_answers'.tr,
          false,
          'sb_learn_quiz_next_open'.tr,
        ),
      LessonQuizState.waiting => (
          kit.warn,
          Icons.schedule_rounded,
          'sb_learn_quiz_waiting'.tr,
          'sb_learn_quiz_waiting_line'.tr,
          null,
          false,
          'sb_learn_quiz_waiting_left'.tr,
        ),
      LessonQuizState.closed => (
          kit.primaryTone,
          Icons.event_busy_rounded,
          'sb_learn_quiz_closed'.tr,
          'sb_learn_quiz_closed_line'.tr,
          null,
          false,
          null,
        ),
      LessonQuizState.none => (
          kit.live,
          Icons.block_rounded,
          'sb_learn_quiz_none'.tr,
          score.isEmpty ? '' : 'sb_learn_quiz_score'.tr.replaceAll('{score}', score),
          null,
          false,
          null,
        ),
    };
    final button = cta == null || data.onOpen == null
        ? null
        : hot
            ? AppButton.hot(label: cta, onPressed: data.onOpen)
            : AppButton.secondary(label: cta, onPressed: data.onOpen);
    final wide = MediaQuery.sizeOf(context).width >= Breakpoints.mobile;
    final head = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: AppTouch.primary,
          height: AppTouch.primary,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.tile),
            gradient: LinearGradient(colors: [Color.lerp(tone.color, c.cardBg, 0.2)!, tone.color]),
          ),
          child: Icon(icon, color: c.onHero, size: AppIconSize.lg),
        ),
        AppSpace.gapMd,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AppSpace.xs,
                runSpacing: AppSpace.xxs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('sb_learn_quiz_title'.tr, style: AppType.section(context)),
                  _Tag(label: tag, tone: tone),
                ],
              ),
              if (line.isNotEmpty) ...[
                const SizedBox(height: AppSpace.xxs),
                Text(line, style: AppType.body(context).copyWith(color: c.textMedium)),
              ],
            ],
          ),
        ),
      ],
    );
    final act = Column(
      crossAxisAlignment: wide ? CrossAxisAlignment.center : CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ?button,
        if (left != null) ...[
          const SizedBox(height: AppSpace.xxs),
          Text(left, textAlign: TextAlign.center, style: AppType.meta(context)),
        ],
      ],
    );
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.cardWide),
        gradient: LinearGradient(
          begin: AlignmentDirectional.centerStart,
          end: AlignmentDirectional.centerEnd,
          colors: [c.cardBg, tone.tint],
        ),
        border: Border.all(color: Color.lerp(tone.tint, tone.color, 0.45)!, width: AppBorder.strong),
      ),
      child: wide
          ? Row(children: [Expanded(child: head), if (button != null || left != null) ...[AppSpace.gapMd, act]])
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              head,
              if (button != null || left != null) ...[AppSpace.gapMd, act],
            ]),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.tone});

  final String label;
  final KitTone tone;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs / 2),
        decoration: BoxDecoration(color: tone.tint, borderRadius: BorderRadius.circular(AppRadius.pill)),
        child: Text(label, style: AppType.overline(context).copyWith(color: tone.ink)),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// The whole content
// ─────────────────────────────────────────────────────────────────────────────

class LessonMaterialView extends StatelessWidget {
  const LessonMaterialView({super.key, this.video, this.files = const [], this.quiz, this.empty, this.footer});

  final LessonVideoData? video;
  final List<LessonFileData> files;
  final LessonQuizData? quiz;

  /// Shown in the card when there is no video and no file.
  final Widget? empty;

  /// Under the files, inside the card (the lesson's rating).
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (video != null) AppFlipIn(group: 'lesson.material', child: LessonVideoCard(data: video!)),
              if (video != null && files.isNotEmpty) AppSpace.gapMd,
              if (files.isNotEmpty)
                LayoutBuilder(builder: (context, box) {
                  final cols = box.maxWidth >= Breakpoints.desktop * 0.6 ? 3 : 2;
                  final rows = <Widget>[];
                  for (var i = 0; i < files.length; i += cols) {
                    rows.add(IntrinsicHeight(
                      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        for (var j = 0; j < cols; j++) ...[
                          if (j > 0) AppSpace.gapSm,
                          Expanded(
                            child: i + j < files.length
                                ? AppFlipIn(
                                    index: i + j + 1,
                                    group: 'lesson.material',
                                    child: LessonMaterialTile(data: files[i + j]),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ]),
                    ));
                  }
                  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    for (final (k, r) in rows.indexed) ...[if (k > 0) AppSpace.gapSm, r],
                  ]);
                }),
              if (video == null && files.isEmpty) ?empty,
              if (footer != null) ...[AppSpace.gapSm, footer!],
            ],
          ),
        ),
        if (quiz != null) ...[
          AppSpace.gapMd,
          AppFlipIn(index: files.length + 2, group: 'lesson.material', child: LessonQuizCard(data: quiz!)),
        ],
      ],
    );
  }
}
