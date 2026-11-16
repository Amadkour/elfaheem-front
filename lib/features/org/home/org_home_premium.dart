// lib/features/org/home/org_home_premium.dart
//
// The organization home's premium dashboard pieces (D-631), plain values in — the SAME OrgHomeData the home already
// has, no request of their own:
//   OrgHomeHero          the forest greeting hero (AppGreetingHero): my name, the organization and what waits for me
//                        in one line, ONE call to action ("Review") while something waits
//   OrgMembersOverview   the desktop side card beside the hero: students · teachers · staff as three big figures, the
//                        people waiting to join and the 7-day joins line (when the server sends `series`)
//   orgHomeStats         the stat row (AppStatCard): what needs me, the departments, then the courses / sub-orgs on a
//                        desktop (the members card carries the people there) or the students / teachers on a phone
//   OrgHomeShortcut      a shortcut tile spec (AppShortcutTile, phones): a sub-page one tap away
//   OrgHomeGreeting      D-1081: the soft-wash home's greeting LINE (no hero): the greeting, the organization and what
//                        waits in one line, "Review" while something waits
//   orgHomeSoftStats     D-1081: the four soft-wash counts from `home_stats` (votes waiting · open requests, red when
//                        overdue · members of my departments · my next council session), each with its 8-week bars
// Colours from context.colors only; spacing / type from app_tokens.dart; texts t(ar, en).
// Layout test: test/ui/org_home_premium_layout_test.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppCountUp;
import 'package:flutter_education_app/design/home_a2.dart' show HomeGreetingRow;
import 'package:flutter_education_app/design/home_kit.dart' show HomeHeader;

import '../../admin/admin_common.dart' show t;
import '../org_common.dart' show orgTypeIcons;
import '../org_dashboard_model.dart';
import '../org_ui.dart' show orgNameOf;

/// A shortcut tile of the phone home: a sub-page one tap away.
class OrgHomeShortcut {
  const OrgHomeShortcut({required this.icon, required this.label, required this.onTap, this.tone = AppBlockTone.emerald});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final AppBlockTone tone;
}

/// "12.8K" for a big figure, the plain number below ten thousand.
String _figure(int n) => n >= 10000 ? appCompactNumber(n) : '$n';

/// "3 items need you" / "All caught up".
String orgHomeWaitingText(int n) => n <= 0
    ? t('لا شيء ينتظرك الآن', 'Nothing is waiting for you')
    : countText(n,
        ar1: 'أمر واحد ينتظرك',
        ar2: 'أمران ينتظرانك',
        arFew: '{n} أمور تنتظرك',
        arMany: '{n} أمرًا ينتظرك',
        en1: '1 item needs you',
        en: '{n} items need you');

/// The home's ONE hero: the greeting, the organization and what waits in one line, Review while something waits.
class OrgHomeHero extends StatelessWidget {
  const OrgHomeHero({
    super.key,
    required this.data,
    required this.waiting,
    this.name = '',
    this.centered = false,
    this.onReview,
  });

  final OrgHomeData data;

  /// What needs me (the tasks' total, else the payload's pending total).
  final int waiting;
  final String name;
  final bool centered;
  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final org = orgNameOf(data.organization);
    final summary = [if (org.isNotEmpty && org != '—') org, orgHomeWaitingText(waiting)].join(' · ');
    return AppGreetingHero(
      key: const ValueKey('org.home.hero'),
      greeting: HomeHeader.greetingLine(name),
      summary: summary,
      centered: centered,
      avatar: Icon(orgTypeIcons[data.organization['type']] ?? Icons.domain_rounded, color: c.onHero, size: AppIconSize.xl),
      cta: waiting > 0 && onReview != null
          ? AppGreetingHeroButton(
              label: t('راجع ما ينتظرك', 'Review what needs you'),
              icon: Icons.checklist_rounded,
              onTap: onReview,
            )
          : null,
    );
  }
}

/// D-1081: the home's greeting as a line, not a hero — the greeting in the page-title face, the organization and what
/// waits under it, a quiet "Review" while something waits.
class OrgHomeGreeting extends StatelessWidget {
  const OrgHomeGreeting({super.key, required this.data, required this.waiting, this.name = '', this.onReview, this.trailing = const [], this.next});

  /// D-1100: with nothing waiting, the line names what comes next ("next session Sun 2 Nov"); null = nothing.
  final String? next;

  /// D-1100: the role switcher ("View as") and the like, at the row's end before Review.
  final List<Widget> trailing;

  final OrgHomeData data;
  final int waiting;
  final String name;
  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final org = orgNameOf(data.organization);
    final summary = [if (org.isNotEmpty && org != '—') org, orgHomeWaitingText(waiting), if (waiting <= 0) ?next].join(' · ');
    if (trailing.isNotEmpty) {
      return KeyedSubtree(
        key: const ValueKey('org.home.greeting'),
        child: HomeGreetingRow(name: name, subline: summary, trailing: [
          ...trailing,
          if (waiting > 0 && onReview != null)
            AppButton.primary(label: t('راجع', 'Review'), icon: Icons.checklist_rounded, size: AppButtonSize.sm, onPressed: onReview),
        ]),
      );
    }
    return Row(key: const ValueKey('org.home.greeting'), crossAxisAlignment: CrossAxisAlignment.center, children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(HomeHeader.greetingLine(name), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.pageTitle(context)),
          const SizedBox(height: AppSpace.xxs),
          Text(summary, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textLight)),
        ]),
      ),
      if (waiting > 0 && onReview != null) ...[
        const SizedBox(width: AppSpace.sm),
        AppButton.secondary(
          label: t('راجع', 'Review'),
          icon: Icons.checklist_rounded,
          size: AppButtonSize.sm,
          onPressed: onReview,
        ),
      ],
    ]);
  }
}

/// D-1081: the four soft-wash counts (AppStatCard with 8-week bars) from `home_stats`. A count with nothing in it
/// reads muted; open requests turn red while one is overdue.
List<Widget> orgHomeSoftStats(
  OrgHomeStats s, {
  VoidCallback? onVotes,
  VoidCallback? onRequests,
  VoidCallback? onMembers,
  VoidCallback? onSession,
}) {
  final weeks = t('آخر 8 أسابيع', 'Last 8 weeks');
  final at = s.nextSessionAt;
  final council = s.nextSessionCouncil;
  return [
    AppStatCard(
      key: const ValueKey('org.home.stat.votes'),
      icon: Icons.how_to_vote_rounded,
      value: _figure(s.votesWaiting),
      label: t('تصويتات بانتظارك', 'Votes waiting'),
      tone: AppBlockTone.emerald,
      footer: s.votesWaiting > 0 ? t('صوتك مطلوب', 'Your vote is needed') : t('لا تصويتات الآن', 'No votes right now'),
      bars: s.votesWeeks,
      barsCaption: weeks,
      onTap: onVotes,
    ),
    AppStatCard(
      key: const ValueKey('org.home.stat.requests'),
      icon: Icons.assignment_rounded,
      value: _figure(s.requestsOpen),
      label: t('طلبات مفتوحة', 'Open requests'),
      tone: AppBlockTone.gold,
      warn: s.requestsOverdue > 0,
      footer: s.requestsOverdue > 0
          ? countText(s.requestsOverdue,
              ar1: 'طلب متأخر', ar2: 'طلبان متأخران', arFew: '{n} طلبات متأخرة', arMany: '{n} طلبًا متأخرًا', en1: '1 overdue', en: '{n} overdue')
          : (s.requestsOpen > 0 ? t('كلها في موعدها', 'All on time') : t('لا طلبات', 'No requests')),
      bars: s.requestsWeeks,
      barsCaption: weeks,
      onTap: onRequests,
    ),
    AppStatCard(
      key: const ValueKey('org.home.stat.members'),
      icon: Icons.groups_rounded,
      value: _figure(s.members),
      label: t('أعضاء أقسامك', 'Members of your departments'),
      tone: AppBlockTone.sky,
      footer: s.members > 0 ? t('في الأقسام التي تتابعها', 'In the departments you see') : t('لا أعضاء بعد', 'No members yet'),
      bars: s.membersWeeks,
      barsCaption: weeks,
      onTap: onMembers,
    ),
    AppStatCard(
      key: const ValueKey('org.home.stat.session'),
      icon: Icons.event_rounded,
      value: at == null ? '—' : AppTime.date(at, pattern: 'EEE d MMM'),
      label: t('الجلسة القادمة', 'Next session'),
      tone: AppBlockTone.peach,
      footer: at == null
          ? t('لا جلسات مجدولة', 'No sessions scheduled')
          : [AppTime.time(at), ?(council ?? s.nextSessionTitle)].join(' · '),
      onTap: at == null ? null : onSession,
    ),
  ];
}

/// The desktop side card: the members as three big figures (the Cuba overview), the people waiting to join and the
/// 7-day joins line. No LayoutBuilder inside: it sits in an equal-height row beside the hero.
class OrgMembersOverview extends StatelessWidget {
  const OrgMembersOverview({super.key, required this.data, this.onOpen});
  final OrgHomeData data;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (students, teachers, staff, pendingJoin) = data.figures;
    final joins = data.trend('joins');
    final all = students + teachers + staff;
    Widget figure(String label, int value, IconData icon, AppBlockTone tone) => Expanded(
          child: Semantics(
            label: '$label: $value',
            excludeSemantics: true,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, size: AppIconSize.md, color: appToneStrong(context, tone)),
              const SizedBox(height: AppSpace.xs),
              AppCountUp(_figure(value),
                  memoryKey: 'org.members:$label',
                  style: AppType.figureLarge(context).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
              const SizedBox(height: AppSpace.xxs),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: c.textMedium)),
            ]),
          ),
        );
    return AppSectionCard(
      key: const ValueKey('org.home.members'),
      title: t('أعضاء المؤسسة', 'Members'),
      subtitle: t('نظرة عامة على من فيها الآن', 'Who is in the organization now'),
      actions: [
        if (onOpen != null) AppButton.ghost(label: t('عرض الكل', 'See all'), size: AppButtonSize.sm, onPressed: onOpen),
      ],
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          figure(t('طالب', 'Students'), students, Icons.school_rounded, AppBlockTone.emerald),
          const SizedBox(width: AppSpace.md),
          figure(t('عضو هيئة تدريس', 'Teachers'), teachers, Icons.co_present_rounded, AppBlockTone.peach),
          const SizedBox(width: AppSpace.md),
          figure(t('فريق العمل', 'Staff'), staff, Icons.badge_rounded, AppBlockTone.sage),
        ]),
        // the mix in one bar, the figures' tones in the same order (decorative: the figures above say it)
        if (all > 0) ...[
          const SizedBox(height: AppSpace.md),
          ExcludeSemantics(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: SizedBox(
                height: AppSpace.xs,
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final (n, tone) in [(students, AppBlockTone.emerald), (teachers, AppBlockTone.peach), (staff, AppBlockTone.sage)])
                    if (n > 0)
                      Expanded(
                        // a share too small to see still gets a sliver
                        flex: (n * 1000 ~/ all).clamp(12, 1000),
                        child: ColoredBox(color: appToneStrong(context, tone)),
                      ),
                ]),
              ),
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
              countText(all,
                  ar1: 'عضو واحد في المؤسسة', ar2: 'عضوان في المؤسسة', arFew: '{n} أعضاء في المؤسسة', arMany: '{n} عضوًا في المؤسسة',
                  en1: '1 member in all', en: '{n} members in all'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.meta(context).copyWith(color: c.textLight)),
        ],
        if ((pendingJoin ?? 0) > 0 || joins != null) ...[
          const SizedBox(height: AppSpace.md),
          Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: c.divider),
          const SizedBox(height: AppSpace.md),
          Row(children: [
            if (joins != null) ...[
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t('انضمامات · 7 أيام', 'Joins · 7 days'),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textLight)),
                  const SizedBox(height: AppSpace.xxs),
                  Text(_figure(joins.value), style: AppType.figure(context)),
                ]),
              ),
              if (joins.spark.length >= 2)
                Expanded(
                  child: AppSparkline(joins.spark,
                      color: appToneStrong(context, AppBlockTone.emerald), label: t('انضمامات', 'Joins')),
                ),
            ],
            if ((pendingJoin ?? 0) > 0) ...[
              if (joins != null) const SizedBox(width: AppSpace.md),
              Flexible(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.person_add_alt_1_rounded, size: AppIconSize.sm, color: appToneStrong(context, AppBlockTone.peach)),
                  const SizedBox(width: AppSpace.xs),
                  Flexible(
                    child: Text(t('$pendingJoin ينتظرون الانضمام', '$pendingJoin waiting to join'),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: c.textMedium)),
                  ),
                ]),
              ),
            ],
          ]),
        ],
      ]),
    );
  }
}

/// The stat row's cards. [wide]: a desktop (the members card beside the hero carries the people, so the row shows
/// the courses and sub-organizations instead); a phone shows the students and teachers here.
List<Widget> orgHomeStats(
  OrgHomeData data, {
  required int waiting,
  required bool wide,
  VoidCallback? onWaiting,
  VoidCallback? onUnits,
}) {
  final (students, teachers, staff, _) = data.figures;
  final joins = data.trend('joins');
  final unitsWaiting = data.units.fold<int>(0, (n, u) => n + (int.tryParse('${u['waiting'] ?? 0}') ?? 0));
  return [
    AppStatCard(
      key: const ValueKey('org.home.stat.waiting'),
      icon: Icons.inbox_rounded,
      value: _figure(waiting),
      label: t('ينتظر قرارك', 'Needs you'),
      tone: AppBlockTone.peach,
      footer: waiting > 0 ? t('رتّبناها حسب الأولوية', 'Sorted by urgency') : t('أنجزت كل شيء', 'All caught up'),
      onTap: waiting > 0 ? onWaiting : null,
    ),
    AppStatCard(
      key: const ValueKey('org.home.stat.units'),
      icon: Icons.apartment_rounded,
      value: _figure(data.units.length),
      label: t('الإدارات والأقسام', 'Departments'),
      tone: AppBlockTone.sage,
      footer: unitsWaiting > 0
          ? countText(unitsWaiting,
              ar1: 'طلب واحد ينتظر في الأقسام', ar2: 'طلبان ينتظران في الأقسام', arFew: '{n} طلبات تنتظر في الأقسام',
              arMany: '{n} طلبًا ينتظر في الأقسام', en1: '1 waiting in departments', en: '{n} waiting in departments')
          : t('لا شيء ينتظر في الأقسام', 'Nothing waiting in them'),
      onTap: onUnits,
    ),
    if (wide) ...[
      if (data.kpis.containsKey('courses'))
        AppStatCard(
          key: const ValueKey('org.home.stat.courses'),
          icon: Icons.menu_book_rounded,
          value: _figure(data.kpi('courses')),
          label: t('مقرر', 'Courses'),
          tone: AppBlockTone.emerald,
          footer: t('في كل أقسام المؤسسة', 'Across the organization'),
        ),
      if (data.kpi('sub_organizations') > 0)
        AppStatCard(
          key: const ValueKey('org.home.stat.sub_orgs'),
          icon: Icons.account_tree_rounded,
          value: _figure(data.kpi('sub_organizations')),
          label: t('مؤسسات فرعية', 'Sub-organizations'),
          tone: AppBlockTone.sage,
          footer: t('تتبع مؤسستك', 'Under your organization'),
        ),
    ] else ...[
      AppStatCard(
        key: const ValueKey('org.home.stat.students'),
        icon: Icons.school_rounded,
        value: _figure(students),
        label: t('طالب', 'Students'),
        tone: AppBlockTone.emerald,
        footer: joins == null || joins.value <= 0
            ? t('في المؤسسة الآن', 'In the organization now')
            : t('${_figure(joins.value)} انضمّوا هذا الأسبوع', '${_figure(joins.value)} joined this week'),
      ),
      AppStatCard(
        key: const ValueKey('org.home.stat.teachers'),
        icon: Icons.co_present_rounded,
        value: _figure(teachers),
        label: t('عضو هيئة تدريس', 'Teachers'),
        tone: AppBlockTone.emerald,
        footer: staff > 0 ? t('و${_figure(staff)} من فريق العمل', '+ ${_figure(staff)} staff') : t('في المؤسسة الآن', 'In the organization now'),
      ),
    ],
  ];
}

/// The phone's shortcut grid (2 columns).
class OrgHomeShortcuts extends StatelessWidget {
  const OrgHomeShortcuts({super.key, required this.items});
  final List<OrgHomeShortcut> items;

  @override
  Widget build(BuildContext context) => AppShortcutGrid(
        maxColumns: 2,
        children: [
          for (final x in items)
            AppShortcutTile(key: ValueKey('org.home.shortcut.${x.label}'), icon: x.icon, label: x.label, tone: x.tone, onTap: x.onTap),
        ],
      );
}
