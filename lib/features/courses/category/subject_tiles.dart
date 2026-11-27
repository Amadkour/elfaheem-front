// lib/features/courses/category/subject_tiles.dart — the redesign's subject tiles (Stu1Discover?screen=explore).
//
//   SubjectTile(name:, onTap:)          one subject: its colour (the same on every screen), a glass glyph box, the
//                                       name and an optional count; a large faint glyph on the bottom-start corner
//   SubjectsCard(categories:, onOpen:)  "Subjects" in one card: a grid of tiles (2 on a phone, 4 wide) and
//                                       "All subjects" at the head
//
// Plain values only. The subject's colour comes from the server name through courseSubjectKeyOf.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppDeal, AppJelly;
import 'package:flutter_education_app/features/courses/category/categories_provider.dart' show CategoryModel;
import 'package:flutter_education_app/features/courses/course_list_card.dart' show courseSubjectIcon, courseSubjectKeyOf;

class SubjectTile extends StatelessWidget {
  const SubjectTile({super.key, required this.name, this.count, this.onTap, this.index = 0});

  final String name;

  /// "24 courses" when the server sends a count.
  final String? count;
  final VoidCallback? onTap;

  /// The tile's place in its grid (the deal's stagger).
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final key = courseSubjectKeyOf(name);
    final s = c.kit.subject(key);
    final icon = courseSubjectIcon(key);
    final radius = BorderRadius.circular(AppRadius.cardFor(MediaQuery.sizeOf(context).width));
    return AppDeal(
      index: index,
      group: 'subjects',
      child: Semantics(
        button: onTap != null,
        label: count == null ? name : '$name, $count',
        excludeSemantics: true,
        child: AppJelly(
          wide: true,
          child: Material(
            color: s.tone.color,
            shape: RoundedRectangleBorder(borderRadius: radius),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Ink(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: AlignmentDirectional.topEnd,
                    end: AlignmentDirectional.bottomStart,
                    colors: [Color.lerp(s.tone.color, c.onHero, .18)!, s.tone.color],
                  ),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: AppDashSize.courseTile / 2 + AppSpace.lg),
                  child: Stack(children: [
                    PositionedDirectional(
                      end: -AppSpace.md,
                      bottom: -AppSpace.lg,
                      child: Transform.rotate(
                        angle: -.2,
                        child: Icon(icon, size: AppDashSize.ring + AppSpace.lg, color: s.fg.withValues(alpha: .16)),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(AppSpace.md),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          width: AppDashSize.glyph,
                          height: AppDashSize.glyph,
                          decoration: BoxDecoration(
                            color: s.fg.withValues(alpha: .2),
                            borderRadius: BorderRadius.circular(AppRadius.glyph),
                          ),
                          child: Icon(icon, size: AppIconSize.md, color: s.fg),
                        ),
                        const SizedBox(height: AppSpace.sm),
                        Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.tileTitle(context).copyWith(color: s.fg)),
                        if (count != null) ...[
                          const SizedBox(height: AppSpace.xxs),
                          Text(count!, style: AppType.meta(context).copyWith(color: s.fg.withValues(alpha: .85))),
                        ],
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Subjects": up to [max] subject tiles in a grid, "All subjects" at the head.
class SubjectsCard extends StatelessWidget {
  const SubjectsCard({super.key, required this.categories, required this.onOpen, this.onAll, this.max = 8});

  final List<CategoryModel> categories;
  final ValueChanged<CategoryModel> onOpen;
  final VoidCallback? onAll;
  final int max;

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) return const SizedBox.shrink();
    final ar = AppConfig.lang == 'ar';
    final shown = categories.take(max).toList();
    final ink = AppAreaScope.of(context).ink;
    final link = onAll == null
        ? null
        : TextButton(
            onPressed: onAll,
            style: TextButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min), foregroundColor: ink),
            child: Text('sa_explore_all_subjects'.tr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: ink)),
          );
    return AppCard(
      child: LayoutBuilder(builder: (context, box) {
        final cols = box.maxWidth >= 900 ? 4 : (box.maxWidth >= 560 ? 3 : 2);
        final w = (box.maxWidth - AppSpace.sm * (cols - 1)) / cols;
        final grid = Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
          for (var i = 0; i < shown.length; i++)
            SizedBox(
              width: w,
              child: SubjectTile(
                index: i,
                name: ar ? (shown[i].nameAr.isNotEmpty ? shown[i].nameAr : shown[i].nameEn) : (shown[i].nameEn.isNotEmpty ? shown[i].nameEn : shown[i].nameAr),
                onTap: () => onOpen(shown[i]),
              ),
            ),
        ]);
        // the head: "Subjects" and "All subjects" (the link gives way first on a narrow card)
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(child: Text('sa_explore_subjects'.tr, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.section(context))),
            if (link != null) ...[const SizedBox(width: AppSpace.xs), Flexible(child: link)],
          ]),
          const SizedBox(height: AppSpace.sm),
          grid,
        ]);
      }),
    );
  }
}
