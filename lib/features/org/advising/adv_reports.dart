// lib/features/org/advising/adv_reports.dart — the advising reports (Phase 8, docs/advising/PHASE8.md): the
// compliance report per term (#25), quick exports and e-mailed schedules. Every file is an Export Studio server
// dataset (`adv.compliance`, `adv.advisors`, `adv.students`, `adv.flags`, `adv.appointments`): a run is started with
// `ExportStudioApi.createRun`, followed with `JobWatch` on `job_updated` kind `export`, then downloaded; a schedule is
// the Export Studio's own sheet. No export code of its own.
//
//   advServerExport        run a dataset now, wait for it, save the file
//   AdvComplianceCard      the compliance preview with its term picker and buttons (plain values)
//   AdvQuickExportsCard    the other datasets, Excel / PDF each (plain values)
//   AdvSchedulesCard       this organization's advising schedules: pause / resume, edit, delete (plain values)
//   AdvReportsPage         loads and wires them
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/export/export_studio_api.dart';
import 'package:flutter_education_app/features/shared/exports/export_schedules_page.dart' show ExportScheduleCard, downloadExportRun, showScheduleExportSheet;

import '../../admin/admin_common.dart' show asInt, t;
import '../org_page_header.dart' show OrgPageRefresh, OrgPushedPage;
import '../org_page_kit.dart';
import '../org_v3.dart' show orgCall;
import 'adv_analytics_api.dart';
import 'adv_analytics_models.dart';
import 'adv_analytics_parts.dart';
import 'adv_drill_page.dart';
import 'adv_models.dart' show AdvPolicy;
import 'adv_parts.dart';

/// The advising datasets and their names.
String advDatasetTitle(String key) => switch (key) {
      'adv.compliance' => t('تقرير الالتزام', 'Compliance report'),
      'adv.advisors' => t('أداء المرشدين', 'Advisor figures'),
      'adv.students' => t('الطلاب ومؤشراتهم', 'Students and their indicators'),
      'adv.flags' => t('التنبيهات', 'Alerts'),
      'adv.appointments' => t('اللقاءات', 'Meetings'),
      'adv.outreach' => t('مستلمو رسالة', 'Message recipients'),
      _ => key,
    };

String advDatasetHint(String key) => switch (key) {
      'adv.advisors' => t('الحمل والتواصل والردود لكل مرشد', 'Load, contact and replies of each advisor'),
      'adv.students' => t('كل طالب: المعدل، الخطر، آخر تواصل، المرشد', 'Each student: CGPA, risk, last contact, advisor'),
      'adv.flags' => t('بلا نصوص الملاحظات', 'Without any note text'),
      'adv.appointments' => t('بلا أسباب الإلغاء', 'Without cancellation reasons'),
      _ => '',
    };

/// Starts a server run of [dataset], waits for it (the export event, a slow poll as the fallback) and saves the
/// file. Says what happened in both languages; true when the file was saved.
Future<bool> advServerExport(BuildContext context, {required String dataset, required Map<String, Object?> params, required String format}) async {
  final api = ExportStudioApi.instance;
  final title = advDatasetTitle(dataset);
  final r = await api.createRun(dataset: dataset, params: params, format: format, lang: AppConfig.lang == 'en' ? 'en' : 'ar');
  if (!r.ok) {
    showAppNotice(r.missing ? t('التقارير تحتاج تحديث الخادم.', 'Reports need a server update.') : r.error!, error: true);
    return false;
  }
  showAppNotice(t('يجري تجهيز «$title»…', 'Preparing "$title"…'));
  var run = r.data!;
  final watch = JobWatch(kind: 'export', id: '${run.id}');
  try {
    final until = DateTime.now().add(const Duration(minutes: 4));
    while (run.pending && DateTime.now().isBefore(until)) {
      await watch.next(const Duration(seconds: 3), fallbackEvery: const Duration(seconds: 15));
      final s = await api.run(run.id);
      if (s.ok) run = s.data!;
    }
  } finally {
    watch.dispose();
  }
  if (run.failed) {
    showAppNotice(t('تعذّر تجهيز «$title»${run.error == null ? '' : ': ${run.error}'}', 'Could not prepare "$title"${run.error == null ? '' : ': ${run.error}'}'), error: true);
    return false;
  }
  if (!run.ready) {
    showAppNotice(t('ما زال «$title» قيد التجهيز — تجده في قائمة تصديراتك عند اكتماله.', '"$title" is still being prepared — it will be in your exports list when ready.'));
    return false;
  }
  return downloadExportRun(run, api: api);
}

// ═════════════════════════════════════════════════════════════════════════════
//  Compliance
// ═════════════════════════════════════════════════════════════════════════════

class AdvComplianceCard extends StatelessWidget {
  const AdvComplianceCard({
    super.key,
    required this.load,
    this.report,
    this.terms = const [],
    this.termId,
    this.errorText,
    this.busyFormat,
    this.onTerm,
    this.onRetry,
    this.onExport,
    this.onSchedule,
    this.onAdvisor,
  });

  final AdvLoad load;
  final AdvCompliance? report;
  final List<AdvTerm> terms;
  final int? termId;
  final String? errorText;

  /// `pdf` · `xlsx` while that file is being prepared.
  final String? busyFormat;
  final ValueChanged<int?>? onTerm;
  final VoidCallback? onRetry, onSchedule;
  final ValueChanged<String>? onExport;
  final ValueChanged<AdvComplianceRow>? onAdvisor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = report;
    final shownTerm = termId ?? r?.term?.id;
    final hasTerm = terms.any((x) => x.id == shownTerm);
    return AdvAnCard(
      icon: Icons.fact_check_rounded,
      title: t('تقرير الالتزام', 'Compliance report'),
      subtitle: r == null
          ? t('تغطية كل مرشد لطلابه في الفصل', 'How well each advisor covered their students in a term')
          : t('الهدف: تواصل مع ${advFigure(r.targetCoveragePct)}% من الطلاب، و${advFigure(r.targetMinContacts)} تواصل لكل طالب على الأقل',
              'Target: contact ${advFigure(r.targetCoveragePct)}% of students, at least ${advFigure(r.targetMinContacts)} contact per student'),
      children: [
        if (terms.isNotEmpty) ...[
          AppDropdown<int?>(
            value: hasTerm ? shownTerm : null,
            decoration: InputDecoration(labelText: t('الفصل', 'Term')),
            items: [
              if (!hasTerm) DropdownMenuItem<int?>(value: null, child: Text(r?.term?.title ?? t('آخر فصل له نتائج', 'The latest term with results'))),
              for (final x in terms) DropdownMenuItem<int?>(value: x.id, child: Text(x.current ? t('${x.title} (الحالي)', '${x.title} (current)') : x.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: onTerm,
          ),
          const SizedBox(height: AppSpace.sm),
        ],
        if (load != AdvLoad.ready || r == null)
          load == AdvLoad.loading || load == AdvLoad.ready
              ? const AppListSkeleton(items: 2, withAvatar: false, padding: EdgeInsets.zero)
              : AdvChartNote(errorText ?? t('تعذّر تحميل التقرير.', 'The report could not be loaded.'), icon: Icons.cloud_off_rounded)
        else ...[
          if (r.pending)
            AppBanner(icon: Icons.hourglass_top_rounded, color: c.warning, text: t('لم يُحسب هذا الفصل بعد — يُحسب في التحديث اليومي القادم.', 'This term is not computed yet — the next daily update computes it.'))
          else ...[
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
              AppBadgePill(t('يحققون الهدف · ${r.meeting}', 'Meet the target · ${r.meeting}'), color: c.success, icon: Icons.check_rounded),
              if (r.missing > 0) AppBadgePill(t('دون الهدف · ${r.missing}', 'Below the target · ${r.missing}'), color: c.danger, icon: Icons.priority_high_rounded),
              if (r.asOf != null) AppBadgePill(t('حُسب ${AppTime.dateTime(r.asOf!)}', 'Computed ${AppTime.dateTime(r.asOf!)}'), color: c.textMedium, icon: Icons.update_rounded),
            ]),
            const SizedBox(height: AppSpace.sm),
            AdvComplianceTable(report: r, onAdvisor: onAdvisor),
          ],
        ],
        const SizedBox(height: AppSpace.sm),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          AppButton.secondary(
            icon: Icons.picture_as_pdf_outlined,
            label: 'PDF',
            busy: busyFormat == 'pdf',
            onPressed: onExport == null || busyFormat != null || r == null || r.pending ? null : () => onExport!('pdf'),
          ),
          AppButton.secondary(
            icon: Icons.grid_on_rounded,
            label: 'Excel',
            busy: busyFormat == 'xlsx',
            onPressed: onExport == null || busyFormat != null || r == null || r.pending ? null : () => onExport!('xlsx'),
          ),
          if (onSchedule != null) AppButton.ghost(icon: Icons.schedule_send_outlined, label: t('جدولة بالبريد', 'Schedule by e-mail'), onPressed: onSchedule),
        ]),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Quick exports · schedules
// ═════════════════════════════════════════════════════════════════════════════

class AdvQuickExportsCard extends StatelessWidget {
  const AdvQuickExportsCard({super.key, required this.datasets, this.busy, this.onExport, this.onSchedule});
  final List<String> datasets;

  /// `<dataset>:<format>` being prepared.
  final String? busy;
  final void Function(String dataset, String format)? onExport;
  final ValueChanged<String>? onSchedule;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AdvAnCard(
      icon: Icons.file_download_outlined,
      title: t('تصدير سريع', 'Quick exports'),
      subtitle: t('بفلاتر الصفحة الحالية', 'With the page\'s current filters'),
      children: [
        for (var i = 0; i < datasets.length; i++) ...[
          if (i > 0) Divider(height: AppSpace.md, color: c.divider),
          LayoutBuilder(builder: (context, box) {
            final d = datasets[i];
            final text = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(advDatasetTitle(d), style: AppType.row(context).copyWith(fontWeight: FontWeight.w600)),
              if (advDatasetHint(d).isNotEmpty) Text(advDatasetHint(d), style: AppType.meta(context)),
            ]);
            final buttons = Wrap(spacing: AppSpace.xxs, children: [
              for (final f in const ['xlsx', 'pdf'])
                AppButton.ghost(
                  icon: f == 'pdf' ? Icons.picture_as_pdf_outlined : Icons.grid_on_rounded,
                  label: f == 'pdf' ? 'PDF' : 'Excel',
                  busy: busy == '$d:$f',
                  onPressed: onExport == null || busy != null ? null : () => onExport!(d, f),
                ),
              if (onSchedule != null)
                IconButton(
                  tooltip: t('جدولة', 'Schedule'),
                  constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
                  icon: const Icon(Icons.schedule_send_outlined, size: AppIconSize.md),
                  onPressed: () => onSchedule!(d),
                ),
            ]);
            if (box.maxWidth < 520) return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [text, const SizedBox(height: AppSpace.xxs), buttons]);
            return Row(children: [Expanded(child: text), buttons]);
          }),
        ],
      ],
    );
  }
}

class AdvSchedulesCard extends StatelessWidget {
  const AdvSchedulesCard({super.key, required this.load, this.schedules = const [], this.busyId, this.onToggle, this.onRunNow, this.onEdit, this.onDelete});
  final AdvLoad load;
  final List<ExportScheduleInfo> schedules;
  final int? busyId;
  final ValueChanged<ExportScheduleInfo>? onToggle, onRunNow, onEdit, onDelete;

  @override
  Widget build(BuildContext context) => AdvAnCard(
        icon: Icons.schedule_send_rounded,
        title: t('التقارير المجدولة', 'Scheduled reports'),
        subtitle: t('تُرسل بالبريد يومياً أو أسبوعياً أو شهرياً', 'E-mailed every day, week or month'),
        children: [
          if (load == AdvLoad.loading)
            const AppListSkeleton(items: 1, withAvatar: false, padding: EdgeInsets.zero)
          else if (load != AdvLoad.ready)
            AdvChartNote(t('تعذّر تحميل الجداول.', 'The schedules could not be loaded.'), icon: Icons.cloud_off_rounded)
          else if (schedules.isEmpty)
            AdvChartNote(t('لا تقارير مجدولة بعد — اختر «جدولة بالبريد» من تقرير أو تصدير.', 'No scheduled reports yet — choose "Schedule by e-mail" on a report or an export.'))
          else
            for (final s in schedules)
              ExportScheduleCard(
                info: s,
                datasetTitle: advDatasetTitle(s.dataset),
                busy: busyId == s.id,
                onToggle: onToggle == null ? null : () => onToggle!(s),
                onRunNow: onRunNow == null ? null : () => onRunNow!(s),
                onEdit: onEdit == null ? null : () => onEdit!(s),
                onDelete: onDelete == null ? null : () => onDelete!(s),
              ),
        ],
      );
}

// ═════════════════════════════════════════════════════════════════════════════
//  Page
// ═════════════════════════════════════════════════════════════════════════════

class AdvReportsPage extends StatelessWidget {
  const AdvReportsPage({super.key, required this.orgId, required this.manage, this.filter = const AdvAnalyticsFilter(), this.terms = const []});
  final int orgId;

  /// A director (every dataset); else the aggregate tier (advisors and compliance only).
  final bool manage;
  final AdvAnalyticsFilter filter;
  final List<AdvTerm> terms;

  @override
  Widget build(BuildContext context) => OrgPushedPage(
        title: t('التقارير والتصدير', 'Reports and exports'),
        helpPageId: 'org.advising',
        maxWidth: AppWidth.wide.max,
        child: _ReportsBody(orgId: orgId, manage: manage, filter: filter, terms: terms),
      );
}

class _ReportsBody extends StatefulWidget {
  const _ReportsBody({required this.orgId, required this.manage, required this.filter, required this.terms});
  final int orgId;
  final bool manage;
  final AdvAnalyticsFilter filter;
  final List<AdvTerm> terms;

  @override
  State<_ReportsBody> createState() => _ReportsBodyState();
}

class _ReportsBodyState extends State<_ReportsBody> {
  late final AdvAnalyticsApi _api = AdvAnalyticsApi(widget.orgId);
  OrgPageRefresh? _refresh;
  AdvLoad _load = AdvLoad.loading, _schedLoad = AdvLoad.loading;
  AdvCompliance? _report;
  String? _error, _busyFormat, _busyQuick;
  int? _termId, _busySchedule;
  List<ExportScheduleInfo> _schedules = const [];

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
    await Future.wait([_loadReport(), _loadSchedules()]);
    if (mounted) OrgPageRefresh.reportUpdated(context);
  }

  Future<void> _loadReport() async {
    setState(() => _load = AdvLoad.loading);
    final r = await orgCall(() => _api.compliance(termId: _termId), quiet: true);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _report = r.data as AdvCompliance;
        _load = AdvLoad.ready;
      } else {
        _load = advFailLoad(r);
        _error = r.endpointMissing ? t('تقرير الالتزام يحتاج تحديث الخادم.', 'The compliance report needs a server update.') : advErrorText(r.error!);
      }
    });
  }

  Future<void> _loadSchedules() async {
    final r = await ExportStudioApi.instance.schedules();
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _schedules = [
          for (final s in r.data!)
            if (s.dataset.startsWith('adv.') && asInt(s.params['org_id']) == widget.orgId) s,
        ];
        _schedLoad = AdvLoad.ready;
      } else {
        _schedLoad = AdvLoad.failed;
      }
    });
  }

  Map<String, Object?> get _complianceParams => {'org_id': widget.orgId, 'term_id': ?(_termId ?? _report?.term?.id)};

  Map<String, Object?> _paramsOf(String dataset) => switch (dataset) {
        'adv.compliance' => _complianceParams,
        'adv.students' => {'org_id': widget.orgId, 'metric': 'all', ...widget.filter.toQuery()},
        'adv.flags' => {'org_id': widget.orgId, 'status': 'open', ...widget.filter.toQuery()},
        _ => {'org_id': widget.orgId, ...widget.filter.toQuery()},
      };

  Future<void> _exportCompliance(String format) async {
    setState(() => _busyFormat = format);
    await advServerExport(context, dataset: 'adv.compliance', params: _complianceParams, format: format);
    if (mounted) setState(() => _busyFormat = null);
  }

  Future<void> _quick(String dataset, String format) async {
    setState(() => _busyQuick = '$dataset:$format');
    await advServerExport(context, dataset: dataset, params: _paramsOf(dataset), format: format);
    if (mounted) setState(() => _busyQuick = null);
  }

  Future<void> _schedule(String dataset) async {
    final saved = await showScheduleExportSheet(context, dataset: dataset, params: _paramsOf(dataset), format: 'pdf', lang: AppConfig.lang, name: advDatasetTitle(dataset));
    if (saved && mounted) {
      showAppNotice(t('حُفظ التقرير المجدول', 'The scheduled report is saved'));
      _loadSchedules();
    }
  }

  Future<void> _scheduleAction(ExportScheduleInfo s, Future<ExportResult<Object?>> Function() call, String ok) async {
    setState(() => _busySchedule = s.id);
    final r = await call();
    if (!mounted) return;
    setState(() => _busySchedule = null);
    if (r.ok) {
      showAppNotice(ok);
      _loadSchedules();
    } else {
      showAppNotice(r.error!, error: true);
    }
  }

  Future<void> _delete(ExportScheduleInfo s) async {
    final yes = await appConfirm(context, danger: true, confirmLabel: t('حذف', 'Delete'), message: t('حذف التقرير المجدول «${s.name.isEmpty ? advDatasetTitle(s.dataset) : s.name}»؟', 'Delete the scheduled report "${s.name.isEmpty ? advDatasetTitle(s.dataset) : s.name}"?'));
    if (!yes || !mounted) return;
    await _scheduleAction(s, () => ExportStudioApi.instance.deleteSchedule(s.id), t('حُذف التقرير المجدول', 'The scheduled report is deleted'));
  }

  Future<void> _edit(ExportScheduleInfo s) async {
    final saved = await showScheduleExportSheet(context, edit: s);
    if (saved && mounted) {
      showAppNotice(t('حُفظ التقرير المجدول', 'The scheduled report is saved'));
      _loadSchedules();
    }
  }

  void _openAdvisor(AdvComplianceRow r) {
    final id = r.userId;
    if (id == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => AdvDrillPage(
        orgId: widget.orgId,
        drill: AdvDrill(metric: 'advisor', key: '$id'),
        filter: widget.filter,
        title: t('طلاب ${r.shown}', '${r.shown}\'s students'),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final compliance = AdvComplianceCard(
      load: _load,
      report: _report,
      terms: widget.terms,
      termId: _termId,
      errorText: _error,
      busyFormat: _busyFormat,
      onTerm: (id) {
        setState(() => _termId = id);
        _loadReport();
      },
      onRetry: _loadReport,
      onExport: _exportCompliance,
      onSchedule: () => _schedule('adv.compliance'),
      onAdvisor: widget.manage ? _openAdvisor : null,
    );
    final quick = AdvQuickExportsCard(
      datasets: widget.manage ? const ['adv.students', 'adv.advisors', 'adv.flags', 'adv.appointments'] : const ['adv.advisors'],
      busy: _busyQuick,
      onExport: _quick,
      onSchedule: _schedule,
    );
    final schedules = AdvSchedulesCard(
      load: _schedLoad,
      schedules: _schedules,
      busyId: _busySchedule,
      onToggle: (s) => _scheduleAction(
        s,
        () => s.paused ? ExportStudioApi.instance.resumeSchedule(s.id) : ExportStudioApi.instance.pauseSchedule(s.id),
        s.paused ? t('استُؤنف التقرير المجدول', 'The scheduled report is resumed') : t('أُوقف التقرير المجدول مؤقتاً', 'The scheduled report is paused'),
      ),
      onRunNow: (s) => _scheduleAction(s, () => ExportStudioApi.instance.runScheduleNow(s.id), t('بدأ التشغيل — يصل الملف حين يكتمل', 'Started — the file arrives when it is ready')),
      onEdit: _edit,
      onDelete: _delete,
    );
    return OrgPageBody(
      child: LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 1000;
        return AdvPageFrame(maxWidth: AppWidth.wide.max, children: [
          compliance,
          const SizedBox(height: AppSpace.md),
          if (wide)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: quick),
              const SizedBox(width: AppSpace.md),
              Expanded(child: schedules),
            ])
          else ...[
            quick,
            const SizedBox(height: AppSpace.md),
            schedules,
          ],
        ]);
      }),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Settings group (adv_config_page.dart, the organization's row only)
// ═════════════════════════════════════════════════════════════════════════════

/// The policy keys of Phase 8 with their defaults and limits: (key, default, min, max).
const advReportsPolicyKeys = [('activity_days', 14, 1, 90), ('compliance_target_pct', 80, 1, 100), ('compliance_min_contacts', 1, 1, 10), ('outreach_weekly_cap', 3, 1, 20)];

/// "Reports and outreach" in the advising settings: the activity window, the compliance targets, the weekly
/// outreach cap. [hint] draws where a value comes from; [onField] null = read only.
List<Widget> advReportsPolicyFields(BuildContext context, {required AdvPolicy shown, void Function(String field, dynamic value)? onField, required Widget Function(String field) hint}) {
  int value(String k, int d) {
    final v = shown.value(k);
    return v is num ? v.toInt() : d;
  }

  String title(String k) => switch (k) {
        'activity_days' => t('نافذة النشاط', 'Activity window'),
        'compliance_target_pct' => t('هدف التغطية', 'Coverage target'),
        'compliance_min_contacts' => t('أقل تواصل لكل طالب', 'Fewest contacts per student'),
        _ => t('حد الرسائل الأسبوعي', 'Weekly message limit'),
      };
  String sub(String k) => switch (k) {
        'activity_days' => t('المرشد نشط إن التقى أو رد أو كتب ملاحظة خلالها (بالأيام)', 'An advisor is active with a meeting, reply or note within it (days)'),
        'compliance_target_pct' => t('نسبة الطلاب الذين يتواصل معهم المرشد في الفصل', 'The share of students an advisor contacts in a term'),
        'compliance_min_contacts' => t('في الفصل، لتقرير الالتزام', 'In a term, for the compliance report'),
        _ => t('أقصى رسائل جماعية تصل الطالب في 7 أيام', 'The most group messages a student gets in 7 days'),
      };
  final c = context.colors;
  return [
    AdvSectionTitle(t('التقارير والرسائل', 'Reports and outreach'), subtitle: t('للمؤسسة كلها', 'For the whole organization')),
    AppCard(
      padding: AppSpace.card,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < advReportsPolicyKeys.length; i++) ...[
          if (i > 0) Divider(height: AppSpace.lg, color: c.divider),
          Builder(builder: (context) {
            final (k, d, min, max) = advReportsPolicyKeys[i];
            final text = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title(k), style: AppType.bodyStrong(context)),
              Text(sub(k), style: AppType.meta(context)),
            ]);
            final stepper = AdvStepper(
              label: title(k),
              value: value(k, d).clamp(min, max),
              min: min,
              max: max,
              step: k == 'compliance_target_pct' ? 5 : 1,
              suffix: k == 'compliance_target_pct' ? '%' : null,
              onChanged: onField == null ? null : (v) => onField(k, v),
            );
            return LayoutBuilder(builder: (context, box) {
              final row = box.maxWidth < 300
                  ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [text, const SizedBox(height: AppSpace.xs), stepper])
                  : Row(children: [Expanded(child: text), const SizedBox(width: AppSpace.sm), stepper]);
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [row, hint(k)]);
            });
          }),
        ],
      ]),
    ),
  ];
}
