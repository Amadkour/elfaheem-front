// lib/features/org/governance/gov_dashboard.dart — the governance numbers of the organization or one entity
// (spec §4 `GET …/dashboard?dept_id=`): pending · pending decision · overdue · decided (30 d) tiles, the
// by-status bar, the SLA on-time share. Every tile opens the unified list on the matching filter.
//
//   GovDashboardStats   pure (fromJson)
//   GovDashboardBody    presentational (layout-tested)
//   GovDashboardCard    loads and shows it
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:provider/provider.dart';

import '../../admin/admin_common.dart' show asDouble, asInt, asMap, t;
import '../org_providers.dart' show OrgSession;
import '../org_v3.dart' show orgCall;
import 'gov_api.dart';
import 'gov_filter.dart';
import 'gov_items_page.dart';
import 'gov_models.dart';
import 'gov_ui.dart';

class GovDashboardStats {
  const GovDashboardStats({this.pending = 0, this.pendingDecision = 0, this.overdue = 0, this.decided30d = 0, this.byStatus = const {}, this.byType = const {}, this.onTimePct});
  final int pending, pendingDecision, overdue, decided30d;
  final Map<String, int> byStatus, byType;
  final double? onTimePct;

  factory GovDashboardStats.fromJson(Map<String, dynamic> j) => GovDashboardStats(
        pending: asInt(j['pending']),
        pendingDecision: asInt(j['pending_decision']),
        overdue: asInt(j['overdue']),
        decided30d: asInt(j['decided_30d']),
        byStatus: {for (final e in asMap(j['by_status']).entries) e.key: asInt(e.value)},
        byType: {for (final e in asMap(j['by_type']).entries) e.key: asInt(e.value)},
        onTimePct: asMap(j['sla'])['on_time_pct'] == null ? null : asDouble(asMap(j['sla'])['on_time_pct']),
      );

  int get total => byStatus.values.fold(0, (a, b) => a + b);
}

/// Filters behind the four tiles.
ItemFilter dashboardTileFilter(String tile) => switch (tile) {
      'pending' => const ItemFilter(statuses: ['open', 'in_review', 'pending_approval', 'in_council']),
      'pending_decision' => const ItemFilter(toMe: true),
      'overdue' => const ItemFilter(overdue: true),
      'decided' => ItemFilter(statuses: const ['approved', 'rejected'], dateFrom: DateTime.now().subtract(const Duration(days: 30))),
      _ => const ItemFilter(),
    };

class GovDashboardBody extends StatelessWidget {
  const GovDashboardBody({super.key, required this.stats, this.onTile, this.compact = false});
  final GovDashboardStats stats;
  final ValueChanged<String>? onTile;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = stats;
    final statuses = itemStatuses.where((k) => (s.byStatus[k] ?? 0) > 0).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppGrid(padding: EdgeInsets.zero, minTile: compact ? 140 : 170, children: [
        AppStatTile(icon: Icons.inbox_rounded, label: t('قيد المعالجة', 'Pending'), value: s.pending, color: c.primary, onTap: onTile == null ? null : () => onTile!('pending')),
        AppStatTile(icon: Icons.gavel_rounded, label: t('بانتظار القرار', 'Pending decision'), value: s.pendingDecision, color: c.warning, onTap: onTile == null ? null : () => onTile!('pending_decision')),
        AppStatTile(icon: Icons.timer_off_rounded, label: t('متأخرة', 'Overdue'), value: s.overdue, color: c.danger, onTap: onTile == null ? null : () => onTile!('overdue')),
        AppStatTile(icon: Icons.task_alt_rounded, label: t('قرارات آخر 30 يوماً', 'Decided (30 d)'), value: s.decided30d, color: c.success, onTap: onTile == null ? null : () => onTile!('decided')),
      ]),
      if (statuses.isNotEmpty) ...[
        const SizedBox(height: 14),
        Text(t('حسب الحالة', 'By status'), style: appText(12, c: c.textLight)),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 12,
            child: Row(children: [
              for (final k in statuses) Expanded(flex: s.byStatus[k]!, child: Container(color: govStatusColor(context, k))),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 6, children: [
          for (final k in statuses)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: govStatusColor(context, k), shape: BoxShape.circle)),
              const SizedBox(width: 5),
              Flexible(child: Text('${itemStatusLabel(k)} ${s.byStatus[k]}', maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(11.5, w: FontWeight.w600, c: c.textMedium))),
            ]),
        ]),
      ],
      if (s.byType.isNotEmpty) ...[
        const SizedBox(height: 12),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final e in s.byType.entries)
            if (e.value > 0) AppBadgePill('${itemTypeLabel(e.key)} ${e.value}', color: c.textMedium, icon: govTypeIcon(e.key)),
        ]),
      ],
      if (s.onTimePct != null) ...[
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: Text(t('الالتزام بالمهلة', 'SLA on time'), style: appText(12, c: c.textLight))),
          Text('${s.onTimePct!.toStringAsFixed(0)}%', style: appText(13, w: FontWeight.w800, c: appScoreColor(context, s.onTimePct))),
        ]),
        const SizedBox(height: 6),
        AppProgressBar(value: s.onTimePct, max: 100),
      ],
    ]);
  }
}

class GovDashboardCard extends StatefulWidget {
  const GovDashboardCard({super.key, this.deptId, this.orgId, this.title, this.compact = false});
  final int? deptId, orgId;
  final String? title;
  final bool compact;

  @override
  State<GovDashboardCard> createState() => _GovDashboardCardState();
}

class _GovDashboardCardState extends State<GovDashboardCard> {
  GovDashboardStats? _stats;
  bool _failed = false, _missing = false;

  int get _orgId => widget.orgId ?? context.read<OrgSession>().currentId ?? 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final r = await orgCall(() => GovApi(_orgId).dashboard(deptId: widget.deptId), quiet: true);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _stats = GovDashboardStats.fromJson(r.map);
        _failed = false;
      } else {
        _failed = true;
        _missing = r.endpointMissing;
      }
    });
  }

  void _openTile(String tile) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => GovItemsPage(
              deptId: widget.deptId,
              orgId: _orgId,
              initial: dashboardTileFilter(tile),
              title: widget.title,
            )));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget body;
    if (_stats == null && !_failed) {
      body = const AppShimmer(child: Column(children: [AppSkeletonBox(height: 70, width: double.infinity), SizedBox(height: 10), AppSkeletonBox(height: 12, width: double.infinity)]));
    } else if (_missing) {
      body = Text(t('تحتاج تحديث الخادم', 'Needs a server update'), style: appText(12.5, c: c.textMedium));
    } else if (_stats == null) {
      body = TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh_rounded), label: Text(t('إعادة المحاولة', 'Retry')));
    } else {
      body = GovDashboardBody(stats: _stats!, onTile: _openTile, compact: widget.compact);
    }
    return AppCard(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.account_tree_rounded, size: 18, color: c.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(widget.title ?? t('الطلبات والمعاملات', 'Requests & workflow'), style: appText(14.5, w: FontWeight.w800, c: c.textDark))),
          IconButton(tooltip: t('تحديث', 'Refresh'), visualDensity: VisualDensity.compact, onPressed: _load, icon: Icon(Icons.refresh_rounded, size: 18, color: c.textLight)),
        ]),
        const SizedBox(height: 10),
        body,
      ]),
    );
  }
}
