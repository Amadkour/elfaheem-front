// lib/features/org/advising/adv_director_page.dart — the advising analytics dashboard of directors and admins
// (manage) and of deans / quality officers who hold the `advising` view right organization-wide (aggregate: totals
// only, small groups hidden, no student lists) — Phase 8, docs/advising/PHASE8.md.
//
// ONE filter (a sheet: range or term, program, level, cohort, the students' advisor), then the KPI row, the data
// check (manage), and the cards: struggling students, advisor load, risk trend, CGPA, meetings, replies and
// complaints, support requests, advisor activity, outcomes, satisfaction; the ways into reports and group messages.
// Every chart has its breakdown rows; a director taps one to see the students behind it (adv_drill_page.dart).
// Phone: one column; wide: two. "Updated …" and Refresh come from the page header (OrgPageRefresh).
//
//   AdvDirectorView          the page's content (plain values)
//   AdvAnalyticsFilterForm   the filter sheet's content (plain values)
//   AdvDirectorPage          loads options, overview and the data check; refresh runs; navigation
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/core/offline/app_connectivity.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show asInt, t;
import '../org_page_header.dart' show OrgPageRefresh, OrgPushedPage;
import '../org_page_kit.dart';
import '../org_v3.dart' show orgCall;
import 'adv_advisors_page.dart';
import 'adv_advisors_stats_page.dart';
import 'adv_analytics_api.dart';
import 'adv_analytics_models.dart';
import 'adv_analytics_parts.dart';
import 'adv_distribute_page.dart';
import 'adv_drill_page.dart';
import 'adv_handovers_page.dart';
import 'adv_models.dart' show AdvPage, AdvPlanRequest;
import 'adv_outreach.dart';
import 'adv_parts.dart';
import 'adv_reports.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  Filter sheet
// ═════════════════════════════════════════════════════════════════════════════

/// The range choices of the sheet: (key, label). `term:<id>` · `last30` · `last90` · `custom` · `` (current term).
String advRangeKey(AdvAnalyticsFilter f, {DateTime? today}) {
  if (f.termId != null) return 'term:${f.termId}';
  if (f.from == null || f.to == null) return '';
  final d = today ?? DateTime.now();
  final day = DateTime(d.year, d.month, d.day);
  if (f.to == day && f.from == day.subtract(const Duration(days: 29))) return 'last30';
  if (f.to == day && f.from == day.subtract(const Duration(days: 89))) return 'last90';
  return 'custom';
}

class AdvAnalyticsFilterForm extends StatelessWidget {
  const AdvAnalyticsFilterForm({super.key, required this.filter, required this.options, required this.onChanged, this.onCustomDates, this.onApply, this.today});
  final AdvAnalyticsFilter filter;
  final AdvAnalyticsOptions options;
  final ValueChanged<AdvAnalyticsFilter> onChanged;
  final VoidCallback? onCustomDates, onApply;

  /// The clock (tests pin it).
  final DateTime? today;

  @override
  Widget build(BuildContext context) {
    final f = filter;
    final o = options;
    final now = today ?? DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    final key = advRangeKey(f, today: day);
    Widget dropdown<T>({required String label, required T? value, required List<(T, String)> items, required ValueChanged<T?> onPick}) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: AppDropdown<T?>(
            value: items.any((x) => x.$1 == value) ? value : null,
            decoration: InputDecoration(labelText: label),
            items: [
              DropdownMenuItem<T?>(value: null, child: Text(t('الكل', 'All'))),
              for (final (v, l) in items) DropdownMenuItem<T?>(value: v, child: Text(l, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: onPick,
          ),
        );
    final err = f.rangeError;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      AdvFieldLabel(t('المدة', 'Period')),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        AppChoiceChip(label: t('الفصل الحالي', 'Current term'), selected: key == '', onTap: () => onChanged(f.withTerm(null))),
        AppChoiceChip(label: t('آخر 30 يوماً', 'Last 30 days'), selected: key == 'last30', onTap: () => onChanged(f.withDates(day.subtract(const Duration(days: 29)), day))),
        AppChoiceChip(label: t('آخر 90 يوماً', 'Last 90 days'), selected: key == 'last90', onTap: () => onChanged(f.withDates(day.subtract(const Duration(days: 89)), day))),
        for (final term in o.terms.where((x) => !x.current).take(4)) AppChoiceChip(label: term.title, selected: key == 'term:${term.id}', onTap: () => onChanged(f.withTerm(term.id))),
        AppChoiceChip(
          icon: Icons.date_range_rounded,
          label: key == 'custom' && f.from != null && f.to != null ? '${advDate(f.from, dateOnly: true)} – ${advDate(f.to, dateOnly: true)}' : t('تواريخ أخرى…', 'Other dates…'),
          selected: key == 'custom',
          onTap: () => onCustomDates?.call(),
        ),
      ]),
      if (err != null) ...[const SizedBox(height: AppSpace.xs), AppBanner(icon: Icons.error_outline_rounded, color: context.colors.danger, text: err)],
      const SizedBox(height: AppSpace.md),
      AdvFieldLabel(t('الطلاب', 'Students'), hint: t('تصفية الطلاب توقف خط «المعرّضون للخطر» ومتوسط الرضا', 'A student filter turns off the at-risk line and the satisfaction average')),
      if (o.programs.isNotEmpty)
        dropdown<int>(label: t('البرنامج', 'Program'), value: f.programId, items: [for (final p in o.programs) (p.id, p.name)], onPick: (v) => onChanged(f.copyWith(programId: () => v))),
      if (o.levels.isNotEmpty) dropdown<String>(label: t('المستوى', 'Level'), value: f.level, items: [for (final l in o.levels) (l, l)], onPick: (v) => onChanged(f.copyWith(level: () => v))),
      if (o.cohorts.isNotEmpty) dropdown<String>(label: t('الدفعة', 'Cohort'), value: f.cohort, items: [for (final c in o.cohorts) (c, c)], onPick: (v) => onChanged(f.copyWith(cohort: () => v))),
      if (o.advisors.isNotEmpty)
        dropdown<int>(
          label: t('المرشد الحالي للطلاب', 'The students\' current advisor'),
          value: f.advisor?.userId,
          items: [for (final a in o.advisors) (a.userId, a.shown)],
          onPick: (v) => onChanged(f.copyWith(advisor: () => v == null ? null : o.advisors.firstWhere((a) => a.userId == v))),
        ),
      const SizedBox(height: AppSpace.xs),
      if (onApply != null) AppPrimaryButton(icon: Icons.check_rounded, label: t('عرض الأرقام', 'Show the figures'), onPressed: err == null ? onApply : null),
      if (f.activeFilters > 0)
        TextButton.icon(
          style: TextButton.styleFrom(minimumSize: const Size(0, AppTouch.min)),
          onPressed: () => onChanged(const AdvAnalyticsFilter()),
          icon: const Icon(Icons.filter_alt_off_rounded, size: AppIconSize.md),
          label: Text(t('مسح التصفية', 'Clear the filters')),
        ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The page's content
// ═════════════════════════════════════════════════════════════════════════════

class AdvDirectorView extends StatelessWidget {
  const AdvDirectorView({
    super.key,
    required this.load,
    required this.filter,
    this.overview,
    this.options,
    this.health,
    this.healthLoading = false,
    this.healthBusy = false,
    this.healthError,
    this.refreshing = false,
    this.errorText,
    this.onRetry,
    this.onFilters,
    this.onClearFilters,
    this.onRefreshData,
    this.onRuns,
    this.onDrill,
    this.onOutcomeDrill,
    this.onAdvisors,
    this.onHealthRun,
    this.onHealthItem,
    this.onReports,
    this.onOutreach,
  });

  final AdvLoad load;
  final AdvAnalyticsFilter filter;
  final AdvOverview? overview;
  final AdvAnalyticsOptions? options;
  final AdvHealth? health;
  final bool healthLoading, healthBusy;
  final String? healthError;

  /// A refresh of the figures is running.
  final bool refreshing;
  final String? errorText;
  final VoidCallback? onRetry, onFilters, onClearFilters, onRefreshData, onRuns, onHealthRun, onReports, onOutreach;

  /// The students behind a figure (manage only; null hides every chevron).
  final ValueChanged<AdvDrill>? onDrill;

  /// An outcome group of the outcomes' term.
  final ValueChanged<String>? onOutcomeDrill;

  /// The advisors table, in an order (`load` · `activity` …).
  final ValueChanged<String>? onAdvisors;
  final ValueChanged<AdvHealthItem>? onHealthItem;

  bool get _manage => overview == null ? (options?.manage ?? false) : !overview!.viewer.aggregate;

  @override
  Widget build(BuildContext context) {
    final o = overview;
    Widget body;
    if (load != AdvLoad.ready || o == null) {
      body = AdvLoadState(state: load == AdvLoad.ready ? AdvLoad.loading : load, errorText: errorText, onRetry: onRetry, items: 6);
    } else if (o.empty) {
      body = AppEmpty(
        icon: Icons.insights_rounded,
        title: filter.activeFilters > 0 ? t('لا طلاب يطابقون التصفية', 'No students match the filters') : t('لا أرقام بعد', 'No figures yet'),
        message: filter.activeFilters > 0
            ? t('جرّب مدة أو برنامجاً آخر.', 'Try another period or program.')
            : t('تظهر الأرقام بعد إسناد الطلاب إلى المرشدين.', 'The figures show once students are assigned to advisors.'),
        actionLabel: filter.activeFilters > 0 && onClearFilters != null ? t('مسح التصفية', 'Clear the filters') : null,
        onAction: filter.activeFilters > 0 ? onClearFilters : null,
      );
    } else {
      body = _content(context, o);
    }
    return OrgPageBody(
      primary: onReports == null ? null : OrgPrimaryAction(icon: Icons.summarize_outlined, label: t('التقارير والتصدير', 'Reports and exports'), onTap: onReports!),
      filter: onFilters == null ? null : _FilterButton(count: filter.activeFilters, onTap: onFilters!),
      more: [
        if (onRefreshData != null) OrgMenuItem(icon: Icons.sync_rounded, label: t('حدّث الأرقام الآن', 'Update the figures now'), onTap: onRefreshData!),
        if (onAdvisors != null) OrgMenuItem(icon: Icons.supervisor_account_rounded, label: t('أداء المرشدين', 'Advisor figures'), onTap: () => onAdvisors!('load')),
        if (onOutreach != null) OrgMenuItem(icon: Icons.campaign_outlined, label: t('الرسائل الجماعية', 'Group messages'), onTap: onOutreach!),
        if (onRuns != null) OrgMenuItem(icon: Icons.history_rounded, label: t('سجل التحديثات', 'Update history'), onTap: onRuns!),
      ],
      child: body,
    );
  }

  Widget _content(BuildContext context, AdvOverview o) {
    final drill = _manage ? onDrill : null;
    VoidCallback? go(String metric, [String? key, String? label]) => drill == null ? null : () => drill(AdvDrill(metric: metric, key: key, label: label));
    final cards = <Widget>[
      AdvStrugglingCard(
        struggling: o.struggling,
        total: o.students.total,
        onBand: drill == null ? null : (k) => drill(AdvDrill(metric: 'risk_band', key: k, label: advRiskBandName(k))),
        onPriority: drill == null ? null : (p) => drill(AdvDrill(metric: 'priority', key: p, label: t('أعلى تنبيه: ${_priority(p)}', 'Highest alert: ${_priority(p)}'))),
        onCategory: drill == null ? null : (x) => drill(AdvDrill(metric: 'category', key: '${x.category.id}', label: x.category.name)),
      ),
      AdvLoadCard(
        load: o.load,
        students: o.students,
        onBucket: onAdvisors == null ? null : (_) => onAdvisors!('load'),
        onAdvisor: drill == null ? null : (a) => drill(AdvDrill(metric: 'advisor', key: '${a.userId}', label: t('طلاب ${a.shown}', '${a.shown}\'s students'))),
        onAllAdvisors: onAdvisors == null ? null : () => onAdvisors!('load'),
      ),
      AdvRiskTrendCard(points: o.riskTrend, interval: o.range.interval, stateSeries: o.stateSeries, onAlerted: go('alerted')),
      AdvGpaCard(gpa: o.gpa, onBand: drill == null ? null : (b) => drill(AdvDrill(metric: 'gpa_band', key: b.key, label: t('المعدل ${b.label}', 'CGPA ${b.label}')))),
      AdvMeetingsCard(meetings: o.meetings, onDrill: drill == null ? null : (k) => drill(AdvDrill(metric: k))),
      AdvResponseCard(response: o.response, complaints: o.complaints, onAwaiting: go('awaiting_reply'), onComplaints: go('complaint')),
      AdvRequestsCard(requests: o.requests, onStage: drill == null ? null : (s) => drill(AdvDrill(metric: 'request_stage', key: s, label: advRequestStageLabel(s)))),
      AdvActivityCard(activity: o.activity, onAdvisors: onAdvisors == null ? null : (k) => onAdvisors!(k == 'inactive' ? 'activity' : 'load')),
      AdvOutcomesCard(outcomes: o.outcomes, onGroup: _manage ? onOutcomeDrill : null),
      AdvSatisfactionCard(satisfaction: o.satisfaction),
    ];
    final entries = <Widget>[
      if (onReports != null)
        AppActionCard(icon: Icons.summarize_outlined, title: t('التقارير والتصدير', 'Reports and exports'), subtitle: t('تقرير الالتزام، ملفات PDF وExcel، والإرسال بالبريد', 'Compliance report, PDF and Excel files, e-mailed schedules'), onTap: onReports!),
      if (onOutreach != null)
        AppActionCard(icon: Icons.campaign_outlined, title: t('الرسائل الجماعية', 'Group messages'), subtitle: t('راسل مجموعة طلاب وتابع من قرأ', 'Message a group of students and see who read it'), onTap: onOutreach!),
    ];
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 960;
      final healthCard = _manage
          ? AdvHealthCard(health: health, loading: healthLoading, busy: healthBusy, errorText: healthError, onRun: onHealthRun, onItem: onHealthItem)
          : null;
      Widget column(List<Widget> list) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < list.length; i++) ...[if (i > 0) const SizedBox(height: AppSpace.md), list[i]],
          ]);
      return AdvPageFrame(maxWidth: 1440, fab: onReports != null, children: [
        AdvFilterSummary(range: o.range, filter: filter, programName: options?.programName(filter.programId), onEdit: onFilters),
        if (refreshing) ...[const SizedBox(height: AppSpace.xs), AdvBusyStrip(label: t('يجري تحديث الأرقام', 'Updating the figures'))],
        if (o.viewer.aggregate) ...[const SizedBox(height: AppSpace.sm), const AdvAggregateBanner()],
        const SizedBox(height: AppSpace.sm),
        AdvKpiRow(
          overview: o,
          onTap: drill == null
              ? null
              : (k) {
                  final m = switch (k) {
                    'students' => 'all',
                    'unassigned' => 'unassigned',
                    'meetings_completed' => 'met',
                    'no_show_rate' => 'no_show',
                    'alerts' => 'alerted',
                    'complaints_open' => 'complaint',
                    'avg_response_hours' => 'awaiting_reply',
                    _ => null,
                  };
                  if (m != null) drill(AdvDrill(metric: m));
                },
        ),
        const SizedBox(height: AppSpace.md),
        if (wide)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: column([?healthCard, for (var i = 0; i < cards.length; i += 2) cards[i]])),
            const SizedBox(width: AppSpace.md),
            Expanded(child: column([for (var i = 1; i < cards.length; i += 2) cards[i], ...entries])),
          ])
        else
          column([?healthCard, ...cards, ...entries]),
      ]);
    });
  }

  static String _priority(String p) => switch (p) {
        'urgent' => t('عاجل', 'Urgent'),
        'high' => t('مرتفع', 'High'),
        'low' => t('منخفض', 'Low'),
        _ => t('عادي', 'Normal'),
      };
}

/// The page's one filter control: "Filters · 2".
class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final active = count > 0;
    final label = active ? t('التصفية · $count', 'Filters · $count') : t('التصفية', 'Filters');
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: active ? c.primaryTint : c.cardBg,
        borderRadius: AppRadius.chipAll,
        child: InkWell(
          borderRadius: AppRadius.chipAll,
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: AppTouch.min),
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
            decoration: BoxDecoration(borderRadius: AppRadius.chipAll, border: Border.all(color: active ? orgInk(context).withValues(alpha: 0.45) : c.divider)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.tune_rounded, size: AppIconSize.sm, color: active ? orgInk(context) : c.textMedium),
              const SizedBox(width: AppSpace.xs),
              Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(color: active ? orgInk(context) : c.textDark))),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The update history (plain values): each run with its status, who started it, counts and time.
class AdvRunsList extends StatelessWidget {
  const AdvRunsList({super.key, required this.runs});
  final List<AdvAnalyticsRun> runs;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (runs.isEmpty) return AdvChartNote(t('لا تحديثات بعد.', 'No updates yet.'));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < runs.length; i++) ...[
        if (i > 0) Divider(height: 1, color: c.divider),
        Builder(builder: (context) {
          final r = runs[i];
          final col = r.failed ? c.danger : (r.running ? c.primary : c.success);
          final secs = r.durationMs == null ? null : (r.durationMs! / 1000).toStringAsFixed(r.durationMs! < 10000 ? 1 : 0);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(r.failed ? Icons.error_outline_rounded : (r.running ? Icons.sync_rounded : Icons.check_circle_outline_rounded), color: appInk(context, col), size: AppIconSize.md),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${advAnalyticsRunKindLabel(r.kind)} · ${advAnalyticsRunStatusLabel(r.status)}', style: AppType.row(context)),
                  Text(
                    [
                      if (r.startedAt != null) AppTime.dateTime(r.startedAt!),
                      r.trigger == 'manual' ? (r.actor == null ? t('يدوي', 'By hand') : r.actor!.shown) : t('تلقائي', 'Automatic'),
                      if (secs != null) t('$secs ث', '$secs s'),
                      if ((r.counts['students'] ?? 0) > 0) advStudentsText(r.counts['students']!),
                    ].join(' · '),
                    style: AppType.meta(context),
                  ),
                  if (r.error != null) Text(r.error!, style: AppType.meta(context).copyWith(color: appInk(context, c.danger)), maxLines: 2, overflow: TextOverflow.ellipsis),
                ]),
              ),
            ]),
          );
        }),
      ],
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Page
// ═════════════════════════════════════════════════════════════════════════════

class AdvDirectorPage extends StatelessWidget {
  const AdvDirectorPage({super.key, required this.orgId, this.outreach = false});
  final int orgId;

  /// I may send group messages (status `me.outreach`).
  final bool outreach;

  @override
  Widget build(BuildContext context) => OrgPushedPage(
        title: t('تحليلات الإرشاد', 'Advising analytics'),
        helpPageId: 'org.advising',
        maxWidth: 1440,
        child: _DirectorBody(orgId: orgId, outreach: outreach),
      );
}

class _DirectorBody extends StatefulWidget {
  const _DirectorBody({required this.orgId, required this.outreach});
  final int orgId;
  final bool outreach;

  @override
  State<_DirectorBody> createState() => _DirectorBodyState();
}

class _DirectorBodyState extends State<_DirectorBody> {
  late final AdvAnalyticsApi _api = AdvAnalyticsApi(widget.orgId);
  OrgPageRefresh? _refresh;
  AdvLoad _load = AdvLoad.loading;
  AdvAnalyticsOptions? _options;
  AdvOverview? _overview;
  AdvHealth? _health;
  bool _healthLoading = false, _healthBusy = false, _refreshing = false;
  String? _error, _healthError;
  AdvAnalyticsFilter _filter = const AdvAnalyticsFilter();
  int _seq = 0;

  bool get _manage => _overview == null ? (_options?.manage ?? false) : !_overview!.viewer.aggregate;

  @override
  void initState() {
    super.initState();
    _refresh = OrgPageRefresh.register(context, _refreshFresh);
    _reload();
  }

  @override
  void dispose() {
    _refresh?.unregister(_refreshFresh);
    super.dispose();
  }

  /// The header's Refresh: figures computed now, not the copy the server keeps for opening the page.
  Future<void> _refreshFresh() => _reload(fresh: true);

  Future<void> _reload({bool fresh = false}) async {
    final seq = ++_seq;
    if (!AppConnectivity.instance.isOnline && _overview == null) {
      setState(() => _load = AdvLoad.offline);
      return;
    }
    final results = await Future.wait([
      if (_options == null) orgCall(() => _api.options(), quiet: true),
      orgCall(() => _api.overview(_filter, fresh: fresh), quiet: true),
    ]);
    if (!mounted || seq != _seq) return;
    final opt = results.length == 2 ? results.first : null;
    final ov = results.last;
    if (fresh && !ov.ok && _overview != null) {
      // the figures on screen stay; a refused refresh says why (and when it works again)
      if (opt != null && opt.ok) setState(() => _options = opt.data as AdvAnalyticsOptions);
      showAppNotice(advFreshFailedText(ov.error!), error: true);
      OrgPageRefresh.reportUpdated(context, _overview!.updatedAt);
      return;
    }
    if (fresh && ov.ok) showAppNotice(t('الأرقام محدّثة الآن', 'The figures are up to date'));
    setState(() {
      if (opt != null && opt.ok) _options = opt.data as AdvAnalyticsOptions;
      if (ov.ok) {
        _overview = ov.data as AdvOverview;
        _load = AdvLoad.ready;
      } else {
        _load = advFailLoad(ov);
        _error = ov.endpointMissing ? t('تحليلات الإرشاد تحتاج تحديث الخادم.', 'Advising analytics need a server update.') : advErrorText(ov.error!);
        _overview = null;
      }
    });
    if (ov.ok && mounted) {
      OrgPageRefresh.reportUpdated(context, _overview?.updatedAt);
      if (_manage) unawaited(_loadHealth());
    }
  }

  Future<void> _loadHealth() async {
    setState(() => _healthLoading = true);
    final r = await orgCall(() => _api.health(), quiet: true);
    if (!mounted) return;
    setState(() {
      _healthLoading = false;
      if (r.ok) {
        _health = r.data as AdvHealth;
        _healthError = null;
      } else {
        _healthError = r.endpointMissing ? t('فحص البيانات يحتاج تحديث الخادم.', 'The data check needs a server update.') : advErrorText(r.error!);
      }
    });
  }

  Future<void> _runHealth() async {
    setState(() => _healthBusy = true);
    final r = await orgCall(() => _api.runHealth(), quiet: true);
    if (!mounted) return;
    setState(() {
      _healthBusy = false;
      if (r.ok) _health = r.data as AdvHealth;
    });
    if (r.ok) {
      final h = _health!;
      showAppNotice(h.issues == 0 ? t('فُحصت البيانات: كل شيء سليم', 'Data checked: everything is fine') : t('فُحصت البيانات: ${h.issues} تحتاج انتباهك', 'Data checked: ${h.issues} need attention'));
    } else {
      showAppNotice(advErrorText(r.error!), error: true);
    }
  }

  void _setFilter(AdvAnalyticsFilter f) {
    setState(() {
      _filter = f;
      _load = AdvLoad.loading;
    });
    _reload();
  }

  Future<void> _filters() async {
    final o = _options;
    if (o == null) return;
    var draft = _filter;
    final apply = await showAppSheet<bool>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
          Future<void> custom() async {
            final now = DateTime.now();
            final picked = await showDateRangePicker(
              context: ctx,
              firstDate: DateTime(now.year - 5),
              lastDate: DateTime(now.year, now.month, now.day),
              initialDateRange: draft.from != null && draft.to != null ? DateTimeRange(start: draft.from!, end: draft.to!) : null,
            );
            if (picked != null) set(() => draft = draft.withDates(DateTime(picked.start.year, picked.start.month, picked.start.day), DateTime(picked.end.year, picked.end.month, picked.end.day)));
          }

          return AppSheetContent(
            title: t('ما الذي تعرضه الأرقام', 'What the figures cover'),
            children: [
              AdvAnalyticsFilterForm(filter: draft, options: o, onChanged: (f) => set(() => draft = f), onCustomDates: custom, onApply: () => Navigator.pop(ctx, true)),
            ],
          );
        }));
    if (apply == true && mounted && draft != _filter) _setFilter(draft);
  }

  Future<void> _refreshData() async {
    final r = await orgCall(() => _api.refresh(), quiet: true);
    if (!mounted) return;
    int runId;
    if (r.ok) {
      runId = (r.data as AdvAnalyticsRun).id;
      showAppNotice(t('بدأ تحديث الأرقام — يستغرق دقائق قليلة', 'Updating the figures — it takes a few minutes'));
    } else if (r.code == 'advising_run_busy') {
      runId = asInt(r.detail['run_id']);
      showAppNotice(t('تحديث يعمل بالفعل — ستتحدث الصفحة حين ينتهي', 'An update is already running — the page updates when it ends'));
    } else {
      showAppNotice(advErrorText(r.error!), error: true);
      return;
    }
    setState(() => _refreshing = true);
    final watch = JobWatch(kind: 'advising_analytics', id: runId == 0 ? null : '$runId');
    var status = 'running';
    try {
      final until = DateTime.now().add(const Duration(minutes: 10));
      while (status == 'running' && DateTime.now().isBefore(until) && mounted) {
        final e = await watch.next(const Duration(seconds: 8), fallbackEvery: const Duration(seconds: 40));
        if (e?.status != null && e!.status != 'running') {
          status = e.status!;
          break;
        }
        final runs = await orgCall(() => _api.runs(kind: 'daily', size: 5), quiet: true);
        if (runs.ok) {
          final run = (runs.data as AdvPage<AdvAnalyticsRun>).items.where((x) => x.id == runId).firstOrNull;
          if (run != null) status = run.status;
        }
      }
    } finally {
      watch.dispose();
    }
    if (!mounted) return;
    setState(() => _refreshing = false);
    if (status == 'done') {
      showAppNotice(t('تحدّثت الأرقام', 'The figures are updated'));
      _reload();
    } else if (status == 'failed') {
      showAppNotice(t('تعذّر تحديث الأرقام — راجع سجل التحديثات', 'The figures could not be updated — see the update history'), error: true);
    }
  }

  Future<void> _runs() async {
    final r = await orgCall(() => _api.runs(size: 20), quiet: true);
    if (!mounted) return;
    if (!r.ok) {
      showAppNotice(advErrorText(r.error!), error: true);
      return;
    }
    await showAppSheet<void>(context, (_) => AppSheetContent(title: t('سجل التحديثات', 'Update history'), children: [AdvRunsList(runs: (r.data as AdvPage<AdvAnalyticsRun>).items)]));
  }

  Future<void> _push(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  void _drill(AdvDrill d, {AdvAnalyticsFilter? filter}) => _push(AdvDrillPage(
        orgId: widget.orgId,
        drill: d,
        filter: filter ?? _filter,
        range: _overview?.range ?? const AdvRange(),
        programName: _options?.programName(_filter.programId),
        canMessage: widget.outreach,
      ));

  void _outcomeDrill(String group) {
    final term = _overview?.outcomes.term;
    _drill(AdvDrill(metric: group, label: advMetricLabel(group)), filter: _filter.withTerm(term?.id));
  }

  void _healthItem(AdvHealthItem i) {
    final id = widget.orgId;
    switch (i.action) {
      case 'distribute':
        _push(AdvDistributePage(orgId: id));
      case 'rebalance':
        _push(AdvDistributePage(orgId: id, initial: const AdvPlanRequest(mode: 'rebalance')));
      case 'reassign':
        _push(AdvDistributePage(orgId: id, initial: const AdvPlanRequest(mode: 'reassign')));
      case 'open_handovers':
        _push(AdvHandoversPage(orgId: id, manage: true));
      case 'open_advisors':
        _push(AdvAdvisorsPage(orgId: id, manage: true));
      default:
        final d = i.drill;
        if (d != null) _drill(AdvDrill(metric: d.metric, key: d.key, label: i.label));
    }
  }

  @override
  Widget build(BuildContext context) {
    final manage = _manage;
    return AdvDirectorView(
      load: _load,
      filter: _filter,
      overview: _overview,
      options: _options,
      health: _health,
      healthLoading: _healthLoading,
      healthBusy: _healthBusy,
      healthError: _healthError,
      refreshing: _refreshing,
      errorText: _error,
      onRetry: _reload,
      onFilters: _options == null ? null : _filters,
      onClearFilters: () => _setFilter(const AdvAnalyticsFilter()),
      onRefreshData: manage && !_refreshing ? _refreshData : null,
      onRuns: manage ? _runs : null,
      onDrill: manage ? _drill : null,
      onOutcomeDrill: manage ? _outcomeDrill : null,
      onAdvisors: (sort) => _push(AdvAdvisorStatsPage(orgId: widget.orgId, filter: _filter, range: _overview?.range ?? const AdvRange(), sort: sort, manage: manage)),
      onHealthRun: manage ? _runHealth : null,
      onHealthItem: manage ? _healthItem : null,
      onReports: () => _push(AdvReportsPage(orgId: widget.orgId, manage: manage, filter: _filter, terms: _options?.terms ?? const [])),
      onOutreach: widget.outreach ? () => _push(AdvOutreachListPage(orgId: widget.orgId, manage: manage)) : null,
    );
  }
}
