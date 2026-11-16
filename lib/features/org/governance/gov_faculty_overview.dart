// lib/features/org/governance/gov_faculty_overview.dart — the faculty overview (Institutions S5, D-979): the dean's
// view across every department, from `GET …/governance/dashboard?scope=faculty` (`faculty` block; absent for anyone
// else). Per department: open · overdue · escalated · council items pending a vote · sessions closing soon.
//
//   FacultyOverview / FacultyRow   pure (fromJson; null when the server sent no `faculty` block)
//   facultyRowFilter               the items-list filter behind a row (or one of its figures)
//   OrgFacultyOverviewCard         the home card: static, no request (shown from `can_faculty_overview`)
//   FacultyOverviewBody            presentational (layout-tested): totals, then cards on phones / a table on wide
//   FacultyOverviewPage            loads it, Refresh, a tap opens GovItemsPage on the row's filter
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:provider/provider.dart';

import '../../admin/admin_common.dart' show asInt, asMap, asMapList, t;
import '../org_page_header.dart' show OrgPageRefresh;
import '../org_page_kit.dart' show OrgPageBody, orgPageWideFrom;
import '../org_providers.dart' show OrgSession;
import '../org_v3.dart' show orgCall, orgErrorText;
import 'gov_api.dart';
import 'gov_filter.dart';
import 'gov_items_page.dart';

/// The five figures of a row, in display order.
const facultyMetrics = ['open', 'overdue', 'escalated', 'council_pending', 'sessions_closing'];

String facultyMetricLabel(String k) => switch (k) {
      'open' => t('مفتوحة', 'Open'),
      'overdue' => t('متأخرة', 'Overdue'),
      'escalated' => t('مصعَّدة', 'Escalated'),
      'council_pending' => t('بنود تنتظر التصويت', 'Awaiting a vote'),
      'sessions_closing' => t('جلسات تُغلق قريباً', 'Sessions closing'),
      _ => k,
    };

IconData facultyMetricIcon(String k) => switch (k) {
      'overdue' => Icons.timer_off_rounded,
      'escalated' => Icons.trending_up_rounded,
      'council_pending' => Icons.how_to_vote_rounded,
      'sessions_closing' => Icons.event_busy_rounded,
      _ => Icons.inbox_rounded,
    };

class FacultyRow {
  const FacultyRow({
    required this.id,
    this.nameAr = '',
    this.nameEn = '',
    this.kind = 'service',
    this.councilLevel,
    this.hasCouncil = false,
    this.counts = const {},
  });

  final int id;
  final String nameAr, nameEn, kind;

  /// `department` (its council folds into it) · `faculty` (the faculty council's own row) · null.
  final String? councilLevel;
  final bool hasCouncil;
  final Map<String, int> counts;

  String get name {
    final n = AppConfig.lang == 'ar' ? (nameAr.isNotEmpty ? nameAr : nameEn) : (nameEn.isNotEmpty ? nameEn : nameAr);
    return n.isEmpty ? '#$id' : n;
  }

  int count(String k) => counts[k] ?? 0;
  bool get isCouncil => kind == 'council';
  bool get isQuiet => facultyMetrics.every((k) => count(k) == 0);

  factory FacultyRow.fromJson(Map<String, dynamic> j) => FacultyRow(
        id: asInt(j['id']),
        nameAr: '${j['name_ar'] ?? ''}',
        nameEn: '${j['name_en'] ?? ''}',
        kind: '${j['kind'] ?? 'service'}',
        councilLevel: j['council_level'] == null ? null : '${j['council_level']}',
        hasCouncil: j['has_council'] == true,
        counts: {for (final k in facultyMetrics) k: asInt(j[k])},
      );
}

class FacultyOverview {
  const FacultyOverview({
    this.scope = 'all',
    this.portfolios = const [],
    this.closingHours = 48,
    this.totals = const {},
    this.rows = const [],
  });

  /// `all` · `portfolio` (a vice dean: the departments of [portfolios] only).
  final String scope;
  final List<String> portfolios;
  final int closingHours;
  final Map<String, int> totals;
  final List<FacultyRow> rows;

  bool get isPortfolio => scope == 'portfolio';

  /// The `faculty` block of the dashboard answer; null when it is absent (not a dean / vice dean / admin, or an
  /// older server).
  static FacultyOverview? fromDashboard(Map<String, dynamic> dashboard) {
    final f = dashboard['faculty'];
    if (f is! Map) return null;
    final j = asMap(f);
    final t = asMap(j['totals']);
    return FacultyOverview(
      scope: '${j['scope'] ?? 'all'}',
      portfolios: [for (final p in (j['portfolios'] is List ? j['portfolios'] as List : const [])) '$p'],
      closingHours: j['closing_hours'] == null ? 48 : asInt(j['closing_hours']),
      totals: {for (final k in facultyMetrics) k: asInt(t[k])},
      rows: [for (final r in asMapList(j['departments'])) FacultyRow.fromJson(r)],
    );
  }
}

const _openStatuses = ['open', 'in_review', 'pending_approval', 'in_council', 'postponed'];

/// The items list behind a row ([metric] null = its open items). Sessions closing has no item filter: it opens
/// the row's items in a council.
ItemFilter facultyRowFilter(int deptId, [String? metric]) => switch (metric) {
      'overdue' => ItemFilter(deptId: deptId, overdue: true),
      'escalated' => ItemFilter(deptId: deptId, escalated: true),
      'council_pending' || 'sessions_closing' => ItemFilter(deptId: deptId, statuses: const ['in_council']),
      _ => ItemFilter(deptId: deptId, statuses: _openStatuses),
    };

/// The tone of a figure: overdue / escalated warn when above zero, everything else stays quiet.
Color _metricColor(BuildContext context, String k, int n) {
  final c = context.colors;
  if (n == 0) return c.textLight;
  return switch (k) {
    'overdue' => c.danger,
    'escalated' || 'sessions_closing' => c.warning,
    _ => c.textMedium,
  };
}

// ═════════════════════════════════════════════════════════════════════════════
//  Home card (static: no request of its own)
// ═════════════════════════════════════════════════════════════════════════════

class OrgFacultyOverviewCard extends StatelessWidget {
  const OrgFacultyOverviewCard({super.key, required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      onTap: onOpen,
      child: Semantics(
        button: true,
        label: t('نظرة على الكلية', 'Faculty overview'),
        excludeSemantics: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTouch.min),
          child: Row(children: [
            Icon(Icons.account_balance_rounded, size: AppIconSize.md, color: c.primary),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(t('نظرة على الكلية', 'Faculty overview'), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
                const SizedBox(height: AppSpace.xxs),
                Text(t('الطلبات والمجالس في كل إدارة', 'Requests and councils in every department'),
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textMedium)),
              ]),
            ),
            const SizedBox(width: AppSpace.xs),
            Icon(Icons.chevron_right_rounded, size: AppIconSize.sm, color: c.textLight),
          ]),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Body (plain values)
// ═════════════════════════════════════════════════════════════════════════════

class FacultyOverviewBody extends StatelessWidget {
  const FacultyOverviewBody({super.key, required this.data, this.onOpen});
  final FacultyOverview data;

  /// A row ([metric] null) or one of its figures was tapped.
  final void Function(FacultyRow row, String? metric)? onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= orgPageWideFrom;
      final note = data.isPortfolio
          ? t('تعرض إدارات ملفك فقط ومجلس الكلية', 'Showing the departments of your portfolio and the faculty council')
          : null;
      return ListView(padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.xxl), children: [
        AppKpiGrid(children: [
          for (final k in facultyMetrics)
            AppKpiCard(
              icon: facultyMetricIcon(k),
              label: k == 'sessions_closing'
                  ? t('جلسات تُغلق خلال ${data.closingHours} ساعة', 'Sessions closing in ${data.closingHours} h')
                  : facultyMetricLabel(k),
              value: '${data.totals[k] ?? 0}',
              highlight: k == 'overdue' && (data.totals[k] ?? 0) > 0,
              tone: k == 'overdue' && (data.totals[k] ?? 0) > 0 ? AppBlockTone.peach : null,
            ),
        ]),
        if (note != null) ...[
          const SizedBox(height: AppSpace.sm),
          Text(note, style: AppType.meta(context).copyWith(color: c.textMedium)),
        ],
        const SizedBox(height: AppSpace.lg),
        Text(t('الإدارات', 'Departments'), style: AppType.section(context)),
        const SizedBox(height: AppSpace.sm),
        if (data.rows.isEmpty)
          AppEmpty(icon: Icons.account_tree_rounded, title: t('لا توجد إدارات بعد', 'No departments yet'))
        else if (wide)
          _FacultyTable(rows: data.rows, onOpen: onOpen)
        else
          for (final r in data.rows) ...[
            _FacultyRowCard(row: r, onOpen: onOpen),
            const SizedBox(height: AppSpace.sm),
          ],
      ]);
    });
  }
}

/// A phone row: the department, then its figures as a wrap of tappable chips (never a table).
class _FacultyRowCard extends StatelessWidget {
  const _FacultyRowCard({required this.row, this.onOpen});
  final FacultyRow row;
  final void Function(FacultyRow row, String? metric)? onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      onTap: onOpen == null ? null : () => onOpen!(row, null),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(row.isCouncil ? Icons.groups_rounded : Icons.apartment_rounded, size: AppIconSize.md, color: c.textMedium),
          const SizedBox(width: AppSpace.xs),
          Expanded(child: Text(row.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context))),
          Icon(Icons.chevron_right_rounded, size: AppIconSize.sm, color: c.textLight),
        ]),
        const SizedBox(height: AppSpace.xs),
        if (row.isQuiet)
          Text(t('لا شيء ينتظر', 'Nothing waiting'), style: AppType.meta(context).copyWith(color: c.textLight))
        else
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
            for (final k in facultyMetrics)
              if (row.count(k) > 0) _MetricChip(metric: k, value: row.count(k), onTap: onOpen == null ? null : () => onOpen!(row, k)),
          ]),
      ]),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.metric, required this.value, this.onTap});
  final String metric;
  final int value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final col = _metricColor(context, metric, value);
    final label = '${facultyMetricLabel(metric)} $value';
    return Semantics(
      button: onTap != null,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTouch.min),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(child: AppBadgePill(label, color: col, icon: facultyMetricIcon(metric))),
          ]),
        ),
      ),
    );
  }
}

/// Wide screens: one row per department with a column per figure, scrolled sideways when it does not fit.
class _FacultyTable extends StatelessWidget {
  const _FacultyTable({required this.rows, this.onOpen});
  final List<FacultyRow> rows;
  final void Function(FacultyRow row, String? metric)? onOpen;

  static const double _nameWidth = AppSpace.xxxl * 5;
  static const double _cellWidth = AppSpace.xxxl * 2 + AppSpace.lg;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget cell(Widget child) => SizedBox(width: _cellWidth, child: Center(child: child));
    final header = Row(children: [
      SizedBox(width: _nameWidth, child: Text(t('الإدارة', 'Department'), style: AppType.label(context).copyWith(color: c.textMedium))),
      for (final k in facultyMetrics)
        cell(Text(facultyMetricLabel(k), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: AppType.meta(context).copyWith(color: c.textMedium, fontWeight: FontWeight.w600))),
    ]);
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      child: AppHScroll(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs), child: header),
          for (final r in rows) ...[
            Divider(height: 1, color: c.divider),
            InkWell(
              onTap: onOpen == null ? null : () => onOpen!(r, null),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: AppTouch.min),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                  child: Row(children: [
                    SizedBox(
                      width: _nameWidth,
                      child: Row(children: [
                        Icon(r.isCouncil ? Icons.groups_rounded : Icons.apartment_rounded, size: AppIconSize.sm, color: c.textLight),
                        const SizedBox(width: AppSpace.xs),
                        Expanded(child: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context))),
                      ]),
                    ),
                    for (final k in facultyMetrics)
                      cell(Semantics(
                        button: onOpen != null && r.count(k) > 0,
                        label: '${r.name} · ${facultyMetricLabel(k)} ${r.count(k)}',
                        excludeSemantics: true,
                        child: InkWell(
                          onTap: onOpen == null || r.count(k) == 0 ? null : () => onOpen!(r, k),
                          borderRadius: BorderRadius.circular(AppRadius.chip),
                          child: SizedBox(
                            width: AppTouch.min,
                            height: AppTouch.min,
                            child: Center(
                              child: Text('${r.count(k)}',
                                  style: AppType.figure(context).copyWith(color: _metricColor(context, k, r.count(k)))),
                            ),
                          ),
                        ),
                      )),
                  ]),
                ),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Page
// ═════════════════════════════════════════════════════════════════════════════

class FacultyOverviewPage extends StatefulWidget {
  const FacultyOverviewPage({super.key, this.orgId});

  /// Defaults to the selected organization of `OrgSession`.
  final int? orgId;

  @override
  State<FacultyOverviewPage> createState() => _FacultyOverviewPageState();
}

class _FacultyOverviewPageState extends State<FacultyOverviewPage> {
  FacultyOverview? _data;
  bool _loading = true, _denied = false;
  String? _error;
  OrgPageRefresh? _refresh;

  int get _orgId => widget.orgId ?? context.read<OrgSession>().currentId ?? 0;

  @override
  void initState() {
    super.initState();
    _refresh = OrgPageRefresh.register(context, _load);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _refresh?.unregister(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final r = await orgCall(() => GovApi(_orgId).facultyDashboard(), quiet: true);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.ok) {
        _data = FacultyOverview.fromDashboard(r.map);
        _denied = _data == null;
        _error = null;
      } else {
        _error = orgErrorText(r.error!);
      }
    });
    if (r.ok && mounted) OrgPageRefresh.reportUpdated(context);
  }

  void _open(FacultyRow row, String? metric) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => GovItemsPage(deptId: row.id, orgId: _orgId, title: row.name, initial: facultyRowFilter(row.id, metric))));
  }

  @override
  Widget build(BuildContext context) {
    final Widget child;
    if (_loading) {
      child = const AppListSkeleton(items: 5, withAvatar: false);
    } else if (_error != null) {
      child = AppEmpty(icon: Icons.cloud_off_rounded, title: _error!, actionLabel: t('إعادة المحاولة', 'Retry'), onAction: _load);
    } else if (_denied) {
      child = AppEmpty(
          icon: Icons.lock_outline_rounded,
          title: t('هذه النظرة للعميد والوكلاء ومدير المؤسسة', 'This overview is for the dean, the vice deans and the admin'));
    } else {
      child = AppRefresh(onRefresh: _load, child: FacultyOverviewBody(data: _data!, onOpen: _open));
    }
    return OrgPageBody(child: child);
  }
}
