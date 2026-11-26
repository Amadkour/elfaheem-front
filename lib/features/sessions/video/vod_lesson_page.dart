// lib/features/sessions/video/vod_lesson_page.dart
//
// The student's lesson player as a page (Stu1Learn player, mode=end, mode=audio): plain values only, so the layout
// harness and the goldens pump it without a video controller. VideoPlayerScreen draws it around its own player
// stack when a student plays a lesson of an enrolled course and the player is not full screen.
//
//   VodLessonHeader    the deep bar: back, "٨. الدوال اللوغاريتمية", "الرياضيات، أ. ماجد الشهري", a pill at the end
//   VodLessonActions   "نزّله وشوفه بدون نت" and "ملخص الدرس" (each left out when it cannot be offered)
//   VodLessonList      "دروس المادة" with "٨ من ٢٤": a coloured thumbnail with its length / "مباشر" badge, the
//                      title, a state line (شاهدته ✓ · حصة مباشرة الحين · تشتغل الحين ٪ · يفتح بعد الاختبار 🔒)
//   VodLessonLayout    phone: header, player, actions, list · wide: header across, the player and the actions on the
//                      start side, the list on the end side
library;

import 'package:flutter/material.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_digits.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';

/// Where a lesson of the list stands.
enum VodLessonState { done, live, current, locked, open }

class VodLessonEntry {
  const VodLessonEntry({
    required this.number,
    required this.title,
    required this.state,
    this.caption,
    this.badge,
    this.onTap,
  });

  final int number;
  final String title;
  final VodLessonState state;

  /// The line under the title; null: from [state].
  final String? caption;

  /// On the thumbnail: the length ("٣٨:١٠"), "مباشر", "٢٠ سؤال".
  final String? badge;
  final VoidCallback? onTap;
}

class VodLessonHeader extends StatelessWidget {
  const VodLessonHeader({super.key, required this.title, this.subtitle, this.onBack, this.trailing});

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpace.md, MediaQuery.paddingOf(context).top + AppSpace.sm, AppSpace.md, AppSpace.sm),
      child: Row(
        children: [
          if (onBack != null) ...[AppBackButton(onPressed: onBack, onHero: true), AppSpace.gapSm],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  header: true,
                  child: Text(title,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.section(context).copyWith(color: c.onHero)),
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(subtitle!,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.onHeroMuted)),
              ],
            ),
          ),
          if (trailing != null) ...[AppSpace.gapSm, trailing!],
        ],
      ),
    );
  }
}

/// A glass pill on the deep page ("باقي لك ٧ مشاهدات هالشهر", the actions under the player).
class VodPagePill extends StatelessWidget {
  const VodPagePill({super.key, required this.label, this.icon, this.onTap, this.progress});

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;

  /// 0..1 drawn as a small ring in place of the icon (a download running).
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lead = progress != null
        ? SizedBox.square(
            dimension: AppIconSize.sm,
            child: CircularProgressIndicator(value: progress, strokeWidth: AppBorder.focus, color: c.onHero, backgroundColor: c.heroGlass),
          )
        : icon == null
            ? null
            : Icon(icon, size: AppIconSize.md, color: c.onHero);
    final pill = Material(
      color: c.heroGlass,
      shape: StadiumBorder(side: BorderSide(color: c.heroGlassBorder, width: AppBorder.strong)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTouch.min),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (lead != null) ...[lead, AppSpace.gapXs],
              Flexible(
                child: Text(label,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: c.onHero, fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
        ),
      ),
    );
    return onTap == null ? pill : AppJelly(child: Semantics(button: true, child: pill));
  }
}

class VodLessonActions extends StatelessWidget {
  const VodLessonActions({super.key, this.onDownload, this.downloaded = false, this.downloading, this.onSummary});

  /// Null: no download here (web, or the lesson cannot be kept).
  final VoidCallback? onDownload;
  final bool downloaded;
  final double? downloading;
  final VoidCallback? onSummary;

  @override
  Widget build(BuildContext context) {
    final items = [
      if (onDownload != null)
        VodPagePill(
          key: const ValueKey('vod.lesson.download'),
          icon: downloaded ? Icons.download_done_rounded : Icons.download_rounded,
          progress: downloading,
          label: downloaded ? 'sb_learn_player_downloaded'.tr : 'sb_learn_player_download'.tr,
          onTap: onDownload,
        ),
      if (onSummary != null)
        VodPagePill(
          key: const ValueKey('vod.lesson.summary'),
          icon: Icons.description_outlined,
          label: 'sb_learn_player_summary'.tr,
          onTap: onSummary,
        ),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: items);
  }
}

KitTone vodLessonTone(BuildContext context, VodLessonState s) {
  final kit = context.colors.kit;
  return switch (s) {
    VodLessonState.done => kit.ok,
    VodLessonState.live => kit.live,
    VodLessonState.current => AppAreaScope.of(context).tone,
    VodLessonState.locked || VodLessonState.open => kit.primaryTone,
  };
}

class VodLessonList extends StatelessWidget {
  const VodLessonList({super.key, required this.entries, this.position, this.total});

  final List<VodLessonEntry> entries;

  /// "٨ من ٢٤".
  final int? position;
  final int? total;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: c.heroGlass.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.cardWide),
        border: Border.all(color: c.heroGlassBorder, width: AppBorder.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: Text('sb_learn_player_lessons'.tr, style: AppType.section(context).copyWith(color: c.onHero)),
            ),
            if (position != null && total != null)
              Flexible(
                child: Text(
                  'sb_learn_player_of'.tr.replaceAll('{n}', appDigits('$position')).replaceAll('{total}', appDigits('$total')),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.meta(context).copyWith(color: c.onHeroMuted),
                ),
              ),
          ]),
          AppSpace.gapSm,
          for (final (i, e) in entries.indexed) ...[
            if (i > 0) const SizedBox(height: AppSpace.xxs),
            AppFlipIn(index: i, group: 'vod.lessons', child: _row(context, e)),
          ],
        ],
      ),
    );
  }

  Widget _row(BuildContext context, VodLessonEntry e) {
    final c = context.colors;
    final kit = c.kit;
    final tone = vodLessonTone(context, e.state);
    final current = e.state == VodLessonState.current;
    final locked = e.state == VodLessonState.locked;
    final caption = e.caption ??
        switch (e.state) {
          VodLessonState.done => 'sb_learn_player_watched'.tr,
          VodLessonState.live => 'sb_learn_player_live'.tr,
          VodLessonState.current => 'sb_learn_player_now'.tr,
          VodLessonState.locked => 'sb_learn_player_locked'.tr,
          VodLessonState.open => '',
        };
    final thumb = Container(
      width: AppTouch.primary * 2 + AppSpace.xxs * 3,
      height: AppTouch.primary + AppSpace.sm,
      padding: const EdgeInsets.all(AppSpace.xxs + AppSpace.xxs / 2),
      alignment: AlignmentDirectional.bottomEnd,
      decoration: BoxDecoration(
        color: locked ? c.heroGlass : tone.color,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: e.badge == null
          ? null
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs / 2),
              decoration: BoxDecoration(color: kit.deep.withValues(alpha: 0.72), borderRadius: BorderRadius.circular(AppRadius.pill)),
              child: Text(e.badge!,
                  textDirection: TextDirection.ltr,
                  style: AppType.overline(context).copyWith(color: c.onHero, fontFeatures: const [FontFeature.tabularFigures()])),
            ),
    );
    final row = Container(
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.tile),
        color: current ? Color.lerp(kit.deep, tone.color, 0.22) : null,
        border: current ? Border.all(color: tone.color.withValues(alpha: 0.7), width: AppBorder.strong) : null,
      ),
      child: Row(children: [
        thumb,
        AppSpace.gapMd,
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('${appDigits('${e.number}')}. ${e.title}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppType.tileTitle(context).copyWith(color: locked ? c.onHeroMuted : c.onHero)),
            if (caption.isNotEmpty)
              Text(caption, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.onHeroMuted)),
          ]),
        ),
        AppSpace.gapSm,
        SizedBox(
          width: AppIconSize.lg,
          child: e.state == VodLessonState.done
              ? Icon(Icons.check_rounded, color: kit.ok.color, size: AppIconSize.lg, semanticLabel: 'completed'.tr)
              : locked
                  ? Icon(Icons.lock_outline_rounded, color: c.onHeroMuted, size: AppIconSize.md)
                  : null,
        ),
      ]),
    );
    return Semantics(
      button: e.onTap != null,
      selected: current,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.tile),
          onTap: e.onTap,
          child: row,
        ),
      ),
    );
  }
}

class VodLessonLayout extends StatelessWidget {
  const VodLessonLayout({
    super.key,
    required this.header,
    required this.player,
    required this.actions,
    required this.list,
    required this.wide,
  });

  final Widget header;
  final Widget player;
  final Widget actions;
  final Widget list;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final g = AppSpace.gutter(MediaQuery.sizeOf(context).width);
    final body = wide
        ? SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(g, AppSpace.sm, g, AppSpace.xl),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  player,
                  AppSpace.gapMd,
                  Align(alignment: AlignmentDirectional.centerEnd, child: actions),
                ]),
              ),
              AppSpace.gapLg,
              SizedBox(width: AppDashSize.courseTile + AppSpace.xxxl * 2 + AppSpace.lg, child: list),
            ]),
          )
        : ListView(
            padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + AppSpace.xl),
            children: [
              player,
              Padding(
                padding: EdgeInsets.fromLTRB(g, AppSpace.md, g, AppSpace.md),
                child: Align(alignment: AlignmentDirectional.centerStart, child: actions),
              ),
              Padding(padding: EdgeInsets.symmetric(horizontal: g), child: list),
            ],
          );
    return AppAreaScope(
      area: AppArea.learn,
      child: ColoredBox(
        color: c.kit.deep,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [header, Expanded(child: body)]),
      ),
    );
  }
}
