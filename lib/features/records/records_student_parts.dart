// lib/features/records/records_student_parts.dart — the student's look of Records (Stu1Learn records): plain values,
// no API, so test/ui/sb_learn_layout_test.dart pumps them with the layout harness.
//
//   RecordsStudentHero     the learn-area hero: "دوراتي" kicker, "تسجيلات حصصي", one line, the filter strip
//   RecordsStudentGroups   one card per group (its colour dot, title, "٣ تسجيلات"), rows of [RecordsStudentRow]
//   RecordsStudentRow      a coloured thumbnail (play mark, length badge), the title, the date, and ONE round action
//                          at the end (the item's options; the selection check while selecting)
//
// The groups are the library's groups (by meeting); each gets a steady accent from its id, so the same group has the
// same colour on every visit.
library;

import 'package:flutter/material.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/kit_palette.dart' show AppAccent, KitTone;
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_time.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_responsive.dart' show Breakpoints;
import 'package:flutter_education_app/design/app_motion_kit.dart';

import 'package:flutter_education_app/features/records/records_api.dart';

/// "٣ تسجيلات" (the student's count line).
String sbRecordsCount(int n) => countText(n,
    ar1: 'تسجيل واحد', ar2: 'تسجيلين', arFew: '{n} تسجيلات', arMany: '{n} تسجيل', en1: '1 recording', en: '{n} recordings');

/// A group's steady colour.
KitTone recordGroupTone(BuildContext context, int key) {
  final kit = context.colors.kit;
  const order = [AppAccent.sun, AppAccent.grape, AppAccent.mint, AppAccent.sky, AppAccent.pink, AppAccent.lime];
  return key == 0 ? kit.warmTone : kit.accent(order[key.abs() % order.length]);
}

/// The hero of the student's Records. [bottom] is the filter strip (AppTabs).
class RecordsStudentHero extends StatelessWidget {
  const RecordsStudentHero({super.key, this.bottom, this.overlap = true});

  final Widget? bottom;

  /// Room under the hero for the first card to ride up (AppHeroOverlap); false when the hero stands alone.
  final bool overlap;

  @override
  Widget build(BuildContext context) => AppHero(
        kicker: 'sb_learn_rec_kicker'.tr,
        title: 'sb_learn_rec_title'.tr,
        subtitle: 'sb_learn_rec_sub'.tr,
        icon: Icons.video_library_rounded,
        bottom: bottom,
        overlap: overlap,
        wipe: false,
      );
}

class RecordsStudentRow extends StatelessWidget {
  const RecordsStudentRow({
    super.key,
    required this.item,
    required this.tone,
    this.selecting = false,
    this.selected = false,
    this.highlighted = false,
    this.onTap,
    this.onLongPress,
    this.onMore,
    this.showImage = true,
  });

  final RecordItem item;
  final KitTone tone;
  final bool selecting;
  final bool selected;
  final bool highlighted;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onMore;
  final bool showImage;

  static const double thumbWidth = AppDashSize.courseTile / 2 + AppSpace.lg;
  static const double rowHeight = AppTouch.primary + AppSpace.xxl - AppSpace.xxs;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final kit = c.kit;
    final r = item;
    final when = r.meetingAt ?? r.finishedAt ?? r.createdAt;
    final date = when == null ? null : AppTime.date(when, pattern: 'EEEE d MMMM');
    final edge = selected || highlighted ? tone.color : kit.line;
    final body = Material(
      color: c.cardBg,
      borderRadius: BorderRadius.circular(AppRadius.tile),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('records.tile.${r.id}'),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          constraints: const BoxConstraints(minHeight: rowHeight),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.tile),
            border: Border.all(color: edge, width: selected || highlighted ? AppBorder.focus : AppBorder.strong),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _thumb(context),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.tileTitle(context)),
                        if (date != null) ...[
                          const SizedBox(height: AppSpace.xxs),
                          Text(date, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                        ],
                        if (r.inProgress || r.isFailed) ...[
                          const SizedBox(height: AppSpace.xxs),
                          Text(
                            recordStatusLabel(r),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.meta(context).copyWith(color: r.isFailed ? kit.error.ink : kit.warn.ink),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Center(child: _action(context)),
                const SizedBox(width: AppSpace.sm),
              ],
            ),
          ),
        ),
      ),
    );
    return AppJelly(wide: true, child: body);
  }

  Widget _thumb(BuildContext context) {
    final c = context.colors;
    final url = item.coverUrl;
    final fill = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topEnd,
          end: AlignmentDirectional.bottomStart,
          colors: [Color.lerp(tone.color, c.cardBg, 0.25)!, tone.color, Color.lerp(tone.color, c.kit.deep, 0.25)!],
        ),
      ),
    );
    return SizedBox(
      width: thumbWidth,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (showImage && url != null && url.startsWith('http'))
            Image.network(url, fit: BoxFit.cover, errorBuilder: (_, _, _) => fill)
          else
            fill,
          if (!selecting && item.canPlay)
            Center(
              child: Container(
                width: AppTouch.min,
                height: AppTouch.min,
                decoration: BoxDecoration(shape: BoxShape.circle, color: c.cardBg),
                child: Icon(Icons.play_arrow_rounded, color: c.kit.live.color, size: AppIconSize.lg),
              ),
            ),
          if (item.durationSeconds > 0)
            PositionedDirectional(
              end: AppSpace.xs,
              bottom: AppSpace.xs,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs),
                decoration: BoxDecoration(color: c.kit.deep, borderRadius: BorderRadius.circular(AppRadius.pill)),
                child: Text(
                  mmss(item.durationSeconds),
                  textDirection: TextDirection.ltr,
                  style: AppType.overline(context).copyWith(color: c.onHero, fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _action(BuildContext context) {
    final c = context.colors;
    if (selecting) {
      return SizedBox.square(
        dimension: AppTouch.min,
        child: Icon(
          selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
          color: selected ? tone.color : c.textLight,
          size: AppIconSize.lg,
          semanticLabel: selected ? 'sb_learn_rec_selected'.tr : 'sb_learn_rec_not_selected'.tr,
        ),
      );
    }
    if (onMore == null) return const SizedBox.shrink();
    return Tooltip(
      message: 'sb_learn_rec_options'.tr,
      child: Semantics(
        button: true,
        label: 'sb_learn_rec_options'.tr,
        child: InkResponse(
          key: ValueKey('records.more.${item.id}'),
          onTap: onMore,
          radius: AppTouch.min / 2,
          child: Container(
            width: AppTouch.min,
            height: AppTouch.min,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: item.isDone ? c.kit.ok.tint : c.cardBg,
              border: Border.all(color: item.isDone ? c.kit.ok.tint : c.kit.line, width: AppBorder.strong),
            ),
            child: Icon(Icons.more_horiz_rounded, color: item.isDone ? c.kit.ok.ink : c.kit.warmTone.ink, size: AppIconSize.md),
          ),
        ),
      ),
    );
  }
}

/// The student's library: one card per group, each with its rows (M1 flip-in on the cards).
class RecordsStudentGroups extends StatelessWidget {
  const RecordsStudentGroups({
    super.key,
    required this.groups,
    this.selected = const {},
    this.highlightId,
    this.onTap,
    this.onLongPress,
    this.onMore,
    this.showImages = true,
  });

  final List<RecordGroup> groups;
  final Set<int> selected;
  final int? highlightId;
  final ValueChanged<RecordItem>? onTap;
  final ValueChanged<RecordItem>? onLongPress;
  final ValueChanged<RecordItem>? onMore;
  final bool showImages;

  @override
  Widget build(BuildContext context) {
    final selecting = selected.isNotEmpty;
    return LayoutBuilder(builder: (context, box) {
      final two = box.maxWidth >= Breakpoints.desktop;
      Widget card(int i, RecordGroup g) {
        final tone = recordGroupTone(context, g.meetingId);
        Widget row(RecordItem r) => RecordsStudentRow(
              item: r,
              tone: tone,
              selecting: selecting,
              selected: selected.contains(r.id),
              highlighted: r.id == highlightId,
              showImage: showImages,
              onTap: onTap == null ? null : () => onTap!(r),
              onLongPress: onLongPress == null ? null : () => onLongPress!(r),
              onMore: onMore == null ? null : () => onMore!(r),
            );
        return AppFlipIn(
          index: i,
          group: 'records.student',
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: AppSpace.md,
                      height: AppSpace.md,
                      decoration: BoxDecoration(color: tone.color, borderRadius: BorderRadius.circular(AppRadius.chip)),
                    ),
                    const SizedBox(width: AppSpace.xs),
                    Expanded(
                      child: Text(g.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
                    ),
                    const SizedBox(width: AppSpace.xs),
                    Text(sbRecordsCount(g.items.length), style: AppType.meta(context)),
                  ],
                ),
                AppSpace.gapMd,
                for (final (k, r) in g.items.indexed) ...[
                  if (k > 0) AppSpace.gapSm,
                  row(r),
                ],
              ],
            ),
          ),
        );
      }

      final cards = [for (final (i, g) in groups.indexed) card(i, g)];
      if (!two) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final (i, w) in cards.indexed) ...[if (i > 0) AppSpace.gapMd, w],
        ]);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var k = 0; k < cards.length; k += 2) ...[
          if (k > 0) AppSpace.gapMd,
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: cards[k]),
            AppSpace.gapMd,
            Expanded(child: k + 1 < cards.length ? cards[k + 1] : const SizedBox.shrink()),
          ]),
        ],
      ]);
    });
  }
}

/// The strip's labels: "الكل", then the first groups, then "Shared with me" when sharing is on.
List<AppTabItem> recordsStudentTabs(List<RecordGroup> groups, {required bool shared, int maxGroups = 2}) => [
      AppTabItem('sb_learn_rec_all'.tr),
      for (final g in groups.take(maxGroups)) AppTabItem(g.title),
      if (shared) AppTabItem('sb_learn_rec_shared'.tr),
    ];
