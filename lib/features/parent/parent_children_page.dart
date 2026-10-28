// lib/features/parent/parent_children_page.dart — the linked children of the parent.
// One card per child, in the same design system as the student / teacher analytics:
//   photo · name · one warm sentence (strongest / weakest area) · progress / attendance / exams rings ·
//   unread alerts · courses that need attention.  Tap → the child's full report.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../shared/analytics/analytics_ui.dart';
import '../teacher/data_lab/data_lab_models.dart' show DlProfile;
import 'parent_link_providers.dart';
import 'parent_reports_page.dart';
import 'parent_widgets.dart';
import '../shared/inbox/unified_inbox.dart' show InboxPreviewCard;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show ErrorRetry;

class ParentChildrenPage extends StatefulWidget {
  const ParentChildrenPage({super.key, required this.onOpenLinkTab});

  final VoidCallback onOpenLinkTab;

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
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          // requests · announcements · offers for the parent, in the same inbox pattern as every role
          const InboxPreviewCard(padding: EdgeInsets.only(bottom: 14)),
          for (final ch in p.children)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _ChildCard(
                data: ch,
                profile: p.profiles[(ch['id'] as num).toInt()],
                profileLoaded: p.profiles.containsKey((ch['id'] as num).toInt()),
                unreadAlerts: unread[(ch['id'] as num).toInt()] ?? 0,
              ),
            ),
          Center(
            child: TextButton.icon(
              onPressed: widget.onOpenLinkTab,
              icon: const Icon(Icons.add_link_rounded, size: 18),
              label: Text(anTr('pl_link_another', 'Link another child')),
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
    final c = context.colors;
    final id = (data['id'] as num).toInt();
    final name = '${data['name']}';
    final pr = profile;
    final attention = pr?.courses.where((b) => _needsAttention(b.attendance, b.examAvg)).length ?? 0;
    void open() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ParentChildReportScreen(studentId: id, studentName: name)));
    return AnCard(
      padding: EdgeInsets.zero,
      borderColor: attention > 0 ? c.warning.withValues(alpha: 0.45) : null,
      onTap: open,
      child: Column(children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 12, 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
              colors: [c.primary.withValues(alpha: 0.10), Colors.transparent],
            ),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c.primary, width: 1.6)),
              child: AnAvatar(name: name, url: '${data['image_url'] ?? ''}', size: 54),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: anText(17, w: FontWeight.w800, c: c.textDark)),
                const SizedBox(height: 3),
                Text(
                  pr != null
                      ? anInsightSentence(pr.progress, pr.attendance, pr.examAvg, mine: false)
                      : '${'pl_linked_at'.tr} ${plDateTime(data['linked_at'])}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: anText(12, c: c.textMedium, h: 1.45),
                ),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, color: c.textLight),
          ]),
        ),
        if (!profileLoaded)
          const Padding(padding: EdgeInsets.fromLTRB(16, 8, 16, 8), child: LinearProgressIndicator(minHeight: 3))
        else if (pr != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              AnRing(value: pr.progress, size: 62, stroke: 6, label: 'dl_progress'.tr),
              AnRing(value: pr.attendance, size: 62, stroke: 6, label: 'dl_attendance'.tr),
              AnRing(value: pr.examAvg, size: 62, stroke: 6, label: 'dl_exams'.tr),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              AnChip(icon: Icons.insights_rounded, label: 'pl_tab_reports'.tr, color: c.primary, onTap: open),
              if (pr != null) AnTag('${pr.courses.length} ${anTr('an_courses', 'Courses')}', c.accent2, icon: Icons.menu_book_rounded),
              if (attention > 0)
                AnTag(anFmt('pl_attention_courses', {'n': attention}, '{n} need attention'), c.warning, icon: Icons.volunteer_activism_rounded),
              if (unreadAlerts > 0)
                AnTag(anFmt('pl_unread_alerts', {'n': unreadAlerts}, '{n} new alerts'), c.danger, icon: Icons.notifications_active_rounded),
            ]),
          ),
        ),
      ]),
    );
  }
}

bool _needsAttention(double? attendance, double? exams) =>
    (attendance != null && attendance < 60) || (exams != null && exams < 50);
