// lib/features/org/org_dashboard_home.dart
//
// The org-admin HOME (Track B.3, D-062): queue first, one tap to everything.
//   OrgHomePage       the live page: OrgSession + OrgDashController + OrgTabs → the hero's callbacks, the attention
//                     cards' deep jumps, the shortcuts, the sheets (generate a term's timetable, extend memberships)
//                     and the cards that follow the live feed (drafts, decisions). Pull / resume / live events reload
//                     through the controller; the body redraws from the last payload while a fresh one loads.
//   OrgHomeBody       presentational, plain values (test/ui/org_home_layout_test.dart pumps it):
//                     OrgHero → "Needs your attention" (pending_total in the title, drawn ONCE) → HomeShortcuts →
//                     trends (AppTrendTile × 3 from `series`) → governance slot → units strip → recent activity;
//                     wide: attention + trends + governance | shortcuts + units + activity.
//   OrgHero           compact: logo · name · status / type / role tags · four figures (students · teachers · staff ·
//                     pending joins, from `members`) · Calendar · Join code · Switch as icon buttons; Edit ·
//                     Sub-organization · Personal in the overflow.
//   OrgHomeSkeleton   the coordinated loading shape (the hero with "—" figures + a list skeleton), no spinner.
//   orgJump / orgPush one tap to a sub-page: the section AND its chip when the section is a tab, else the page is
//                     pushed on top (phones keep Services inside "More"); back from a pushed page, the home reloads
//                     only when the organization's attention items changed (OrgDashController.afterReturn).
// Colours: context.colors only (a calm card; the organization's colour tints its logo tile). Texts: t(ar, en).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/attention/attention_service.dart';
import 'package:flutter_education_app/design/app_kit.dart'
    show AppBanner, AppCard, AppListSkeleton, AppPill, AppRefresh, AppTime, AppTrendTile, appChartPalette, appCompactNumber, appInk, appText;
import 'package:flutter_education_app/design/context_switcher.dart' show ContextExitButton, leaveToPersonal;
import 'package:flutter_education_app/design/home_kit.dart' show HomeSection, HomeSectionTitle, HomeShortcut, HomeShortcuts;
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';

import '../admin/admin_common.dart';
import '../admin/admin_list.dart' show AdminAvatar, IconBadge;
import 'governance/gov_dashboard.dart' show GovDashboardCard;
import 'governance/gov_wiring.dart' show govEnabled;
import 'org_academic_pages.dart' show OrgAcademicPage;
import 'org_access_page.dart' show OrgActivityPage;
import 'org_common.dart';
import 'org_dashboard_model.dart';
import 'org_dashboard_screen.dart' show OrgTabs;
import 'org_dashboard_settings.dart' show showJoinCode, showOrgForm, showOrgSwitcher;
import 'org_department_dashboard.dart' show openDepartmentDashboard;
import 'org_departments_page.dart' show DeptLogo;
import 'org_join_pages.dart' show OrgJoinInboxPage;
import 'org_providers.dart';
import 'org_schedule_autopilot.dart' show TermNeed, TermTimetableCard;
import 'org_ui.dart';
import 'org_v3.dart' show orgCall, orgErrorText, orgParseUtc, orgUtc;
import 'package:flutter_education_app/design/app_icons.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  Plain-value specs
// ═════════════════════════════════════════════════════════════════════════════

class OrgHeroSpec {
  const OrgHeroSpec({
    required this.name,
    this.logoUrl = '',
    this.typeLabel = '',
    this.typeIcon = Icons.domain_rounded,
    required this.statusLabel,
    required this.roleLabel,
    required this.color,
    this.onCalendar,
    this.onJoinCode,
    this.onSwitch,
    this.onEdit,
    this.onSubOrg,
    this.onPersonal,
  });

  final String name, logoUrl, typeLabel, statusLabel, roleLabel;
  final IconData typeIcon;
  final Color color;

  /// Null hides the button / menu entry.
  final VoidCallback? onCalendar, onJoinCode, onSwitch, onEdit, onSubOrg, onPersonal;
}

class OrgAttentionSpec {
  const OrgAttentionSpec({
    required this.icon,
    required this.severity,
    required this.title,
    required this.subtitle,
    required this.action,
    required this.onTap,
  });

  final IconData icon;

  /// danger · warning · info → the card's colour.
  final String severity;
  final String title, subtitle, action;
  final VoidCallback onTap;

  /// From the server item's texts.
  static OrgAttentionSpec? of(OrgAttentionItem a, VoidCallback onTap) {
    final x = orgAttentionText(a);
    if (x == null) return null;
    return OrgAttentionSpec(icon: x.icon, severity: a.severity, title: x.title, subtitle: x.subtitle, action: x.action, onTap: onTap);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Body
// ═════════════════════════════════════════════════════════════════════════════

class OrgHomeBody extends StatelessWidget {
  const OrgHomeBody({
    super.key,
    required this.data,
    required this.hero,
    this.cards = const [],
    this.live,
    this.shortcuts = const [],
    this.governance,
    this.unitsTitle,
    this.onOpenUnit,
    this.onSeeAllUnits,
    this.onActivityLog,
  });

  final OrgHomeData data;
  final OrgHeroSpec hero;

  /// The attention cards from the payload.
  final List<OrgAttentionSpec> cards;

  /// Cards that follow the live feed, drawn after [cards] (null = none; then an empty queue shows "all good").
  final Widget? live;
  final List<HomeShortcut> shortcuts;

  /// The governance card (null = hidden).
  final Widget? governance;
  final String? unitsTitle;
  final void Function(Map<String, dynamic> unit)? onOpenUnit;
  final VoidCallback? onSeeAllUnits, onActivityLog;

  @override
  Widget build(BuildContext context) {
    final heroW = OrgHero(spec: hero, figures: data.figures);
    final attention = OrgAttentionSection(count: data.pendingTotal, cards: cards, live: live);
    final shortcutsW = shortcuts.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: HomeShortcuts(items: shortcuts, padding: const EdgeInsets.symmetric(horizontal: 16)),
          );
    final trends = data.hasTrends ? OrgTrendRow(trends: data.trends) : const SizedBox.shrink();
    final gov = governance == null ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: governance);
    final units = OrgUnitsStrip(units: data.units, title: unitsTitle, onOpen: onOpenUnit, onSeeAll: onSeeAllUnits);
    final activity = OrgRecentActivity(items: data.recentActivity, onLog: onActivityLog);
    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth < 900) {
        return ListView(padding: const EdgeInsets.only(bottom: 40), children: [heroW, attention, shortcutsW, trends, gov, units, activity]);
      }
      return ListView(padding: const EdgeInsets.only(bottom: 40), children: [
        heroW,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 3, child: Column(children: [attention, trends, gov])),
            Expanded(flex: 2, child: Column(children: [shortcutsW, units, activity])),
          ]),
        ),
      ]);
    });
  }
}

/// The loading shape: the hero already knows the organization; the rest is a calm skeleton.
class OrgHomeSkeleton extends StatelessWidget {
  const OrgHomeSkeleton({super.key, required this.hero});
  final OrgHeroSpec hero;

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.only(bottom: 40), children: [
        OrgHero(spec: hero),
        const SizedBox(height: 8),
        const AppListSkeleton(items: 4),
      ]);
}

// ═════════════════════════════════════════════════════════════════════════════
//  Hero
// ═════════════════════════════════════════════════════════════════════════════

class OrgHero extends StatelessWidget {
  const OrgHero({super.key, required this.spec, this.figures});
  final OrgHeroSpec spec;

  /// students · teachers · staff · pending joins (null while loading → "—"; a null pendingJoin = older server).
  final (int, int, int, int?)? figures;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final base = spec.color;
    final f = figures;
    String v(int? n) => f == null ? '—' : appCompactNumber(n ?? 0);
    final pendingJoin = f?.$4;
    final figs = <Widget>[
      _HeroFigure(icon: Icons.school_rounded, value: v(f?.$1), label: t('الطلاب', 'Students')),
      _HeroFigure(icon: Icons.person_pin_rounded, value: v(f?.$2), label: t('هيئة التدريس', 'Teachers')),
      _HeroFigure(icon: Icons.badge_rounded, value: v(f?.$3), label: t('الموظفون', 'Staff')),
      _HeroFigure(
          icon: Icons.person_add_alt_1_rounded,
          value: f != null && pendingJoin == null ? '—' : v(pendingJoin),
          label: t('بانتظار الانضمام', 'Pending joins'),
          hot: (pendingJoin ?? 0) > 0),
    ];
    final menu = <(IconData, String, VoidCallback)>[
      if (spec.onEdit != null) (Icons.edit_rounded, t('تعديل البيانات', 'Edit details'), spec.onEdit!),
      if (spec.onSubOrg != null) (Icons.account_tree_rounded, t('مؤسسة فرعية', 'Sub-organization'), spec.onSubOrg!),
      if (spec.onPersonal != null) (DirIcons.logout, 'ctx_personal'.tr, spec.onPersonal!),
    ];
    final icons = <Widget>[
      if (spec.onCalendar != null) _HeroIcon(Icons.event_rounded, t('التقويم', 'Calendar'), spec.onCalendar!),
      if (spec.onJoinCode != null) _HeroIcon(Icons.vpn_key_rounded, t('كود الانضمام', 'Join code'), spec.onJoinCode!),
      if (spec.onSwitch != null) _HeroIcon(Icons.swap_horiz_rounded, t('تبديل المؤسسة', 'Switch'), spec.onSwitch!),
      if (menu.isNotEmpty)
        PopupMenuButton<int>(
          tooltip: t('المزيد', 'More'),
          onSelected: (i) => menu[i].$3(),
          itemBuilder: (_) => [
            for (var i = 0; i < menu.length; i++)
              PopupMenuItem(
                value: i,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(menu[i].$1, size: 18, color: c.textMedium),
                  const SizedBox(width: 10),
                  Flexible(child: Text(menu[i].$2, maxLines: 1, overflow: TextOverflow.ellipsis)),
                ]),
              ),
          ],
          child: const SizedBox.square(dimension: 48, child: Center(child: _HeroIconBox(Icons.more_horiz_rounded))),
        ),
    ];
    Widget iconRow() => Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < icons.length; i++) ...[if (i > 0) const SizedBox(width: 2), icons[i]],
        ]);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      padding: const EdgeInsets.all(16),
      // calm like the student / instructor homes: the card surface with a hairline, the organization's colour only
      // in its logo tile (the gradient hero with loud figures read heavier than everything under it)
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(c.radiusLarge),
        color: c.cardBg,
        border: Border.all(color: c.divider),
      ),
      child: LayoutBuilder(builder: (context, box) {
        final roomy = box.maxWidth >= 520;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: base.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16)),
              clipBehavior: Clip.antiAlias,
              child: spec.logoUrl.isNotEmpty
                  ? Image.network(spec.logoUrl, fit: BoxFit.cover, errorBuilder: (_, _, _) => Icon(spec.typeIcon, color: appInk(context, base), size: 26))
                  : Icon(spec.typeIcon, color: appInk(context, base), size: 26),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(spec.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(18, w: FontWeight.w600, c: c.textDark, h: 1.2)),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  _HeroTag(Icons.verified_rounded, spec.statusLabel),
                  if (spec.typeLabel.isNotEmpty) _HeroTag(spec.typeIcon, spec.typeLabel),
                  _HeroTag(Icons.badge_rounded, spec.roleLabel),
                ]),
              ]),
            ),
            if (roomy && icons.isNotEmpty) ...[const SizedBox(width: 10), iconRow()],
          ]),
          const SizedBox(height: 14),
          if (box.maxWidth >= 440)
            Row(children: [for (var i = 0; i < figs.length; i++) ...[if (i > 0) const SizedBox(width: 8), Expanded(child: figs[i])]])
          else
            Column(children: [
              Row(children: [Expanded(child: figs[0]), const SizedBox(width: 8), Expanded(child: figs[1])]),
              const SizedBox(height: 8),
              Row(children: [Expanded(child: figs[2]), const SizedBox(width: 8), Expanded(child: figs[3])]),
            ]),
          if (!roomy && icons.isNotEmpty) ...[
            const SizedBox(height: 12),
            Align(alignment: AlignmentDirectional.centerEnd, child: iconRow()),
          ],
        ]);
      }),
    );
  }
}

class _HeroFigure extends StatelessWidget {
  const _HeroFigure({required this.icon, required this.value, required this.label, this.hot = false});
  final IconData icon;
  final String value, label;
  final bool hot;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: hot ? c.warning.withValues(alpha: 0.5) : c.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(value, maxLines: 1, style: appText(20, w: FontWeight.w600, c: hot ? appInk(context, c.warning) : c.textDark, h: 1.1)),
        ),
        const SizedBox(height: 2),
        Row(children: [
          Icon(icon, size: 12, color: c.textLight),
          const SizedBox(width: 4),
          Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(11, c: c.textMedium))),
        ]),
      ]),
    );
  }
}

class _HeroIconBox extends StatelessWidget {
  const _HeroIconBox(this.icon);
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(color: c.background, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.divider)),
      child: Icon(icon, size: 19, color: c.textMedium),
    );
  }
}

class _HeroIcon extends StatelessWidget {
  const _HeroIcon(this.icon, this.tooltip, this.onTap);
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          type: MaterialType.transparency,
          // the box stays 38 px; the tap target around it is 48 (Android / iOS minimum)
          child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: SizedBox.square(dimension: 48, child: Center(child: _HeroIconBox(icon)))),
        ),
      );
}

class _HeroTag extends StatelessWidget {
  const _HeroTag(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.divider),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: c.textLight),
        const SizedBox(width: 4),
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(11, w: FontWeight.w500, c: c.textMedium))),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Needs your attention
// ═════════════════════════════════════════════════════════════════════════════

class OrgAttentionSection extends StatelessWidget {
  const OrgAttentionSection({super.key, required this.count, required this.cards, this.live});
  final int count;
  final List<OrgAttentionSpec> cards;
  final Widget? live;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        HomeSectionTitle(t('يحتاج انتباهك', 'Needs your attention'), count: count, padding: const EdgeInsets.fromLTRB(16, 8, 12, 10)),
        if (cards.isEmpty && live == null) const OrgAllGood() else ...[for (final x in cards) OrgAttentionCard(spec: x), ?live],
      ]);
}

/// The empty queue.
class OrgAllGood extends StatelessWidget {
  const OrgAllGood({super.key, this.text});
  final String? text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: AppBanner(
          icon: Icons.spa_rounded,
          color: context.colors.success,
          text: text ?? t('لا شيء ينتظرك الآن — كل شيء على ما يرام 🌿', 'Nothing is waiting for you — all good 🌿'),
        ),
      );
}

class OrgAttentionCard extends StatelessWidget {
  const OrgAttentionCard({super.key, required this.spec});
  final OrgAttentionSpec spec;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = switch (spec.severity) { 'danger' => c.danger, 'warning' => c.warning, _ => c.primary };
    return AppCard(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      onTap: spec.onTap,
      child: Row(children: [
        Container(width: 4, height: 40, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
        const SizedBox(width: 10),
        IconBadge(spec.icon, color, size: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(spec.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: orgText(context, size: 14, w: FontWeight.w600)),
            if (spec.subtitle.isNotEmpty)
              Text(spec.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: orgText(context, size: 12, color: c.textMedium)),
          ]),
        ),
        const SizedBox(width: 8),
        // capped so a long action label (or a 1.3 text scale on a 320 px phone) never squeezes the title out
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width >= 600 ? 160 : 96),
          child: TextButton(
            onPressed: spec.onTap,
            style: TextButton.styleFrom(
                foregroundColor: appInk(context, color), padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(48, 40)),
            child: Text(spec.action, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Trends · units · activity
// ═════════════════════════════════════════════════════════════════════════════

/// AppTrendTile per trend (joins · attendance · complaints): the last 7 days, the change against the week before,
/// the 30-day sparkline.
class OrgTrendRow extends StatelessWidget {
  const OrgTrendRow({super.key, required this.trends});
  final List<OrgTrend> trends;

  static (String, IconData, bool) describe(String key) => switch (key) {
        'joins' => (t('انضمامات · 7 أيام', 'Joins · 7 days'), Icons.person_add_alt_1_rounded, true),
        'attendance' => (t('حضور · 7 أيام', 'Attendance · 7 days'), Icons.fact_check_rounded, true),
        'complaints' => (t('شكاوى · 7 أيام', 'Complaints · 7 days'), Icons.support_agent_rounded, false),
        'work_items' => (t('معاملات · 7 أيام', 'Work items · 7 days'), Icons.account_tree_rounded, true),
        _ => (key, Icons.timeline_rounded, true),
      };

  @override
  Widget build(BuildContext context) {
    if (trends.isEmpty) return const SizedBox.shrink();
    final palette = appChartPalette(context);
    const slots = {'joins': 0, 'attendance': 2, 'complaints': 4};
    // folds from its title (HomeSection, remembered per user on the device)
    return HomeSection(
      id: 'org_admin.trends',
      title: t('الاتجاهات · 30 يوماً', 'Trends · 30 days'),
      titlePadding: const EdgeInsets.fromLTRB(16, 8, 12, 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: LayoutBuilder(builder: (context, box) {
          const gap = 10.0;
          final cols = (box.maxWidth / 140).floor().clamp(1, 3);
          final w = (box.maxWidth - gap * (cols - 1)) / cols;
          return Wrap(spacing: gap, runSpacing: gap, children: [
            for (var i = 0; i < trends.length; i++)
              SizedBox(
                width: w,
                child: Builder(builder: (context) {
                  final x = trends[i];
                  final (label, icon, upIsGood) = describe(x.key);
                  return AppTrendTile(
                    label: label,
                    value: appCompactNumber(x.value),
                    delta: x.delta,
                    spark: x.spark,
                    upIsGood: upIsGood,
                    icon: icon,
                    color: palette[(slots[x.key] ?? i) % palette.length],
                    deltaHint: t('مقابل الأسبوع السابق', 'vs the week before'),
                  );
                }),
              ),
          ]);
        }),
      ),
    );
  }
}

/// My departments (service + academic), each with what waits there → the department dashboard.
class OrgUnitsStrip extends StatelessWidget {
  const OrgUnitsStrip({super.key, required this.units, this.title, this.onOpen, this.onSeeAll, this.max = 6});
  final List<Map<String, dynamic>> units;
  final String? title;
  final void Function(Map<String, dynamic> unit)? onOpen;
  final VoidCallback? onSeeAll;
  final int max;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (units.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      HomeSectionTitle(title ?? t('الإدارات والأقسام', 'Departments'),
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 10),
          actionLabel: onSeeAll == null ? null : t('عرض الكل', 'See all'),
          onAction: onSeeAll),
      for (final u in units.take(max))
        AppCard(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          onTap: onOpen == null ? null : () => onOpen!(u),
          child: Row(children: [
            u['unit_type'] == 'program' ? IconBadge(Icons.school_rounded, c.purple, size: 38) : DeptLogo(d: u, size: 38),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(orgNameOf(u), maxLines: 1, overflow: TextOverflow.ellipsis, style: orgText(context, w: FontWeight.w600)),
                Text(
                    u['unit_type'] == 'program'
                        ? t('قسم علمي · ${asInt(u['students'])} طالب', 'Academic · ${asInt(u['students'])} students')
                        : t('إدارة خدمية · ${asInt(u['team'])} في الفريق', 'Service · ${asInt(u['team'])} team'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: orgText(context, size: 11.5, color: c.textLight)),
              ]),
            ),
            if (asInt(u['waiting']) > 0) OrgPill(t('${u['waiting']} تنتظر', '${u['waiting']} waiting'), color: c.warning),
            Icon(Icons.chevron_right_rounded, color: c.textLight),
          ]),
        ),
    ]);
  }
}

class OrgRecentActivity extends StatelessWidget {
  const OrgRecentActivity({super.key, required this.items, this.onLog, this.max = 5});
  final List<Map<String, dynamic>> items;
  final VoidCallback? onLog;
  final int max;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      HomeSectionTitle(t('آخر النشاط', 'Recent activity'),
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 10), actionLabel: onLog == null ? null : t('السجل', 'Log'), onAction: onLog),
      AppCard(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(children: [
          for (final a in items.take(max))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.history_rounded, size: 18, color: c.textLight),
                const SizedBox(width: 10),
                Expanded(child: Text('${a['summary']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: orgText(context, size: 12.5))),
                const SizedBox(width: 8),
                Text(relTime(a['created_at']), style: orgText(context, size: 11, color: c.textLight)),
              ]),
            ),
        ]),
      ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Navigation: one tap to a sub-page
// ═════════════════════════════════════════════════════════════════════════════

/// Pushes an org page over the dashboard (the session carried along, the exit button in its bar). Back from it,
/// the home reloads only when the organization's attention items changed meanwhile.
Future<void> orgPushPage(BuildContext context,
    {required OrgSession session, required OrgDashController dash, required String title, required Widget page, double maxWidth = 1100}) async {
  final epoch = dash.attentionEpoch;
  await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider.value(
          value: session,
          child: BasePage(
              useWebCard: true,
              maxWith: maxWidth,
              appBar: ScreenAppBar(title: title, actions: const [ContextExitButton()]),
              child: page))));
  dash.afterReturn(epoch);
}

Future<void> orgPush(BuildContext context, String title, Widget page, {double maxWidth = 1100}) =>
    orgPushPage(context, session: context.read<OrgSession>(), dash: context.read<OrgDashController>(), title: title, page: page, maxWidth: maxWidth);

/// The section AND its chip when the section is a tab; else the sub-page pushed on top (phones: Services lives in
/// "More"); else [fallback] (a page the server points at although I hold no section for it).
Future<void> orgJump(BuildContext context, String section, {String? sub, (String, Widget)? fallback}) async {
  final tabs = context.read<OrgTabs>();
  if (tabs.go(section, sub: sub)) return;
  final x = sub == null ? null : tabs.subOf(section, sub);
  if (x != null) return orgPush(context, x.$2, x.$4);
  if (fallback != null) return orgPush(context, fallback.$1, fallback.$2);
}

// ═════════════════════════════════════════════════════════════════════════════
//  The live page
// ═════════════════════════════════════════════════════════════════════════════

class OrgHomePage extends StatelessWidget {
  const OrgHomePage({super.key});

  OrgHeroSpec _hero(BuildContext context, OrgSession s) {
    final org = s.current ?? const <String, dynamic>{};
    final role = '${org['my_role'] ?? ''}';
    return OrgHeroSpec(
      name: s.name,
      logoUrl: '${org['logo_url'] ?? ''}',
      typeLabel: orgTypeLabels()[org['type']] ?? '',
      typeIcon: orgTypeIcons[org['type']] ?? Icons.domain_rounded,
      statusLabel: s.approved ? t('مفعّلة', 'Active') : statusLabel(s.status),
      roleLabel: role == 'org_admin' || role == 'platform_admin'
          ? t('مدير المؤسسة', 'Organization admin')
          : (memberRoleLabels()[role] ?? t('فريق الإدارة', 'Staff')),
      color: orgColor(context, org),
      onCalendar: () => Navigator.of(context).pushNamed('/calendar', arguments: {'org_id': s.currentId}),
      onJoinCode: s.isOrgAdmin ? () => showJoinCode(context) : null,
      onSwitch: s.items.length > 1 || s.canCreateRoot ? () => showOrgSwitcher(context) : null,
      onEdit: s.isOrgAdmin ? () => showOrgForm(context, edit: s.current) : null,
      onSubOrg: s.can('sub_orgs', 'insert') || s.isOrgAdmin ? () => showOrgForm(context, parentId: s.currentId) : null,
      onPersonal: () => leaveToPersonal(context),
    );
  }

  /// One tap to every sub-page I hold (section + chip, or the page pushed on phones).
  List<HomeShortcut> _shortcuts(BuildContext context, OrgTabs tabs, OrgHomeData d) {
    HomeShortcut? sc(String section, String sub, IconData icon, String label, {int badge = 0}) => tabs.has(section, sub)
        ? HomeShortcut(icon: icon, label: label, badge: badge, onTap: () => orgJump(context, section, sub: sub))
        : null;
    return [
      ?sc('people', 'members', Icons.groups_rounded, t('الأعضاء', 'Members')),
      ?sc('people', 'join_requests', Icons.how_to_reg_rounded, t('طلبات الانضمام', 'Join requests'),
          badge: d.count('org_join_requests') + d.count('unit_join_requests')),
      ?sc('people', 'departments', Icons.apartment_rounded, t('الإدارات', 'Departments')),
      ?sc('academics', 'courses', Icons.menu_book_rounded, t('المقررات', 'Courses')),
      if (tabs.keys.contains('timetable'))
        HomeShortcut(icon: Icons.calendar_month_rounded, label: t('الجدول', 'Timetable'), onTap: () => orgJump(context, 'timetable')),
      ?sc('services', 'announcements', Icons.campaign_rounded, t('الإعلانات', 'News')),
      ?sc('services', 'complaints', Icons.support_agent_rounded, t('الشكاوى', 'Complaints'), badge: d.count('open_complaints')),
      ?sc('services', 'forms', Icons.assignment_rounded, t('النماذج', 'Forms'), badge: d.count('pending_forms')),
      HomeShortcut(icon: Icons.tune_rounded, label: t('الإعدادات', 'Settings'), onTap: () => orgJump(context, 'settings')),
    ];
  }

  List<OrgAttentionSpec> _cards(BuildContext context, OrgHomeData d) => [
        for (final a in d.attention)
          ?OrgAttentionSpec.of(a, switch (a.key) {
            'org_join_requests' => () => orgJump(context, 'people', sub: 'members'),
            'unit_join_requests' => () => orgJump(context, 'people', sub: 'join_requests', fallback: (t('طلبات الانضمام', 'Join requests'), const OrgJoinInboxPage())),
            'program_choices' => () => orgJump(context, 'academics', sub: 'structure', fallback: (t('الهيكل الأكاديمي', 'Academic structure'), const OrgAcademicPage())),
            'pending_forms' => () => orgJump(context, 'services', sub: 'forms'),
            'open_complaints' => () => orgJump(context, 'services', sub: 'complaints'),
            'schedule_unplaced' || 'schedule_suggestions' => () => orgJump(context, 'timetable'),
            'term_without_timetable' => () => _generateTerms(context, a.terms),
            'expiring_memberships' => () => _showExpiring(context, a),
            'pending_sub_orgs' => () => showOrgSwitcher(context),
            _ => () {},
          }),
      ];

  @override
  Widget build(BuildContext context) {
    final s = context.watch<OrgSession>();
    final dash = context.watch<OrgDashController>();
    final tabs = context.read<OrgTabs>();
    final d = dash.data;
    final hero = _hero(context, s);
    Future<void> refresh() => dash.load(s);
    if (d == null) {
      if (dash.failed) {
        return AppRefresh(
          onRefresh: refresh,
          child: ListView(children: [
            OrgHero(spec: hero),
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: ErrorRetry(message: dash.error ?? t('تعذّر تحميل لوحة المؤسسة', 'Could not load the dashboard'), onRetry: refresh)),
          ]),
        );
      }
      return OrgHomeSkeleton(hero: hero);
    }
    final cards = _cards(context, d);
    return AppRefresh(
      onRefresh: refresh,
      child: OrgHomeBody(
        data: d,
        hero: hero,
        cards: cards,
        live: _LiveAttention(baseEmpty: cards.isEmpty, hasTermCard: d.count('term_without_timetable') > 0),
        shortcuts: _shortcuts(context, tabs, d),
        governance: govEnabled() && (s.isOrgAdmin || s.canAny('workflow')) ? const GovDashboardCard(compact: true) : null,
        unitsTitle: s.isOrgAdmin ? t('الإدارات والأقسام', 'Departments') : t('أقسامي', 'My departments'),
        onOpenUnit: (u) async {
          // no reload after every visit: only when the attention items changed meanwhile (OrgDashController.afterReturn)
          final epoch = dash.attentionEpoch;
          await openDepartmentDashboard(context, unitType: '${u['unit_type']}', unitId: asInt(u['id']), seed: u);
          dash.afterReturn(epoch);
        },
        onSeeAllUnits: tabs.has('people', 'departments') ? () => orgJump(context, 'people', sub: 'departments') : null,
        onActivityLog: () => orgPush(context, t('سجل النشاط', 'Activity log'), const OrgActivityPage(), maxWidth: 1000),
      ),
    );
  }
}

/// Cards that follow GET /me/attention (it knows before the dashboard reloads): a term without a timetable, the
/// auto-created drafts to approve, the registrar's open decisions. Only this widget repaints on a feed tick.
class _LiveAttention extends StatelessWidget {
  const _LiveAttention({required this.baseEmpty, required this.hasTermCard});
  final bool baseEmpty, hasTermCard;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: AttentionService.instance,
        builder: (context, _) {
          final s = context.read<OrgSession>();
          final cards = <OrgAttentionSpec>[];
          if (!hasTermCard) {
            final live = AttentionService.instance.items(AttentionTabs.orgTimetable, orgId: s.currentId).where((x) => x.kind == 'term_without_timetable').toList();
            if (live.isNotEmpty) {
              final n = live.fold<int>(0, (a, x) => a + x.count);
              cards.add(OrgAttentionSpec(
                  icon: Icons.auto_awesome_rounded,
                  severity: 'warning',
                  title: n == 1 ? t('فصل دراسي بلا جدول', 'A term has no timetable yet') : t('$n فصول دراسية بلا جدول', '$n terms have no timetable yet'),
                  subtitle: t('بضغطة واحدة يُنشأ الجدول ويُولَّد وتُصلَح تعارضاته', 'One tap creates, generates and fixes the timetable'),
                  action: t('ولّد الآن', 'Generate now'),
                  onTap: () => context.read<OrgTabs>().go('timetable', sub: 'generate')));
            }
          }
          final acad = AttentionService.instance.items(AttentionTabs.orgAcademics, orgId: s.currentId);
          final drafts = acad.where((x) => x.isSuggestion).length;
          final decisions = acad.where((x) => x.kind == 'decision').fold<int>(0, (n, x) => n + x.count);
          if (drafts > 0) {
            cards.add(OrgAttentionSpec(
                icon: Icons.auto_fix_high_rounded,
                severity: 'info',
                title: t('$drafts اقتراح جاهز للاعتماد', '$drafts drafts ready for approval'),
                subtitle: t('أنشأها النظام تلقائياً (مثل الفصول الناقصة) — اعتمد أو عدّل أو ارفض', 'Created automatically (e.g. missing terms) — approve, edit or reject'),
                action: t('مراجعة', 'Review'),
                onTap: () => orgJump(context, 'academics', sub: 'structure', fallback: (t('الهيكل الأكاديمي', 'Academic structure'), const OrgAcademicPage()))));
          }
          if (decisions > 0) {
            cards.add(OrgAttentionSpec(
                icon: Icons.gavel_rounded,
                severity: 'warning',
                title: t('$decisions قرار ينتظرك', '$decisions decisions waiting'),
                subtitle: t('حالات لم يحسمها النظام وحده', 'Cases the system did not settle alone'),
                action: t('فتح', 'Open'),
                onTap: () => orgJump(context, 'academics', sub: 'registrar')));
          }
          if (cards.isEmpty) return baseEmpty ? const OrgAllGood() : const SizedBox.shrink();
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final x in cards) OrgAttentionCard(spec: x)]);
        },
      );
}

// ═════════════════════════════════════════════════════════════════════════════
//  Sheets
// ═════════════════════════════════════════════════════════════════════════════

/// The term cards in a sheet; Generate now = POST …/schedules/auto, then the Timetable section opens that draft.
Future<void> _generateTerms(BuildContext context, List<TermNeed> terms) async {
  final s = context.read<OrgSession>();
  final tabs = context.read<OrgTabs>();
  final dash = context.read<OrgDashController>();
  final busy = <int>{};
  await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SheetHeader(t('فصول بلا جدول', 'Terms without a timetable')),
            Text(t('يُنشأ الجدول من مقررات الفصل، يُولَّد خلال نحو دقيقة، وتُصلَح تعارضاته تلقائياً؛ ثم تراجعه وتنشره.', 'The timetable is created from the term\'s courses, generated in about a minute and its conflicts fixed automatically; then you review and publish it.'),
                style: orgText(ctx, size: 12.5, color: ctx.colors.textMedium)),
            const SizedBox(height: 10),
            for (final n in terms)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TermTimetableCard(
                  need: n,
                  busy: busy.contains(n.id),
                  onSetup: () {
                    Navigator.pop(ctx);
                    tabs.go('timetable', sub: 'generate');
                  },
                  onGenerate: () async {
                    set(() => busy.add(n.id));
                    final r = await orgCall(() => s.api.post('${s.base}/schedules/auto', body: {'term_id': n.id}), quiet: true);
                    if (!ctx.mounted) return;
                    set(() => busy.remove(n.id));
                    final running = asMap(r.detail['run']);
                    if (!r.ok && !(r.code == 'generation_running' && running['schedule_id'] != null)) {
                      toast(orgErrorText(r.error!), error: true);
                      return;
                    }
                    Navigator.pop(ctx);
                    // someone already pressed it: open the timetable the run is writing
                    tabs.go('timetable', sub: 'open:${r.ok ? asMap(r.map['schedule'])['id'] : running['schedule_id']}');
                    dash.load(s);
                  },
                ),
              ),
          ]),
        );
      }));
}

/// Memberships ending soon → extend in place (1 month · 3 months · 6 months · 1 year · permanent).
Future<void> _showExpiring(BuildContext context, OrgAttentionItem a) async {
  final s = context.read<OrgSession>();
  final dash = context.read<OrgDashController>();
  final rows = a.items;
  final done = <int>{};
  await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        final c = ctx.colors;
        Future<void> extend(Map<String, dynamic> m, int? months) async {
          final mid = asInt(m['member_id']);
          final from = orgParseUtc(m['expires_at']) ?? DateTime.now();
          final until = months == null ? null : DateTime(from.year, from.month + months, from.day, from.hour, from.minute);
          final r = await orgCall(() => ApiClient().post('${s.base}/members/$mid/extend', body: {'expires_at': orgUtc(until), 'reactivate': true}),
              ok: t('تم التمديد', 'Extended'));
          if (r.ok) set(() => done.add(mid));
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SheetHeader(t('عضويات تنتهي قريباً', 'Memberships ending soon')),
            Text(t('بعد تاريخ الانتهاء يفقد الشخص الوصول وتتوقف صلاحياته تلقائياً.', 'After the end date the person loses access and their rights switch off automatically.'),
                style: orgText(ctx, size: 12.5, color: c.textMedium)),
            const SizedBox(height: 12),
            for (final m in rows)
              AppCard(
                margin: const EdgeInsets.only(bottom: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    AdminAvatar(name: '${asMap(m['user'])['name'] ?? '—'}', url: asMap(m['user'])['image_url'] as String?, size: 38),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${asMap(m['user'])['name'] ?? '—'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: orgText(ctx, w: FontWeight.w500)),
                        Text(
                            '${memberRoleLabels()['${m['role']}'] ?? m['role']} · '
                            '${t('تنتهي', 'ends')} ${orgParseUtc(m['expires_at']) == null ? '—' : AppTime.date(orgParseUtc(m['expires_at'])!.toUtc())}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: orgText(ctx, size: 11.5, color: c.textLight)),
                      ]),
                    ),
                    if (done.contains(asInt(m['member_id']))) Icon(Icons.check_circle_rounded, color: c.success),
                  ]),
                  if (!done.contains(asInt(m['member_id']))) ...[
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final (label, months) in [
                        (t('شهر', '1 month'), 1),
                        (t('3 أشهر', '3 months'), 3),
                        (t('6 أشهر', '6 months'), 6),
                        (t('سنة', '1 year'), 12),
                        (t('دائمة', 'Permanent'), null),
                      ])
                        AppPill(icon: months == null ? Icons.all_inclusive_rounded : Icons.add_rounded, label: label, onTap: () => extend(m, months)),
                    ]),
                  ],
                ]),
              ),
            if (a.count > rows.length)
              Text(t('تظهر أقرب ${rows.length} — الباقي في صفحة الأعضاء.', 'Showing the nearest ${rows.length} — the rest are on the People page.'),
                  style: orgText(ctx, size: 12, color: c.textMedium)),
          ]),
        );
      }));
  if (done.isNotEmpty) dash.load(s);
}
