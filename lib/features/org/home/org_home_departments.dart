// lib/features/org/home/org_home_departments.dart
//
// "Departments" on the organization home (D-103, spec §2) — plain values, so the layout harness pumps it:
//   OrgDepartmentsSection   the departments the dashboard lists for me (service departments, then academic ones) as
//                           simple cards — logo / icon, name, ONE meta line ("3 waiting for you", "4 on the team") —
//                           two per row when there is room; the first [max] + "See all (n)"; nothing at all → one
//                           friendly line (the section folds, HomeSection `empty:`)
//   OrgDeptCard             one card (tap → the department page with the tabs the server lists for me)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart' show appInk;
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppPressScale;
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/design/home_kit.dart' show HomeSection;

import '../../admin/admin_common.dart' show asInt, t;
import '../../admin/admin_list.dart' show IconBadge;
import '../org_departments_page.dart' show DeptLogo;
import '../org_ui.dart' show orgNameOf;
import 'org_home_logic.dart';

class OrgDepartmentsSection extends StatefulWidget {
  const OrgDepartmentsSection({super.key, required this.units, this.isAdmin = false, this.onOpen, this.onSeeAll, this.max = 6});

  /// `departments` then `programs` of the dashboard (each a map with unit_type, name, waiting, team / students, tabs).
  final List<Map<String, dynamic>> units;
  final bool isAdmin;
  final void Function(Map<String, dynamic> unit)? onOpen;

  /// The full departments page; null → "See all" unfolds the rest in place.
  final VoidCallback? onSeeAll;
  final int max;

  @override
  State<OrgDepartmentsSection> createState() => _OrgDepartmentsSectionState();
}

class _OrgDepartmentsSectionState extends State<OrgDepartmentsSection> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final n = w.units.length;
    final shown = _all ? w.units : w.units.take(w.max).toList();
    final more = n > w.max;
    return HomeSection(
      id: 'org.departments',
      title: w.isAdmin ? t('الإدارات والأقسام', 'Departments') : t('أقسامي', 'My departments'),
      count: n,
      empty: n == 0,
      emptySummary: w.isAdmin
          ? t('لا إدارات بعد — أنشئها من صفحة الإدارات', 'No departments yet — create them on the Departments page')
          : t('لست ضمن فريق أي قسم بعد', "You're not part of a department yet"),
      actionLabel: n == 0
          ? (w.isAdmin && w.onSeeAll != null ? t('الإدارات', 'Departments') : null)
          : more
              ? (w.onSeeAll != null ? t('عرض الكل ($n)', 'See all ($n)') : (_all ? t('عرض أقل', 'Show less') : t('عرض الكل ($n)', 'See all ($n)')))
              : null,
      onAction: n == 0 || more ? (w.onSeeAll ?? () => setState(() => _all = !_all)) : null,
      titlePadding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, 0, AppSpace.xs, AppSpace.xs),
      child: n == 0
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
              child: Text(
                  w.isAdmin
                      ? t('تظهر هنا الإدارات والأقسام العلمية بعد إنشائها.', 'Your departments show up here once they are created.')
                      : t('عندما يضيفك المسؤول إلى فريق قسم، سيظهر هنا.', 'When an admin adds you to a department team, it shows up here.'),
                  style: AppType.meta(context)),
            )
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
              child: LayoutBuilder(builder: (context, box) {
                final cols = box.maxWidth >= 520 ? 2 : 1;
                const gap = AppSpace.sm;
                final cw = (box.maxWidth - gap * (cols - 1)) / cols;
                return Wrap(spacing: gap, runSpacing: gap, children: [
                  for (final u in shown)
                    SizedBox(width: cw, child: OrgDeptCard(unit: u, onTap: w.onOpen == null ? null : () => w.onOpen!(u))),
                ]);
              }),
            ),
    );
  }
}

class OrgDeptCard extends StatelessWidget {
  const OrgDeptCard({super.key, required this.unit, this.onTap});
  final Map<String, dynamic> unit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final u = unit;
    final waiting = asInt(u['waiting']) > 0;
    final program = u['unit_type'] == 'program';
    // paper + a warm hairline (a resting card has no shadow); a press sinks it a little
    return Semantics(
      button: onTap != null,
      child: AppPressScale(
        enabled: onTap != null,
        child: Material(
        color: c.cardBg,
        shape: RoundedRectangleBorder(
            borderRadius: AppRadius.cardAll, side: BorderSide(color: c.divider, width: AppBorder.hairline)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: AppTouch.primary + AppSpace.md),
            padding: const EdgeInsets.all(AppSpace.sm),
            child: Row(children: [
              program
                  ? IconBadge(Icons.school_rounded, c.primary, size: AppIconSize.hero)
                  : DeptLogo(d: u, size: AppIconSize.hero),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(orgNameOf(u), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
                  const SizedBox(height: AppSpace.xxs / 2),
                  Row(children: [
                    if (waiting) ...[
                      Container(
                          width: AppSpace.xxs * 1.5,
                          height: AppSpace.xxs * 1.5,
                          decoration: BoxDecoration(color: c.warning, shape: BoxShape.circle)),
                      const SizedBox(width: AppSpace.xs * 0.75),
                    ],
                    Flexible(
                      child: Text(orgDeptMeta(u), maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: AppType.meta(context).copyWith(
                              color: waiting ? appInk(context, c.warning) : null, fontWeight: waiting ? FontWeight.w500 : null)),
                    ),
                  ]),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, color: c.textLight, size: AppIconSize.lg),
            ]),
          ),
        ),
      ),
      ),
    );
  }
}
