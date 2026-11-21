// lib/features/org/students/student_report_page.dart — "Students report" (student lifecycle phase 7, contract §9):
// where the organization's students stand at the end of a period and what changed inside it, for staff who are not
// technical. Summary first, then the detail.
//
//   openStudentReport(context, orgId, canExport:)   pushes the page (keeps the OrgSession; Export with students:export)
//   exportStudents(context, orgId, filters:) the Export Studio for the dataset `org_students` with the Students
//                                            list's filters (every row fetched behind a progress dialog, so the
//                                            older in-app flow has them too; the v3 flow renders from the dataset)
//   OrgStudentReportPage                     loads GET …/academic/terms once (the "This term" / "This year" choices;
//                                            a failure only hides them) and GET …/students/status-report?from=&to=
//   StudentReportView                        plain values (the layout harness pumps it): the period picker, the four
//                                            summary cards, enrolment / standing / marks as labelled bars, the
//                                            period's changes (how they happened, as a donut, and which decisions),
//                                            the most common reasons, the recommendations waiting, per programme and
//                                            per level (cards on phones, a scrolling table on wide windows)
//
// Errors: 403 student_forbidden, 409 status_disabled, 422 bad_filter — texts from studentsCodeTexts / orgErrorText.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/export/export_job.dart' show ExportJob;

import '../../admin/admin_common.dart' show t;
import '../../admin/admin_table_export.dart' show exportFetched;
import '../org_page_header.dart' show OrgPushedPage;
import '../org_providers.dart' show orgBase;
import '../org_v3.dart';
import 'student_file_page.dart' show pushStudentPage;
import 'student_report_models.dart';
import 'students_api.dart';
import 'students_errors.dart';
import 'students_models.dart';

/// Opens the Students report of [orgId]. [canExport]: the caller holds `students:export` (the Export button).
Future<void> openStudentReport(BuildContext context, int orgId, {required bool canExport}) =>
    pushStudentPage<void>(context, OrgStudentReportPage(orgId: orgId, canExport: canExport));

String _errorText(ApiException e) => studentsCodeTexts()[e.code] ?? orgErrorText(e);

/// The report's two calls (the Students API file belongs to the list; this page keeps its own).
class StudentReportApi {
  StudentReportApi(this.orgId, [ApiClient? api]) : _api = api ?? ApiClient();
  final int orgId;
  final ApiClient _api;

  Future<OrgCall> report(ReportPeriod p) =>
      orgCall(() => _api.get('$orgBase/orgs/$orgId/students/status-report', queryParams: p.toQuery()), quiet: true);

  Future<OrgCall> terms() => orgCall(() => _api.get('$orgBase/orgs/$orgId/academic/terms'), quiet: true);
}

// ═════════════════════════════════════════════════════════════════════════════
//  Export
// ═════════════════════════════════════════════════════════════════════════════

/// The dataset parameters of [q]: the list's filters (no page, size or sort) plus the org and the language.
Map<String, Object?> studentsExportParams(int orgId, StudentsQuery q) {
  final f = Map<String, Object?>.from(q.toQuery())
    ..remove('page')
    ..remove('size')
    ..remove('sort');
  return {'org_id': orgId, ...f, 'lang': AppConfig.lang};
}

/// The printed "filters" line of [q].
Map<String, String> _filterLine(StudentsQuery q) => {
      if (q.q.trim().isNotEmpty) t('بحث', 'Search'): q.q.trim(),
      if (q.enrol != null) t('القيد', 'Enrolment'): enrolLabel(q.enrol!),
      if (q.standing != null) t('الوضع الأكاديمي', 'Standing'): standingLabel(q.standing!),
      if (q.flag != null) t('العلامة', 'Mark'): flagLabel(q.flag!),
      if (q.level != null) t('المستوى', 'Level'): q.level!,
      if (q.memberStatus != null) t('العضوية', 'Membership'): memberStatusLabel(q.memberStatus!),
    };

Map<String, dynamic> _exportRow(StudentRow s) => {
      'name': s.user.name.trim().isEmpty ? s.user.nameEn : s.user.name,
      'name_en': s.user.nameEn,
      'student_code': s.studentCode,
      'program': s.program?.label,
      'level': s.level,
      'cohort': s.cohort,
      'member_status': s.memberStatus,
      'enrol_status': s.enrolStatus,
      'enrol_until': s.enrolUntil,
      'acad_standing': s.acadStanding,
      'flags': s.flags.map(flagLabel).join('، '),
      'missing_count': s.missingCount,
      'intake': s.intake?.label,
    };

AppTableExport _studentsTable(int orgId, StudentsQuery q, List<Map<String, dynamic>> rows) {
  AppExportColumn col(String id, String ar, String en, {AppColType type = AppColType.text, bool visible = true, bool locked = false, Map<String, String>? statusLabels}) =>
      AppExportColumn(id, t(ar, en), type: type, visible: visible, locked: locked, statusLabels: statusLabels, labels: {'ar': ar, 'en': en});
  return AppTableExport(
    id: 'org_students',
    title: t('الطلاب', 'Students'),
    orgId: orgId,
    serverDataset: 'org_students',
    serverParams: studentsExportParams(orgId, q),
    filters: _filterLine(q),
    columns: [
      col('name', 'الطالب', 'Student', locked: true),
      col('name_en', 'الاسم بالإنجليزية', 'Name in English', visible: false),
      col('student_code', 'الرقم الجامعي', 'Student ID'),
      col('program', 'البرنامج', 'Programme'),
      col('level', 'المستوى', 'Level'),
      col('cohort', 'الدفعة', 'Cohort', visible: false),
      col('member_status', 'العضوية', 'Membership', type: AppColType.status, visible: false, statusLabels: {for (final k in memberStatuses) k: memberStatusLabel(k)}),
      col('enrol_status', 'القيد', 'Enrolment', type: AppColType.status, statusLabels: {for (final k in enrolStatuses) k: enrolLabel(k)}),
      col('enrol_until', 'القيد حتى', 'Enrolment until', type: AppColType.date, visible: false),
      col('acad_standing', 'الوضع الأكاديمي', 'Standing', type: AppColType.status, statusLabels: {for (final k in standings) k: standingLabel(k)}),
      col('flags', 'العلامات', 'Marks'),
      col('missing_count', 'بيانات ناقصة', 'Missing items', type: AppColType.integer, visible: false),
      col('intake', 'القبول', 'Admission', type: AppColType.status, visible: false, statusLabels: {for (final k in intakeLabels) k: intakeLabelText(k)}),
    ],
    rows: rows,
  );
}

/// The Export Studio for the students of [orgId] with the list's [filters] (dataset `org_students`).
Future<void> exportStudents(BuildContext context, int orgId, {StudentsQuery filters = const StudentsQuery(), StudentsApi? api}) {
  final a = api ?? StudentsApi(orgId);
  return exportFetched(
    context,
    fetch: (ExportJob job) async {
      final out = <Map<String, dynamic>>[];
      for (var page = 1; page <= 100; page++) {
        job.throwIfCancelled();
        final r = await a.list(filters.copyWith(page: page, size: 100));
        if (!r.ok) throw r.error!;
        final d = StudentsPageData.fromJson(r.map);
        out.addAll([for (final s in d.items) _exportRow(s)]);
        job.step('${t('جلب الطلاب', 'Fetching students')} ${out.length} / ${d.total}', d.pages <= 0 ? null : page / d.pages);
        if (page >= d.pages || d.items.isEmpty) break;
      }
      return out;
    },
    build: (rows) => _studentsTable(orgId, filters, rows),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
//  The page
// ═════════════════════════════════════════════════════════════════════════════

class OrgStudentReportPage extends StatefulWidget {
  const OrgStudentReportPage({super.key, required this.orgId, this.api, this.canExport = false});
  final int orgId;
  final StudentReportApi? api;

  /// Offer "Export" (the server still checks `students:export`).
  final bool canExport;

  @override
  State<OrgStudentReportPage> createState() => _OrgStudentReportPageState();
}

class _OrgStudentReportPageState extends State<OrgStudentReportPage> {
  late final StudentReportApi _api = widget.api ?? StudentReportApi(widget.orgId);
  List<ReportTerm> _terms = const [];
  late ReportPeriod _period = last30Days(_today);
  StudentReport? _report;
  bool _loading = true;
  String? _error;
  int _seq = 0;

  static DateTime get _today => AppTime.toZone(DateTime.now().toUtc());

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final r = await _api.terms();
    if (!mounted) return;
    if (r.ok) {
      _terms = ReportTerm.listOf(r.map);
      final term = termPeriod(_terms, _today);
      if (term != null) _period = term;
    }
    await _load();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await _api.report(_period);
    if (!mounted || seq != _seq) return;
    setState(() {
      _loading = false;
      if (r.ok) {
        _report = StudentReport.fromJson(r.map);
      } else {
        _error = _errorText(r.error!);
      }
    });
  }

  List<ReportPeriodKind> get _kinds => [
        ReportPeriodKind.days30,
        if (termPeriod(_terms, _today) != null) ReportPeriodKind.term,
        ReportPeriodKind.year,
        ReportPeriodKind.custom,
      ];

  Future<void> _pick(ReportPeriodKind k) async {
    final today = _today;
    ReportPeriod? next = switch (k) {
      ReportPeriodKind.days30 => last30Days(today),
      ReportPeriodKind.term => termPeriod(_terms, today),
      ReportPeriodKind.year => yearPeriod(_terms, today),
      ReportPeriodKind.custom => await _askDates(),
    };
    if (next == null || !mounted || next == _period) return;
    setState(() {
      _period = next;
      _report = null;
    });
    _load();
  }

  Future<ReportPeriod?> _askDates() async {
    final today = _today;
    final last = DateTime(today.year, today.month, today.day);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(last.year - 10),
      lastDate: last,
      initialDateRange: DateTimeRange(start: _period.from.isAfter(last) ? last : _period.from, end: _period.to.isAfter(last) ? last : _period.to),
      helpText: t('اختر بداية الفترة ونهايتها', 'Pick the first and last day'),
    );
    return picked == null ? null : customPeriod(picked.start, picked.end, today);
  }

  void _export() => exportStudents(context, widget.orgId);

  @override
  Widget build(BuildContext context) {
    return OrgPushedPage(
      title: t('تقرير الطلاب', 'Students report'),
      subtitle: t('أين يقف الطلاب وما الذي تغيّر في الفترة', 'Where students stand and what changed in the period'),
      helpPageId: 'org.students',
      width: AppWidth.content,
      primaryAction: widget.canExport
          ? AppButton.tonal(label: t('تصدير', 'Export'), icon: Icons.file_download_outlined, onPressed: _export)
          : null,
      child: StudentReportView(
        report: _report,
        period: _period,
        kinds: _kinds,
        loading: _loading,
        error: _error,
        onRetry: _load,
        onPeriod: _pick,
        onChangeDates: () => _pick(ReportPeriodKind.custom),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The view (plain values)
// ═════════════════════════════════════════════════════════════════════════════

class StudentReportView extends StatelessWidget {
  const StudentReportView({
    super.key,
    required this.report,
    required this.period,
    this.kinds = ReportPeriodKind.values,
    this.loading = false,
    this.error,
    this.onRetry,
    this.onPeriod,
    this.onChangeDates,
  });

  final StudentReport? report;
  final ReportPeriod period;
  final List<ReportPeriodKind> kinds;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;
  final ValueChanged<ReportPeriodKind>? onPeriod;
  final VoidCallback? onChangeDates;

  @override
  Widget build(BuildContext context) {
    final r = report;
    final Widget body;
    if (r == null && loading) {
      body = const AppListSkeleton(items: 5, withAvatar: false, padding: EdgeInsets.zero);
    } else if (r == null && error != null) {
      body = AppErrorState(message: error, onRetry: onRetry);
    } else if (r == null || r.isEmpty) {
      body = AppEmpty(
        icon: Icons.groups_outlined,
        title: t('لا يوجد طلاب بعد', 'No students yet'),
        message: t('يظهر التقرير حين يُضاف طلاب إلى المؤسسة', 'The report fills in once students join the organization'),
      );
    } else {
      body = _ReportBody(report: r, period: period);
    }
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth.isFinite ? box.maxWidth : MediaQuery.sizeOf(context).width;
      return SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: AppWidth.gutter(w) / 2, vertical: AppSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PeriodPicker(period: period, kinds: kinds, onPeriod: onPeriod, onChangeDates: onChangeDates, generatedAt: r?.generatedAt),
            AppSpace.gapMd,
            if (loading && r != null) ...[const LinearProgressIndicator(minHeight: AppBorder.strong), AppSpace.gapSm],
            if (error != null && r != null) ...[_ErrorLine(text: error!, onRetry: onRetry), AppSpace.gapSm],
            body,
          ],
        ),
      );
    });
  }
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine({required this.text, this.onRetry});
  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.error_outline, color: c.danger, size: AppIconSize.md),
          AppSpace.gapSm,
          Expanded(child: Text(text, style: AppType.body(context))),
        ]),
        if (onRetry != null)
          Align(alignment: AlignmentDirectional.centerEnd, child: AppButton.ghost(label: t('أعد المحاولة', 'Try again'), size: AppButtonSize.sm, onPressed: onRetry)),
      ]),
    );
  }
}

class _PeriodPicker extends StatelessWidget {
  const _PeriodPicker({required this.period, required this.kinds, this.onPeriod, this.onChangeDates, this.generatedAt});
  final ReportPeriod period;
  final List<ReportPeriodKind> kinds;
  final ValueChanged<ReportPeriodKind>? onPeriod;
  final VoidCallback? onChangeDates;
  final DateTime? generatedAt;

  @override
  Widget build(BuildContext context) {
    final i = kinds.indexOf(period.kind);
    final range = '${AppTime.wall(period.from)} – ${AppTime.wall(period.to)}';
    final name = period.termLabel;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppTabs(
        items: [for (final k in kinds) AppTabItem(reportPeriodName(k))],
        index: i < 0 ? 0 : i,
        onChanged: (n) => onPeriod?.call(kinds[n]),
      ),
      AppSpace.gapSm,
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpace.xs,
        runSpacing: AppSpace.xxs,
        children: [
          Icon(Icons.event_outlined, size: AppIconSize.sm, color: context.colors.textMedium),
          Text(name == null || name.isEmpty ? range : '$name · $range', style: AppType.label(context)),
          if (period.kind == ReportPeriodKind.custom && onChangeDates != null)
            AppButton.ghost(label: t('غيّر التواريخ', 'Change dates'), size: AppButtonSize.sm, onPressed: onChangeDates),
        ],
      ),
      if (generatedAt != null)
        Padding(
          padding: const EdgeInsetsDirectional.only(top: AppSpace.xxs),
          child: Text(t('أُعدّ في ${AppTime.dateTime(generatedAt!)}', 'Prepared on ${AppTime.dateTime(generatedAt!)}'), style: AppType.meta(context)),
        ),
    ]);
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({required this.report, required this.period});
  final StudentReport report;
  final ReportPeriod period;

  @override
  Widget build(BuildContext context) {
    final r = report, a = r.atTo;
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= AppWidth.reading.max;
      Widget pair(Widget x, Widget y) => wide
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: x), AppSpace.gapMd, Expanded(child: y)])
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [x, AppSpace.gapMd, y]);

      final enrol = reportBars(a.enrolment, enrolStatuses, enrolLabel);
      final standing = reportBars(a.standing, standings, standingLabel);
      final flags = reportBars(a.flags, flagKeys, flagLabel);
      final decisions = [for (final d in r.byDecision) if (d.count > 0) (key: d.key, label: d.label, count: d.count)];
      final reasons = [for (final x in r.topReasons) if (x.count > 0) (key: x.code, label: reportReasonLabel(x.code), count: x.count)];
      final pending = [for (final d in r.pendingByDecision) if (d.count > 0) (key: d.key, label: d.label, count: d.count)];

      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // ── summary ──
        AppKpiGrid(children: [
          AppStatCard(
            icon: Icons.groups_outlined,
            value: '${a.total}',
            label: t('الطلاب', 'Students'),
            footer: t('${a.studying} مقيد · ${a.paused} موقوف أو مؤجل', '${a.studying} enrolled · ${a.paused} paused'),
          ),
          AppStatCard(
            icon: Icons.priority_high_rounded,
            value: '${a.attention}',
            label: t('يحتاجون متابعة', 'Need attention'),
            tone: AppBlockTone.peach,
            warn: a.attention > 0,
            footer: t('إنذار، إعادة، فرصة أخيرة أو متعثر', 'Warning, repeating, final chance or struggling'),
          ),
          AppStatCard(
            icon: Icons.swap_horiz_rounded,
            value: '${r.movementsTotal}',
            label: t('تغييرات في الفترة', 'Changes in the period'),
            tone: AppBlockTone.sky,
            footer: r.undone > 0 ? countText(r.undone, ar1: 'تراجع واحد', ar2: 'تراجعان', arFew: '{n} تراجعات', arMany: '{n} تراجعاً', en1: '1 undone', en: '{n} undone') : t('لا تراجع', 'Nothing undone'),
          ),
          AppStatCard(
            icon: Icons.pending_actions_outlined,
            value: '${r.pendingTotal}',
            label: t('توصيات تنتظر القرار', 'Recommendations waiting'),
            tone: AppBlockTone.gold,
            footer: t('مفتوحة الآن', 'Open now'),
          ),
        ]),

        // ── where they stand ──
        AppSection(
          title: t('أين يقف الطلاب', 'Where students stand'),
          subtitle: t('في ${AppTime.wall(period.to)}', 'On ${AppTime.wall(period.to)}'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            pair(
              _BarsCard(title: t('القيد', 'Enrolment'), bars: enrol, total: a.total, empty: t('لا أحد', 'No one')),
              _BarsCard(title: t('الوضع الأكاديمي', 'Academic standing'), bars: standing, total: a.total, empty: t('لا أحد', 'No one')),
            ),
            AppSpace.gapMd,
            _BarsCard(
              title: t('العلامات', 'Marks'),
              hint: t('قد يحمل الطالب أكثر من علامة', 'A student can carry more than one mark'),
              bars: flags,
              total: a.total,
              empty: t('لا يحمل أي طالب علامة', 'No student carries a mark'),
            ),
          ]),
        ),

        // ── what changed ──
        AppSection(
          title: t('ما الذي تغيّر في الفترة', 'What changed in the period'),
          child: r.movementsTotal == 0
              ? _QuietCard(icon: Icons.check_circle_outline, text: t('لم يتغير وضع أي طالب في هذه الفترة', 'No student\'s status changed in this period'))
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  pair(
                    _HowCard(report: r),
                    _BarsCard(title: t('القرارات', 'Decisions'), bars: decisions, empty: t('لا قرارات', 'No decisions')),
                  ),
                  AppSpace.gapMd,
                  _BarsCard(
                    title: t('أكثر الأسباب', 'Most common reasons'),
                    hint: t('بدون التراجعات', 'Undo steps not counted'),
                    bars: reasons,
                    empty: t('لم يُذكر سبب', 'No reason was given'),
                  ),
                ]),
        ),

        // ── waiting ──
        if (r.pendingTotal > 0)
          AppSection(
            title: t('توصيات تنتظر القرار', 'Recommendations waiting for a decision'),
            child: _BarsCard(title: t('حسب القرار المقترح', 'By the proposed decision'), bars: pending, empty: t('لا توصيات', 'No recommendations')),
          ),

        // ── per programme / level ──
        if (r.byProgramme.isNotEmpty)
          AppSection(
            title: t('حسب البرنامج', 'By programme'),
            child: ReportGroupTable(groups: r.byProgramme, none: t('بلا برنامج', 'No programme'), nameHeader: t('البرنامج', 'Programme')),
          ),
        if (r.byLevel.isNotEmpty)
          AppSection(
            title: t('حسب المستوى', 'By level'),
            child: ReportGroupTable(groups: r.byLevel, none: t('بلا مستوى', 'No level'), nameHeader: t('المستوى', 'Level')),
          ),
        AppSpace.gapLg,
      ]);
    });
  }
}

class _QuietCard extends StatelessWidget {
  const _QuietCard({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => AppCard(
        child: Row(children: [
          Icon(icon, size: AppIconSize.md, color: context.colors.textMedium),
          AppSpace.gapSm,
          Expanded(child: Text(text, style: AppType.body(context))),
        ]),
      );
}

/// A titled card of labelled horizontal bars; [total] adds each row's share of it.
class _BarsCard extends StatelessWidget {
  const _BarsCard({required this.title, required this.bars, required this.empty, this.total, this.hint});
  final String title;
  final String? hint;
  final List<ReportBar> bars;
  final int? total;
  final String empty;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: AppType.section(context)),
        if (hint != null) Text(hint!, style: AppType.meta(context)),
        AppSpace.gapSm,
        if (bars.isEmpty) Text(empty, style: AppType.meta(context)) else ReportBarList(bars: bars, total: total, title: title),
      ]),
    );
  }
}

/// Labelled horizontal bars, longest = full width (the value and, with [total], its share at the end).
class ReportBarList extends StatelessWidget {
  const ReportBarList({super.key, required this.bars, this.total, this.title});
  final List<ReportBar> bars;
  final int? total;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = appChartPalette(context).first;
    final top = bars.fold<int>(0, (m, b) => math.max(m, b.count));
    final sem = [for (final b in bars) '${b.label}: ${b.count}'].join('. ');
    return Semantics(
      container: true,
      label: title == null ? sem : '$title. $sem',
      child: ExcludeSemantics(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final b in bars)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Text(b.label, style: AppType.row(context))),
                  AppSpace.gapXs,
                  Text(
                    total != null && total! > 0 ? '${b.count} · ${(b.count * 100 / total!).round()}%' : '${b.count}',
                    style: AppType.label(context).copyWith(color: c.textMedium, fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ]),
                const SizedBox(height: AppSpace.xxs),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: SizedBox(
                    height: AppSpace.xs,
                    child: Stack(fit: StackFit.expand, children: [
                      ColoredBox(color: c.inputBg),
                      FractionallySizedBox(
                        alignment: AlignmentDirectional.centerStart,
                        widthFactor: top <= 0 ? 0 : b.count / top,
                        child: ColoredBox(color: color),
                      ),
                    ]),
                  ),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}

/// How the period's changes happened: by the rules, by staff, from a request, undone (a donut of `by_via`).
class _HowCard extends StatelessWidget {
  const _HowCard({required this.report});
  final StudentReport report;

  @override
  Widget build(BuildContext context) {
    final vias = report.vias;
    final dim = report.byDimension;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t('كيف حدثت التغييرات', 'How the changes happened'), style: AppType.section(context)),
        Text(
          t('القيد ${dim['enrolment'] ?? 0} · الوضع ${dim['standing'] ?? 0} · العلامات ${dim['flag'] ?? 0}',
              'Enrolment ${dim['enrolment'] ?? 0} · Standing ${dim['standing'] ?? 0} · Marks ${dim['flag'] ?? 0}'),
          style: AppType.meta(context),
        ),
        AppSpace.gapMd,
        if (vias.isEmpty)
          Text(t('لا تغييرات', 'No changes'), style: AppType.meta(context))
        else
          Center(
            child: AppDonut(
              title: t('كيف حدثت التغييرات', 'How the changes happened'),
              parts: [for (final v in vias) AppChartPart(reportViaLabel(v.via), v.count.toDouble())],
            ),
          ),
      ]),
    );
  }
}

/// Per programme / level: a card per group on phones, a table (scrolling sideways when needed) on wide windows.
class ReportGroupTable extends StatelessWidget {
  const ReportGroupTable({super.key, required this.groups, required this.none, required this.nameHeader});
  final List<ReportGroup> groups;
  final String none, nameHeader;

  static List<(String, int Function(ReportCounts))> get _cols => [
        (t('الطلاب', 'Students'), (c) => c.total),
        (t('مقيد', 'Enrolled'), (c) => c.studying),
        (t('موقوف أو مؤجل', 'Paused'), (c) => c.paused),
        (t('غادر', 'Left'), (c) => c.left),
        (t('يحتاجون متابعة', 'Need attention'), (c) => c.attention),
        (t('تغييرات', 'Changes'), (c) => c.movements),
      ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth < AppWidth.phoneMax) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final g in groups) ...[_card(context, g), AppSpace.gapSm],
        ]);
      }
      return _table(context, box.maxWidth);
    });
  }

  Widget _card(BuildContext context, ReportGroup g) {
    final c = context.colors;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(g.label(none), style: AppType.bodyStrong(context)),
        if (g.code != null) Text(g.code!, style: AppType.meta(context)),
        AppSpace.gapSm,
        Wrap(spacing: AppSpace.md, runSpacing: AppSpace.xs, children: [
          for (final (label, of) in _cols)
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('${of(g.counts)}', style: AppType.figure(context).copyWith(color: label == _cols[4].$1 && g.counts.attention > 0 ? c.danger : null)),
              Text(label, style: AppType.meta(context)),
            ]),
        ]),
      ]),
    );
  }

  Widget _table(BuildContext context, double available) {
    final c = context.colors;
    final cols = _cols;
    // the name takes 3 shares, each figure 1; below this the table scrolls sideways
    final minWidth = AppWidth.phoneMax;
    final width = math.max(available, minWidth);
    Widget cell(String text, {bool head = false, bool alert = false, bool name = false}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.sm),
          child: Text(
            text,
            textAlign: name ? TextAlign.start : TextAlign.end,
            style: (head ? AppType.label(context).copyWith(color: c.textMedium) : (name ? AppType.row(context) : AppType.row(context).copyWith(fontFeatures: const [FontFeature.tabularFigures()])))
                .copyWith(color: alert ? c.danger : null),
          ),
        );
    Widget line(List<Widget> cells, {bool divider = true}) => DecoratedBox(
          decoration: BoxDecoration(border: divider ? Border(bottom: BorderSide(color: c.divider, width: AppBorder.hairline)) : null),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(flex: 3, child: cells.first),
            for (final x in cells.skip(1)) Expanded(child: x),
          ]),
        );
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs),
      child: LayoutBuilder(builder: (context, inner) {
        final w = math.max(inner.maxWidth, width - 2 * AppSpace.xs);
        return AppHScroll(
          child: SizedBox(
            width: w,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              line([cell(nameHeader, head: true, name: true), for (final (label, _) in cols) cell(label, head: true)]),
              for (var i = 0; i < groups.length; i++)
                line([
                  cell(groups[i].code == null ? groups[i].label(none) : '${groups[i].label(none)} (${groups[i].code})', name: true),
                  for (var k = 0; k < cols.length; k++)
                    cell('${cols[k].$2(groups[i].counts)}', alert: k == 4 && groups[i].counts.attention > 0),
                ], divider: i < groups.length - 1),
            ]),
          ),
        );
      }),
    );
  }
}

