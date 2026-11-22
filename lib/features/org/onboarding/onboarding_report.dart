// lib/features/org/onboarding/onboarding_report.dart — the admissions report (phase D, D-1200): the funnel, the
// overdue cases, the average review time and the reviewers, for a date range and a type; "Download Excel" is the
// same data as a workbook (`?format=xlsx`).
//
//   OnbReport         parse of `GET …/onboarding/report` (no identity numbers in it)
//   OnbReportView     plain-values presentational body (the layout test pumps this)
//   OnbReportPage     the pushed page: loads, filters, downloads
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';

import '../../admin/admin_common.dart' show t, asMap, asMapList, asInt, asStr, asDouble;
import '../org_page_header.dart' show OrgPushedPage;
import '../org_v3.dart' show orgErrorText, orgParseUtc;
import 'onboarding_api.dart';
import 'onboarding_import.dart' show onbSaveXlsx;
import 'onboarding_models.dart';

class OnbReportOverdue {
  const OnbReportOverdue({this.caseId = 0, this.fullName = '', this.typeKey = '', this.dueAt, this.missing = const []});
  final int caseId;
  final String fullName, typeKey;
  final DateTime? dueAt;
  final List<String> missing;
}

class OnbReportReviewer {
  const OnbReportReviewer({this.userId = 0, this.name = '', this.decided = 0, this.avgHours});
  final int userId, decided;
  final String name;
  final double? avgHours;
}

class OnbReport {
  const OnbReport({this.funnel = const {}, this.overdue = const [], this.avgReviewHours, this.byReviewer = const []});
  final Map<String, int> funnel;
  final List<OnbReportOverdue> overdue;
  final double? avgReviewHours;
  final List<OnbReportReviewer> byReviewer;

  int get total => funnel.values.fold(0, (a, b) => a + b);
  int count(String status) => funnel[status] ?? 0;

  factory OnbReport.fromJson(Map<String, dynamic> j) => OnbReport(
        funnel: {for (final e in asMap(j['funnel']).entries) e.key: asInt(e.value)},
        overdue: [
          for (final x in asMapList(j['overdue']))
            OnbReportOverdue(
              caseId: asInt(x['case_id']),
              fullName: asStr(x['full_name']),
              typeKey: asStr(x['type_key']),
              dueAt: orgParseUtc(x['due_at']),
              missing: [for (final m in (x['missing'] is List ? x['missing'] as List : const [])) '$m'],
            ),
        ],
        avgReviewHours: j['avg_review_hours'] == null ? null : asDouble(j['avg_review_hours']),
        byReviewer: [
          for (final x in asMapList(j['by_reviewer']))
            OnbReportReviewer(userId: asInt(x['user_id']), name: asStr(x['name']), decided: asInt(x['decided']), avgHours: x['avg_hours'] == null ? null : asDouble(x['avg_hours'])),
        ],
      );
}

/// "36 h" / "1.5 d": hours under two days, days above.
String onbHoursText(double? h) {
  if (h == null) return '—';
  if (h < 48) {
    final v = h.toStringAsFixed(h < 10 ? 1 : 0);
    return t('$v س', '$v h');
  }
  final d = (h / 24).toStringAsFixed(1);
  return t('$d يوم', '$d d');
}

String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

// ═════════════════════════════════════════════════════════════════════════════
//  Presentational body
// ═════════════════════════════════════════════════════════════════════════════

class OnbReportView extends StatelessWidget {
  const OnbReportView({
    super.key,
    required this.report,
    this.types = const [],
    this.type = '',
    this.range,
    this.error,
    this.onType,
    this.onRange,
    this.onClearRange,
    this.onRetry,
    this.onDownload,
    this.onOpenCase,
    this.downloading = false,
  });
  final OnbReport? report;
  final List<OnbType> types;
  final String type;
  final DateTimeRange? range;
  final bool downloading;
  final String? error;
  final ValueChanged<String>? onType;
  final VoidCallback? onRange, onClearRange, onRetry, onDownload;
  final ValueChanged<int>? onOpenCase;

  String _typeLabel(String key) {
    for (final ty in types) {
      if (ty.key == key) return ty.label.isEmpty ? key : ty.label;
    }
    return key;
  }

  @override
  Widget build(BuildContext context) {
    final r = report;
    return ListView(padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.xxxl), children: [
      _filters(context),
      AppSpace.gapMd,
      if (error != null && r == null)
        AppErrorState(message: error, onRetry: onRetry)
      else if (r == null)
        const AppListSkeleton(items: 3)
      else
        ..._body(context, r),
    ]);
  }

  Widget _filters(BuildContext context) {
    final rangeText = range == null ? t('كل الفترات', 'All time') : '${AppTime.date(range!.start)} – ${AppTime.date(range!.end)}';
    return Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, crossAxisAlignment: WrapCrossAlignment.center, children: [
      AppButton.tonal(key: const ValueKey('onb.report.range'), label: rangeText, icon: Icons.date_range_rounded, size: AppButtonSize.sm, onPressed: onRange),
      if (range != null) AppButton.tonal(key: const ValueKey('onb.report.range.clear'), label: t('مسح', 'Clear'), size: AppButtonSize.sm, onPressed: onClearRange),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280, minWidth: 160),
        child: AppDropdown<String>(
          key: const ValueKey('onb.report.type'),
          value: types.any((x) => x.key == type) ? type : '',
          items: [
            DropdownMenuItem(value: '', child: Text(t('كل الأنواع', 'All types'))),
            for (final ty in types) DropdownMenuItem(value: ty.key, child: Text(ty.label.isEmpty ? ty.key : ty.label, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => onType?.call(v ?? ''),
        ),
      ),
    ]);
  }

  List<Widget> _body(BuildContext context, OnbReport r) {
    final inReview = r.count('submitted') + r.count('under_review');
    final decided = r.count('approved') + r.count('active') + r.count('rejected');
    return [
      AppGrid(minTile: 150, spacing: AppSpace.xs, padding: EdgeInsets.zero, children: [
        AppStatTile(key: const ValueKey('onb.report.total'), icon: Icons.folder_copy_outlined, label: t('كل الملفات', 'All files'), value: r.total),
        AppStatTile(key: const ValueKey('onb.report.inreview'), icon: Icons.hourglass_top_rounded, label: t('بانتظار المراجعة', 'Waiting for review'), value: inReview),
        AppStatTile(key: const ValueKey('onb.report.decided'), icon: Icons.verified_outlined, label: t('تم البت فيها', 'Decided'), value: decided),
        AppStatTile(key: const ValueKey('onb.report.overdue'), icon: Icons.schedule_rounded, label: t('متأخرة', 'Overdue'), value: r.overdue.length),
        AppStatTile(key: const ValueKey('onb.report.avg'), icon: Icons.timer_outlined, label: t('متوسط وقت المراجعة', 'Average review time'), value: onbHoursText(r.avgReviewHours)),
      ]),
      AppSection(
        title: t('مراحل الالتحاق', 'Admission funnel'),
        child: AppCard(
          child: r.total == 0
              ? Padding(padding: const EdgeInsets.all(AppSpace.md), child: Center(child: Text(t('لا توجد ملفات في هذه الفترة', 'No files in this period'), style: AppType.meta(context))))
              : AppBarChart(
                  key: const ValueKey('onb.report.funnel'),
                  title: t('عدد الملفات في كل مرحلة', 'Files in each stage'),
                  labels: [for (final s in onbStatuses) onbStatusLabel(s)],
                  series: [
                    AppChartSeries(t('الملفات', 'Files'), [for (final s in onbStatuses) r.count(s).toDouble()])
                  ],
                  integerAxis: true,
                ),
        ),
      ),
      AppSection(
        title: t('الملفات المتأخرة', 'Overdue files'),
        subtitle: t('مستندات مؤجلة تجاوزت موعدها', 'Deferred documents past their date'),
        child: r.overdue.isEmpty
            ? AppCard(child: Text(t('لا توجد ملفات متأخرة', 'Nothing is overdue'), style: AppType.meta(context)))
            : Column(children: [for (final o in r.overdue) Padding(padding: const EdgeInsets.only(bottom: AppSpace.xs), child: _overdueCard(context, o))]),
      ),
      AppSection(
        title: t('حسب المراجع', 'By reviewer'),
        child: r.byReviewer.isEmpty
            ? AppCard(child: Text(t('لم يُبتّ في أي ملف بعد', 'No file has been decided yet'), style: AppType.meta(context)))
            : Column(children: [for (final v in r.byReviewer) Padding(padding: const EdgeInsets.only(bottom: AppSpace.xs), child: _reviewerCard(context, v))]),
      ),
      AppSpace.gapMd,
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: AppButton.secondary(
            key: const ValueKey('onb.report.xlsx'), label: t('تنزيل Excel', 'Download Excel'), icon: Icons.download_rounded, busy: downloading, onPressed: onDownload),
      ),
    ];
  }

  Widget _overdueCard(BuildContext context, OnbReportOverdue o) {
    final c = context.colors;
    return AppCard(
      key: ValueKey('onb.report.overdue.${o.caseId}'),
      onTap: onOpenCase == null ? null : () => onOpenCase!(o.caseId),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(o.fullName.isEmpty ? '#${o.caseId}' : o.fullName, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context))),
          if (o.dueAt != null) ...[AppSpace.gapXs, Text(AppTime.date(o.dueAt!), style: AppType.meta(context).copyWith(color: c.danger))],
        ]),
        Text(_typeLabel(o.typeKey), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
        if (o.missing.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xxs),
            child: Text(t('ناقص: ${o.missing.join('، ')}', 'Missing: ${o.missing.join(', ')}'), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
          ),
      ]),
    );
  }

  Widget _reviewerCard(BuildContext context, OnbReportReviewer v) => AppCard(
        key: ValueKey('onb.report.reviewer.${v.userId}'),
        child: Row(children: [
          Expanded(child: Text(v.name.isEmpty ? '#${v.userId}' : v.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context))),
          AppSpace.gapSm,
          Flexible(
            child: Text(t('${v.decided} قرار · ${onbHoursText(v.avgHours)}', '${v.decided} decided · ${onbHoursText(v.avgHours)}'),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
          ),
        ]),
      );
}

// ═════════════════════════════════════════════════════════════════════════════
//  The page
// ═════════════════════════════════════════════════════════════════════════════

class OnbReportPage extends StatefulWidget {
  const OnbReportPage({super.key, required this.orgId, required this.api, this.types = const [], this.onOpenCase});
  final int orgId;
  final OnboardingApi api;
  final List<OnbType> types;

  /// Opens the case page of an overdue row.
  final ValueChanged<int>? onOpenCase;

  @override
  State<OnbReportPage> createState() => _OnbReportPageState();
}

class _OnbReportPageState extends State<OnbReportPage> {
  OnbReport? _report;
  String? _error;
  String _type = '';
  DateTimeRange? _range;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String? get _from => _range == null ? null : _ymd(_range!.start);
  String? get _to => _range == null ? null : _ymd(_range!.end);

  Future<void> _load() async {
    final r = await widget.api.report(widget.orgId, from: _from, to: _to, type: _type);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _report = OnbReport.fromJson(r.map);
        _error = null;
      } else {
        _error = orgErrorText(r.error!);
      }
    });
  }

  void _refilter(void Function() change) {
    setState(() {
      change();
      _report = null;
      _error = null;
    });
    _load();
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(context: context, firstDate: DateTime(now.year - 6), lastDate: DateTime(now.year + 1), initialDateRange: _range);
    if (picked == null || !mounted) return;
    _refilter(() => _range = picked);
  }

  Future<void> _download() async {
    setState(() => _downloading = true);
    final bytes = await widget.api.reportBytes(widget.orgId, from: _from, to: _to, type: _type);
    final saved = bytes != null && await onbSaveXlsx(bytes, 'admissions-report-${_ymd(DateTime.now())}');
    if (!mounted) return;
    setState(() => _downloading = false);
    showAppNotice(saved ? t('تم حفظ الملف', 'File saved') : t('تعذر تنزيل التقرير', 'Could not download the report'), error: !saved);
  }

  @override
  Widget build(BuildContext context) {
    return ParentComponent(
      featureKey: onboardingFeatureKey,
      child: OrgPushedPage(
        title: t('تقرير الالتحاق والتعيين', 'Admissions report'),
        subtitle: t('المراحل والمتأخرات ووقت المراجعة', 'Stages, overdue files and review time'),
        helpPageId: 'org.onboarding',
        width: AppWidth.content,
        child: OnbReportView(
          report: _report,
          types: widget.types,
          type: _type,
          range: _range,
          error: _error,
          downloading: _downloading,
          onType: (v) => _refilter(() => _type = v),
          onRange: _pickRange,
          onClearRange: () => _refilter(() => _range = null),
          onRetry: _load,
          onDownload: _download,
          onOpenCase: widget.onOpenCase,
        ),
      ),
    );
  }
}
