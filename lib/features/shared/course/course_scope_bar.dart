// lib/features/shared/course/course_scope_bar.dart
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
library;

import 'package:flutter/material.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../core/display/app_fonts.dart';
import '../../../utils/widget/app_network_image.dart';
import 'course_scope.dart';

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
          style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w600, fontSize: size * 0.42,
              color: courseScopeInk(context, tone), height: 1),
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
        border: Border.all(color: tone.withValues(alpha: 0.35), width: 1.2),
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
        padding: const EdgeInsetsDirectional.fromSTEB(3, 3, 9, 3),
        decoration: BoxDecoration(
          color: c.cardBg.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: courseScopeColor(context, org).withValues(alpha: 0.45)),
          boxShadow: [BoxShadow(color: c.heroShade.withValues(alpha: 0.12), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          CourseScopeMark(scope: scope, org: org, size: 18),
          const SizedBox(width: 5),
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: AppFonts.family, fontSize: 11, fontWeight: FontWeight.w600, color: c.textDark)),
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
    final tone = courseScopeColor(context, org);
    final title = scope.isOrg ? (org?.name ?? 'course_scope_org'.tr) : 'course_scope_personal_title'.tr;
    final sub = scope.isOrg ? 'course_scope_org_sub'.tr : 'course_scope_personal_sub'.tr;
    final hint = elsewhere <= 0
        ? null
        : (scope.isOrg ? 'course_scope_elsewhere_personal' : 'course_scope_elsewhere_orgs').tr.replaceAll('{n}', '$elsewhere');
    final show = hint == null ? null : onShowElsewhere;
    final action = show ?? onSwitch;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [
            Color.alphaBlend(tone.withValues(alpha: 0.10), c.cardBg),
            c.cardBg,
          ],
        ),
        border: Border.all(color: tone.withValues(alpha: 0.22)),
        boxShadow: [BoxShadow(color: c.heroShade.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          CourseScopeMark(scope: scope, org: org, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: AppFonts.family, fontSize: 15, fontWeight: FontWeight.w600, color: c.textDark)),
              const SizedBox(height: 2),
              Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: AppFonts.family, fontSize: 12, color: c.textMedium, height: 1.3)),
            ]),
          ),
          if (count != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: tone.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: Text('$count',
                  style: TextStyle(fontFamily: AppFonts.family, fontSize: 14, fontWeight: FontWeight.w600, color: c.textDark)),
            ),
          ],
        ]),
        if (hint != null || action != null) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (hint != null)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.layers_rounded, size: 14, color: c.textLight),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(hint, style: TextStyle(fontFamily: AppFonts.family, fontSize: 12, color: c.textMedium)),
                  ),
                ]),
              if (action != null)
                TextButton.icon(
                  key: ValueKey(show != null ? 'course_scope.show_elsewhere' : 'course_scope.switch'),
                  onPressed: action,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    foregroundColor: courseScopeInk(context, c.primary),
                  ),
                  icon: Icon(show != null ? Icons.menu_book_rounded : Icons.swap_horiz_rounded, size: 18),
                  label: Text((show != null ? 'course_scope_show_elsewhere' : 'course_scope_switch').tr,
                      style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w600, fontSize: 13)),
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
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
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
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => onSelect(chip.scope),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            constraints: const BoxConstraints(maxWidth: 220, minHeight: 48),
            padding: const EdgeInsetsDirectional.fromSTEB(6, 6, 12, 6),
            decoration: BoxDecoration(
              color: selected ? Color.alphaBlend(tone.withValues(alpha: 0.14), c.cardBg) : c.cardBg,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: selected ? tone : c.divider, width: selected ? 1.6 : 1),
              boxShadow: selected
                  ? [BoxShadow(color: tone.withValues(alpha: 0.18), blurRadius: 10, offset: const Offset(0, 3))]
                  : const [],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              CourseScopeMark(scope: chip.scope, org: chip.org, size: 30),
              const SizedBox(width: 8),
              Flexible(
                child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppFonts.family,
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected ? c.textDark : c.textMedium,
                    )),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: selected ? tone.withValues(alpha: 0.18) : c.inputBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('${chip.count}',
                    style: TextStyle(fontFamily: AppFonts.family, fontSize: 11, fontWeight: FontWeight.w600, color: c.textDark)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
