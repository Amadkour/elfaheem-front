// Exam feedback store settings and export (Phase 8), platform level (super admin).
//
//   GET|PUT /api/v1/exam/admin/feedback/settings   {enabled, org_default, retention_days}  (+ `records` count on GET)
//   GET     /api/v1/exam/admin/feedback/export     ?org_id=&format=jsonl|csv&since=        (a download)
//
// The organization-level twin lives in lib/features/org/org_feedback_risk.dart and reuses [FeedbackSettings],
// [FeedbackDraft], [FeedbackSettingsForm] and [FeedbackExportBar] from here. Pure parts are unit-tested.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../shared/exam_engine/exam_engine_api.dart' show EngineResult, ExamEngineApi, engineCall;
import 'admin_common.dart' show asBool, asInt, shortDateTime, asStrOrNull, t;
import 'admin_money_p8.dart' show draftErrorText, p8SaveBytes, parseNum;

const feedbackMaxDays = 3650;

class FeedbackSettings {
  const FeedbackSettings({this.enabled = false, this.orgDefault = false, this.retentionDays = 365, this.records, this.updatedAt,
      this.platformEnabled, this.effective, this.effectiveDays, this.inherits = false});
  final bool enabled;
  final bool orgDefault; // platform only
  final int retentionDays;
  final int? records; // platform only
  final String? updatedAt;

  // organization only
  final bool? platformEnabled;
  final bool? effective;
  final int? effectiveDays;
  final bool inherits;

  factory FeedbackSettings.fromJson(Map<String, dynamic> j) => FeedbackSettings(
      enabled: asBool(j['enabled']),
      orgDefault: asBool(j['org_default']),
      retentionDays: asInt(j['retention_days'], 365),
      records: j['records'] == null ? null : asInt(j['records']),
      updatedAt: asStrOrNull(j['updated_at']),
      platformEnabled: j['platform_enabled'] is bool ? j['platform_enabled'] as bool : null,
      effective: j['effective'] is bool ? j['effective'] as bool : null,
      effectiveDays: j['effective_retention_days'] == null ? null : asInt(j['effective_retention_days']),
      inherits: asBool(j['inherits']));
}

class FeedbackDraft {
  FeedbackDraft({this.enabled = false, this.orgDefault = false, this.days = '365'});
  bool enabled, orgDefault;
  String days;

  factory FeedbackDraft.of(FeedbackSettings s) =>
      FeedbackDraft(enabled: s.enabled, orgDefault: s.orgDefault, days: '${s.retentionDays}');

  /// null when valid
  String? validate() {
    final d = parseNum(days);
    if (d == null || d != d.truncateToDouble() || d < 1 || d > feedbackMaxDays) return 'bad_days';
    return null;
  }

  int get daysValue => parseNum(days)!.toInt();

  Map<String, dynamic> platformBody() => {'enabled': enabled, 'org_default': orgDefault, 'retention_days': daysValue};
  Map<String, dynamic> orgBody() => {'enabled': enabled, 'retention_days': daysValue};
}

String feedbackCodeText(String? code, String fallback) => switch (code) {
      'super_admin_required' => t('للمشرف العام فقط', 'Super admin only'),
      'org_admin_required' => t('لمدير المؤسسة فقط', 'Organization admin only'),
      'forbidden' => t('ليس لديك صلاحية', 'You do not have permission'),
      'bad_format' => t('الصيغة jsonl أو csv', 'The format is jsonl or csv'),
      'bad_since' => t('تاريخ غير صالح', 'Invalid date'),
      _ => fallback,
    };

/// `?since=` for the export: an ISO instant at midnight UTC of the picked day; null when not set.
String? feedbackSince(DateTime? day) => day == null ? null : DateTime.utc(day.year, day.month, day.day).toIso8601String();

String feedbackExportName(String format, {int? orgId}) => 'feedback-${orgId ?? 'all'}.$format';

class FeedbackApi {
  FeedbackApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;
  static const base = ExamEngineApi.base;

  Future<EngineResult> platform() => engineCall(() => _api.get('$base/admin/feedback/settings'));
  Future<EngineResult> savePlatform(FeedbackDraft d) => engineCall(() => _api.put('$base/admin/feedback/settings', body: d.platformBody()));
  Future<EngineResult> org(int orgId) => engineCall(() => _api.get('$base/orgs/$orgId/feedback/settings'));
  Future<EngineResult> saveOrg(int orgId, FeedbackDraft d) => engineCall(() => _api.put('$base/orgs/$orgId/feedback/settings', body: d.orgBody()));
  Future<Uint8List> exportPlatform({int? orgId, required String format, String? since}) => _api.getBytes('$base/admin/feedback/export',
      queryParams: {'org_id': ?orgId, 'format': format, 'since': ?since});
  Future<Uint8List> exportOrg(int orgId, {required String format, String? since}) =>
      _api.getBytes('$base/orgs/$orgId/feedback/export', queryParams: {'format': format, 'since': ?since});
  Future<EngineResult> risk(int orgId) => engineCall(() => _api.get('$base/orgs/$orgId/risk'));
}

/// Enabled · (org default) · retention days. Presentational: [onSave] receives a validated draft.
class FeedbackSettingsForm extends StatefulWidget {
  const FeedbackSettingsForm({super.key, required this.settings, required this.onSave, this.platform = false, this.busy = false, this.readOnly = false});
  final FeedbackSettings settings;
  final bool platform, busy, readOnly;
  final void Function(FeedbackDraft draft) onSave;

  @override
  State<FeedbackSettingsForm> createState() => _FeedbackSettingsFormState();
}

class _FeedbackSettingsFormState extends State<FeedbackSettingsForm> {
  late final FeedbackDraft _d = FeedbackDraft.of(widget.settings);
  late final TextEditingController _days = TextEditingController(text: _d.days);
  String? _err;

  @override
  void dispose() {
    _days.dispose();
    super.dispose();
  }

  void _submit() {
    _d.days = _days.text;
    final e = _d.validate();
    setState(() => _err = e);
    if (e == null) widget.onSave(_d);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = widget.settings;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!widget.platform && s.platformEnabled == false)
        Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppBanner(icon: Icons.info_outline_rounded, text: t('جمع الملاحظات متوقف على مستوى المنصة، فلن يعمل هنا حتى لو فعّلته.', 'Feedback collection is off on the platform, so it will not run here even if you enable it.'))),
      if (!widget.platform && s.inherits)
        Padding(padding: const EdgeInsets.only(bottom: 10), child: AppBanner(icon: Icons.subdirectory_arrow_right_rounded, text: t('تستخدم المؤسسة الإعداد الافتراضي للمنصة.', 'This organization uses the platform default.'))),
      AppSwitchTile(
          title: t('جمع ملاحظات الأسئلة', 'Collect question feedback'),
          subtitle: t('تُخزَّن ملاحظات الامتحانات بلا هوية لتحسين الأسئلة', 'Exam feedback is stored without identity to improve questions'),
          value: _d.enabled,
          onChanged: widget.readOnly ? null : (v) => setState(() => _d.enabled = v)),
      if (widget.platform)
        AppSwitchTile(
            title: t('تفعيل افتراضي للمؤسسات', 'On by default for organizations'),
            subtitle: t('المؤسسات التي لم تضبط إعدادها ترث هذا', 'Organizations that did not set their own inherit this'),
            value: _d.orgDefault,
            onChanged: widget.readOnly ? null : (v) => setState(() => _d.orgDefault = v)),
      const SizedBox(height: 8),
      AppField(controller: _days, label: t('مدة الاحتفاظ (أيام)', 'Retention (days)'), keyboard: TextInputType.number),
      if (!widget.platform && s.effectiveDays != null)
        Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('${t('الفعلي الآن', 'Effective now')}: ${s.effective == true ? t('مفعّل', 'on') : t('متوقف', 'off')} · ${s.effectiveDays} ${t('يوم', 'days')}', style: appText(12, c: c.textLight))),
      if (widget.platform && s.records != null)
        Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('${t('السجلات المخزنة', 'Stored records')}: ${s.records}', style: appText(12, c: c.textLight))),
      if (_err != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: draftErrorText(_err!))),
      if (!widget.readOnly) AppPrimaryButton(label: t('حفظ', 'Save'), icon: Icons.check_rounded, busy: widget.busy, onPressed: widget.busy ? null : _submit),
    ]);
  }
}

/// Format chips + optional "since" day + the download button. [onExport] gets (format, since) and does the download.
class FeedbackExportBar extends StatefulWidget {
  const FeedbackExportBar({super.key, required this.onExport, this.busy = false});
  final Future<void> Function(String format, String? since) onExport;
  final bool busy;

  @override
  State<FeedbackExportBar> createState() => _FeedbackExportBarState();
}

class _FeedbackExportBarState extends State<FeedbackExportBar> {
  String _format = 'jsonl';
  DateTime? _since;

  Future<void> _pick() async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, initialDate: _since ?? now, firstDate: DateTime(2020), lastDate: now);
    if (d != null && mounted) setState(() => _since = d);
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        AppChoiceChip(label: 'JSONL', selected: _format == 'jsonl', onTap: () => setState(() => _format = 'jsonl')),
        AppChoiceChip(label: 'CSV', selected: _format == 'csv', onTap: () => setState(() => _format = 'csv')),
        OutlinedButton.icon(
            onPressed: _pick,
            icon: const Icon(Icons.event_rounded, size: 18),
            label: Text('${t('منذ', 'Since')}: ${_since == null ? t('البداية', 'the beginning') : AppTime.date(_since!.toUtc())}')),
        if (_since != null) IconButton(tooltip: t('مسح', 'Clear'), onPressed: () => setState(() => _since = null), icon: const Icon(Icons.close_rounded, size: 18)),
      ]),
      const SizedBox(height: 12),
      AppPrimaryButton(
          label: t('تنزيل التصدير', 'Download export'),
          icon: Icons.download_rounded,
          busy: widget.busy,
          onPressed: widget.busy ? null : () => widget.onExport(_format, feedbackSince(_since))),
    ]);
  }
}

/// Saves a feedback export and reports the result; shared by both pages.
Future<void> saveFeedbackExport(Future<Uint8List> Function() fetch, String format, {int? orgId}) async {
  try {
    final bytes = await fetch();
    if (bytes.isEmpty) {
      appToast(t('لا توجد سجلات للتصدير', 'No records to export'));
      return;
    }
    await p8SaveBytes(bytes, feedbackExportName(format, orgId: orgId), mime: format == 'csv' ? 'text/csv' : 'application/x-ndjson');
  } on ApiException catch (e) {
    appToast(feedbackCodeText(e.code, e.message), error: true);
  } catch (e) {
    appToast('$e', error: true);
  }
}

class AdminFeedbackSettingsPage extends StatefulWidget {
  const AdminFeedbackSettingsPage({super.key, this.api});
  final FeedbackApi? api;

  @override
  State<AdminFeedbackSettingsPage> createState() => _AdminFeedbackSettingsPageState();
}

class _AdminFeedbackSettingsPageState extends State<AdminFeedbackSettingsPage> {
  late final FeedbackApi _api = widget.api ?? FeedbackApi();
  final _org = TextEditingController();
  FeedbackSettings? _s;
  bool _loading = true, _busy = false, _exporting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _org.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await _api.platform();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = r.ok ? null : (r.unavailable ? t('غير متاح على هذا الخادم بعد', 'Not available on this server yet') : feedbackCodeText(r.code, r.message));
      _s = r.ok ? FeedbackSettings.fromJson(r.map) : null;
    });
  }

  Future<void> _save(FeedbackDraft d) async {
    setState(() => _busy = true);
    final r = await _api.savePlatform(d);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.ok) _s = FeedbackSettings.fromJson(r.map);
    });
    if (r.ok) {
      appToast(t('تم الحفظ', 'Saved'));
    } else {
      appToast(feedbackCodeText(r.code, r.message), error: true);
    }
  }

  Future<void> _export(String format, String? since) async {
    final org = int.tryParse(_org.text.trim());
    setState(() => _exporting = true);
    await saveFeedbackExport(() => _api.exportPlatform(orgId: org, format: format, since: since), format, orgId: org);
    if (mounted) setState(() => _exporting = false);
  }

  @override
  Widget build(BuildContext context) {
    return BasePage(
      key: const ValueKey('admin.feedback_settings'),
      useWebCard: true,
      maxWith: 800,
      appBar: ScreenAppBar(title: t('ملاحظات الامتحانات', 'Exam feedback')),
      child: _loading
          ? const AppListSkeleton(items: 3, withAvatar: false)
          : _s == null
              ? AppEmpty(icon: Icons.error_outline_rounded, title: _error ?? '', actionLabel: t('إعادة المحاولة', 'Retry'), onAction: _load)
              : ListView(padding: const EdgeInsets.all(16), children: [
                  AppCard(child: FeedbackSettingsForm(settings: _s!, platform: true, busy: _busy, onSave: _save)),
                  AppSectionTitle(t('تصدير', 'Export'), subtitle: t('كل المؤسسات، أو مؤسسة واحدة', 'Every organization, or just one')),
                  AppCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      AppField(controller: _org, label: t('رقم المؤسسة (اختياري)', 'Organization id (optional)'), keyboard: TextInputType.number),
                      FeedbackExportBar(onExport: _export, busy: _exporting),
                    ]),
                  ),
                ]),
    );
  }
}

/// Used by tests: a short "updated" line.
String feedbackUpdated(FeedbackSettings s) => s.updatedAt == null ? '' : shortDateTime(s.updatedAt);
