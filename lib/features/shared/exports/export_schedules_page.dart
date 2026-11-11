// lib/features/shared/exports/export_schedules_page.dart
//
// Scheduled exports (feature key `export.schedules`, `/api/v1/exports/schedules`, D-130): a server dataset rendered
// with a saved template every day / week / month, kept in my exports list or e-mailed. The server owns the clock:
// weekday 0 = Monday … 6 = Sunday (services/export_jobs.next_run uses Python's `date.weekday()`), hour:minute in the
// schedule's timezone, `next_run_at` naive UTC.
//
//   ExportSchedulesPage({api})        my schedules: pause / resume · run now · files · edit · delete; "New schedule"
//   showScheduleExportSheet(...)      the create / edit sheet (also the export flow's "Schedule" action)
//   ExportScheduleCard(info, …)       one schedule (plain values)
//   ExportScheduleDraft               the form's mutable values → the server body
//   ExportScheduleFormBody            the form (plain values: datasets, templates, draft)
//   ExportRunsSheetBody / ExportRunTile   a schedule's files with Download for ready ones
//   downloadExportRun(run)            downloads a ready run and saves it (notice "<name> · <size>")
//   exportCadenceText / exportWeekdayName / exportPauseReasonText / exportRunStatusLabel
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/design/export/export_studio_api.dart';
import 'package:flutter_education_app/design/export/export_studio_model.dart';
import 'package:flutter_education_app/design/export/table_export_model.dart' show tx;
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../../teacher/data_lab/data_lab_saver_io.dart' if (dart.library.html) '../../teacher/data_lab/data_lab_saver_web.dart' as saver;
import 'export_links_page.dart' show exportContextOrg;
import 'export_log_page.dart' show exportRowsLabel;
import 'exports_center_page.dart';

String exportSchedulesTitle() => tx('exs_sched_title', 'Scheduled exports', 'التصدير المجدول');

// ═════════════════════════════════════════════════════════════════════════════
//  Words
// ═════════════════════════════════════════════════════════════════════════════

const _weekdaysEn = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _weekdaysAr = ['الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];

/// The server's weekday: 0 = Monday … 6 = Sunday.
String exportWeekdayName(int weekday) {
  final d = weekday.clamp(0, 6);
  return tx('exs_weekday_$d', _weekdaysEn[d], _weekdaysAr[d]);
}

/// "Every Monday at 7:00 AM" / "Every day at …" / "Every month on day 5 at …".
String exportCadenceText({required String cadence, required int hour, required int minute, int? weekday, int? monthday}) {
  final at = AppTime.clockMinutes(hour * 60 + minute);
  final s = switch (cadence) {
    'daily' => tx('exs_cadence_daily_at', 'Every day at {t}', 'كل يوم الساعة {t}'),
    'monthly' => tx('exs_cadence_monthly_at', 'Every month on day {d} at {t}', 'كل شهر يوم {d} الساعة {t}')
        .replaceAll('{d}', '${monthday ?? 1}'),
    _ => tx('exs_cadence_weekly_at', 'Every {w} at {t}', 'كل {w} الساعة {t}').replaceAll('{w}', exportWeekdayName(weekday ?? 0)),
  };
  return s.replaceAll('{t}', at);
}

/// The cadence of a saved schedule; its timezone is named when it is not the one the app shows times in.
String exportScheduleCadence(ExportScheduleInfo s) {
  final base = exportCadenceText(cadence: s.cadence, hour: s.hour, minute: s.minute, weekday: s.weekday, monthday: s.monthday);
  return s.timezone.isEmpty || s.timezone == AppTime.zoneId ? base : '$base (${s.timezone})';
}

String exportLangLabel(String lang) => lang == 'en' ? 'English' : 'العربية';

String exportPauseReasonText(String? reason) => switch (reason) {
      'owner' => tx('exs_pause_owner', 'You paused it', 'أوقفتها أنت'),
      'failures' => tx('exs_pause_failures', 'Paused after three runs failed in a row', 'أُوقفت بعد فشل ثلاث مرات متتالية'),
      'permission_revoked' =>
        tx('exs_pause_permission', 'Paused: you no longer have access to this data', 'أُوقفت: لم تعد تملك صلاحية على هذه البيانات'),
      _ => tx('exs_pause_other', 'Paused', 'متوقفة'),
    };

String exportRunStatusLabel(String status) => switch (status) {
      'queued' => tx('exs_run_queued', 'Waiting', 'في الانتظار'),
      'running' => tx('exs_run_running', 'Preparing', 'قيد التجهيز'),
      'ready' || 'done' || 'succeeded' => tx('exs_run_ready', 'Ready', 'جاهز'),
      'failed' || 'error' => tx('exs_run_failed', 'Failed', 'فشل'),
      'expired' => tx('exs_run_expired', 'Expired', 'منتهي'),
      _ => status,
    };

Color exportRunStatusColor(BuildContext context, String status) {
  final c = context.colors;
  return switch (status) {
    'ready' || 'done' || 'succeeded' => c.success,
    'failed' || 'error' => c.danger,
    'queued' || 'running' => c.warning,
    _ => c.textMedium,
  };
}

IconData exportRunStatusIcon(String status) => switch (status) {
      'ready' || 'done' || 'succeeded' => Icons.check_circle_rounded,
      'failed' || 'error' => Icons.error_rounded,
      'queued' || 'running' => Icons.hourglass_top_rounded,
      _ => Icons.history_rounded,
    };

/// A dataset parameter's label (the server's keys; unknown ones as they are).
String exportParamLabel(String key) => switch (key) {
      'org_id' => tx('exs_param_org_id', 'Organization number', 'رقم المؤسسة'),
      'course_id' => tx('exs_param_course_id', 'Course number', 'رقم المقرر'),
      'dept_id' => tx('exs_param_dept_id', 'Department number', 'رقم القسم'),
      'roles' => tx('exs_param_roles', 'Roles', 'الأدوار'),
      'status' => tx('exs_param_status', 'Status', 'الحالة'),
      'include_dropped' => tx('exs_param_include_dropped', 'Include dropped students', 'تضمين المنسحبين'),
      'overdue' => tx('exs_param_overdue', 'Overdue only', 'المتأخرة فقط'),
      'lang' => tx('exs_param_lang', 'Language of the values', 'لغة القيم'),
      'type' => tx('exs_param_type', 'Type', 'النوع'),
      'q' => tx('exs_param_q', 'Search', 'بحث'),
      _ => key,
    };

/// The roles of the `org.people` dataset (the server's ROLE_MODULE keys), in the picker's order.
const exportPeopleRoles = ['student', 'teacher', 'teacher_assistant', 'admin_assistant', 'org_admin'];

String exportRoleLabel(String role) => switch (role) {
      'student' => tx('exs_role_student', 'Students', 'الطلاب'),
      'teacher' => tx('exs_role_teacher', 'Teachers', 'المعلمون'),
      'teacher_assistant' => tx('exs_role_ta', 'Teaching assistants', 'المعيدون'),
      'admin_assistant' => tx('exs_role_admin_assistant', 'Administrative staff', 'الإداريون'),
      'org_admin' => tx('exs_role_org_admin', 'Organization admins', 'مديرو المؤسسة'),
      _ => role,
    };

/// Yes / no parameters, drawn as a switch and sent as `true` / `false`.
bool exportParamIsFlag(String key) => key == 'include_dropped' || key == 'overdue';

/// The fixed values of a parameter of [dataset] as (value, label), drawn as a dropdown; null = free text. The first
/// entry is the server's default ('' = no filter).
List<(String, String)>? exportParamChoices(String dataset, String key) => switch ((dataset, key)) {
      (_, 'lang') => [('ar', tx('exs_lang_ar', 'Arabic', 'العربية')), ('en', tx('exs_lang_en', 'English', 'الإنجليزية'))],
      ('org.people', 'status') => [
          ('active', tx('exs_st_active', 'Active members', 'الأعضاء النشطون')),
          ('all', tx('exs_st_all', 'Everyone', 'الجميع')),
        ],
      ('org.complaints', 'status') => [
          ('', tx('exs_st_any', 'Any status', 'أي حالة')),
          ('open', tx('exs_st_open', 'Open', 'مفتوحة')),
          ('in_progress', tx('exs_st_in_progress', 'In progress', 'قيد المعالجة')),
          ('resolved', tx('exs_st_resolved', 'Resolved', 'تم حلها')),
          ('closed', tx('exs_st_closed', 'Closed', 'مغلقة')),
        ],
      ('gov.items', 'status') => [
          ('', tx('exs_st_any', 'Any status', 'أي حالة')),
          ('open', tx('exs_st_open', 'Open', 'مفتوحة')),
          ('in_review', tx('exs_st_in_review', 'In review', 'قيد المراجعة')),
          ('pending', tx('exs_st_pending', 'Pending', 'معلّقة')),
          ('approved', tx('exs_st_approved', 'Approved', 'مقبولة')),
          ('rejected', tx('exs_st_rejected', 'Rejected', 'مرفوضة')),
          ('closed', tx('exs_st_closed', 'Closed', 'مغلقة')),
          ('withdrawn', tx('exs_st_withdrawn', 'Withdrawn', 'مسحوبة')),
        ],
      _ => null,
    };

/// The roles a comma-separated `roles` value holds (empty = the server's default: every role but org admins).
Set<String> exportRolesOf(String? v) => {for (final r in (v ?? '').split(',')) if (r.trim().isNotEmpty) r.trim()};

final _emailRe = RegExp(r'^[^@\s,;]+@[^@\s,;]+\.[^@\s,;]+$');

/// Whether [s] looks like an e-mail address.
bool exportEmailValid(String s) => _emailRe.hasMatch(s.trim());

// ═════════════════════════════════════════════════════════════════════════════
//  Download a run
// ═════════════════════════════════════════════════════════════════════════════

/// Downloads a ready run and saves it (desktop: Downloads; phones: the share sheet; web: the browser). Shows
/// "name · size" or the error; true when the file was saved.
Future<bool> downloadExportRun(ExportRunInfo run, {ExportStudioApi? api}) async {
  final r = await (api ?? ExportStudioApi.instance).downloadRun(run.id);
  if (!r.ok) {
    showAppNotice(r.error!, error: true);
    return false;
  }
  final bytes = r.data!;
  final name = (run.fileName ?? '').trim().isNotEmpty ? run.fileName!.trim() : exportFileName(run.dataset.isEmpty ? 'export' : run.dataset, run.format);
  try {
    await saver.dlSaveBytes(bytes, name, exportMimeOf(name));
  } catch (_) {
    showAppNotice(tx('exs_save_failed', 'The file could not be saved', 'تعذّر حفظ الملف'), error: true);
    return false;
  }
  showAppNotice('${exportLtr(name)} · ${exportLtr(exportSizeLabel(bytes.length))}');
  return true;
}

// ═════════════════════════════════════════════════════════════════════════════
//  Page
// ═════════════════════════════════════════════════════════════════════════════

class ExportSchedulesPage extends StatefulWidget {
  const ExportSchedulesPage({super.key, this.api});

  final ExportStudioApi? api;

  @override
  State<ExportSchedulesPage> createState() => _ExportSchedulesPageState();
}

class _ExportSchedulesPageState extends State<ExportSchedulesPage> {
  ExportStudioApi get _api => widget.api ?? ExportStudioApi.instance;

  List<ExportScheduleInfo>? _items;
  Map<String, ExportDatasetInfo> _datasets = const {};
  String? _error;
  bool _missing = false;
  int? _busy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    final ds = _api.datasets();
    final r = await _api.schedules();
    final d = await ds;
    if (!mounted) return;
    setState(() {
      _missing = r.missing;
      if (r.ok) {
        _items = r.data!;
      } else {
        _error = r.error;
      }
      if (d.ok) _datasets = {for (final x in d.data!) x.key: x};
    });
  }

  String? _titleOf(ExportScheduleInfo s) => _datasets[s.dataset]?.title(AppConfig.lang);

  void _replace(ExportScheduleInfo s) {
    final list = _items;
    if (list == null) return;
    setState(() => _items = [for (final x in list) x.id == s.id ? s : x]);
  }

  Future<void> _toggle(ExportScheduleInfo s) async {
    setState(() => _busy = s.id);
    final r = s.paused ? await _api.resumeSchedule(s.id) : await _api.pauseSchedule(s.id);
    if (!mounted) return;
    setState(() => _busy = null);
    if (r.ok) {
      _replace(r.data!);
      showAppNotice(r.data!.paused
          ? tx('exs_sched_paused', 'Schedule paused', 'أُوقفت الجدولة')
          : tx('exs_sched_resumed', 'Schedule resumed', 'استُؤنفت الجدولة'));
    } else {
      showAppNotice(r.error!, error: true);
    }
  }

  Future<void> _runNow(ExportScheduleInfo s) async {
    showAppNotice(tx('exs_preparing', 'Preparing the file…', 'جارٍ تجهيز الملف…'));
    final r = await _api.runScheduleNow(s.id);
    if (!mounted) return;
    if (!r.ok) showAppNotice(r.error!, error: true);
  }

  Future<void> _edit(ExportScheduleInfo? s) async {
    final saved = await showScheduleExportSheet(context, edit: s, api: _api);
    if (saved && mounted) await _load();
  }

  Future<void> _delete(ExportScheduleInfo s) async {
    final ok = await appConfirm(
      context,
      danger: true,
      confirmLabel: tx('exs_delete', 'Delete', 'حذف'),
      message: tx('exs_sched_delete_q', 'Delete "{name}"? Files already prepared stay in your list until they expire.',
              'حذف «{name}»؟ الملفات الجاهزة تبقى في قائمتك حتى تنتهي صلاحيتها.')
          .replaceAll('{name}', s.name),
    );
    if (!ok || !mounted) return;
    setState(() => _busy = s.id);
    final r = await _api.deleteSchedule(s.id);
    if (!mounted) return;
    setState(() {
      _busy = null;
      if (r.ok) _items = [for (final x in _items ?? const <ExportScheduleInfo>[]) if (x.id != s.id) x];
    });
    showAppNotice(r.ok ? tx('exs_sched_deleted', 'Schedule deleted', 'حُذفت الجدولة') : r.error!, error: !r.ok);
  }

  void _runs(ExportScheduleInfo s) {
    showAppSheet<void>(context, (_) => _RunsSheet(api: _api, schedule: s));
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return BasePage(
      key: const ValueKey(kExportSchedulesKey),
      appBar: ScreenAppBar(title: exportSchedulesTitle(), actions: [AppRefreshAction(onRefresh: _load)]),
      floatingActionButton: _missing || items == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _edit(null),
              icon: const Icon(Icons.add_rounded),
              label: Text(tx('exs_sched_new', 'New schedule', 'جدولة جديدة')),
            ),
      child: LayoutBuilder(
        builder: (context, box) => AppRefresh(
          onRefresh: _load,
          child: ListView(
            padding: exportsListPadding(box.maxWidth, bottom: 96),
            children: [
              if (_missing)
                ExportsLoadError(message: _error ?? '', missing: true)
              else if (items == null && _error != null)
                ExportsLoadError(message: _error!, onRetry: _load)
              else if (items == null)
                const AppListSkeleton(items: 4, padding: EdgeInsets.zero)
              else if (items.isEmpty)
                AppEmpty(
                  icon: Icons.event_repeat_rounded,
                  title: tx('exs_sched_empty', 'No scheduled exports yet', 'لا تصديرات مجدولة بعد'),
                  message: tx('exs_sched_empty_sub', 'Schedule an export to get a fresh file every day, week or month.',
                      'جدوِل تصديرًا لتصلك نسخة حديثة كل يوم أو أسبوع أو شهر.'),
                  actionLabel: tx('exs_sched_new', 'New schedule', 'جدولة جديدة'),
                  onAction: () => _edit(null),
                )
              else ...[
                if (_error != null) ...[
                  AppBanner(icon: Icons.error_outline_rounded, text: _error!, color: context.colors.danger),
                  AppSpace.gapSm,
                ],
                for (final s in items)
                  ExportScheduleCard(
                    info: s,
                    datasetTitle: _titleOf(s),
                    busy: _busy == s.id,
                    onToggle: () => _toggle(s),
                    onRunNow: () => _runNow(s),
                    onRuns: () => _runs(s),
                    onEdit: () => _edit(s),
                    onDelete: () => _delete(s),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Card
// ═════════════════════════════════════════════════════════════════════════════

/// One schedule with its actions. [onToggle] pauses an active schedule and resumes a paused one.
class ExportScheduleCard extends StatelessWidget {
  const ExportScheduleCard({
    super.key,
    required this.info,
    this.datasetTitle,
    this.busy = false,
    this.onToggle,
    this.onRunNow,
    this.onRuns,
    this.onEdit,
    this.onDelete,
  });

  final ExportScheduleInfo info;
  final String? datasetTitle;
  final bool busy;
  final VoidCallback? onToggle, onRunNow, onRuns, onEdit, onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = info;
    final meta = AppType.meta(context);
    Widget line(IconData icon, String text, {int maxLines = 1, TextDirection? dir}) => Padding(
          padding: const EdgeInsets.only(top: AppSpace.xxs),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: AppIconSize.sm, color: c.textLight)),
            const SizedBox(width: AppSpace.xs),
            Expanded(child: Text(text, maxLines: maxLines, overflow: TextOverflow.ellipsis, textDirection: dir, style: meta)),
          ]),
        );
    final fmtColor = exportFormatColor(context, s.format);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: fmtColor.withValues(alpha: 0.12), borderRadius: AppRadius.chipAll),
              child: Icon(exportFormatIcon(s.format), color: fmtColor, size: AppIconSize.md),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.name.isEmpty ? (datasetTitle ?? s.dataset) : s.name,
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(fontWeight: FontWeight.w600)),
                if ((datasetTitle ?? s.dataset).isNotEmpty)
                  Text(datasetTitle ?? s.dataset, maxLines: 1, overflow: TextOverflow.ellipsis, style: meta),
              ]),
            ),
            const SizedBox(width: AppSpace.xs),
            s.paused
                ? ExportTintPill(tx('exs_sched_status_paused', 'Paused', 'متوقفة'), color: c.warning, icon: Icons.pause_circle_rounded)
                : ExportTintPill(tx('exs_sched_status_active', 'Active', 'نشطة'), color: c.success, icon: Icons.play_circle_rounded),
          ]),
          const SizedBox(height: AppSpace.xs),
          line(Icons.schedule_rounded, exportScheduleCadence(s), maxLines: 2),
          if (!s.paused && s.nextRunAt != null)
            line(Icons.event_rounded, tx('exs_sched_next', 'Next file: {t}', 'الملف التالي: {t}').replaceAll('{t}', AppTime.dateTime(s.nextRunAt!))),
          line(Icons.translate_rounded, '${exportFormatLabel(s.format)} · ${exportLangLabel(s.lang)}'),
          if (s.delivery == 'email')
            line(Icons.mail_outline_rounded,
                tx('exs_sched_email_to', 'E-mailed to {list}', 'يُرسل بالبريد إلى {list}')
                    .replaceAll('{list}', s.recipients.isEmpty ? tx('exs_sched_email_me', 'your e-mail', 'بريدك') : s.recipients.join(', ')),
                maxLines: 2)
          else
            line(Icons.inbox_rounded, tx('exs_sched_keep', 'Kept in your exports list', 'يُحفظ في قائمة تصديراتك')),
          if (s.lastStatus != null)
            line(exportRunStatusIcon(s.lastStatus!),
                tx('exs_sched_last', 'Last file: {status}', 'آخر ملف: {status}').replaceAll('{status}',
                    '${exportRunStatusLabel(s.lastStatus!)}${s.lastRunAt == null ? '' : ' · ${AppTime.dateTime(s.lastRunAt!)}'}')),
          if (s.paused) ...[
            AppSpace.gapXs,
            AppBanner(icon: Icons.pause_circle_outline_rounded, text: exportPauseReasonText(s.pauseReason), color: c.warning),
          ],
          const SizedBox(height: AppSpace.xs),
          Divider(height: 1, color: c.divider),
          const SizedBox(height: AppSpace.xxs),
          Wrap(spacing: AppSpace.xxs, runSpacing: 0, children: [
            ExportActionButton(
              icon: s.paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              label: s.paused ? tx('exs_resume', 'Resume', 'استئناف') : tx('exs_pause', 'Pause', 'إيقاف مؤقت'),
              busy: busy,
              onPressed: onToggle,
            ),
            ExportActionButton(icon: Icons.bolt_rounded, label: tx('exs_run_now', 'Run now', 'تشغيل الآن'), onPressed: busy ? null : onRunNow),
            ExportActionButton(icon: Icons.folder_open_rounded, label: tx('exs_files', 'Files', 'الملفات'), onPressed: onRuns),
            ExportActionButton(icon: Icons.edit_rounded, label: tx('exs_edit', 'Edit', 'تعديل'), onPressed: busy ? null : onEdit),
            ExportActionButton(
              icon: Icons.delete_outline_rounded,
              label: tx('exs_delete', 'Delete', 'حذف'),
              color: c.danger,
              onPressed: busy ? null : onDelete,
            ),
          ]),
        ]),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Runs
// ═════════════════════════════════════════════════════════════════════════════

class _RunsSheet extends StatefulWidget {
  const _RunsSheet({required this.api, required this.schedule});
  final ExportStudioApi api;
  final ExportScheduleInfo schedule;

  @override
  State<_RunsSheet> createState() => _RunsSheetState();
}

class _RunsSheetState extends State<_RunsSheet> {
  List<ExportRunInfo>? _runs;
  String? _error;
  bool _missing = false;
  int? _downloading;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    final r = await widget.api.runs(scheduleId: widget.schedule.id);
    if (!mounted) return;
    setState(() {
      _missing = r.missing;
      if (r.ok) {
        _runs = r.data!.items;
      } else {
        _error = r.error;
      }
    });
  }

  Future<void> _download(ExportRunInfo run) async {
    setState(() => _downloading = run.id);
    await downloadExportRun(run, api: widget.api);
    if (mounted) setState(() => _downloading = null);
  }

  @override
  Widget build(BuildContext context) => ExportRunsSheetBody(
        title: widget.schedule.name,
        runs: _runs,
        error: _error,
        missing: _missing,
        downloadingId: _downloading,
        onDownload: _download,
        onRetry: _load,
      );
}

/// A schedule's files in a sheet. [runs] null with no [error] = loading.
class ExportRunsSheetBody extends StatelessWidget {
  const ExportRunsSheetBody({
    super.key,
    required this.title,
    this.runs,
    this.error,
    this.missing = false,
    this.downloadingId,
    this.onDownload,
    this.onRetry,
  });

  final String title;
  final List<ExportRunInfo>? runs;
  final String? error;
  final bool missing;
  final int? downloadingId;
  final ValueChanged<ExportRunInfo>? onDownload;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final list = runs;
    Widget body;
    if (missing || (list == null && error != null)) {
      body = ExportsLoadError(message: error ?? '', missing: missing, onRetry: onRetry);
    } else if (list == null) {
      body = const AppListSkeleton(items: 3, padding: EdgeInsets.zero);
    } else if (list.isEmpty) {
      body = AppEmpty(
        icon: Icons.folder_open_rounded,
        title: tx('exs_runs_empty', 'No files yet', 'لا ملفات بعد'),
        message: tx('exs_runs_empty_sub', 'Each run of this schedule leaves a file here for a week.', 'كل تشغيل لهذه الجدولة يترك ملفًا هنا لمدة أسبوع.'),
      );
    } else {
      body = Column(children: [
        for (final r in list) ExportRunTile(run: r, busy: downloadingId == r.id, onDownload: onDownload == null ? null : () => onDownload!(r)),
      ]);
    }
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppSheetHeader(title.isEmpty ? tx('exs_files', 'Files', 'الملفات') : title),
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.md),
          child: body,
        ),
      ),
    ]);
  }
}

/// One run: file name · status · size · rows · time, Download when it is ready.
class ExportRunTile extends StatelessWidget {
  const ExportRunTile({super.key, required this.run, this.busy = false, this.onDownload});

  final ExportRunInfo run;
  final bool busy;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = run;
    final meta = AppType.meta(context);
    final name = (r.fileName ?? '').trim().isNotEmpty ? r.fileName! : '${exportFormatLabel(r.format)} · ${exportLangLabel(r.lang)}';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: Container(
        padding: const EdgeInsets.all(AppSpace.sm),
        decoration: BoxDecoration(color: c.cardBg, borderRadius: AppRadius.cardAll, border: Border.all(color: c.divider)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(exportFormatIcon(r.format), color: exportFormatColor(context, r.format), size: 22),
            const SizedBox(width: AppSpace.xs),
            Expanded(child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context))),
          ]),
          const SizedBox(height: AppSpace.xxs),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
            ExportTintPill(exportRunStatusLabel(r.status), color: exportRunStatusColor(context, r.status), icon: exportRunStatusIcon(r.status)),
            if (r.size != null) Text(exportLtr(exportSizeLabel(r.size!)), style: meta),
            if (r.rows != null) Text(exportRowsLabel(r.rows!), style: meta),
            if (r.createdAt != null) Text(AppTime.dateTime(r.createdAt!), style: meta),
          ]),
          if (r.failed && (r.error ?? '').isNotEmpty) ...[
            const SizedBox(height: AppSpace.xxs),
            Text(exportStudioErrorText(r.error, r.error), maxLines: 3, overflow: TextOverflow.ellipsis, style: meta),
          ],
          if (r.ready)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: ExportActionButton(
                icon: Icons.file_download_rounded,
                label: tx('exs_download', 'Download', 'تنزيل'),
                busy: busy,
                onPressed: onDownload,
              ),
            ),
        ]),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Form
// ═════════════════════════════════════════════════════════════════════════════

/// The schedule form's values (mutable while the form is open).
class ExportScheduleDraft {
  ExportScheduleDraft({
    this.name = '',
    this.dataset,
    Map<String, String>? params,
    this.templateId,
    this.format = 'xlsx',
    this.lang = 'ar',
    this.cadence = 'weekly',
    this.hour = 7,
    this.minute = 0,
    this.weekday = 0,
    this.monthday = 1,
    this.delivery = 'list',
    List<String>? recipients,
    String? timezone,
  })  : params = params ?? {},
        recipients = recipients ?? [],
        timezone = timezone ?? _zone();

  String name;
  String? dataset;
  final Map<String, String> params;
  int? templateId;

  /// xlsx | docx | pdf
  String format;

  /// ar | en
  String lang;

  /// daily | weekly | monthly
  String cadence;
  int hour, minute;

  /// 0 = Monday … 6 = Sunday (the server's convention).
  int weekday;
  int monthday;

  /// list | email
  String delivery;
  final List<String> recipients;
  String timezone;

  static String _zone() {
    try {
      final z = AppTime.zoneId;
      return z.isEmpty ? 'UTC' : z;
    } catch (_) {
      return 'UTC';
    }
  }

  factory ExportScheduleDraft.fromInfo(ExportScheduleInfo s) => ExportScheduleDraft(
        name: s.name,
        dataset: s.dataset.isEmpty ? null : s.dataset,
        params: {for (final e in s.params.entries) if (e.value != null) e.key: '${e.value}'},
        templateId: s.templateId,
        format: s.format,
        lang: s.lang,
        cadence: s.cadence,
        hour: s.hour,
        minute: s.minute,
        weekday: s.weekday ?? 0,
        monthday: s.monthday ?? 1,
        delivery: s.delivery,
        recipients: [...s.recipients],
        timezone: s.timezone.isEmpty ? null : s.timezone,
      );

  /// Parameters as the server reads them: whole numbers as ints, empty values left out.
  Map<String, dynamic> typedParams() => {
        for (final e in params.entries)
          if (e.value.trim().isNotEmpty) e.key: int.tryParse(e.value.trim()) ?? e.value.trim(),
      };

  /// The body of POST / PUT /schedules.
  Map<String, dynamic> toBody() => ExportScheduleInfo.body(
        name: name,
        dataset: dataset ?? '',
        params: typedParams(),
        templateId: templateId,
        format: format,
        lang: lang,
        cadence: cadence,
        hour: hour,
        minute: minute,
        weekday: weekday,
        monthday: monthday,
        timezone: timezone,
        delivery: delivery,
        recipients: recipients,
      );
}

/// Opens the schedule sheet: a new schedule, or [edit] an existing one. [dataset] fixes the data source (the export
/// flow's "Schedule"), with its [params], [templateId], [format], [lang] and [name] as the starting values.
/// True when the schedule was saved.
Future<bool> showScheduleExportSheet(
  BuildContext context, {
  ExportScheduleInfo? edit,
  String? dataset,
  Map<String, Object?>? params,
  int? templateId,
  String format = 'xlsx',
  String lang = 'ar',
  String? name,
  ExportStudioApi? api,
}) async {
  final draft = edit != null
      ? ExportScheduleDraft.fromInfo(edit)
      : ExportScheduleDraft(
          name: name ?? '',
          dataset: dataset,
          params: {for (final e in (params ?? const <String, Object?>{}).entries) if (e.value != null) e.key: '${e.value}'},
          templateId: templateId,
          format: const ['xlsx', 'docx', 'pdf'].contains(format) ? format : 'xlsx',
          lang: lang == 'en' ? 'en' : 'ar',
        );
  final saved = await showAppSheet<bool>(
    context,
    (_) => _ScheduleSheet(api: api ?? ExportStudioApi.instance, draft: draft, editId: edit?.id, datasetFixed: edit == null && dataset != null),
  );
  return saved == true;
}

class _ScheduleSheet extends StatefulWidget {
  const _ScheduleSheet({required this.api, required this.draft, this.editId, this.datasetFixed = false});
  final ExportStudioApi api;
  final ExportScheduleDraft draft;
  final int? editId;
  final bool datasetFixed;

  @override
  State<_ScheduleSheet> createState() => _ScheduleSheetState();
}

class _ScheduleSheetState extends State<_ScheduleSheet> {
  List<ExportDatasetInfo>? _datasets;
  List<StudioTemplate>? _templates;
  String? _loadError, _error;
  bool _missing = false, _busy = false;

  @override
  void initState() {
    super.initState();
    _loadDatasets();
    _loadTemplates(widget.draft.format);
  }

  Future<void> _loadDatasets() async {
    setState(() => _loadError = null);
    final r = await widget.api.datasets();
    if (!mounted) return;
    setState(() {
      _missing = r.missing;
      if (r.ok) {
        _datasets = r.data!;
      } else {
        _loadError = r.error;
      }
    });
  }

  Future<void> _loadTemplates(String format) async {
    setState(() => _templates = null);
    final r = await widget.api.templates(format: format);
    if (!mounted || widget.draft.format != format) return;
    setState(() => _templates = r.ok ? [for (final t in r.data!.items) if (t.format == format) t] : const []);
  }

  Future<void> _submit() async {
    final d = widget.draft;
    if ((d.dataset ?? '').isEmpty) {
      setState(() => _error = tx('exs_sched_pick_dataset', 'Choose a data source', 'اختر مصدر البيانات'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final body = d.toBody();
    final r = widget.editId == null ? await widget.api.createSchedule(body) : await widget.api.updateSchedule(widget.editId!, body);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      showAppNotice(widget.editId == null
          ? tx('exs_sched_created', 'Schedule created', 'أُنشئت الجدولة')
          : tx('exs_sched_saved', 'Schedule saved', 'حُفظت الجدولة'));
      Navigator.of(context).pop(true);
    } else {
      setState(() => _error = r.error);
      showAppNotice(r.error!, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final edit = widget.editId != null;
    Widget body;
    if (_missing) {
      body = const ExportsLoadError(message: '', missing: true);
    } else if (_datasets == null && _loadError != null) {
      body = ExportsLoadError(message: _loadError!, onRetry: _loadDatasets);
    } else if (_datasets == null) {
      body = const AppListSkeleton(items: 4, withAvatar: false, padding: EdgeInsets.zero);
    } else {
      body = ExportScheduleFormBody(
        draft: widget.draft,
        datasets: _datasets!,
        templates: _templates,
        datasetFixed: widget.datasetFixed,
        isEdit: edit,
        busy: _busy,
        error: _error,
        onChanged: () => setState(() {}),
        onFormatChanged: (f) {
          widget.draft.templateId = null;
          _loadTemplates(f);
        },
        onSubmit: _submit,
      );
    }
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppSheetHeader(edit ? tx('exs_sched_edit_title', 'Edit schedule', 'تعديل الجدولة') : tx('exs_sched_new_title', 'Schedule an export', 'جدولة تصدير')),
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.lg),
          child: body,
        ),
      ),
    ]);
  }
}

/// The schedule form. It writes into [draft] and calls [onChanged]; [templates] null = still loading. A recipient
/// typed but not yet added is added (when valid) before [onSubmit] runs.
class ExportScheduleFormBody extends StatefulWidget {
  const ExportScheduleFormBody({
    super.key,
    required this.draft,
    required this.datasets,
    this.templates,
    this.datasetFixed = false,
    this.isEdit = false,
    this.busy = false,
    this.error,
    this.onChanged,
    this.onFormatChanged,
    this.onSubmit,
  });

  final ExportScheduleDraft draft;
  final List<ExportDatasetInfo> datasets;
  final List<StudioTemplate>? templates;
  final bool datasetFixed, isEdit, busy;
  final String? error;
  final VoidCallback? onChanged;
  final ValueChanged<String>? onFormatChanged;
  final VoidCallback? onSubmit;

  @override
  State<ExportScheduleFormBody> createState() => _ExportScheduleFormBodyState();
}

class _ExportScheduleFormBodyState extends State<ExportScheduleFormBody> {
  late final _name = TextEditingController(text: widget.draft.name);
  final _params = <String, TextEditingController>{};
  final _recipient = TextEditingController();
  String? _recipientError;

  ExportScheduleDraft get d => widget.draft;

  @override
  void initState() {
    super.initState();
    _prefillOrg();
  }

  @override
  void dispose() {
    _name.dispose();
    _recipient.dispose();
    for (final c in _params.values) {
      c.dispose();
    }
    super.dispose();
  }

  ExportDatasetInfo? get _dataset => widget.datasets.where((x) => x.key == d.dataset).firstOrNull;

  void _prefillOrg() {
    final ds = _dataset;
    if (ds == null || !ds.params.contains('org_id') || (d.params['org_id'] ?? '').trim().isNotEmpty) return;
    // the organization mode's org, else the org dashboard's (an org admin's dashboard keeps it in OrgSession only)
    final org = exportContextOrg(context);
    if (org != null) d.params['org_id'] = '$org';
  }

  TextEditingController _paramCtl(String key) => _params.putIfAbsent(key, () => TextEditingController(text: d.params[key] ?? ''));

  /// A switch for a yes / no parameter, chips for the roles, a dropdown for fixed values, else a text field.
  Widget _paramInput(String dataset, String p) {
    if (exportParamIsFlag(p)) {
      return AppSwitchTile(
        title: exportParamLabel(p),
        value: const {'1', 'true', 'yes'}.contains((d.params[p] ?? '').toLowerCase()),
        onChanged: (v) => _changed(() => d.params[p] = v ? 'true' : 'false'),
      );
    }
    if (p == 'roles') {
      final picked = exportRolesOf(d.params[p]);
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(exportParamLabel(p), style: Theme.of(context).textTheme.labelLarge),
            AppSpace.gapXs,
            Wrap(
              spacing: AppSpace.xs,
              runSpacing: AppSpace.xs,
              children: [
                for (final r in exportPeopleRoles)
                  FilterChip(
                    label: Text(exportRoleLabel(r)),
                    selected: picked.contains(r),
                    onSelected: (on) => _changed(() {
                      final next = {...picked};
                      on ? next.add(r) : next.remove(r);
                      d.params[p] = [for (final x in exportPeopleRoles) if (next.contains(x)) x].join(',');
                    }),
                  ),
              ],
            ),
          ],
        ),
      );
    }
    final choices = exportParamChoices(dataset, p);
    if (choices != null) {
      final cur = d.params[p] ?? '';
      final value = choices.any((c) => c.$1 == cur) ? cur : choices.first.$1;
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.sm),
        child: AppDropdown<String>(
          value: value,
          decoration: InputDecoration(labelText: exportParamLabel(p)),
          items: [for (final c in choices) DropdownMenuItem(value: c.$1, child: Text(c.$2, maxLines: 1, overflow: TextOverflow.ellipsis))],
          onChanged: (v) => _changed(() => d.params[p] = v ?? ''),
        ),
      );
    }
    return AppField(
      controller: _paramCtl(p),
      label: exportParamLabel(p),
      ltr: p.endsWith('_id'),
      keyboard: p.endsWith('_id') ? TextInputType.number : null,
      onChanged: (v) => d.params[p] = v,
    );
  }

  void _changed(VoidCallback fn) {
    setState(fn);
    widget.onChanged?.call();
  }

  /// Adds every valid address typed in the recipients field; false when one is not an e-mail.
  bool _commitRecipients({bool keepLast = false}) {
    final raw = _recipient.text;
    final parts = raw.split(RegExp(r'[,;\s]+'));
    final last = keepLast ? parts.removeLast() : '';
    final bad = <String>[];
    for (final p in parts) {
      final e = p.trim().toLowerCase();
      if (e.isEmpty) continue;
      if (exportEmailValid(e)) {
        if (!d.recipients.contains(e)) d.recipients.add(e);
      } else {
        bad.add(p.trim());
      }
    }
    final rest = [...bad, if (last.isNotEmpty) last].join(', ');
    if (rest != raw) {
      _recipient.value = TextEditingValue(text: rest, selection: TextSelection.collapsed(offset: rest.length));
    }
    _changed(() => _recipientError = bad.isEmpty
        ? null
        : tx('exs_sched_bad_email', 'Not an e-mail address: {list}', 'ليس عنوان بريد: {list}').replaceAll('{list}', bad.join(', ')));
    return bad.isEmpty;
  }

  void _submit() {
    if (d.delivery == 'email' && _recipient.text.trim().isNotEmpty && !_commitRecipients()) return;
    widget.onSubmit?.call();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay(hour: d.hour, minute: d.minute));
    if (picked == null || !mounted) return;
    _changed(() {
      d.hour = picked.hour;
      d.minute = picked.minute;
    });
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: AppSpace.xs, bottom: AppSpace.xs),
        child: Text(text, style: AppType.bodyStrong(context)),
      );

  Widget _chips(List<Widget> children) => Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: children);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lang = AppConfig.lang;
    final ds = _dataset;
    final templates = widget.templates;
    final meta = AppType.meta(context);
    final templateIds = {for (final t in templates ?? const <StudioTemplate>[]) t.id};
    final templateValue = templateIds.contains(d.templateId) ? d.templateId : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      AppField(
        controller: _name,
        label: tx('exs_sched_name', 'Name', 'الاسم'),
        hint: tx('exs_sched_name_hint', 'Empty = the data source\'s name', 'فارغ = اسم مصدر البيانات'),
        onChanged: (v) => d.name = v,
      ),
      if (widget.datasetFixed)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: InputDecorator(
            decoration: InputDecoration(labelText: tx('exs_sched_dataset', 'Data source', 'مصدر البيانات'), enabled: false),
            child: Text(ds?.title(lang) ?? d.dataset ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
          ),
        )
      else
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: AppDropdown<String>(
            value: d.dataset,
            decoration: InputDecoration(labelText: tx('exs_sched_dataset', 'Data source', 'مصدر البيانات')),
            hint: Text(tx('exs_sched_pick_dataset', 'Choose a data source', 'اختر مصدر البيانات')),
            items: [for (final x in widget.datasets) DropdownMenuItem(value: x.key, child: Text(x.title(lang)))],
            onChanged: (v) => _changed(() {
              d.dataset = v;
              _prefillOrg();
              for (final e in _params.entries) {
                e.value.text = d.params[e.key] ?? '';
              }
            }),
          ),
        ),
      if (ds != null)
        for (final p in ds.params) _paramInput(ds.key, p),
      Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.xs),
        child: AppDropdown<int?>(
          value: templateValue,
          enabled: templates != null,
          decoration: InputDecoration(labelText: tx('exs_sched_template', 'Saved template', 'القالب المحفوظ')),
          hint: Text(templates == null ? tx('exs_loading', 'Loading…', 'جارٍ التحميل…') : tx('exs_standard_layout', 'Standard layout', 'التنسيق القياسي')),
          items: [
            DropdownMenuItem<int?>(value: null, child: Text(tx('exs_standard_layout', 'Standard layout', 'التنسيق القياسي'))),
            for (final t in templates ?? const <StudioTemplate>[]) DropdownMenuItem<int?>(value: t.id, child: Text(t.name)),
          ],
          onChanged: (v) => _changed(() => d.templateId = v),
        ),
      ),
      _label(tx('exs_sched_format', 'Format', 'الصيغة')),
      _chips([
        for (final f in const ['xlsx', 'docx', 'pdf'])
          AppChoiceChip(
            label: exportFormatLabel(f),
            icon: exportFormatIcon(f),
            selected: d.format == f,
            onTap: () {
              if (d.format == f) return;
              _changed(() => d.format = f);
              widget.onFormatChanged?.call(f);
            },
          ),
      ]),
      _label(tx('exs_sched_lang', 'Language', 'اللغة')),
      _chips([
        for (final l in const ['ar', 'en'])
          AppChoiceChip(label: exportLangLabel(l), selected: d.lang == l, onTap: () => _changed(() => d.lang = l)),
      ]),
      _label(tx('exs_sched_repeat', 'Repeat', 'التكرار')),
      _chips([
        AppChoiceChip(label: tx('exs_cadence_daily', 'Daily', 'يوميًا'), selected: d.cadence == 'daily', onTap: () => _changed(() => d.cadence = 'daily')),
        AppChoiceChip(label: tx('exs_cadence_weekly', 'Weekly', 'أسبوعيًا'), selected: d.cadence == 'weekly', onTap: () => _changed(() => d.cadence = 'weekly')),
        AppChoiceChip(label: tx('exs_cadence_monthly', 'Monthly', 'شهريًا'), selected: d.cadence == 'monthly', onTap: () => _changed(() => d.cadence = 'monthly')),
      ]),
      if (d.cadence == 'weekly') ...[
        _label(tx('exs_sched_on_day', 'On', 'في يوم')),
        _chips([
          for (var i = 0; i < 7; i++) AppChoiceChip(label: exportWeekdayName(i), selected: d.weekday == i, onTap: () => _changed(() => d.weekday = i)),
        ]),
      ],
      if (d.cadence == 'monthly') ...[
        AppSpace.gapXs,
        AppDropdown<int>(
          value: d.monthday,
          decoration: InputDecoration(labelText: tx('exs_sched_monthday', 'Day of the month', 'يوم الشهر')),
          items: [for (var i = 1; i <= 31; i++) DropdownMenuItem(value: i, child: Text('$i'))],
          onChanged: (v) => _changed(() => d.monthday = v ?? 1),
        ),
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.xxs),
          child: Text(tx('exs_sched_monthday_note', 'A month without this day uses its last day.', 'الشهر الذي لا يحتوي هذا اليوم يُستخدم آخر أيامه.'),
              style: meta),
        ),
      ],
      _label(tx('exs_sched_time', 'Time', 'الوقت')),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(AppTouch.min * 2, AppTouch.min),
            shape: RoundedRectangleBorder(borderRadius: AppRadius.chipAll),
          ),
          onPressed: _pickTime,
          icon: const Icon(Icons.schedule_rounded),
          label: Text(AppTime.clockMinutes(d.hour * 60 + d.minute), style: AppType.bodyStrong(context).copyWith(color: c.textDark)),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: AppSpace.xxs),
        child: Text(
          '${exportCadenceText(cadence: d.cadence, hour: d.hour, minute: d.minute, weekday: d.weekday, monthday: d.monthday)} · '
          '${tx('exs_sched_zone', 'Times are in {zone}', 'الأوقات بتوقيت {zone}').replaceAll('{zone}', d.timezone)}',
          style: meta,
        ),
      ),
      _label(tx('exs_sched_delivery', 'Delivery', 'التسليم')),
      _chips([
        AppChoiceChip(
          label: tx('exs_delivery_list', 'Keep in my exports list', 'الحفظ في قائمة تصديراتي'),
          icon: Icons.inbox_rounded,
          selected: d.delivery == 'list',
          onTap: () => _changed(() => d.delivery = 'list'),
        ),
        AppChoiceChip(
          label: tx('exs_delivery_email', 'E-mail', 'البريد الإلكتروني'),
          icon: Icons.mail_outline_rounded,
          selected: d.delivery == 'email',
          onTap: () => _changed(() => d.delivery = 'email'),
        ),
      ]),
      if (d.delivery == 'email') ...[
        AppSpace.gapSm,
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: AppField(
              controller: _recipient,
              label: tx('exs_sched_recipients', 'Recipients', 'المستلمون'),
              hint: 'name@example.com',
              keyboard: TextInputType.emailAddress,
              ltr: true,
              onChanged: (v) {
                if (RegExp(r'[,;\s]').hasMatch(v)) _commitRecipients(keepLast: true);
              },
              onSubmitted: (_) => _commitRecipients(),
            ),
          ),
          const SizedBox(width: AppSpace.xs),
          SizedBox(
            height: 52,
            child: ExportActionButton(icon: Icons.add_rounded, label: tx('exs_add', 'Add', 'إضافة'), onPressed: () => _commitRecipients()),
          ),
        ]),
        if (_recipientError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xs),
            child: Text(_recipientError!, style: AppType.label(context).copyWith(color: c.danger, fontWeight: FontWeight.w600)),
          ),
        if (d.recipients.isNotEmpty)
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            for (final r in d.recipients)
              InputChip(
                label: Text(r, textDirection: TextDirection.ltr, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textDark)),
                onDeleted: () => _changed(() => d.recipients.remove(r)),
                deleteButtonTooltipMessage: tx('exs_remove', 'Remove', 'إزالة'),
                materialTapTargetSize: MaterialTapTargetSize.padded,
              ),
          ]),
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.xxs),
          child: Text(
              tx('exs_sched_recipients_note', 'Leave it empty to send the file to your own e-mail. Only people who may see this data can receive it.',
                  'اتركه فارغًا ليصلك الملف على بريدك. لا يستلمه إلا من يملك صلاحية رؤية هذه البيانات.'),
              style: meta),
        ),
      ],
      if (widget.error != null) ...[
        AppSpace.gapMd,
        AppBanner(icon: Icons.error_outline_rounded, text: widget.error!, color: c.danger),
      ],
      AppSpace.gapLg,
      AppPrimaryButton(
        label: widget.isEdit ? tx('exs_save_changes', 'Save changes', 'حفظ التغييرات') : tx('exs_sched_create', 'Create schedule', 'إنشاء الجدولة'),
        icon: Icons.check_rounded,
        busy: widget.busy,
        onPressed: widget.onSubmit == null ? null : _submit,
      ),
    ]);
  }
}
