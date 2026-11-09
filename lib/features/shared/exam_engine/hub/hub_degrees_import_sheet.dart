// "Import degrees from Excel" (D-353): one sheet in two steps. First the file (with the course's own student list to
// fill in, if the teacher wants it), then what the file holds: the server's guess at the two columns, how many rows
// match, what will be left out and why, and the full mark. Nothing is saved until the last button.
//
// The ONE totals import: the hub's row and the Get Result screen both open it. HubDegreesPickBody / HubDegreesPreviewBody take
// plain values (under the layout harness); the calls: `hub_degrees_import.dart`.
library;

import 'dart:async' show Timer;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../../admin/admin_common.dart' show t;
import '../../../admin/admin_money_p8.dart' show p8SaveBytes;
import 'hub_degrees_import.dart';

/// Opens the sheet; true once degrees were saved (the caller reloads its list).
Future<bool> openHubDegreesImport(BuildContext context, {required int examId, required String title}) async {
  final saved = await showAppSheet<bool>(context, (_) => HubDegreesImportSheet(examId: examId, title: title));
  return saved == true;
}

class HubDegreesImportSheet extends StatefulWidget {
  const HubDegreesImportSheet({super.key, required this.examId, required this.title, this.api, this.initialFileName, this.initialBytes});
  final int examId;
  final String title;

  /// Tests: replaces the real calls.
  final DegreesApi? api;

  /// Tests: a file already chosen, past the system picker.
  final String? initialFileName;
  final Uint8List? initialBytes;

  @override
  State<HubDegreesImportSheet> createState() => _HubDegreesImportSheetState();
}

class _HubDegreesImportSheetState extends State<HubDegreesImportSheet> {
  late final DegreesApi _api = widget.api ?? DegreesApi();
  final _max = TextEditingController();

  String? _fileName;
  Uint8List? _bytes;
  DegreesPreview? _preview;
  String? _error;
  bool _reading = false, _saving = false, _downloading = false;

  // The rows on screen were checked against [_evaluatedMax]. A mark being typed has not been asked about yet ([_maxPending]),
  // and only the newest question ([_asked]) may answer, so the summary is always what Save will write.
  double? _evaluatedMax;
  bool _maxPending = false;
  int _asked = 0;
  Timer? _maxTimer;

  @override
  void initState() {
    super.initState();
    if (widget.initialBytes != null) {
      _fileName = widget.initialFileName;
      _bytes = widget.initialBytes;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _read();
      });
    }
  }

  @override
  void dispose() {
    _maxTimer?.cancel();
    _max.dispose();
    super.dispose();
  }

  Future<void> _template() async {
    setState(() => _downloading = true);
    try {
      final bytes = await _api.template(widget.examId);
      await p8SaveBytes(bytes, 'degrees_${widget.examId}.xlsx', mime: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      showAppNotice(t('تم تنزيل قائمة الطلاب', 'The student list is downloaded'));
    } catch (e) {
      showAppNotice(ApiException.from(e).message, error: true);
    }
    if (mounted) setState(() => _downloading = false);
  }

  Future<void> _pick() async {
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: kDegreesFileTypes);
    if (f == null || !mounted) return;
    Uint8List? bytes;
    try {
      bytes = await f.readAsBytes();
    } catch (_) {}
    if (!mounted) return;
    if (bytes == null) {
      setState(() => _error = t('تعذّرت قراءة الملف', 'The file could not be read'));
      return;
    }
    if (bytes.length > kDegreesMaxBytes) {
      setState(() => _error = t('الملف أكبر من 2 ميجابايت', 'The file is larger than 2 MB'));
      return;
    }
    _fileName = f.name;
    _bytes = bytes;
    await _read();
  }

  /// Sends the file (again, when a column was changed) and shows what it holds.
  Future<void> _read({String? match, String? degree}) async {
    _maxTimer?.cancel();
    final ask = ++_asked;
    final max = parseFullMark(_max.text);
    setState(() {
      _reading = true;
      _maxPending = false;
      _error = null;
    });
    final (p, r) = await _api.preview(widget.examId, fileName: _fileName!, bytes: _bytes!, matchColumn: match, degreeColumn: degree, maxScore: max);
    if (!mounted || ask != _asked) return;
    setState(() {
      _reading = false;
      if (p == null) {
        _error = degreesErrorText(r);
        return;
      }
      _preview = p;
      _evaluatedMax = p.maxScore ?? max;   // the server says which mark it used
      // the full mark the exam knows; a teacher's own change survives a column change
      if (_max.text.trim().isEmpty && p.maxScore != null) _max.text = fullMarkText(p.maxScore!);
    });
  }

  /// The full mark changed: whatever was on its way was about another mark, and the rows are checked again once typing stops.
  void _maxChanged() {
    _maxTimer?.cancel();
    final v = parseFullMark(_max.text);
    _asked++;
    setState(() {
      _reading = false;
      _maxPending = v != null && v != _evaluatedMax;
    });
    if (_maxPending) _maxTimer = Timer(const Duration(milliseconds: 400), () => _read(match: _preview?.matchColumn, degree: _preview?.degreeColumn));
  }

  Future<void> _save() async {
    final p = _preview;
    final max = parseFullMark(_max.text);
    if (p == null || !p.canSave || max == null || max != _evaluatedMax) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final r = await _api.commit(widget.examId, importKey: p.importKey!, maxScore: max);
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _saving = false;
        _error = degreesErrorText(r);
        if (r.code == 'import_expired' || r.code == 'import_key_invalid') _preview = null;
      });
      return;
    }
    final n = r.map['written'] is num ? (r.map['written'] as num).toInt() : p.matched;
    showAppNotice(countText(n,
        ar1: 'حُفظت درجة واحدة', ar2: 'حُفظت درجتان', arFew: 'حُفظت {n} درجات', arMany: 'حُفظت {n} درجة', en1: '1 degree saved', en: '{n} degrees saved'));
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final p = _preview;
    return AppSheetContent(title: t('استيراد الدرجات من Excel', 'Import degrees from Excel'), children: [
      Text(widget.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(13, c: context.colors.textMedium)),
      AppSpace.gapMd,
      if (_error != null) ...[
        AppBanner(icon: Icons.error_outline_rounded, color: context.colors.danger, text: _error!),
        AppSpace.gapSm,
      ],
      if (p == null)
        HubDegreesPickBody(reading: _reading, downloading: _downloading, onTemplate: _template, onPick: _pick)
      else
        HubDegreesPreviewBody(
          fileName: _fileName ?? '',
          preview: p,
          maxController: _max,
          reading: _reading,
          saving: _saving,
          evaluated: !_maxPending && parseFullMark(_max.text) == _evaluatedMax,
          onChangeFile: _pick,
          onMaxChanged: _maxChanged,
          onMatchColumn: (v) => _read(match: v, degree: p.degreeColumn),
          onDegreeColumn: (v) => _read(match: p.matchColumn, degree: v),
          onSave: _save,
        ),
    ]);
  }
}

class _StepLine extends StatelessWidget {
  const _StepLine(this.n, this.text);
  final int n;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: c.primaryTint, shape: BoxShape.circle),
          child: Text('$n', style: appText(12.5, w: FontWeight.w700, c: c.primary)),
        ),
        AppSpace.gapSm,
        Expanded(child: Padding(padding: const EdgeInsets.only(top: 3), child: Text(text, style: appText(13.5, c: c.textDark).copyWith(height: 1.45)))),
      ]),
    );
  }
}

/// Step one: choose the file. The student list is offered, never required: any sheet with names or ids works.
class HubDegreesPickBody extends StatelessWidget {
  const HubDegreesPickBody({super.key, required this.onTemplate, required this.onPick, this.reading = false, this.downloading = false});
  final VoidCallback onTemplate, onPick;
  final bool reading, downloading;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      _StepLine(1, t('نزّل قائمة طلاب المقرر، أو استخدم أي ملف لديك فيه اسم الطالب أو رقمه.', 'Download the course\'s student list, or use any file that has the student\'s name or ID.')),
      _StepLine(2, t('اكتب درجة كل طالب في عمود الدرجة.', 'Write each student\'s degree in the degree column.')),
      _StepLine(3, t('ارفع الملف، وسنريك ما طابقناه قبل الحفظ.', 'Upload the file. You will see what matched before anything is saved.')),
      AppSpace.gapSm,
      AppButton.primary(
          key: const ValueKey('exam.hub.degrees.pick'),
          label: reading ? t('جارٍ قراءة الملف', 'Reading the file') : t('اختر الملف', 'Choose the file'),
          icon: Icons.upload_file_rounded,
          expand: true,
          busy: reading,
          onPressed: reading ? null : onPick),
      const SizedBox(height: AppSpace.xs),
      AppButton.secondary(
          key: const ValueKey('exam.hub.degrees.template'),
          label: t('تنزيل قائمة الطلاب', 'Download the student list'),
          icon: Icons.download_rounded,
          expand: true,
          busy: downloading,
          onPressed: downloading ? null : onTemplate),
    ]);
  }
}

class _CountTile extends StatelessWidget {
  const _CountTile({required this.value, required this.label, required this.color});
  final int value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.sm),
      decoration: BoxDecoration(color: color.withValues(alpha: .10), borderRadius: AppRadius.chipAll),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('$value', style: appText(20, w: FontWeight.w700, c: c.textDark)),
        Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(12, c: c.textMedium)),
      ]),
    );
  }
}

/// The rows that will be left out: the first few, the rest on demand.
class _IssueGroup extends StatefulWidget {
  const _IssueGroup({required this.title, required this.items, required this.reason, required this.color});
  final String title;
  final List<DegreeIssue> items;
  final String Function(DegreeIssue) reason;
  final Color color;

  @override
  State<_IssueGroup> createState() => _IssueGroupState();
}

class _IssueGroupState extends State<_IssueGroup> {
  static const _few = 3;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shown = _all ? widget.items : widget.items.take(_few).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(widget.title, style: appText(13, w: FontWeight.w700, c: c.textDark)),
      const SizedBox(height: AppSpace.xxs),
      for (final x in shown)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('صف ${x.row}', 'Row ${x.row}'), style: appText(12, w: FontWeight.w600, c: widget.color)),
            AppSpace.gapXs,
            Expanded(
              child: Text(x.value.isEmpty ? widget.reason(x) : '${x.value} · ${widget.reason(x)}',
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(12.5, c: c.textMedium)),
            ),
          ]),
        ),
      if (widget.items.length > _few && !_all)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppButton.ghost(
              label: t('عرض الكل (${widget.items.length})', 'Show all (${widget.items.length})'), size: AppButtonSize.sm, onPressed: () => setState(() => _all = true)),
        ),
    ]);
  }
}

/// Step two: what the file holds, before anything is saved.
class HubDegreesPreviewBody extends StatelessWidget {
  const HubDegreesPreviewBody({
    super.key,
    required this.fileName,
    required this.preview,
    required this.maxController,
    required this.onChangeFile,
    required this.onMaxChanged,
    required this.onMatchColumn,
    required this.onDegreeColumn,
    required this.onSave,
    this.reading = false,
    this.saving = false,
    this.evaluated = true,
  });

  /// The rows shown were checked against the full mark in the field. False while it is being typed or asked about.
  final bool evaluated;
  final String fileName;
  final DegreesPreview preview;
  final TextEditingController maxController;
  final bool reading, saving;
  final VoidCallback onChangeFile, onMaxChanged, onSave;
  final ValueChanged<String> onMatchColumn, onDegreeColumn;

  Widget _columnPicker(String label, IconData icon, String? value, ValueChanged<String> onChanged) => AppDropdown<String>(
        value: value,
        enabled: !reading && !saving,
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon, size: 20)),
        items: [for (final col in preview.columns) DropdownMenuItem(value: col, child: Text(col, overflow: TextOverflow.ellipsis))],
        onChanged: (v) {
          if (v != null && v != value) onChanged(v);
        },
      );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = preview;
    final maxOk = parseFullMark(maxController.text) != null;
    final student = _columnPicker(t('عمود الطالب', 'Student column'), Icons.badge_outlined, p.matchColumn, onMatchColumn);
    final degree = _columnPicker(t('عمود الدرجة', 'Degree column'), Icons.numbers_rounded, p.degreeColumn, onDegreeColumn);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Icon(Icons.table_chart_outlined, size: 20, color: c.primary),
        AppSpace.gapXs,
        Expanded(child: Text(fileName, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13.5, w: FontWeight.w600, c: c.textDark))),
        AppButton.ghost(key: const ValueKey('exam.hub.degrees.change'), label: t('تغيير', 'Change'), size: AppButtonSize.sm, onPressed: reading || saving ? null : onChangeFile),
      ]),
      AppSpace.gapSm,
      Text(degreesHeadline(p), style: appText(15, w: FontWeight.w700, c: c.textDark)),
      AppSpace.gapSm,
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: _CountTile(value: p.matched, label: t('مطابق', 'Matched'), color: c.success)),
        AppSpace.gapXs,
        Expanded(child: _CountTile(value: p.unmatched.length, label: t('غير مطابق', 'Not matched'), color: c.warning)),
        AppSpace.gapXs,
        Expanded(child: _CountTile(value: p.invalid.length, label: t('غير صالح', 'Not valid'), color: c.danger)),
      ]),
      AppSpace.gapMd,
      // two columns, both recognised: nothing to choose
      if (p.needsColumns || p.columns.length > 2) ...[
        LayoutBuilder(builder: (context, box) {
          if (box.maxWidth < 480) {
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [student, AppSpace.gapSm, degree]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: student), AppSpace.gapSm, Expanded(child: degree)]);
        }),
        AppSpace.gapSm,
      ],
      Padding(padding: const EdgeInsets.only(bottom: AppSpace.sm), child: AppNumberField(controller: maxController, label: t('الدرجة العظمى', 'Full mark'), hint: t('مثال: 20', 'For example: 20'), min: 0, decimals: 2, onChanged: (_) => onMaxChanged())),
      Text(t('الدرجات الأعلى منها لن تُحفظ.', 'Degrees above it are not saved.'), style: appText(12, c: c.textLight)),
      if (p.unmatched.isNotEmpty) ...[
        AppSpace.gapMd,
        _IssueGroup(
            title: t('لم نجد هؤلاء في المقرر', 'Not found in this course'),
            items: p.unmatched,
            reason: (_) => t('غير موجود', 'No such student'),
            color: c.warning),
      ],
      if (p.invalid.isNotEmpty) ...[
        AppSpace.gapMd,
        _IssueGroup(title: t('درجات لن تُحفظ', 'Degrees that will not be saved'), items: p.invalid, reason: (x) => degreeReasonText(x.reason), color: c.danger),
      ],
      AppSpace.gapLg,
      AppButton.primary(
          key: const ValueKey('exam.hub.degrees.save'),
          label: degreesSaveLabel(p.matched),
          icon: Icons.check_rounded,
          expand: true,
          busy: saving,
          onPressed: p.canSave && maxOk && evaluated && !reading && !saving ? onSave : null),
    ]);
  }
}
