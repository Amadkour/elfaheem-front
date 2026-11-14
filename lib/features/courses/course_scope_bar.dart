// lib/features/courses/course_scope_bar.dart
//
// The look of a course list's side (course_scope.dart), plain values only so test/ui/course_scope_layout_test.dart
// can pump every part without a provider:
//
//   CourseScopeMark    the side's round mark: the organization's logo (else its initial on its brand tint),
//                      a person for Personal, a grid for All
//   CourseOrgBadge     a slim pill over a course card naming where the course lives (lists that mix sides)
//   CourseScopeBanner  the teacher's header: the side the list follows (the mode), its count, how many courses
//                      wait on the other sides and "Switch" (the context switcher)
//   CourseScopeChipBar the student's switcher: All · Personal · each organization, with counts
//
// Warm Editorial: the organization's colour lives in its MARK only (the round logo / initial); the banner, the
// badge and the chips are paper on a warm hairline, the chosen chip the ink outline with the mark's tint behind
// its count. No washes, no resting shadows.
library;

import 'package:flutter/material.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart'
    show AppSpace, AppRadius, AppType, AppIconSize, AppBorder, AppTouch, AppMotion, AppButton, AppButtonSize;
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppEase;
import 'package:flutter_education_app/utils/widget/app_network_image.dart';
import 'package:flutter_education_app/features/courses/course_scope.dart';

/// The side's colour: the organization's brand colour when it has one, else the theme's primary.
Color courseScopeColor(BuildContext context, CourseOrg? org) {
  final argb = org?.argb;
  return argb != null ? Color(argb) : context.colors.primary;
}

/// Ink in the side's colour that stays readable: on a dark surface it is lifted toward the theme's text colour
/// (a deep brand colour such as maroon or navy disappears on a dark card).
Color courseScopeInk(BuildContext context, Color tone) {
  final c = context.colors;
  return c.isDark ? Color.lerp(tone, c.textDark, 0.55)! : tone;
}

/// What a side is called on a chip / badge.
String courseScopeLabel(CourseScope scope, CourseOrg? org) => switch (scope.kind) {
      CourseScopeKind.all => 'course_scope_all'.tr,
      CourseScopeKind.personal => 'course_scope_personal'.tr,
      CourseScopeKind.org => org?.name ?? 'course_scope_org'.tr,
    };

class CourseScopeMark extends StatelessWidget {
  const CourseScopeMark({super.key, required this.scope, this.org, this.size = 40});

  final CourseScope scope;
  final CourseOrg? org;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = courseScopeColor(context, org);
    final logo = org?.logoUrl;
    Widget inner;
    if (scope.isOrg && logo != null) {
      inner = AppNetworkImage(url: logo, width: size, height: size, fit: BoxFit.cover,
          borderRadius: BorderRadius.circular(size / 2));
    } else if (scope.isOrg) {
      final name = org?.name ?? '';
      inner = Center(
        child: Text(
          name.isEmpty ? '#' : name.characters.first.toUpperCase(),
          style: AppType.label(context).copyWith(
            fontWeight: FontWeight.w600,
            fontSize: size * 0.42,
            color: courseScopeInk(context, tone),
            height: 1,
          ),
        ),
      );
    } else {
      inner = Icon(scope.isAll ? Icons.apps_rounded : Icons.person_rounded, size: size * 0.52,
          color: courseScopeInk(context, c.primary));
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Color.alphaBlend(tone.withValues(alpha: 0.14), c.cardBg),
        border: Border.all(color: tone.withValues(alpha: 0.35), width: AppBorder.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: inner,
    );
  }
}

class CourseOrgBadge extends StatelessWidget {
  const CourseOrgBadge({super.key, required this.org});

  /// null = a personal course.
  final CourseOrg? org;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final scope = org == null ? CourseScope.personal : CourseScope.org(org!.id);
    final label = courseScopeLabel(scope, org);
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 150),
        padding: const EdgeInsetsDirectional.fromSTEB(3, 3, AppSpace.xs + 1, 3),
        decoration: BoxDecoration(
          color: c.cardBg.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: c.divider, width: AppBorder.hairline),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          CourseScopeMark(scope: scope, org: org, size: 18),
          const SizedBox(width: AppSpace.xxs + 1),
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: AppType.overline(context).copyWith(letterSpacing: 0, color: c.textDark)),
          ),
        ]),
      ),
    );
  }
}

class CourseScopeBanner extends StatelessWidget {
  const CourseScopeBanner({
    super.key,
    required this.scope,
    this.org,
    this.count,
    this.elsewhere = 0,
    this.onSwitch,
    this.onShowElsewhere,
  });

  /// personal or org — the mode's side.
  final CourseScope scope;
  final CourseOrg? org;

  /// Courses on this side (null while unknown).
  final int? count;

  /// Courses on the other sides (personal ↔ organizations); 0 hides the hint.
  final int elsewhere;

  /// Opens the context switcher; null hides "Switch" (nothing to switch to).
  final VoidCallback? onSwitch;

  /// Opens the courses waiting on the other sides (the personal list → those courses in their organization).
  /// Given while [elsewhere] > 0, it replaces "Switch" with "Show them": the way to those courses, not to a home.
  final VoidCallback? onShowElsewhere;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final title = scope.isOrg ? (org?.name ?? 'course_scope_org'.tr) : 'course_scope_personal_title'.tr;
    final sub = scope.isOrg ? 'course_scope_org_sub'.tr : 'course_scope_personal_sub'.tr;
    final hint = elsewhere <= 0
        ? null
        : (scope.isOrg ? 'course_scope_elsewhere_personal' : 'course_scope_elsewhere_orgs').tr.replaceAll('{n}', '$elsewhere');
    final show = hint == null ? null : onShowElsewhere;
    final action = show ?? onSwitch;
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.sm),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.divider, width: AppBorder.hairline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          CourseScopeMark(scope: scope, org: org, size: 42),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
              const SizedBox(height: AppSpace.xxs / 2),
              Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(height: 1.35)),
            ]),
          ),
          if (count != null) ...[
            const SizedBox(width: AppSpace.xs),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm - 2, vertical: AppSpace.xxs),
              decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(AppRadius.pill)),
              child: Text('$count',
                  style: AppType.bodyStrong(context).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
            ),
          ],
        ]),
        if (hint != null || action != null) ...[
          const SizedBox(height: AppSpace.xs),
          Wrap(
            spacing: AppSpace.xs,
            runSpacing: AppSpace.xxs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (hint != null)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.layers_rounded, size: AppIconSize.xs, color: c.textLight),
                  const SizedBox(width: AppSpace.xxs),
                  Flexible(child: Text(hint, style: AppType.meta(context))),
                ]),
              if (action != null)
                AppButton.ghost(
                  key: ValueKey(show != null ? 'course_scope.show_elsewhere' : 'course_scope.switch'),
                  onPressed: action,
                  size: AppButtonSize.sm,
                  icon: show != null ? Icons.menu_book_rounded : Icons.swap_horiz_rounded,
                  label: (show != null ? 'course_scope_show_elsewhere' : 'course_scope_switch').tr,
                ),
            ],
          ),
        ],
      ]),
    );
  }
}

class CourseScopeChipBar extends StatelessWidget {
  const CourseScopeChipBar({super.key, required this.chips, required this.selected, required this.onSelect});

  final List<CourseScopeChip> chips;
  final CourseScope selected;
  final ValueChanged<CourseScope> onSelect;

  @override
  Widget build(BuildContext context) {
    if (chips.length < 2) return const SizedBox.shrink(); // one side only: nothing to tell apart
    return SizedBox(
      height: AppTouch.min,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpace.xs),
        itemBuilder: (context, i) => _ScopeChip(chip: chips[i], selected: chips[i].scope == selected, onSelect: onSelect),
      ),
    );
  }
}

class _ScopeChip extends StatelessWidget {
  const _ScopeChip({required this.chip, required this.selected, required this.onSelect});

  final CourseScopeChip chip;
  final bool selected;
  final ValueChanged<CourseScope> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = courseScopeColor(context, chip.org);
    final label = courseScopeLabel(chip.scope, chip.org);
    return Semantics(
      button: true,
      selected: selected,
      label: '$label, ${chip.count}',
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: () => onSelect(chip.scope),
          child: AnimatedContainer(
            duration: AppMotion.of(context).fast,
            curve: AppEase.out,
            constraints: const BoxConstraints(maxWidth: 220, minHeight: AppTouch.min),
            padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.xs - 2, AppSpace.xs - 2, AppSpace.sm, AppSpace.xs - 2),
            decoration: BoxDecoration(
              color: c.cardBg,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              // the chosen side: an ink outline (the brief's selection without a colour wash)
              border: Border.all(
                color: selected ? c.textDark : c.divider,
                width: selected ? AppBorder.strong : AppBorder.hairline,
              ),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              CourseScopeMark(scope: chip.scope, org: chip.org, size: 30),
              const SizedBox(width: AppSpace.xs),
              Flexible(
                child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: AppType.label(context).copyWith(
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected ? c.textDark : c.textMedium,
                    )),
              ),
              const SizedBox(width: AppSpace.xs - 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs - 1, vertical: AppSpace.xxs / 2),
                decoration: BoxDecoration(
                  color: selected ? Color.alphaBlend(tone.withValues(alpha: 0.16), c.cardBg) : c.inputBg,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text('${chip.count}',
                    style: AppType.overline(context).copyWith(
                      letterSpacing: 0,
                      color: c.textDark,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    )),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
