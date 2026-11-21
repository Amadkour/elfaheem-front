// lib/features/org/onboarding/onboarding_import.dart — member onboarding from an Excel / CSV list (Phase B, D-1200).
//
//   OnbImportPage          choose the type → download the template → pick the file and a mode (draft · submit ·
//                          invite) → upload → preview → confirm → the done screen. The staged batch lives 24 h on the
//                          server; a 410 `batch_expired` offers "upload again".
//   OnbImportSetupView     the first step over plain values
//   OnbImportPreviewView   the live counts as filters, "repeated errors" (fix one value in every row, `rows/fix`), the
//                          row cards, the "include warnings" / "skip errors" switches and the confirm button (off while
//                          errors remain unless they are skipped on purpose)
//   OnbImportRowCard       one row: errors and warnings each with their own mark, "repeats row N: show both" for an ID
//                          twice in the file, and the inline editor (OnbImportRowEditor) of only the failing cells:
//                          `PATCH rows/{id}` re-checks the row alone. An edited row stays in place under the filter, so
//                          nothing jumps when it turns valid.
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
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_bidi.dart' show ltrIsolate;
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t;
import '../org_page_header.dart' show OrgPushedPage;
import '../org_v3.dart' show OrgCall, orgErrorText;
import '../../rag/app_assistant.dart' show appAssistantTabFace;
import 'onboarding_api.dart';
import 'onboarding_models.dart';
import 'onboarding_wizard.dart' show OnbPlaces;

/// A server message with the figures it quotes ("2005-03-15", "+20 100 …") held left to right: spliced into an
/// Arabic sentence, a date would otherwise read back to front ("15-03-2005").
String onbBidiText(String s) => s.replaceAllMapped(RegExp(r'[+]?\d[\d\-/.:]*\d'), (m) => ltrIsolate(m[0]!));

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
  bool _includeWarnings = false, _skipErrors = false, _busy = false, _expired = false, _fixing = false;
  String? _error;

  /// The row whose editor is open, the row being saved.
  int? _editing, _saving;

  /// Rows edited since the filter was chosen: they stay in place even when they leave the filter (nothing jumps).
  final Set<int> _touched = {};

  /// Row numbers shown alone (a duplicate and its twin); empty: every row of the filter.
  List<int> _focus = const [];

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
      _skipErrors = false;
      _editing = null;
      _touched.clear();
      _focus = const [];
      _phase = _Phase.preview;
    });
  }

  /// A refused edit: an expired or confirmed batch offers "upload again", anything else is a notice.
  void _editFailed(OrgCall r) {
    final code = r.code ?? '';
    if (code == 'batch_expired' || code == 'batch_not_staged' || r.error?.statusCode == 410) {
      setState(() {
        _expired = true;
        _editing = null;
        _error = orgErrorText(r.error!);
      });
      return;
    }
    if (code == 'row_not_found') {
      _reload();
    }
    showAppNotice(orgErrorText(r.error!), error: true);
  }

  /// The whole batch again (after a fix that touched many rows, or a duplicate mark that moved).
  Future<void> _reload() async {
    final b = _batch;
    if (b == null) return;
    final r = await _api.importBatch(widget.orgId, b.id);
    if (!mounted || !r.ok) return;
    setState(() => _batch = OnbBatch.fromJson(r.map));
  }

  /// Saves the edited cells of [row]. With [everywhere], its field is replaced in every row that reads the same value
  /// first (`rows/fix`), then any other edited cell goes through the row's PATCH.
  Future<void> _saveRow(OnbImportRow row, Map<String, dynamic> fields, {OnbRepeatedFix? everywhere}) async {
    final b = _batch;
    if (b == null || fields.isEmpty) return;
    setState(() => _saving = row.id);
    var reload = false;
    var rest = fields;
    if (everywhere != null && fields.containsKey(everywhere.field)) {
      final r = await _api.fixImportRows(widget.orgId, b.id, field: everywhere.field, from: everywhere.value, to: fields[everywhere.field]);
      if (!mounted) return;
      if (!r.ok) {
        setState(() => _saving = null);
        _editFailed(r);
        return;
      }
      final res = OnbRowFixResult.fromJson(r.map);
      showAppNotice(onbFixedRowsText(res.changed));
      rest = {for (final e in fields.entries) if (e.key != everywhere.field) e.key: e.value};
      reload = true;
    }
    if (rest.isNotEmpty) {
      final r = await _api.patchImportRow(widget.orgId, b.id, row.id, rest);
      if (!mounted) return;
      if (!r.ok) {
        setState(() => _saving = null);
        if (reload) await _reload();
        if (mounted) _editFailed(r);
        return;
      }
      final res = OnbRowPatchResult.fromJson(r.map);
      final inFile = row.dupOfRow != null || res.row.dupOfRow != null || [...row.messages, ...res.row.messages].any((m) => m.inFile);
      setState(() => _batch = _batch!.withRow(res.row, res.counts));
      reload = reload || inFile;
    }
    if (reload) await _reload();
    if (!mounted) return;
    final now = _batch?.rows.where((r) => r.id == row.id).firstOrNull;
    setState(() {
      _saving = null;
      _touched.add(row.id);
      // The editor closes once the row has no error left; a row still failing keeps it open with the new messages.
      if (now == null || now.state != 'error') _editing = null;
      if (_batch!.error == 0) _skipErrors = false;
    });
  }

  /// The organization's programmes / departments, loaded once for the "fix everywhere" picker.
  OnbPlaces? _places;

  /// What a cell of [f] may hold, by name (the file holds names, the server matches them): a programme or department
  /// field picks from the organization's list; other kinds use their own options (empty: free text).
  Future<Map<String, String>> _choicesOf(OnbField? f) async {
    if (f == null || (f.kind != 'program' && f.kind != 'department')) return const {};
    final p = _places ??= await OnbPlaces.load(widget.orgId);
    final names = f.kind == 'program' ? p.programs.values : p.departments.values;
    return {for (final n in names) if (n.isNotEmpty) n: n};
  }

  /// "Fix the same value in N rows" from the strip above the list.
  Future<void> _fixEverywhere(OnbRepeatedFix fix) async {
    final b = _batch;
    if (b == null) return;
    final field = _type?.field(fix.field);
    final choices = await _choicesOf(field);
    if (!mounted) return;
    final to = await showOnbFixEverywhereDialog(context, fix: fix, field: field, choices: choices);
    if (to == null || !mounted) return;
    setState(() => _fixing = true);
    final r = await _api.fixImportRows(widget.orgId, b.id, field: fix.field, from: fix.value, to: to);
    if (!mounted) return;
    if (!r.ok) {
      setState(() => _fixing = false);
      _editFailed(r);
      return;
    }
    final res = OnbRowFixResult.fromJson(r.map);
    await _reload();
    if (!mounted) return;
    setState(() {
      _fixing = false;
      for (final no in fix.rows) {
        final id = _batch?.rowNo(no)?.id;
        if (id != null) _touched.add(id);
      }
    });
    showAppNotice(onbFixedRowsText(res.changed));
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
        _editing = null;
        _touched.clear();
        _focus = const [];
      });

  @override
  Widget build(BuildContext context) {
    final b = _batch;
    return OrgPushedPage(
      title: t('استيراد من Excel', 'Import from Excel'),
      // a phone's header keeps one short line ("Updated …"); the section name shows from tablet width
      subtitle: MediaQuery.sizeOf(context).width < AppRoadmap.wideFrom ? null : t('الالتحاق والتعيين', 'Admissions & appointments'),
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
            skipErrors: _skipErrors,
            busy: _busy || _fixing,
            error: _error,
            expired: _expired,
            editingRowId: _editing,
            savingRowId: _saving,
            touched: _touched,
            focus: _focus,
            onFilter: (v) => setState(() {
              _filter = v;
              _touched.clear();
              _focus = const [];
            }),
            onIncludeWarnings: (v) => setState(() => _includeWarnings = v),
            onSkipErrors: (v) => setState(() => _skipErrors = v),
            onEdit: (r) => setState(() => _editing = r?.id),
            onSaveRow: _saveRow,
            onFixEverywhere: _fixEverywhere,
            onShowRows: (rows) => setState(() => _focus = rows),
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
      AppSectionTitle(t('1 · النوع', '1 · Type')),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final ty in types)
          AppChoiceChip(key: ValueKey('onb.import.type.${ty.key}'), label: ty.label.isEmpty ? ty.key : ty.label, selected: type?.key == ty.key, onTap: () => onType?.call(ty)),
      ]),
      AppSpace.gapMd,
      AppSectionTitle(t('2 · القالب', '2 · Template')),
      Text(t('نزّل القالب واملأه، فكل نوع له أعمدته الخاصة.', 'Download the template and fill it in: every type has its own columns.'), style: AppType.meta(context)),
      AppSpace.gapXs,
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: AppButton.secondary(key: const ValueKey('onb.import.template'), label: t('تنزيل القالب', 'Download the template'), icon: Icons.download_rounded, busy: busy && fileName.isEmpty, onPressed: type == null || busy ? null : onTemplate),
      ),
      AppSpace.gapMd,
      AppSectionTitle(t('3 · الملف والوضع', '3 · File and mode')),
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
//  Step 2: preview and the inline fix
// ═════════════════════════════════════════════════════════════════════════════

String onbRowsText(int n) => countText(n, ar1: 'صف واحد', ar2: 'صفان', arFew: '{n} صفوف', arMany: '{n} صفاً', en1: '1 row', en: '{n} rows');

String onbFixedRowsText(int n) =>
    countText(n, ar1: 'صُحح صف واحد', ar2: 'صُحح صفان', arFew: 'صُححت {n} صفوف', arMany: 'صُحح {n} صفاً', en1: 'Fixed 1 row', en: 'Fixed {n} rows', ar0: 'لم يتغير أي صف', en0: 'No row changed');

/// The label of a column of [type] (the key when the type does not name it).
String onbColumnLabel(OnbType? type, String key) {
  if (key.isEmpty) return '';
  final f = type?.field(key);
  return f == null || f.label.isEmpty ? key : f.label;
}

/// The values the inline editor sends: only the cells that changed (a masked ID left as it is never goes back).
Map<String, dynamic> onbChangedCells(OnbImportRow row, Map<String, String> values) => {
      for (final e in values.entries)
        if (e.value.trim() != row.cell(e.key).trim()) e.key: e.value.trim(),
    };

class OnbImportPreviewView extends StatelessWidget {
  const OnbImportPreviewView({
    super.key,
    required this.batch,
    this.type,
    this.filter = '',
    this.includeWarnings = false,
    this.skipErrors = false,
    this.busy = false,
    this.error,
    this.expired = false,
    this.editingRowId,
    this.savingRowId,
    this.touched = const {},
    this.focus = const [],
    this.onFilter,
    this.onIncludeWarnings,
    this.onSkipErrors,
    this.onEdit,
    this.onSaveRow,
    this.onFixEverywhere,
    this.onShowRows,
    this.onConfirm,
    this.onReport,
    this.onAgain,
  });

  final OnbBatch batch;
  final OnbType? type;
  final String filter;
  final bool includeWarnings, skipErrors, busy, expired;
  final String? error;

  /// The row whose editor is open, the row being saved (ids).
  final int? editingRowId, savingRowId;

  /// Rows edited under this filter: kept in place even when they no longer match it.
  final Set<int> touched;

  /// Row numbers shown alone (a duplicate and its twin).
  final List<int> focus;
  final void Function(String)? onFilter;
  final void Function(bool)? onIncludeWarnings, onSkipErrors;

  /// Opens (a row) or closes (null) the inline editor.
  final void Function(OnbImportRow?)? onEdit;
  final Future<void> Function(OnbImportRow row, Map<String, dynamic> fields, {OnbRepeatedFix? everywhere})? onSaveRow;
  final void Function(OnbRepeatedFix)? onFixEverywhere;
  final void Function(List<int>)? onShowRows;
  final VoidCallback? onConfirm, onReport, onAgain;

  bool get _editable => batch.staged && !expired && onSaveRow != null;

  /// On a phone the assistant's docked tab sits on the END edge low on the screen, right where these switches are:
  /// keep their trailing switch clear of the tab's drawn face (wide windows have no edge tab).
  static Widget _clearOfTab(bool wide, Widget child) => wide
      ? child
      : Padding(padding: const EdgeInsetsDirectional.only(end: appAssistantTabFace - AppSpace.md + AppSpace.xs), child: child);

  List<OnbImportRow> get _rows {
    if (focus.isNotEmpty) return [for (final no in focus) ?batch.rowNo(no)];
    if (filter.isEmpty) return batch.rows;
    return [for (final r in batch.rows) if (r.state == filter || touched.contains(r.id)) r];
  }

  int _count(String s) => switch (s) {
        'ok' => batch.ok,
        'warning' => batch.warning,
        'error' => batch.error,
        _ => batch.total,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rows = _rows;
    final will = batch.willCreate(includeWarnings: includeWarnings);
    final skip = batch.willSkip(includeWarnings: includeWarnings);
    final fixes = _editable ? batch.repeatedFixes() : const <OnbRepeatedFix>[];
    final blocked = batch.error > 0 && !skipErrors;
    const pad = EdgeInsets.symmetric(horizontal: AppSpace.md);
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 720;
      return CustomScrollView(slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, 0),
          sliver: SliverList.list(children: [
            // The live counts are the filters.
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
              for (final s in const ['', 'error', 'warning', 'ok'])
                AppChoiceChip(
                  key: ValueKey('onb.import.filter.$s'),
                  icon: switch (s) {
                    'error' => Icons.error_outline_rounded,
                    'warning' => Icons.warning_amber_rounded,
                    'ok' => Icons.check_circle_outline_rounded,
                    _ => null,
                  },
                  label: '${onbRowStateLabel(s)} ${_count(s)}',
                  selected: filter == s && focus.isEmpty,
                  onTap: () => onFilter?.call(s),
                ),
            ]),
            if (batch.error > 0 && _editable) ...[
              AppSpace.gapXs,
              Text(t('افتح الصف لتصحيح الخانات الخاطئة فقط، ويُعاد فحصه فوراً دون رفع الملف من جديد.', 'Open a row to correct only the wrong cells; it is checked again at once, with no new upload.'),
                  style: AppType.meta(context)),
            ],
            if (fixes.isNotEmpty) ...[
              AppSpace.gapSm,
              OnbRepeatedFixesCard(fixes: fixes, type: type, busy: busy, onFix: onFixEverywhere),
            ],
            if (focus.isNotEmpty) ...[
              AppSpace.gapSm,
              AppBanner(
                key: const ValueKey('onb.import.focus'),
                icon: Icons.link_rounded,
                text: t('تعرض الصفوف ${focus.join('، ')} فقط', 'Showing rows ${focus.join(', ')} only'),
                action: AppButton.ghost(key: const ValueKey('onb.import.focus.all'), label: t('عرض الكل', 'Show all'), size: AppButtonSize.sm, onPressed: () => onShowRows?.call(const [])),
              ),
            ],
            AppSpace.gapSm,
          ]),
        ),
        if (rows.isEmpty)
          SliverToBoxAdapter(
            child: Padding(padding: const EdgeInsets.symmetric(vertical: AppSpace.lg), child: Center(child: Text(t('لا صفوف في هذه الفئة', 'No rows in this group'), style: AppType.meta(context)))),
          )
        else
          SliverPadding(
            padding: pad,
            sliver: SliverList.builder(
              itemCount: rows.length,
              itemBuilder: (context, i) {
                final r = rows[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.xs),
                  child: OnbImportRowCard(
                    row: r,
                    type: type,
                    compact: wide,
                    editing: editingRowId == r.id,
                    saving: savingRowId == r.id,
                    canEdit: _editable && r.editable && savingRowId == null,
                    repeated: [for (final f in fixes) if (f.rows.contains(r.rowNo) && r.errorFields.contains(f.field)) f],
                    onEdit: onEdit == null ? null : () => onEdit!(editingRowId == r.id ? null : r),
                    onCancel: () => onEdit?.call(null),
                    onSave: onSaveRow == null ? null : (fields, {everywhere}) => onSaveRow!(r, fields, everywhere: everywhere),
                    onShowDuplicate: r.dupOfRow == null || onShowRows == null ? null : () => onShowRows!([r.rowNo, r.dupOfRow!]..sort()),
                  ),
                );
              },
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.xxxl),
          sliver: SliverList.list(children: [
            if (batch.warning > 0) ...[
              AppSpace.gapSm,
              _clearOfTab(wide, AppSwitchTile(
                key: const ValueKey('onb.import.warnings'),
                title: t('إدراج الصفوف ذات التحذيرات', 'Include rows with warnings'),
                subtitle: t('التحذيرات لا تمنع الحفظ، لكن راجعها أولاً.', 'Warnings do not block saving, but review them first.'),
                value: includeWarnings,
                onChanged: onIncludeWarnings,
              )),
            ],
            if (batch.error > 0)
              _clearOfTab(wide, AppSwitchTile(
                key: const ValueKey('onb.import.skip_errors'),
                title: t('تخطي الصفوف ذات الأخطاء (${batch.error})', 'Skip the rows with errors (${batch.error})'),
                subtitle: t('صحّحها أعلاه، أو تخطَّها صراحةً لحفظ الباقي.', 'Fix them above, or skip them on purpose to save the rest.'),
                value: skipErrors,
                onChanged: onSkipErrors,
              )),
            if (error != null) ...[
              AppSpace.gapSm,
              AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!),
            ],
            AppSpace.gapMd,
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
              if (expired)
                AppButton.primary(key: const ValueKey('onb.import.again'), label: t('رفع الملف من جديد', 'Upload again'), icon: Icons.refresh_rounded, onPressed: onAgain)
              else ...[
                AppButton.primary(
                  key: const ValueKey('onb.import.confirm'),
                  label: skip > 0 ? t('حفظ $will وتخطي $skip', 'Save $will, skip $skip') : t('تأكيد وحفظ $will', 'Confirm and save $will'),
                  icon: Icons.check_rounded,
                  busy: busy && savingRowId == null,
                  onPressed: will == 0 || busy || blocked || savingRowId != null ? null : onConfirm,
                ),
                AppButton.ghost(key: const ValueKey('onb.import.back'), label: t('ملف آخر', 'Another file'), onPressed: busy ? null : onAgain),
              ],
              if (batch.error + batch.warning > 0) AppButton.secondary(key: const ValueKey('onb.import.report'), label: t('تقرير الأخطاء', 'Error report'), icon: Icons.download_rounded, onPressed: onReport),
            ]),
            if (blocked && !expired) ...[
              AppSpace.gapXs,
              Text(t('يُفعَّل الحفظ بعد تصحيح الأخطاء أو اختيار تخطيها.', 'Saving opens once the errors are fixed or you choose to skip them.'), style: AppType.meta(context)),
            ],
          ]),
        ),
      ]);
    });
  }
}

/// "The same value fails in N rows": one line per value, each fixed once for every row.
class OnbRepeatedFixesCard extends StatelessWidget {
  const OnbRepeatedFixesCard({super.key, required this.fixes, this.type, this.busy = false, this.onFix});
  final List<OnbRepeatedFix> fixes;
  final OnbType? type;
  final bool busy;
  final void Function(OnbRepeatedFix)? onFix;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shown = fixes.take(3).toList();
    return AppCard(
      key: const ValueKey('onb.import.repeated'),
      padding: const EdgeInsets.all(AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.auto_fix_high_rounded, size: AppIconSize.sm, color: c.primary),
          AppSpace.gapXs,
          Expanded(child: Text(t('أخطاء متكررة: صحّحها مرة واحدة', 'Repeated errors: fix each once'), style: AppType.bodyStrong(context))),
        ]),
        for (final f in shown) ...[
          AppSpace.gapXs,
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text.rich(
              TextSpan(children: [
                TextSpan(text: '${onbColumnLabel(type, f.field)}: ', style: AppType.meta(context).copyWith(fontWeight: FontWeight.w700)),
                TextSpan(text: '«${f.value}»', style: AppType.meta(context).copyWith(color: c.danger)),
                TextSpan(text: ' · ${onbRowsText(f.count)}'),
              ]),
              style: AppType.meta(context),
            ),
            AppButton.tonal(
              key: ValueKey('onb.import.repeated.${f.field}.${f.value}'),
              label: t('تصحيح في ${onbRowsText(f.count)}', 'Fix in ${onbRowsText(f.count)}'),
              size: AppButtonSize.sm,
              onPressed: busy || onFix == null ? null : () => onFix!(f),
            ),
          ]),
        ],
      ]),
    );
  }
}

/// The new value for a repeated one (null: cancelled).
/// [choices] (value → label) turn the free text into a picker: a choice field's options, or the organization's
/// programmes / departments for those kinds; empty: the field's own options, else free text.
Future<String?> showOnbFixEverywhereDialog(BuildContext context, {required OnbRepeatedFix fix, OnbField? field, Map<String, String> choices = const {}}) {
  final ctl = TextEditingController(text: fix.value);
  final opts = choices.isNotEmpty ? choices : {for (final o in field?.options ?? const <OnbOption>[]) o.value: o.label.isEmpty ? o.value : o.label};
  String? pick = opts.containsKey(fix.value) ? fix.value : null;
  final label = field == null || field.label.isEmpty ? fix.field : field.label;
  return showAppDialog<String>(
    context,
    title: t('تصحيح القيمة في كل الصفوف', 'Fix the value in every row'),
    icon: Icons.auto_fix_high_rounded,
    body: StatefulBuilder(
      builder: (ctx, set) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t('«${fix.value}» في ${onbRowsText(fix.count)}. اكتب القيمة الصحيحة مرة واحدة.', '“${fix.value}” in ${onbRowsText(fix.count)}. Enter the right value once.'), style: AppType.body(ctx)),
        AppSpace.gapSm,
        if (opts.isNotEmpty)
          AppDropdown<String>(
            key: const ValueKey('onb.import.fixall.pick'),
            value: pick,
            decoration: InputDecoration(labelText: label),
            items: [for (final e in opts.entries) DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))],
            onChanged: (v) => set(() => pick = v),
          )
        else
          AppField(key: const ValueKey('onb.import.fixall.value'), controller: ctl, label: label, autofocus: true),
      ]),
    ),
    actions: [
      // The dialog's own context: the page's would pop the page under it and orphan the dialog.
      Builder(builder: (ctx) => AppButton.ghost(label: t('إلغاء', 'Cancel'), onPressed: () => Navigator.of(ctx).pop())),
      Builder(
        builder: (ctx) => AppButton.primary(
          key: const ValueKey('onb.import.fixall.save'),
          label: t('تصحيح', 'Fix'),
          onPressed: () {
            final v = opts.isNotEmpty ? (pick ?? '') : ctl.text.trim();
            if (v.isEmpty || v == fix.value) return;
            Navigator.of(ctx).pop(v);
          },
        ),
      ),
    ],
  ).whenComplete(ctl.dispose);
}

/// One staged row: the person, its state, the errors and warnings (each kind with its own mark), the link to its
/// twin when the ID repeats in the file, and the inline editor of the failing cells.
class OnbImportRowCard extends StatelessWidget {
  const OnbImportRowCard({
    super.key,
    required this.row,
    this.type,
    this.compact = false,
    this.editing = false,
    this.saving = false,
    this.canEdit = false,
    this.repeated = const [],
    this.onEdit,
    this.onCancel,
    this.onSave,
    this.onShowDuplicate,
  });
  final OnbImportRow row;
  final OnbType? type;
  final bool compact, editing, saving, canEdit;

  /// The repeated values of this row's failing cells ("also fix in the other rows").
  final List<OnbRepeatedFix> repeated;
  final VoidCallback? onEdit, onCancel, onShowDuplicate;
  final Future<void> Function(Map<String, dynamic> fields, {OnbRepeatedFix? everywhere})? onSave;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasError = row.state == 'error';
    return AppCard(
      key: ValueKey('onb.import.row.${row.rowNo}'),
      padding: const EdgeInsets.all(AppSpace.sm),
      child: AnimatedSize(
        duration: AppMotion.of(context).base,
        curve: AppMotion.curve,
        alignment: AlignmentDirectional.topStart,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('#${row.rowNo}', textDirection: TextDirection.ltr, style: AppType.meta(context).copyWith(color: c.textMedium)),
            AppSpace.gapXs,
            Expanded(child: Text(row.title, maxLines: compact ? 1 : 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context))),
            AppSpace.gapXs,
            if (row.edited) ...[
              AppStatusBadge(key: ValueKey('onb.import.row.${row.rowNo}.edited'), label: t('عُدّل', 'Edited'), tone: AppTone.info, dense: true),
              const SizedBox(width: AppSpace.xxs),
            ],
            AppStatusBadge(label: onbRowStateLabel(row.state), tone: onbRowStateTone(row.state), dense: true),
          ]),
          if (!editing)
            for (final m in [...row.errors, ...row.warnings]) OnbRowMessageLine(message: m, type: type),
          if (row.dupOfRow != null && onShowDuplicate != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xxs),
              child: AppButton.ghost(
                key: ValueKey('onb.import.row.${row.rowNo}.dup'),
                label: t('مكرر مع الصف ${row.dupOfRow}: عرضهما معاً', 'Repeats row ${row.dupOfRow}: show both'),
                icon: Icons.link_rounded,
                size: AppButtonSize.sm,
                onPressed: onShowDuplicate,
              ),
            ),
          if (editing)
            OnbImportRowEditor(key: ValueKey('onb.import.editor.${row.id}'), row: row, type: type, saving: saving, repeated: repeated, onCancel: onCancel, onSave: onSave)
          else if (hasError && canEdit && onEdit != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xs),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: AppButton.tonal(
                  key: ValueKey('onb.import.row.${row.rowNo}.fix'),
                  label: t('تصحيح الصف', 'Fix this row'),
                  icon: Icons.edit_outlined,
                  size: AppButtonSize.sm,
                  onPressed: onEdit,
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// One message: an error (danger mark) or a warning (warning mark), with the column it names.
class OnbRowMessageLine extends StatelessWidget {
  const OnbRowMessageLine({super.key, required this.message, this.type});
  final OnbRowMessage message;
  final OnbType? type;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final m = message;
    final ink = m.isError ? c.danger : c.warning;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.xxs),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(m.isError ? Icons.error_outline_rounded : Icons.warning_amber_rounded, size: AppIconSize.xs, color: ink, semanticLabel: m.isError ? t('خطأ', 'Error') : t('تحذير', 'Warning')),
        const SizedBox(width: AppSpace.xxs),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              if (m.field.isNotEmpty) TextSpan(text: '${onbColumnLabel(type, m.field)}: ', style: AppType.meta(context).copyWith(fontWeight: FontWeight.w700, color: m.isError ? c.danger : c.textDark)),
              TextSpan(text: onbBidiText(m.text.isEmpty ? m.code : m.text)),
            ]),
            style: AppType.meta(context),
          ),
        ),
      ]),
    );
  }
}

/// The inline fix of one row: only the failing cells open (each with its message under it); "Show the other
/// columns" reveals the rest. Save sends only what changed and is off until something did.
class OnbImportRowEditor extends StatefulWidget {
  const OnbImportRowEditor({super.key, required this.row, this.type, this.saving = false, this.repeated = const [], this.onCancel, this.onSave});
  final OnbImportRow row;
  final OnbType? type;
  final bool saving;
  final List<OnbRepeatedFix> repeated;
  final VoidCallback? onCancel;
  final Future<void> Function(Map<String, dynamic> fields, {OnbRepeatedFix? everywhere})? onSave;

  @override
  State<OnbImportRowEditor> createState() => _OnbImportRowEditorState();
}

class _OnbImportRowEditorState extends State<OnbImportRowEditor> {
  final Map<String, TextEditingController> _ctl = {};
  final Map<String, String> _picked = {};
  bool _all = false, _everywhere = false;

  OnbImportRow get _row => widget.row;

  /// The failing cells first, then (with "show all") every other column of the type, else of the row.
  List<String> get _keys {
    final err = _row.errorFields;
    if (!_all && err.isNotEmpty) return err;
    final others = widget.type != null ? [for (final f in widget.type!.fields) f.key] : [..._row.data.keys, ..._row.raw.keys];
    return <String>{...err, for (final k in others) if (!err.contains(k)) k}.toList();
  }

  OnbField? _field(String k) => widget.type?.field(k);

  bool _isPick(String k) => (_field(k)?.options ?? const []).isNotEmpty && _field(k)?.kind == 'select';

  TextEditingController _c(String k) => _ctl.putIfAbsent(k, () => TextEditingController(text: _row.cell(k))..addListener(_changed));

  void _changed() => setState(() {});

  Map<String, String> get _values => {
        for (final k in _keys) k: _isPick(k) ? (_picked[k] ?? _row.cell(k)) : _c(k).text,
        // A cell edited before "show all" was closed again still counts.
        for (final e in _ctl.entries) if (!_keys.contains(e.key)) e.key: e.value.text,
        for (final e in _picked.entries) if (!_keys.contains(e.key)) e.key: e.value,
      };

  Map<String, dynamic> get _changes => onbChangedCells(_row, _values);

  @override
  void didUpdateWidget(OnbImportRowEditor old) {
    super.didUpdateWidget(old);
    if (!identical(old.row, widget.row)) {
      // The row came back from the server (still failing): start again from what it now holds.
      for (final c in _ctl.values) {
        c.removeListener(_changed);
        c.dispose();
      }
      _ctl.clear();
      _picked.clear();
      _everywhere = false;
    }
  }

  @override
  void dispose() {
    for (final c in _ctl.values) {
      c.removeListener(_changed);
      c.dispose();
    }
    super.dispose();
  }

  TextInputType? _keyboard(String kind) => switch (kind) {
        'email' => TextInputType.emailAddress,
        'phone' => TextInputType.phone,
        'number' || 'national_id' => TextInputType.number,
        'date' => TextInputType.datetime,
        _ => null,
      };

  Widget _input(String k) {
    final f = _field(k);
    final label = onbColumnLabel(widget.type, k);
    final msgs = _row.messagesFor(k).where((m) => m.isError).map((m) => onbBidiText(m.text.isEmpty ? m.code : m.text)).toList();
    final err = msgs.isEmpty ? null : msgs.join(' · ');
    if (_isPick(k)) {
      final cur = _picked[k] ?? _row.cell(k);
      final opts = f!.options;
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.sm),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AppDropdown<String>(
            key: ValueKey('onb.import.cell.${_row.rowNo}.$k'),
            value: opts.any((o) => o.value == cur) ? cur : null,
            decoration: InputDecoration(labelText: label),
            hint: cur.isEmpty ? null : Text(cur, maxLines: 1, overflow: TextOverflow.ellipsis),
            items: [for (final o in opts) DropdownMenuItem(value: o.value, child: Text(o.label.isEmpty ? o.value : o.label))],
            onChanged: widget.saving ? null : (v) => setState(() => _picked[k] = v ?? ''),
          ),
          if (err != null) Padding(padding: const EdgeInsets.only(top: AppSpace.xxs), child: Text(err, style: AppType.meta(context).copyWith(color: context.colors.danger))),
        ]),
      );
    }
    final kind = f?.kind ?? (k == 'email' || k == 'phone' || k == 'national_id' ? k : 'text');
    final ltr = const {'email', 'phone', 'national_id', 'number', 'date'}.contains(kind) || k == 'passport_no';
    return AppField(
      key: ValueKey('onb.import.cell.${_row.rowNo}.$k'),
      controller: _c(k),
      label: label,
      ltr: ltr,
      keyboard: _keyboard(kind),
      hint: kind == 'date' ? 'YYYY-MM-DD' : null,
      helper: _row.isRaw(k) ? t('هذا ما كُتب في الملف ولم يُفهم', 'This is what the file says; it could not be read') : null,
      errorText: err,
      enabled: !widget.saving,
    );
  }

  Future<void> _save() async {
    final ch = _changes;
    if (ch.isEmpty) return;
    OnbRepeatedFix? every;
    if (_everywhere && widget.repeated.isNotEmpty) {
      final r = widget.repeated.first;
      if (ch.containsKey(r.field)) every = r;
    }
    await widget.onSave?.call(ch, everywhere: every);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final keys = _keys;
    final changed = _changes.isNotEmpty;
    final rep = widget.repeated.isEmpty ? null : widget.repeated.first;
    final others = _row.errorFields.isNotEmpty;
    final rowMsgs = [for (final m in _row.messages) if (m.field.isEmpty || !keys.contains(m.field)) m];
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.xs),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Messages with no cell of their own (or for a hidden column) stay readable while editing.
        for (final m in rowMsgs) OnbRowMessageLine(message: m, type: widget.type),
        if (rowMsgs.isNotEmpty) AppSpace.gapXs,
        for (final k in keys) _input(k),
        if (rep != null)
          AppSwitchTile(
            key: ValueKey('onb.import.row.${_row.rowNo}.everywhere'),
            dense: true,
            title: t('صحّح «${rep.value}» في كل الصفوف (${onbRowsText(rep.count)})', 'Fix “${rep.value}” in every row (${onbRowsText(rep.count)})'),
            value: _everywhere,
            onChanged: widget.saving ? null : (v) => setState(() => _everywhere = v),
          ),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
          AppButton.primary(
            key: ValueKey('onb.import.row.${_row.rowNo}.save'),
            label: t('حفظ وإعادة الفحص', 'Save and check again'),
            icon: Icons.check_rounded,
            size: AppButtonSize.sm,
            busy: widget.saving,
            onPressed: !changed || widget.saving ? null : _save,
          ),
          AppButton.ghost(key: ValueKey('onb.import.row.${_row.rowNo}.cancel'), label: t('إلغاء', 'Cancel'), size: AppButtonSize.sm, onPressed: widget.saving ? null : widget.onCancel),
          if (others)
            AppButton.ghost(
              key: ValueKey('onb.import.row.${_row.rowNo}.all'),
              label: _all ? t('الخانات الخاطئة فقط', 'Only the wrong cells') : t('عرض باقي الأعمدة', 'Show the other columns'),
              icon: _all ? Icons.unfold_less_rounded : Icons.unfold_more_rounded,
              size: AppButtonSize.sm,
              onPressed: widget.saving ? null : () => setState(() => _all = !_all),
            ),
        ]),
        if (!changed && !widget.saving)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xxs),
            child: Text(t('عدّل خانة واحدة على الأقل للحفظ.', 'Change at least one cell to save.'), style: AppType.meta(context).copyWith(color: c.textMedium)),
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
