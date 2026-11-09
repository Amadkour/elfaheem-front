// lib/features/org/advising/adv_drill_page.dart — the students behind a dashboard figure (Phase 8,
// docs/advising/PHASE8.md `GET /analytics/students`, manage only): the workspace's card list for one metric and the
// dashboard's filters, with search, order, paging, the Export Studio export of the same list (`adv.students`, so it
// can also be scheduled) and "Message these students" (the outreach composer with the same audience).
//
//   AdvDrillView   the list (plain values, test/ui/adv_analytics_layout_test.dart)
//   AdvDrillPage   loads the list
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t;
import '../../admin/admin_table_export.dart' show exportFetched;
import '../org_page_header.dart' show OrgPageRefresh, OrgPushedPage;
import '../org_page_kit.dart';
import '../org_v3.dart' show orgCall;
import 'adv_analytics_api.dart';
import 'adv_analytics_models.dart';
import 'adv_analytics_parts.dart' show AdvFilterSummary;
import 'adv_models.dart';
import 'adv_outreach.dart' show showAdvOutreachComposer;
import 'adv_parts.dart';
import 'adv_student_page.dart';
import 'adv_workspace_page.dart' show AdvCaseCard, advStandingLabel;

class AdvDrillView extends StatelessWidget {
  const AdvDrillView({
    super.key,
    required this.load,
    required this.title,
    required this.filter,
    required this.range,
    this.page,
    this.sort = 'risk',
    this.search = '',
    this.errorText,
    this.programName,
    this.now,
    this.onRetry,
    this.onSearch,
    this.onSort,
    this.onPage,
    this.onOpen,
    this.onMessage,
    this.onExport,
  });

  final AdvLoad load;
  final String title;
  final AdvAnalyticsFilter filter;
  final AdvRange range;
  final AdvPage<AdvCaseItem>? page;
  final String sort, search;
  final String? errorText, programName;
  final DateTime? now;
  final VoidCallback? onRetry, onMessage, onExport;
  final ValueChanged<String>? onSearch, onSort;
  final ValueChanged<int>? onPage;
  final ValueChanged<AdvCaseItem>? onOpen;

  @override
  Widget build(BuildContext context) {
    final p = page;
    Widget body;
    if (load != AdvLoad.ready || p == null) {
      body = AdvLoadState(state: load == AdvLoad.ready ? AdvLoad.loading : load, errorText: errorText, onRetry: onRetry);
    } else if (p.items.isEmpty) {
      body = AppEmpty(
        icon: search.trim().isEmpty ? Icons.check_circle_outline_rounded : Icons.filter_alt_off_rounded,
        title: search.trim().isEmpty ? t('لا طلاب هنا', 'No students here') : t('لا طلاب يطابقون البحث', 'No students match the search'),
        message: search.trim().isEmpty ? t('لا أحد يطابق هذا الرقم الآن.', 'Nobody matches this figure right now.') : t('جرّب بحثاً آخر.', 'Try another search.'),
      );
    } else {
      body = AdvPageFrame(maxWidth: 1440, fab: onMessage != null, children: [
        AdvFilterSummary(range: range, filter: filter, programName: programName),
        const SizedBox(height: AppSpace.xs),
        Semantics(
          header: true,
          child: Text(
            '$title · ${countText(p.total, ar1: 'طالب واحد', ar2: 'طالبان', arFew: '${p.total} طلاب', arMany: '${p.total} طالباً', en1: '1 student', en: '${p.total} students')}',
            style: AppType.meta(context),
          ),
        ),
        const SizedBox(height: AppSpace.xs),
        for (final s in p.items) AdvCaseCard(item: s, showAdvisor: true, now: now, onTap: onOpen == null ? null : () => onOpen!(s)),
        if (p.pages > 1 && onPage != null) ...[
          const SizedBox(height: AppSpace.sm),
          AppPagination(page: p.page, pageCount: p.pages, total: p.total, pageSize: p.size, onPage: onPage!),
        ],
      ]);
    }
    final canMessage = onMessage != null && (p?.total ?? 0) > 0;
    return OrgPageBody(
      primary: canMessage ? OrgPrimaryAction(icon: Icons.campaign_outlined, label: t('راسل هؤلاء الطلاب', 'Message these students'), onTap: onMessage!) : null,
      search: onSearch == null ? null : OrgSearchField(hint: t('ابحث بالاسم أو الرقم', 'Search by name or ID'), onChanged: onSearch!),
      filter: onSort == null
          ? null
          : OrgFilterButton<String>(
              value: sort,
              defaultValue: 'risk',
              label: t('الترتيب', 'Order'),
              icon: Icons.sort_rounded,
              options: {for (final s in advWorkspaceSorts) s: advWorkspaceSortLabel(s)},
              onChanged: onSort!,
            ),
      more: [
        if (onExport != null && (p?.total ?? 0) > 0) OrgMenuItem(icon: Icons.file_download_outlined, label: t('تصدير القائمة', 'Export the list'), onTap: onExport!),
      ],
      child: body,
    );
  }
}

class AdvDrillPage extends StatelessWidget {
  const AdvDrillPage({super.key, required this.orgId, required this.drill, required this.filter, this.range = const AdvRange(), this.title, this.programName, this.canMessage = true});
  final int orgId;
  final AdvDrill drill;
  final AdvAnalyticsFilter filter;

  /// The dashboard's range (the chips on top).
  final AdvRange range;
  final String? title, programName;
  final bool canMessage;

  @override
  Widget build(BuildContext context) {
    final shown = title ?? drill.label ?? advMetricLabel(drill.metric);
    return OrgPushedPage(
      title: shown,
      helpPageId: 'org.advising',
      maxWidth: 1440,
      child: _DrillBody(orgId: orgId, drill: drill, filter: filter, range: range, title: shown, programName: programName, canMessage: canMessage),
    );
  }
}

class _DrillBody extends StatefulWidget {
  const _DrillBody({required this.orgId, required this.drill, required this.filter, required this.range, required this.title, this.programName, required this.canMessage});
  final int orgId;
  final AdvDrill drill;
  final AdvAnalyticsFilter filter;
  final AdvRange range;
  final String title;
  final String? programName;
  final bool canMessage;

  @override
  State<_DrillBody> createState() => _DrillBodyState();
}

class _DrillBodyState extends State<_DrillBody> {
  late final AdvAnalyticsApi _api = AdvAnalyticsApi(widget.orgId);
  OrgPageRefresh? _refresh;
  AdvLoad _load = AdvLoad.loading;
  AdvPage<AdvCaseItem>? _page;
  AdvDrillMetric? _metric;
  String? _error;
  String _q = '', _sort = 'risk';
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
    final r = await orgCall(() => _api.students(widget.drill, widget.filter, q: _q, sort: _sort, page: _pageNo), quiet: true);
    if (!mounted || seq != _seq) return;
    setState(() {
      if (r.ok) {
        final d = r.data as AdvDrillResult;
        _page = d.page;
        _metric = d.metric;
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

  Map<String, Object?> get _params => {'org_id': widget.orgId, ...widget.drill.toQuery(), ...widget.filter.toQuery(), if (_q.trim().isNotEmpty) 'q': _q.trim()};

  Future<void> _export() => exportFetched(
        context,
        fetch: (job) async {
          final out = <Map<String, dynamic>>[];
          for (var page = 1; page <= 50; page++) {
            job.throwIfCancelled();
            final d = await _api.students(widget.drill, widget.filter, q: _q, sort: _sort, page: page, size: 100);
            out.addAll([for (final s in d.page.items) _row(s)]);
            job.step('${t('جلب الصفوف', 'Fetching rows')} ${out.length} / ${d.page.total}', d.page.pages <= 0 ? null : page / d.page.pages);
            if (page >= d.page.pages) break;
          }
          return out;
        },
        build: (rows) => AppTableExport(
          id: 'adv.students',
          title: widget.title,
          orgId: widget.orgId,
          serverDataset: 'adv.students',
          serverParams: _params,
          columns: [
            AppExportColumn('name', t('الطالب', 'Student'), locked: true, labels: const {'ar': 'الطالب', 'en': 'Student'}),
            AppExportColumn('code', t('الرقم', 'ID'), labels: const {'ar': 'الرقم', 'en': 'ID'}),
            AppExportColumn('program', t('البرنامج', 'Program'), labels: const {'ar': 'البرنامج', 'en': 'Program'}),
            AppExportColumn('level', t('المستوى', 'Level'), labels: const {'ar': 'المستوى', 'en': 'Level'}),
            AppExportColumn('cohort', t('الدفعة', 'Cohort'), visible: false, labels: const {'ar': 'الدفعة', 'en': 'Cohort'}),
            AppExportColumn('advisor', t('المرشد', 'Advisor'), labels: const {'ar': 'المرشد', 'en': 'Advisor'}),
            AppExportColumn('cgpa', t('المعدل', 'CGPA'), type: AppColType.number, decimals: 2, labels: const {'ar': 'المعدل', 'en': 'CGPA'}),
            AppExportColumn('standing', t('الوضع', 'Standing'), visible: false, labels: const {'ar': 'الوضع', 'en': 'Standing'}),
            AppExportColumn('risk', t('درجة الخطر', 'Risk score'), type: AppColType.integer, labels: const {'ar': 'درجة الخطر', 'en': 'Risk score'}),
            AppExportColumn('last_contact', t('آخر تواصل', 'Last contact'), type: AppColType.dateTime, labels: const {'ar': 'آخر تواصل', 'en': 'Last contact'}),
          ],
          rows: rows,
        ),
      );

  Map<String, dynamic> _row(AdvCaseItem s) => {
        'name': s.shown,
        'code': s.code,
        'program': s.program,
        'level': s.level,
        'cohort': s.cohort,
        'advisor': s.primary?.shown,
        'cgpa': s.cgpa,
        'standing': s.standing == null ? null : advStandingLabel(s.standing!),
        'risk': s.riskScore,
        'last_contact': s.lastContactAt,
      };

  Future<void> _message() => showAdvOutreachComposer(
        context,
        orgId: widget.orgId,
        audience: AdvAudience.of(widget.drill, widget.filter, q: _q),
        audienceTitle: widget.title,
      );

  Future<void> _open(AdvCaseItem s) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AdvStudentPage(orgId: widget.orgId, memberId: s.memberId, name: s.shown)));
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final title = _metric?.label ?? widget.title;
    return AdvDrillView(
      load: _load,
      title: title,
      filter: widget.filter,
      range: widget.range,
      page: _page,
      sort: _sort,
      search: _q,
      errorText: _error,
      programName: widget.programName,
      onRetry: () => _set(),
      onSearch: (q) => _set(q: q),
      onSort: (s) => _set(sort: s),
      onPage: (p) => _set(page: p),
      onOpen: _open,
      onMessage: widget.canMessage ? _message : null,
      onExport: _export,
    );
  }
}
