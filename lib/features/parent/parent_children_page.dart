// lib/features/parent/parent_children_page.dart — the linked children of the parent.
// One card per child, in the same design system as the student / teacher analytics:
//   photo · name · one warm sentence (strongest / weakest area) · progress / attendance / exams rings ·
//   unread alerts · courses that need attention.  Tap → the child's panel (D-290: their courses, grades and history,
//   as the child sees them); the Reports chip and the panel's action → the child's full report.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import 'package:flutter_education_app/features/analytics/analytics_ui.dart';
import 'package:flutter_education_app/features/data_lab/data_lab_models.dart' show DlProfile;
import 'parent_consent.dart';
import 'parent_link_providers.dart';
import 'parent_reports_page.dart';
import 'parent_widgets.dart';
import 'package:flutter_education_app/features/messaging/inbox/unified_inbox.dart' show InboxEntryCard;
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppReveal;
import 'package:flutter_education_app/design/master_detail/entity_detail_view.dart' show EntityPanelAction;
import 'package:flutter_education_app/design/master_detail/entity_navigator.dart';
import 'package:flutter_education_app/design/master_detail/entity_panel_controller.dart';
import 'package:flutter_education_app/design/master_detail/master_detail_scaffold.dart';
import 'package:flutter_education_app/features/games/games_api.dart' show gamesOff, gamesLabel;
import 'package:flutter_education_app/features/games/games_progress.dart' show ParentChildGamesPage;
import 'package:flutter_education_app/features/admin/admin_common.dart' show ErrorRetry;

class ParentChildrenPage extends StatefulWidget {
  const ParentChildrenPage({super.key, required this.onOpenLinkTab});

  final VoidCallback onOpenLinkTab;

  @override
  State<ParentChildrenPage> createState() => _ParentChildrenPageState();
}

class _ParentChildrenPageState extends State<ParentChildrenPage> {
  final _panel = EntityPanelController(rowKind: EntityKind.student);

  @override
  void dispose() {
    _panel.dispose();
    super.dispose();
  }

  void _openReport(BuildContext context, int id, String name) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => ParentChildReportScreen(studentId: id, studentName: name)));

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
  Widget build(BuildContext context) => MasterDetailScaffold(
        controller: _panel,
        rootLabel: 'md_p7_my_children'.tr,
        actions: (ref, s) => [
          if (ref.kind == EntityKind.student)
            EntityPanelAction(
              icon: Icons.insights_rounded,
              label: 'pl_view_report'.tr,
              primary: true,
              onPressed: () => _openReport(context, ref.id, ref.name),
            ),
        ],
        list: Builder(builder: _list),
      );

  Widget _list(BuildContext context) {
    final p = context.watch<ParentLinkProvider>();
    final unread = _unread(context);
    _panel.siblings = [
      for (final ch in p.children) EntityRef(EntityKind.student, (ch['id'] as num).toInt(), label: '${ch['name']}'),
    ];

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
        actionLabel: 'pl_link_child'.tr,
        onAction: widget.onOpenLinkTab,
      );
    }

    return AppRefresh(
      onRefresh: p.loadAll,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.xl),
        children: [
          // requests · announcements · offers for the parent: ONE entry into the inbox, as on every role's home
          const InboxEntryCard(padding: EdgeInsets.only(bottom: AppSpace.md)),
          for (final (i, ch) in p.children.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.md),
              // the one entrance of the page: the children's blocks, in order
              child: AppReveal(
                index: i,
                group: 'parent.children',
                child: _ChildCard(
                  data: ch,
                  profile: p.profiles[(ch['id'] as num).toInt()],
                  profileLoaded: p.profiles.containsKey((ch['id'] as num).toInt()),
                  unreadAlerts: unread[(ch['id'] as num).toInt()] ?? 0,
                ),
              ),
            ),
          Center(
            child: AppButton(
              label: anTr('pl_link_another', 'Link another child'),
              icon: Icons.add_link_rounded,
              variant: AppButtonVariant.ghost,
              onPressed: widget.onOpenLinkTab,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChildCard extends StatelessWidget {
  const _ChildCard({required this.data, required this.profile, required this.profileLoaded, required this.unreadAlerts});

  final Map<String, dynamic> data;
  final DlProfile? profile;
  final bool profileLoaded;
  final int unreadAlerts;

  @override
  Widget build(BuildContext context) {
    final id = (data['id'] as num).toInt();
    final name = '${data['name']}';
    final pr = profile;
    final attention = pr?.courses.where((b) => _needsAttention(b.attendance, b.examAvg)).length ?? 0;
    void report() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ParentChildReportScreen(studentId: id, studentName: name)));
    // The child's own tone (the same one their report hero wears): a parent learns each child's colour.
    return AppBlock(
      tone: parentChildTone(id),
      semanticLabel: name,
      onTap: () => EntityNavigator.open(context, EntityRef(EntityKind.student, id, label: name)),
      child: Builder(builder: (context) {
        final b = AppBlock.colorsOf(context);
        Widget ring(double? v, String label) => Flexible(
              child: AnRing(value: v, size: AppTouch.min + AppSpace.sm, stroke: AppSpace.xxs * 1.5, label: label, color: b.accentInk(anScoreColor(context, v))),
            );
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            AnAvatar(name: name, url: '${data['image_url'] ?? ''}', size: AppTouch.min + AppSpace.xs),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.section(context).copyWith(color: b.ink)),
                const SizedBox(height: AppSpace.xxs),
                Text(
                  pr != null
                      ? anInsightSentence(pr.progress, pr.attendance, pr.examAvg, mine: false)
                      : '${'pl_linked_at'.tr} ${plDateTime(data['linked_at'])}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.meta(context).copyWith(color: b.muted),
                ),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, color: b.muted),
          ]),
          if (!profileLoaded)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpace.md),
              child: LinearProgressIndicator(minHeight: AppSpace.xxs),
            )
          else if (pr != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                ring(pr.progress, 'dl_progress'.tr),
                ring(pr.attendance, 'dl_attendance'.tr),
                ring(pr.examAvg, 'dl_exams'.tr),
              ]),
            )
          else
            const SizedBox(height: AppSpace.md),
          if (data['needs_consent'] == true) ...[
            ConsentNeededNotice(onGive: () => _giveConsent(context, id, name)),
            const SizedBox(height: AppSpace.sm),
          ],
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
            AppButton(label: 'pl_tab_reports'.tr, icon: Icons.insights_rounded, variant: AppButtonVariant.secondary, size: AppButtonSize.sm, onPressed: report),
            // the child's games: stars, badges, rounds (D-1346; hidden with the Games tab)
            if (!gamesOff())
              AppButton(
                key: ValueKey('parent.games.$id'),
                label: gamesLabel(),
                icon: Icons.extension_rounded,
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.sm,
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  settings: RouteSettings(name: '/parent/children/$id/games'),
                  builder: (_) => ParentChildGamesPage(studentId: id, studentName: name),
                )),
              ),
            if (pr != null) AppStatusBadge(label: '${pr.courses.length} ${anTr('an_courses', 'Courses')}', icon: Icons.menu_book_rounded),
            if (attention > 0)
              AppStatusBadge(
                label: anFmt('pl_attention_courses', {'n': attention}, '{n} need attention'),
                tone: AppTone.warning,
                icon: Icons.volunteer_activism_rounded,
              ),
            if (unreadAlerts > 0)
              AppStatusBadge(
                label: anFmt('pl_unread_alerts', {'n': unreadAlerts}, '{n} new alerts'),
                tone: AppTone.danger,
                icon: Icons.notifications_active_rounded,
              ),
          ]),
        ]);
      }),
    );
  }
}

Future<void> _giveConsent(BuildContext context, int id, String name) async {
  final p = context.read<ParentLinkProvider>();
  if (!await showParentConsentDialog(context, childName: name)) return;
  final ok = await p.giveConsent(id);
  if (!ok) plToast(p.errorMessage);
}

bool _needsAttention(double? attendance, double? exams) =>
    (attendance != null && attendance < 60) || (exams != null && exams < 50);
