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
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppFill;
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
      // the queue is the page's one key figure: Pending is the sky block (information), the rest paper (D-612)
      AppKpiGrid(children: [
        AppKpiCard(icon: Icons.inbox_rounded, label: t('قيد المعالجة', 'Pending'), value: '${s.pending}', highlight: true, tone: AppBlockTone.sky, onTap: onTile == null ? null : () => onTile!('pending')),
        AppKpiCard(icon: Icons.gavel_rounded, label: t('بانتظار القرار', 'Pending decision'), value: '${s.pendingDecision}', onTap: onTile == null ? null : () => onTile!('pending_decision')),
        AppKpiCard(icon: Icons.timer_off_rounded, label: t('متأخرة', 'Overdue'), value: '${s.overdue}', onTap: onTile == null ? null : () => onTile!('overdue')),
        AppKpiCard(icon: Icons.task_alt_rounded, label: t('قرارات آخر 30 يوماً', 'Decided (30 d)'), value: '${s.decided30d}', onTap: onTile == null ? null : () => onTile!('decided')),
      ]),
      if (statuses.isNotEmpty) ...[
        const SizedBox(height: AppSpace.lg),
        Text(t('حسب الحالة', 'By status'), style: AppType.label(context)),
        const SizedBox(height: AppSpace.xs),
        // the split draws in once from the reading start (AppFill parks under Reduce motion)
        AppFill(
          value: 1,
          builder: (context, v) => ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.chip),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: v.clamp(0.0, 1.0),
              child: SizedBox(
                height: AppSpace.sm,
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final k in statuses) Expanded(flex: s.byStatus[k]!, child: ColoredBox(color: govStatusColor(context, k))),
                ]),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        Wrap(spacing: AppSpace.md, runSpacing: AppSpace.xs, children: [
          for (final k in statuses)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: AppSpace.xs, height: AppSpace.xs, decoration: BoxDecoration(color: govStatusColor(context, k), shape: BoxShape.circle)),
              const SizedBox(width: AppSpace.xxs),
              Flexible(child: Text('${itemStatusLabel(k)} ${s.byStatus[k]}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: c.textMedium))),
            ]),
        ]),
      ],
      if (s.byType.isNotEmpty) ...[
        const SizedBox(height: AppSpace.sm),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final e in s.byType.entries)
            if (e.value > 0) AppBadgePill('${itemTypeLabel(e.key)} ${e.value}', color: c.textMedium, icon: govTypeIcon(e.key)),
        ]),
      ],
      if (s.onTimePct != null) ...[
        const SizedBox(height: AppSpace.md),
        Row(children: [
          Expanded(child: Text(t('الالتزام بالمهلة', 'SLA on time'), style: AppType.meta(context).copyWith(color: c.textLight))),
          Text('${s.onTimePct!.toStringAsFixed(0)}%', style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: appScoreColor(context, s.onTimePct))),
        ]),
        const SizedBox(height: AppSpace.xs),
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
      body = const AppShimmer(
          child: Column(children: [
        AppSkeletonBox(height: AppSpace.xxxl + AppSpace.lg, width: double.infinity),
        SizedBox(height: AppSpace.lg),
        AppSkeletonBox(height: AppSpace.sm, width: double.infinity),
      ]));
    } else if (_missing) {
      body = Text(t('تحتاج تحديث الخادم', 'Needs a server update'), style: AppType.label(context).copyWith(color: c.textMedium));
    } else if (_stats == null) {
      body = TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh_rounded), label: Text(t('إعادة المحاولة', 'Retry')));
    } else {
      body = GovDashboardBody(stats: _stats!, onTile: _openTile, compact: widget.compact);
    }
    return AppCard(
      margin: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.xs),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.account_tree_rounded, size: AppIconSize.md, color: c.textMedium),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: Text(widget.title ?? t('الطلبات والمعاملات', 'Requests & workflow'),
                maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
          ),
          IconButton(tooltip: t('تحديث', 'Refresh'), onPressed: _load, icon: Icon(Icons.refresh_rounded, size: AppIconSize.md, color: c.textMedium)),
        ]),
        const SizedBox(height: AppSpace.md),
        body,
      ]),
    );
  }
}
