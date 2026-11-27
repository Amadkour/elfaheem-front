// lib/features/parent/parent_children_page.dart — the parent's "Children" tab (Pa2Kids `screen=list`, phase 4).
//
//   hero      "My children": n children linked, the one waiting for consent, four figures (courses · average
//             attendance · new alerts · waiting for consent)
//   inbox     ONE entry into the inbox (requests, announcements, offers), as on every role's home
//   cards     one card per child in the child's own colour: avatar · name · grade · one plain sentence · progress /
//             attendance / exams rings · Reports · Games · Quran · Nahw (each behind its tab's switch) · the consent
//             notice or "withdraw consent" · courses that need attention · new alerts. The card opens the child's
//             page (pa_child_pages.dart); the switcher in the top bar narrows the list to one child.
// Data: ParentLinkProvider (GET /parent/children + one /profile per child, started from the overview's seed) and
// the Alerts tab's provider for the unread counts (optional).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import 'package:flutter_education_app/core/app_digits.dart';
import 'package:flutter_education_app/features/analytics/analytics_ui.dart' show anInsightSentence;
import 'package:flutter_education_app/features/data_lab/data_lab_models.dart' show DlProfile;
import 'package:flutter_education_app/features/messaging/inbox/unified_inbox.dart' show InboxEntryCard;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/games/games_api.dart' show gamesOff, gamesLabel;
import 'package:flutter_education_app/features/games/games_progress.dart' show ParentChildGamesPage;
import 'package:flutter_education_app/features/admin/admin_common.dart' show ErrorRetry, t;
import 'package:flutter_education_app/features/quran/quran_api.dart' show quranOff;
import 'package:flutter_education_app/features/quran/quran_progress.dart' show QuranProgressPage;
import 'package:flutter_education_app/features/nahw/nahw_api.dart' show nahwOff, nahwLabel;
import 'package:flutter_education_app/features/nahw/nahw_tab.dart' show ParentChildNahwPage;
import 'pa_child_pages.dart';
import 'pa_kit.dart';
import 'parent_consent.dart';
import 'parent_link_providers.dart';
import 'parent_reports_page.dart';
import 'parent_widgets.dart';

class ParentChildrenPage extends StatefulWidget {
  const ParentChildrenPage({super.key, required this.onOpenLinkTab, this.onAddChild});

  final VoidCallback onOpenLinkTab;

  /// "Add your child" (the parent creates the child's account); null = not offered.
  final VoidCallback? onAddChild;

  @override
  State<ParentChildrenPage> createState() => _ParentChildrenPageState();
}

class _ParentChildrenPageState extends State<ParentChildrenPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ParentLinkProvider>().ensureLoaded();
    });
  }

  /// Unread alerts per child (the Alerts tab's provider lives in the parent dashboard; optional here).
  Map<int, int> _unread(BuildContext context) {
    final out = <int, int>{};
    try {
      final alerts = context.watch<ParentAlertsProvider>();
      for (final a in alerts.items) {
        if (a['unread'] != true) continue;
        final id = ((a['child'] as Map?)?['id'] as num?)?.toInt();
        if (id != null) out[id] = (out[id] ?? 0) + 1;
      }
    } on ProviderNotFoundException {
      // not inside the dashboard — no counts
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ParentLinkProvider>();
    final unread = _unread(context);
    final kids = PaKids.maybeOf(context);

    if (p.hasError && p.children.isEmpty) {
      return ErrorRetry(message: p.errorMessage ?? '', onRetry: p.loadAll);
    }
    if (p.children.isEmpty && p.isLoading) {
      return const AppListSkeleton(items: 3);
    }
    if (p.children.isEmpty) {
      return AppEmpty(
        icon: Icons.family_restroom_rounded,
        title: 'pl_no_children_title'.tr,
        message: 'pl_no_children_hint'.tr,
        actionLabel: 'pa_link_child'.tr,
        onAction: widget.onOpenLinkTab,
      );
    }

    final all = [for (final ch in p.children) if (ch['id'] is num) ch];
    final sel = kids?.selected;
    final shown = sel == null ? all : [for (final ch in all) if ((ch['id'] as num).toInt() == sel) ch];
    final waiting = [for (final ch in all) if (ch['needs_consent'] == true) '${ch['name']}'.split(' ').first];
    final profiles = [for (final ch in all) p.profiles[(ch['id'] as num).toInt()]].whereType<DlProfile>().toList();
    final courses = profiles.fold<int>(0, (n, pr) => n + pr.courses.length);
    final atts = [for (final pr in profiles) ?pr.attendance];
    final avg = atts.isEmpty ? null : (atts.reduce((a, b) => a + b) / atts.length).round();
    final newAlerts = unread.values.fold<int>(0, (a, b) => a + b);

    final hero = AppHero(
      kicker: 'pa_my_kids'.tr,
      title: paFmt('pa_kids_linked', {'n': appDigits('${all.length}')}),
      subtitle: waiting.isEmpty ? 'pa_kids_sub'.tr : paFmt('pa_kids_waiting', {'name': waiting.first}),
      stats: [
        AppHeroStat(label: 'pa_courses'.tr, value: profiles.isEmpty ? '—' : appDigits('$courses')),
        AppHeroStat(label: 'pa_avg_attendance'.tr, value: avg == null ? '—' : appDigits('$avg%')),
        AppHeroStat(label: 'pa_new_alerts'.tr, value: appDigits('$newAlerts')),
        AppHeroStat(label: 'pa_waiting_consent'.tr, value: appDigits('${waiting.length}')),
      ],
    );
    return PaHeroPage(
      onRefresh: p.loadAll,
      hero: hero,
      body: PaStack(children: [
        // requests · announcements · offers for the parent: ONE entry into the inbox, as on every role's home
        const InboxEntryCard(padding: EdgeInsets.zero),
        for (final ch in shown)
          ParentChildCard(
            data: ch,
            profile: p.profiles[(ch['id'] as num).toInt()],
            profileLoaded: p.profiles.containsKey((ch['id'] as num).toInt()),
            unreadAlerts: unread[(ch['id'] as num).toInt()] ?? 0,
          ),
        Wrap(alignment: WrapAlignment.center, spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          AppButton.ghost(label: 'pl_link_another'.tr, icon: Icons.add_link_rounded, onPressed: widget.onOpenLinkTab),
          if (widget.onAddChild != null)
            AppButton.ghost(
              key: const ValueKey('pa.kids.add'),
              label: 'pa_add_child_cta'.tr,
              icon: Icons.person_add_alt_1_rounded,
              onPressed: widget.onAddChild,
            ),
        ]),
      ]),
    );
  }
}

/// One child (Pa2Kids `screen=list`): the card in the child's own colour; it opens the child's page.
class ParentChildCard extends StatelessWidget {
  const ParentChildCard({super.key, required this.data, required this.profile, required this.profileLoaded, required this.unreadAlerts});

  final Map<String, dynamic> data;
  final DlProfile? profile;
  final bool profileLoaded;
  final int unreadAlerts;

  @override
  Widget build(BuildContext context) {
    final id = (data['id'] as num).toInt();
    final name = '${data['name']}';
    final grade = '${data['grade_name'] ?? ''}';
    final pr = profile;
    final attention = pr?.courses.where((b) => _needsAttention(b.attendance, b.examAvg)).length ?? 0;
    final needsConsent = data['needs_consent'] == true;
    void openPage() => paPush<void>(context, ParentChildPage(childId: id));
    return AppCard(
      variant: AppCardVariant.tint,
      tone: paKidTone(context, id),
      onTap: openPage,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(
          button: true,
          label: name,
          child: Row(children: [
            PaKidAvatar(id: id, name: name, size: AppDashSize.avatarSm),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
                Text(grade.isNotEmpty ? grade : '${'pl_linked_at'.tr} ${plDateTime(data['linked_at'])}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded),
          ]),
        ),
        if (pr != null) ...[
          const SizedBox(height: AppSpace.sm),
          Text(anInsightSentence(pr.progress, pr.attendance, pr.examAvg, mine: false), style: AppType.body(context)),
        ],
        if (!profileLoaded)
          const Padding(padding: EdgeInsets.symmetric(vertical: AppSpace.md), child: AppSkeletonBox(height: AppSpace.xxxl))
        else if (pr != null)
          Padding(padding: const EdgeInsets.symmetric(vertical: AppSpace.md), child: PaRings(profile: pr)),
        if (needsConsent) ...[
          ConsentNeededNotice(onGive: () => paGiveConsent(context, id, name, grade)),
          const SizedBox(height: AppSpace.sm),
        ],
        ParentChildActions(id: id, name: name, needsConsent: needsConsent),
        if (attention > 0 || unreadAlerts > 0) ...[
          const SizedBox(height: AppSpace.xs),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
            if (attention > 0)
              AppStatusBadge(label: paFmt('pa_attention_courses', {'n': appDigits('$attention')}), tone: AppTone.warning),
            if (unreadAlerts > 0)
              AppStatusBadge(label: paFmt('pa_new_alerts_n', {'n': appDigits('$unreadAlerts')}), tone: AppTone.danger),
          ]),
        ],
      ]),
    );
  }
}

/// Progress · attendance · exams as three rings.
class PaRings extends StatelessWidget {
  const PaRings({super.key, required this.profile});
  final DlProfile profile;

  @override
  Widget build(BuildContext context) {
    final kit = context.colors.kit;
    KitTone tone(double? v) => v == null ? KitTone(kit.lock, kit.track, context.colors.textMedium) : (v >= 75 ? kit.ok : (v >= 50 ? kit.warn : kit.live));
    Widget ring(double? v, String label) => Expanded(
          child: Column(children: [
            AppProgressRing(
              value: (v ?? 0) / 100,
              size: AppDashSize.ring,
              tone: tone(v),
              label: v == null ? '—' : null,
              semanticLabel: '$label ${v == null ? '—' : '${v.round()}%'}',
            ),
            const SizedBox(height: AppSpace.xxs),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
          ]),
        );
    return Row(children: [
      ring(profile.progress, 'pa_progress'.tr),
      ring(profile.attendance, 'pa_attendance'.tr),
      ring(profile.examAvg, 'pa_exams'.tr),
    ]);
  }
}

/// Reports · Games · Quran · Nahw (each hidden with its tab) · withdraw consent.
class ParentChildActions extends StatelessWidget {
  const ParentChildActions({super.key, required this.id, required this.name, required this.needsConsent});

  final int id;
  final String name;
  final bool needsConsent;

  @override
  Widget build(BuildContext context) {
    // a child tab can ask for the consent itself (403 consent_required, D-1371): the card follows on the way back
    void openTab(Route<void> route) {
      final p = context.read<ParentLinkProvider>();
      Navigator.of(context).push(route).then((_) {
        if (needsConsent) p.refreshChildrenAndRequests();
      });
    }

    return Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
      AppButton.secondary(
        key: ValueKey('parent.report.$id'),
        label: 'pl_tab_reports'.tr,
        icon: Icons.bar_chart_rounded,
        size: AppButtonSize.sm,
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ParentChildReportScreen(studentId: id, studentName: name))),
      ),
      // the child's games: stars, badges, rounds (D-1346; hidden with the Games tab)
      if (!gamesOff())
        AppButton.secondary(
          key: ValueKey('parent.games.$id'),
          label: gamesLabel(),
          icon: Icons.sports_esports_outlined,
          size: AppButtonSize.sm,
          onPressed: () => openTab(MaterialPageRoute<void>(
            settings: RouteSettings(name: '/parent/children/$id/games'),
            builder: (_) => paRole(ParentChildGamesPage(studentId: id, studentName: name)),
          )),
        ),
      // the child's Quran memorization by surah and juz (D-1347; hidden with the Quran tab)
      if (!quranOff())
        AppButton.secondary(
          key: ValueKey('parent.quran.$id'),
          label: t('القرآن', 'Quran'),
          icon: Icons.menu_book_rounded,
          size: AppButtonSize.sm,
          onPressed: () => openTab(MaterialPageRoute<void>(
            settings: RouteSettings(name: '/parent/children/$id/quran'),
            builder: (_) => paRole(QuranProgressPage.child(childId: id, name: name)),
          )),
        ),
      // the child's Arabic grammar progress per level and lesson (D-1349; hidden with the Grammar tab)
      if (!nahwOff())
        AppButton.secondary(
          key: ValueKey('parent.nahw.$id'),
          label: nahwLabel(),
          icon: Icons.short_text_rounded,
          size: AppButtonSize.sm,
          onPressed: () => openTab(MaterialPageRoute<void>(
            settings: RouteSettings(name: '/parent/children/$id/nahw'),
            builder: (_) => paRole(ParentChildNahwPage(studentId: id, studentName: name)),
          )),
        ),
      // withdraw this parent's consent (D-1371): the server says first whether there is one to withdraw
      if (!needsConsent && !(gamesOff() && quranOff() && nahwOff()))
        AppButton.ghost(
          key: ValueKey('consent.revoke.$id'),
          label: 'pa_withdraw_consent'.tr,
          size: AppButtonSize.sm,
          onPressed: () async {
            final p = context.read<ParentLinkProvider>();
            if (await revokeParentConsentFlow(context, id, name)) await p.refreshChildrenAndRequests();
          },
        ),
    ]);
  }
}

/// The consent sheet, then POST; the list follows.
Future<void> paGiveConsent(BuildContext context, int id, String name, String grade) async {
  final p = context.read<ParentLinkProvider>();
  if (!await showParentConsentDialog(context, childName: name, grade: grade)) return;
  final ok = await p.giveConsent(id);
  if (!ok) plToast(p.errorMessage);
}

bool _needsAttention(double? attendance, double? exams) =>
    (attendance != null && attendance < 60) || (exams != null && exams < 50);

