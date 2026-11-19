// lib/features/org/onboarding/onboarding_import.dart — member onboarding from an Excel / CSV list (Phase B, D-1200).
//
//   OnbImportPage          choose the type → download the template → pick the file and a mode (draft · submit ·
//                          invite) → upload → preview → confirm → the done screen. The staged batch lives 24 h on the
//                          server; a 410 `batch_expired` offers "upload again".
//   OnbImportSetupView     the first step over plain values
//   OnbImportPreviewView   counts chips, a state filter, the row cards (a compact list on wide windows), the
//                          "include warnings" switch and the confirm button
//   OnbImportDoneView      created / invited / skipped and "download the error report"
//
// Gates (the Add dialog): kill switch `org.onboarding.import` + the import right of the type's module.
library;

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t;
import '../org_page_header.dart' show OrgPushedPage;
import '../org_v3.dart' show orgErrorText;
import 'onboarding_api.dart';
import 'onboarding_models.dart';

/// The kill switches of the entry methods (`feature_catalog.py`).
const onboardingImportKey = 'org.onboarding.import';
const onboardingInviteKey = 'org.onboarding.invite';
const onboardingIntakeKey = 'org.onboarding.intake';

String onbImportModeLabel(String m) => switch (m) {
      'submit' => t('إرسال للمراجعة', 'Submit for review'),
      'invite' => t('دعوة لاستكمال البيانات', 'Invite to complete'),
      _ => t('حفظ كمسودات', 'Save as drafts'),
    };

String onbImportModeHint(String m) => switch (m) {
      'submit' => t('الصفوف السليمة تُرسل مباشرة للمراجعة.', 'Valid rows go straight to review.'),
      'invite' => t('يصل كل شخص رابط ليُكمل بياناته بنفسه.', 'Each person gets a link to complete their own details.'),
      _ => t('تُحفظ مسودات تكملها لاحقاً.', 'Saved as drafts you complete later.'),
    };

String onbRowStateLabel(String s) => switch (s) {
      'error' => t('أخطاء', 'Errors'),
      'warning' => t('تحذيرات', 'Warnings'),
      'ok' => t('سليمة', 'Valid'),
      _ => t('الكل', 'All'),
    };

AppTone onbRowStateTone(String s) => switch (s) {
      'error' => AppTone.danger,
      'warning' => AppTone.warning,
      _ => AppTone.success,
    };

/// Saves bytes as a file (a download on the web, the system's save on phones).
Future<bool> onbSaveXlsx(Uint8List bytes, String name) async {
  try {
    await FileSaver.instance.saveFile(name: name, bytes: bytes, fileExtension: 'xlsx', mimeType: MimeType.microsoftExcel);
    return true;
  } catch (_) {
    return false;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The flow
// ═════════════════════════════════════════════════════════════════════════════

enum _Phase { setup, preview, done }

class OnbImportPage extends StatefulWidget {
  const OnbImportPage({super.key, required this.orgId, required this.types, this.initialType, this.initialMode = 'draft', this.canInvite = true, this.api});
  final int orgId;

  /// The types the person may import into (active, with the insert right).
  final List<OnbType> types;
  final OnbType? initialType;
  final String initialMode;

  /// False when the invite kill switch or right is off: the "invite" mode is not offered.
  final bool canInvite;
  final OnboardingApi? api;

  @override
  State<OnbImportPage> createState() => _OnbImportPageState();
}

class _OnbImportPageState extends State<OnbImportPage> {
  late final OnboardingApi _api = widget.api ?? OnboardingApi();
  late OnbType? _type = widget.initialType ?? (widget.types.length == 1 ? widget.types.first : null);
  late String _mode = widget.initialMode;
  _Phase _phase = _Phase.setup;
  String _fileName = '';
  String? _path;
  Uint8List? _bytes;
  OnbBatch? _batch;
  OnbImportResult? _result;
  String _filter = '';
  bool _includeWarnings = false, _busy = false, _expired = false;
  String? _error;

  Future<void> _template() async {
    final ty = _type;
    if (ty == null) return;
    setState(() => _busy = true);
    final bytes = await _api.templateBytes(widget.orgId, ty.key);
    if (!mounted) return;
    setState(() => _busy = false);
    if (bytes == null || !await onbSaveXlsx(bytes, 'onboarding_${ty.key}')) {
      if (mounted) showAppNotice(t('تعذر تنزيل القالب', 'Could not download the template'), error: true);
      return;
    }
    if (mounted) showAppNotice(t('نُزّل القالب', 'Template downloaded'));
  }

  Future<void> _pick() async {
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['xlsx', 'csv']);
    if (f == null || !mounted) return;
    final bytes = kIsWeb ? await f.readAsBytes() : null;
    if (kIsWeb ? bytes == null : f.path == null) {
      showAppNotice(t('تعذّرت قراءة الملف', 'Could not read the file'), error: true);
      return;
    }
    setState(() {
      _fileName = f.name;
      _path = kIsWeb ? null : f.path;
      _bytes = bytes;
      _error = null;
    });
  }

  Future<void> _upload() async {
    final ty = _type;
    if (ty == null || _fileName.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
      _expired = false;
    });
    final r = await _api.uploadImport(widget.orgId, typeKey: ty.key, mode: _mode, fileName: _fileName, path: _path, bytes: _bytes);
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _busy = false;
        _error = orgErrorText(r.error!);
      });
      return;
    }
    setState(() {
      _busy = false;
      _batch = OnbBatch.fromJson(r.map);
      _filter = (_batch!.error > 0) ? 'error' : '';
      _includeWarnings = false;
      _phase = _Phase.preview;
    });
  }

  Future<void> _confirm() async {
    final b = _batch;
    if (b == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await _api.confirmImport(widget.orgId, b.id, includeWarnings: _includeWarnings);
    if (!mounted) return;
    if (!r.ok) {
      final gone = r.code == 'batch_expired' || r.error?.statusCode == 410;
      setState(() {
        _busy = false;
        _expired = gone;
        _error = orgErrorText(r.error!);
      });
      return;
    }
    setState(() {
      _busy = false;
      _result = OnbImportResult.fromJson(r.map);
      _phase = _Phase.done;
    });
  }

  Future<void> _report() async {
    final b = _batch;
    if (b == null) return;
    final bytes = await _api.importReportBytes(widget.orgId, b.id);
    if (!mounted) return;
    if (bytes == null || !await onbSaveXlsx(bytes, 'import_report_${b.id}')) {
      if (mounted) showAppNotice(t('تعذر تنزيل التقرير', 'Could not download the report'), error: true);
    }
  }

  void _again() => setState(() {
        _phase = _Phase.setup;
        _batch = null;
        _expired = false;
        _error = null;
      });

  @override
  Widget build(BuildContext context) {
    final b = _batch;
    return OrgPushedPage(
      title: t('استيراد من Excel', 'Import from Excel'),
      subtitle: t('الالتحاق والتعيين', 'Admissions & appointments'),
      helpPageId: 'org.onboarding.import',
      width: AppWidth.content,
      child: switch (_phase) {
        _Phase.setup => OnbImportSetupView(
            types: widget.types,
            type: _type,
            mode: _mode,
            fileName: _fileName,
            busy: _busy,
            error: _error,
            canInvite: widget.canInvite,
            onType: (v) => setState(() => _type = v),
            onMode: (v) => setState(() => _mode = v),
            onTemplate: _template,
            onPick: _pick,
            onUpload: _upload,
          ),
        _Phase.preview => OnbImportPreviewView(
            batch: b!,
            type: _type,
            filter: _filter,
            includeWarnings: _includeWarnings,
            busy: _busy,
            error: _error,
            expired: _expired,
            onFilter: (v) => setState(() => _filter = v),
            onIncludeWarnings: (v) => setState(() => _includeWarnings = v),
            onConfirm: _confirm,
            onReport: _report,
            onAgain: _again,
          ),
        _Phase.done => OnbImportDoneView(result: _result ?? const OnbImportResult(), mode: _mode, hasProblems: (_batch?.error ?? 0) + (_batch?.warning ?? 0) > 0, onReport: _report, onClose: () => Navigator.of(context).maybePop(true)),
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Step 1: type, template, file, mode
// ═════════════════════════════════════════════════════════════════════════════

class OnbImportSetupView extends StatelessWidget {
  const OnbImportSetupView({
    super.key,
    required this.types,
    this.type,
    this.mode = 'draft',
    this.fileName = '',
    this.busy = false,
    this.error,
    this.canInvite = true,
    this.onType,
    this.onMode,
    this.onTemplate,
    this.onPick,
    this.onUpload,
  });

  final List<OnbType> types;
  final OnbType? type;
  final String mode, fileName;
  final bool busy, canInvite;
  final String? error;
  final void Function(OnbType)? onType;
  final void Function(String)? onMode;
  final VoidCallback? onTemplate, onPick, onUpload;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final modes = ['draft', 'submit', if (canInvite) 'invite'];
    return ListView(padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.xxxl), children: [
      AppSectionTitle(t('١ · النوع', '1 · Type')),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final ty in types)
          AppChoiceChip(key: ValueKey('onb.import.type.${ty.key}'), label: ty.label.isEmpty ? ty.key : ty.label, selected: type?.key == ty.key, onTap: () => onType?.call(ty)),
      ]),
      AppSpace.gapMd,
      AppSectionTitle(t('٢ · القالب', '2 · Template')),
      Text(t('نزّل القالب واملأه، فكل نوع له أعمدته الخاصة.', 'Download the template and fill it in: every type has its own columns.'), style: AppType.meta(context)),
      AppSpace.gapXs,
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: AppButton.secondary(key: const ValueKey('onb.import.template'), label: t('تنزيل القالب', 'Download the template'), icon: Icons.download_rounded, busy: busy && fileName.isEmpty, onPressed: type == null || busy ? null : onTemplate),
      ),
      AppSpace.gapMd,
      AppSectionTitle(t('٣ · الملف والوضع', '3 · File and mode')),
      AppCard(
        key: const ValueKey('onb.import.file'),
        onTap: busy ? null : onPick,
        child: Row(children: [
          Icon(Icons.upload_file_rounded, color: c.primary),
          AppSpace.gapSm,
          Expanded(
            child: Text(fileName.isEmpty ? t('اختر ملف xlsx أو csv', 'Choose an xlsx or csv file') : fileName, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
          ),
        ]),
      ),
      AppSpace.gapSm,
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final m in modes) AppChoiceChip(key: ValueKey('onb.import.mode.$m'), label: onbImportModeLabel(m), selected: mode == m, onTap: () => onMode?.call(m)),
      ]),
      AppSpace.gapXs,
      Text(onbImportModeHint(mode), style: AppType.meta(context)),
      if (error != null) ...[
        AppSpace.gapSm,
        AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!),
      ],
      AppSpace.gapMd,
      AppButton.primary(
        key: const ValueKey('onb.import.upload'),
        label: t('رفع ومعاينة', 'Upload and preview'),
        icon: Icons.fact_check_outlined,
        busy: busy,
        onPressed: type == null || fileName.isEmpty || busy ? null : onUpload,
      ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Step 2: preview
// ═════════════════════════════════════════════════════════════════════════════

class OnbImportPreviewView extends StatelessWidget {
  const OnbImportPreviewView({
    super.key,
    required this.batch,
    this.type,
    this.filter = '',
    this.includeWarnings = false,
    this.busy = false,
    this.error,
    this.expired = false,
    this.onFilter,
    this.onIncludeWarnings,
    this.onConfirm,
    this.onReport,
    this.onAgain,
  });

  final OnbBatch batch;
  final OnbType? type;
  final String filter;
  final bool includeWarnings, busy, expired;
  final String? error;
  final void Function(String)? onFilter;
  final void Function(bool)? onIncludeWarnings;
  final VoidCallback? onConfirm, onReport, onAgain;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rows = batch.rowsIn(filter);
    final will = batch.willCreate(includeWarnings: includeWarnings);
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 720;
      return ListView(padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.xxxl), children: [
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          AppStatusBadge(key: const ValueKey('onb.import.count.ok'), label: '${onbRowStateLabel('ok')} ${batch.ok}', tone: AppTone.success),
          AppStatusBadge(key: const ValueKey('onb.import.count.warning'), label: '${onbRowStateLabel('warning')} ${batch.warning}', tone: AppTone.warning),
          AppStatusBadge(key: const ValueKey('onb.import.count.error'), label: '${onbRowStateLabel('error')} ${batch.error}', tone: AppTone.danger),
        ]),
        AppSpace.gapSm,
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final s in const ['', 'error', 'warning', 'ok']) AppChoiceChip(key: ValueKey('onb.import.filter.$s'), label: onbRowStateLabel(s), selected: filter == s, onTap: () => onFilter?.call(s)),
        ]),
        AppSpace.gapSm,
        if (rows.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(vertical: AppSpace.lg), child: Center(child: Text(t('لا صفوف في هذه الفئة', 'No rows in this group'), style: AppType.meta(context))))
        else
          for (final r in rows) Padding(padding: const EdgeInsets.only(bottom: AppSpace.xs), child: OnbImportRowCard(row: r, type: type, compact: wide)),
        if (batch.warning > 0) ...[
          AppSpace.gapSm,
          AppSwitchTile(
            key: const ValueKey('onb.import.warnings'),
            title: t('إدراج الصفوف ذات التحذيرات', 'Include rows with warnings'),
            subtitle: t('التحذيرات لا تمنع الحفظ، لكن راجعها أولاً.', 'Warnings do not block saving, but review them first.'),
            value: includeWarnings,
            onChanged: onIncludeWarnings,
          ),
        ],
        if (error != null) ...[
          AppSpace.gapSm,
          AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!),
        ],
        AppSpace.gapMd,
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          if (expired)
            AppButton.primary(key: const ValueKey('onb.import.again'), label: t('رفع الملف من جديد', 'Upload again'), icon: Icons.refresh_rounded, onPressed: onAgain)
          else ...[
            AppButton.primary(
              key: const ValueKey('onb.import.confirm'),
              label: t('تأكيد وحفظ $will', 'Confirm and save $will'),
              icon: Icons.check_rounded,
              busy: busy,
              onPressed: will == 0 || busy ? null : onConfirm,
            ),
            AppButton.ghost(key: const ValueKey('onb.import.back'), label: t('ملف آخر', 'Another file'), onPressed: busy ? null : onAgain),
          ],
          if (batch.error + batch.warning > 0) AppButton.secondary(key: const ValueKey('onb.import.report'), label: t('تقرير الأخطاء', 'Error report'), icon: Icons.download_rounded, onPressed: onReport),
        ]),
      ]);
    });
  }
}

/// One staged row: the person, its state and the messages naming the field.
class OnbImportRowCard extends StatelessWidget {
  const OnbImportRowCard({super.key, required this.row, this.type, this.compact = false});
  final OnbImportRow row;
  final OnbType? type;
  final bool compact;

  String _field(String key) {
    if (key.isEmpty) return '';
    final f = type?.field(key);
    return f == null || f.label.isEmpty ? key : f.label;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      key: ValueKey('onb.import.row.${row.rowNo}'),
      padding: const EdgeInsets.all(AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('#${row.rowNo}', textDirection: TextDirection.ltr, style: AppType.meta(context).copyWith(color: c.textMedium)),
          AppSpace.gapXs,
          Expanded(child: Text(row.title, maxLines: compact ? 1 : 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context))),
          AppSpace.gapXs,
          AppStatusBadge(label: onbRowStateLabel(row.state), tone: onbRowStateTone(row.state), dense: true),
        ]),
        for (final m in row.messages)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xxs),
            child: Text.rich(
              TextSpan(children: [
                if (m.field.isNotEmpty) TextSpan(text: '${_field(m.field)}: ', style: AppType.meta(context).copyWith(fontWeight: FontWeight.w700, color: row.state == 'error' ? c.danger : c.warning)),
                TextSpan(text: m.text.isEmpty ? m.code : m.text),
              ]),
              style: AppType.meta(context),
            ),
          ),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Step 3: done
// ═════════════════════════════════════════════════════════════════════════════

class OnbImportDoneView extends StatelessWidget {
  const OnbImportDoneView({super.key, required this.result, this.mode = 'draft', this.hasProblems = false, this.onReport, this.onClose});
  final OnbImportResult result;
  final String mode;
  final bool hasProblems;
  final VoidCallback? onReport, onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListView(padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.xxxl), children: [
      Icon(Icons.check_circle_rounded, size: AppIconSize.xl, color: c.success),
      AppSpace.gapSm,
      Text(t('اكتمل الاستيراد', 'Import finished'), textAlign: TextAlign.center, style: AppType.section(context)),
      AppSpace.gapMd,
      Wrap(alignment: WrapAlignment.center, spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        AppStatusBadge(key: const ValueKey('onb.import.done.created'), label: t('أُنشئ ${result.created}', 'Created ${result.created}'), tone: AppTone.success),
        if (mode == 'invite' || result.invited > 0) AppStatusBadge(key: const ValueKey('onb.import.done.invited'), label: t('دُعي ${result.invited}', 'Invited ${result.invited}'), tone: AppTone.info),
        if (result.keptDraft > 0)
          AppStatusBadge(key: const ValueKey('onb.import.done.kept'), label: t('بقي مسودة ${result.keptDraft} لنقص المستندات', 'Kept as draft ${result.keptDraft} (documents missing)'), tone: AppTone.warning),
        if (result.inviteSkipped > 0)
          AppStatusBadge(key: const ValueKey('onb.import.done.invite_skipped'), label: t('تعذرت دعوة ${result.inviteSkipped}', 'Not invited ${result.inviteSkipped}'), tone: AppTone.warning),
        AppStatusBadge(key: const ValueKey('onb.import.done.skipped'), label: t('تُخطّي ${result.skipped}', 'Skipped ${result.skipped}'), tone: result.skipped > 0 ? AppTone.warning : AppTone.neutral),
      ]),
      AppSpace.gapMd,
      Wrap(alignment: WrapAlignment.center, spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        if (hasProblems) AppButton.secondary(key: const ValueKey('onb.import.done.report'), label: t('تنزيل تقرير الأخطاء', 'Download the error report'), icon: Icons.download_rounded, onPressed: onReport),
        AppButton.primary(key: const ValueKey('onb.import.done.close'), label: t('تم', 'Done'), onPressed: onClose),
      ]),
    ]);
  }
}
