// lib/features/org/advising/adv_advisors_stats_page.dart — the advisors table of the advising analytics (Phase 8,
// docs/advising/PHASE8.md `GET /analytics/advisors`, manage · aggregate): each advisor's load, students at risk /
// without contact, meetings, replies, notes and activity in the dashboard's range. Cards on phones, a scrollable
// table on wide screens; one search, one order; the facets (active · inactive · over · warn) as calm counts. A
// director taps an advisor to see their students (the drill-down `advisor`).
//
//   AdvAdvisorStatsView   the list (plain values)      AdvAdvisorStatsPage   loads it
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t;
import '../org_page_header.dart' show OrgPageRefresh, OrgPushedPage;
import '../org_page_kit.dart';
import '../org_v3.dart' show orgCall;
import 'adv_analytics_api.dart';
import 'adv_analytics_models.dart';
import 'adv_analytics_parts.dart';
import 'adv_drill_page.dart';
import 'adv_models.dart' show AdvPage;
import 'adv_parts.dart';

class AdvAdvisorStatsView extends StatelessWidget {
  const AdvAdvisorStatsView({
    super.key,
    required this.load,
    this.page,
    this.sort = 'load',
    this.errorText,
    this.onRetry,
    this.onSearch,
    this.onSort,
    this.onPage,
    this.onOpen,
  });

  final AdvLoad load;
  final AdvPage<AdvAdvisorStat>? page;
  final String sort;
  final String? errorText;
  final VoidCallback? onRetry;
  final ValueChanged<String>? onSearch, onSort;
  final ValueChanged<int>? onPage;

  /// An advisor → their students (manage); null for the aggregate tier.
  final ValueChanged<AdvAdvisorStat>? onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = page;
    Widget body;
    if (load != AdvLoad.ready || p == null) {
      body = AdvLoadState(state: load == AdvLoad.ready ? AdvLoad.loading : load, errorText: errorText, onRetry: onRetry);
    } else if (p.items.isEmpty) {
      body = AppEmpty(icon: Icons.supervisor_account_rounded, title: t('لا مرشدين هنا', 'No advisors here'), message: t('جرّب بحثاً آخر.', 'Try another search.'));
    } else {
      body = LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 900;
        return AdvPageFrame(maxWidth: wide ? 1240 : 880, children: [
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            AppBadgePill(advAdvisorsText(p.total), color: c.textMedium, icon: Icons.supervisor_account_rounded),
            if (p.facet('active') > 0) AppBadgePill(t('نشطون · ${p.facet('active')}', 'Active · ${p.facet('active')}'), color: c.success, icon: Icons.bolt_rounded),
            if (p.facet('inactive') > 0) AppBadgePill(t('غير نشطين · ${p.facet('inactive')}', 'Inactive · ${p.facet('inactive')}'), color: c.textMedium, icon: Icons.bedtime_outlined),
            if (p.facet('warn') > 0) AppBadgePill(t('قرب الحد · ${p.facet('warn')}', 'Near the maximum · ${p.facet('warn')}'), color: c.warning),
            if (p.facet('over') > 0) AppBadgePill(t('فوق الحد · ${p.facet('over')}', 'Over the maximum · ${p.facet('over')}'), color: c.danger),
          ]),
          const SizedBox(height: AppSpace.sm),
          if (wide)
            AppCard(padding: const EdgeInsets.all(AppSpace.xs), child: _Table(items: p.items, onOpen: onOpen))
          else
            for (final a in p.items) AdvAdvisorStatRow(stat: a, onTap: onOpen == null ? null : () => onOpen!(a)),
          if (p.pages > 1 && onPage != null) ...[
            const SizedBox(height: AppSpace.sm),
            AppPagination(page: p.page, pageCount: p.pages, total: p.total, pageSize: p.size, onPage: onPage!),
          ],
        ]);
      });
    }
    return OrgPageBody(
      search: onSearch == null ? null : OrgSearchField(hint: t('ابحث عن مرشد', 'Search for an advisor'), onChanged: onSearch!),
      filter: onSort == null
          ? null
          : OrgFilterButton<String>(
              value: sort,
              defaultValue: 'load',
              label: t('الترتيب', 'Order'),
              icon: Icons.sort_rounded,
              options: {for (final s in advAdvisorStatSorts) s: advAdvisorStatSortLabel(s)},
              onChanged: onSort!,
            ),
      child: body,
    );
  }
}

class _Table extends StatelessWidget {
  const _Table({required this.items, this.onOpen});
  final List<AdvAdvisorStat> items;
  final ValueChanged<AdvAdvisorStat>? onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final head = AppType.meta(context).copyWith(fontWeight: FontWeight.w700, color: c.textMedium);
    final cell = AppType.row(context).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    String n(int? v) => v == null ? '<5' : '$v';
    final cols = <(String, double, String Function(AdvAdvisorStat))>[
      (t('معرّضون للخطر', 'At risk'), 100, (a) => n(a.atRisk)),
      (t('بلا تواصل', 'No contact'), 96, (a) => n(a.noContactTerm)),
      (t('لقاءات', 'Meetings'), 80, (a) => '${a.meetingsCompleted}'),
      (t('الغياب', 'No-shows'), 84, (a) => a.noShowRate == null ? '${a.noShow}' : '${a.noShow} · ${advRate(a.noShowRate)}'),
      (t('ردود', 'Replies'), 72, (a) => '${a.replies}'),
      (t('زمن الرد', 'Reply time'), 90, (a) => a.avgResponseHours == null ? '—' : advHours(a.avgResponseHours)),
      (t('في الموعد', 'On time'), 84, (a) => a.slaMetPct == null ? '—' : advRate(a.slaMetPct)),
      (t('ملاحظات', 'Notes'), 76, (a) => '${a.notes}'),
      (t('تنبيهات أُغلقت', 'Alerts resolved'), 110, (a) => '${a.alertsResolved}'),
      (t('آخر نشاط', 'Last active'), 120, (a) => a.lastActiveAt == null ? '—' : advDate(a.lastActiveAt)),
    ];
    const nameW = 220.0, loadW = 180.0;
    final width = nameW + loadW + cols.fold<double>(0, (s, x) => s + x.$2);
    Widget row(AdvAdvisorStat? a) {
      final r = Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xs),
        child: Row(children: [
          SizedBox(
            width: nameW,
            child: a == null
                ? Text(t('المرشد', 'Advisor'), style: head)
                : Row(children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: a.active ? c.success : c.divider)),
                    const SizedBox(width: AppSpace.xs),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(a.shown, textDirection: advTextDirection(a.shown), style: cell.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(advAdvisorStatusText(a), style: AppType.meta(context), maxLines: 1),
                      ]),
                    ),
                  ]),
          ),
          SizedBox(
            width: loadW,
            child: a == null
                ? Text(t('الحمل', 'Load'), style: head)
                : Padding(padding: const EdgeInsetsDirectional.only(end: AppSpace.sm), child: AdvLoadBar(load: a.load, max: a.maxLoad, warn: a.warn, over: a.over)),
          ),
          for (final (label, w, f) in cols)
            SizedBox(width: w, child: Text(a == null ? label : f(a), style: a == null ? head : cell, textAlign: TextAlign.center, textDirection: a == null ? null : TextDirection.ltr, maxLines: 2)),
        ]),
      );
      if (a == null) return r;
      return InkWell(
        borderRadius: AppRadius.chipAll,
        onTap: onOpen == null ? null : () => onOpen!(a),
        child: ConstrainedBox(constraints: const BoxConstraints(minHeight: AppTouch.min), child: r),
      );
    }

    return AppHScroll(
      child: SizedBox(
        width: width + AppSpace.md,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          row(null),
          Divider(height: 1, color: c.divider),
          for (final a in items) ...[row(a), Divider(height: 1, color: c.divider)],
        ]),
      ),
    );
  }
}

class AdvAdvisorStatsPage extends StatelessWidget {
  const AdvAdvisorStatsPage({super.key, required this.orgId, required this.filter, this.range = const AdvRange(), this.sort = 'load', this.manage = true});
  final int orgId;
  final AdvAnalyticsFilter filter;
  final AdvRange range;
  final String sort;
  final bool manage;

  @override
  Widget build(BuildContext context) => OrgPushedPage(
        title: t('أداء المرشدين', 'Advisor figures'),
        helpPageId: 'org.advising',
        maxWidth: 1240,
        child: _Body(orgId: orgId, filter: filter, range: range, sort: sort, manage: manage),
      );
}

class _Body extends StatefulWidget {
  const _Body({required this.orgId, required this.filter, required this.range, required this.sort, required this.manage});
  final int orgId;
  final AdvAnalyticsFilter filter;
  final AdvRange range;
  final String sort;
  final bool manage;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  late final AdvAnalyticsApi _api = AdvAnalyticsApi(widget.orgId);
  OrgPageRefresh? _refresh;
  AdvLoad _load = AdvLoad.loading;
  AdvPage<AdvAdvisorStat>? _page;
  String? _error;
  late String _sort = widget.sort;
  String _q = '';
  int _pageNo = 1, _seq = 0;

  @override
  void initState() {
    super.initState();
    _refresh = OrgPageRefresh.register(context, _reload);
    _reload();
  }

  @override
  void dispose() {
    _refresh?.unregister(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final seq = ++_seq;
    final r = await orgCall(() => _api.advisors(widget.filter, q: _q, sort: _sort, page: _pageNo), quiet: true);
    if (!mounted || seq != _seq) return;
    setState(() {
      if (r.ok) {
        _page = r.data as AdvPage<AdvAdvisorStat>;
        _load = AdvLoad.ready;
      } else {
        _load = advFailLoad(r);
        _error = advErrorText(r.error!);
      }
    });
    if (r.ok && mounted) OrgPageRefresh.reportUpdated(context);
  }

  void _set({String? q, String? sort, int page = 1}) {
    setState(() {
      _q = q ?? _q;
      _sort = sort ?? _sort;
      _pageNo = page;
      _load = AdvLoad.loading;
    });
    _reload();
  }

  void _open(AdvAdvisorStat a) => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => AdvDrillPage(
          orgId: widget.orgId,
          drill: AdvDrill(metric: 'advisor', key: '${a.userId}'),
          filter: widget.filter,
          range: widget.range,
          title: t('طلاب ${a.shown}', '${a.shown}\'s students'),
        ),
      ));

  @override
  Widget build(BuildContext context) => AdvAdvisorStatsView(
        load: _load,
        page: _page,
        sort: _sort,
        errorText: _error,
        onRetry: () => _set(),
        onSearch: (q) => _set(q: q),
        onSort: (s) => _set(sort: s),
        onPage: (p) => _set(page: p),
        onOpen: widget.manage ? _open : null,
      );
}
