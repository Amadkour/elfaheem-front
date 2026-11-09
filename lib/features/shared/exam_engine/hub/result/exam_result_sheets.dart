// The two sheets of "Get result" (Exam Hub, F5): writing the results to a Data Lab column the teacher chooses (contract 1.4:
// choose or create, preview, a plain before / after, confirm), and importing totals from Excel (1.5: template, file, what
// matched, confirm). [ResultLabDiff] and [ResultDegreeSummary] take plain values for the layout harness.
library;

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../../../admin/admin_common.dart' show t;
import '../../../../admin/admin_money_p8.dart' show p8SaveBytes;
import '../../paper/review/omr_review.dart' show omrLtr, omrNum;
import 'exam_result_data.dart';

String _v(double? v) => v == null ? '—' : omrNum(v);

class _Count extends StatelessWidget {
  const _Count(this.label, this.value, {this.color});
  final String label;
  final int value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
      decoration: BoxDecoration(color: (color ?? c.textMedium).withValues(alpha: .10), borderRadius: BorderRadius.circular(AppRadius.chip)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('$value', style: appText(18, w: FontWeight.w800, c: c.textDark)),
        Text(label, style: appText(12, c: c.textMedium)),
      ]),
    );
  }
}

/// Before and after: who changes and how, what stays, what is held back, who is not in the course, and any scaling.
class ResultLabDiff extends StatelessWidget {
  const ResultLabDiff({super.key, required this.preview});
  final LabPreviewData preview;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = preview;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(t('العمود: «${p.label}»${p.max == null ? '' : ' من ${omrLtr(_v(p.max))}'}', 'Column: "${p.label}"${p.max == null ? '' : ' out of ${_v(p.max)}'}'), style: appText(14, w: FontWeight.w700, c: c.textDark)),
      const SizedBox(height: AppSpace.xs),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        _Count(t('ستتغير', 'Will change'), p.changes.length, color: c.primary),
        _Count(t('بلا تغيير', 'Unchanged'), p.unchanged),
        if (p.held > 0) _Count(t('محجوزة حتى التصحيح', 'Held until marked'), p.held, color: c.warning),
        if (p.unmatched.isNotEmpty) _Count(t('خارج المقرر', 'Not in the course'), p.unmatched.length, color: c.danger),
      ]),
      if (p.scaled) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(
          icon: Icons.straighten_rounded,
          text: t('الاختبار من ${omrLtr(_v(p.examMax))} والعمود من ${omrLtr(_v(p.max))}، فتُحوَّل كل درجة بالنسبة نفسها.', 'The exam is out of ${_v(p.examMax)} and the column out of ${_v(p.max)}, so every mark is scaled by the same ratio.'),
        ),
      ],
      if (p.overwrites > 0) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(
          icon: Icons.warning_amber_rounded,
          color: c.warning,
          text: t('ستُستبدل ${p.overwrites} من الدرجات الموجودة في هذا العمود.', '${p.overwrites} existing marks in this column will be replaced.'),
        ),
      ],
      if (p.changes.isNotEmpty) ...[
        const SizedBox(height: AppSpace.sm),
        Container(
          constraints: const BoxConstraints(maxHeight: 260),
          decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(AppRadius.chip)),
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs),
            itemCount: p.changes.length,
            separatorBuilder: (_, _) => Divider(height: 1, color: c.divider.withValues(alpha: .6)),
            itemBuilder: (_, i) {
              final x = p.changes[i];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
                child: Row(children: [
                  Expanded(child: Text(x.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13.5, c: c.textDark))),
                  const SizedBox(width: AppSpace.xs),
                  Text(omrLtr(_v(x.oldValue)), style: appText(13, c: c.textMedium)),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs), child: Icon(Icons.arrow_forward_rounded, size: 14, color: c.textLight)),
                  Text(omrLtr(_v(x.newValue)), style: appText(13.5, w: FontWeight.w800, c: c.textDark)),
                ]),
              );
            },
          ),
        ),
      ],
      if (p.unmatched.isNotEmpty) ...[
        const SizedBox(height: AppSpace.sm),
        Text(t('ليسوا في هذا المقرر ولن تُكتب درجاتهم: ${p.unmatched.take(6).join('، ')}${p.unmatched.length > 6 ? '…' : ''}', 'Not in this course, so not written: ${p.unmatched.take(6).join(', ')}${p.unmatched.length > 6 ? '…' : ''}'),
            style: appText(12.5, c: c.textMedium, h: 1.45)),
      ],
    ]);
  }
}

/// Opens the Data Lab sheet; true when marks were written.
Future<bool> showResultDataLabSheet(BuildContext context, {required ResultsBoard board, required List<LabColumnChoice> columns, ResultsHubApi? api}) async =>
    await showAppSheet<bool>(context, (_) => _DataLabSheet(board: board, columns: columns, api: api ?? ResultsHubApi())) ?? false;

class _DataLabSheet extends StatefulWidget {
  const _DataLabSheet({required this.board, required this.columns, required this.api});
  final ResultsBoard board;
  final List<LabColumnChoice> columns;
  final ResultsHubApi api;

  @override
  State<_DataLabSheet> createState() => _DataLabSheetState();
}

class _DataLabSheetState extends State<_DataLabSheet> {
  static const _newKey = '__new__';
  late String _pick = labDefaultColumn(widget.columns, lastWritten: widget.board.dataLabColumn, title: widget.board.title) ?? _newKey;
  late final _label = TextEditingController(text: widget.board.title);
  late final _max = TextEditingController(text: omrNum(_examMax));
  LabPreviewData? _preview;
  bool _busy = false;
  String? _error;

  double? get _examMax => widget.board.stats.gradedEntries.isEmpty ? null : widget.board.stats.gradedEntries.first.maxScore;
  bool get _isNew => _pick == _newKey;

  @override
  void dispose() {
    _label.dispose();
    _max.dispose();
    super.dispose();
  }

  Map<String, dynamic>? _body() {
    if (!_isNew) return labBody(columnKey: _pick);
    final label = _label.text.trim();
    final max = double.tryParse(_max.text.trim().replaceAll(',', '.'));
    if (label.isEmpty) {
      setState(() => _error = t('اكتب اسم العمود', 'Enter the column\'s name'));
      return null;
    }
    if (max == null || max <= 0) {
      setState(() => _error = t('اكتب الدرجة العظمى للعمود', 'Enter the column\'s full mark'));
      return null;
    }
    return labBody(newLabel: label, newMax: max);
  }

  Future<void> _previewNow() async {
    final body = _body();
    if (body == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await widget.api.labPreview(widget.board.examId, body);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.ok) {
        _preview = LabPreviewData.fromJson(r.map);
      } else {
        _error = resultErrorText(r);
      }
    });
  }

  Future<void> _apply() async {
    final p = _preview;
    final body = _body();
    if (p == null || body == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await widget.api.labApply(widget.board.examId, body);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      setState(() => _error = resultErrorText(r));
      return;
    }
    final written = (r.map['written'] as num?)?.toInt() ?? 0, skipped = (r.map['skipped'] as num?)?.toInt() ?? 0;
    showAppNotice(skipped == 0 ? t('كُتبت $written درجة في «${p.label}»', '$written marks written to "${p.label}"') : t('كُتبت $written درجة في «${p.label}»، ولم تُكتب $skipped', '$written marks written to "${p.label}", $skipped not written'));
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = _preview;
    return AppSheetContent(title: t('الكتابة في Data Lab', 'Write to the Data Lab'), children: [
      if (p == null) ...[
        Text(t('أين تُكتب الدرجات؟', 'Where should the marks go?'), style: appText(14, w: FontWeight.w700, c: c.textDark)),
        const SizedBox(height: AppSpace.xs),
        Wrap(spacing: AppSpace.xxs, runSpacing: AppSpace.xxs, children: [
          for (final x in widget.columns)
            AppChoiceChip(key: ValueKey('result.lab.${x.key}'), label: '${x.label} (${omrLtr(omrNum(x.max))})', selected: _pick == x.key, onTap: () => setState(() => _pick = x.key)),
          AppChoiceChip(key: const ValueKey('result.lab.new'), label: t('عمود جديد', 'New column'), icon: Icons.add_rounded, selected: _isNew, onTap: () => setState(() => _pick = _newKey)),
        ]),
        if (_isNew) ...[
          const SizedBox(height: AppSpace.sm),
          AppField(controller: _label, label: t('اسم العمود', 'Column name')),
          const SizedBox(height: AppSpace.xs),
          AppField(controller: _max, label: t('الدرجة العظمى', 'Full mark'), keyboard: const TextInputType.numberWithOptions(decimal: true), ltr: true),
        ],
      ] else
        ResultLabDiff(preview: p),
      if (_error != null) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: _error!),
      ],
      const SizedBox(height: AppSpace.md),
      if (p == null)
        AppPrimaryButton(key: const ValueKey('result.lab.preview'), label: t('معاينة التغييرات', 'Preview the changes'), icon: Icons.visibility_outlined, busy: _busy, onPressed: _busy ? null : _previewNow)
      else ...[
        AppPrimaryButton(
          key: const ValueKey('result.lab.apply'),
          label: p.changes.isEmpty ? t('لا يوجد ما يُكتب', 'Nothing to write') : t('كتابة ${p.changes.length} درجة', 'Write ${p.changes.length} marks'),
          icon: Icons.check_rounded,
          busy: _busy,
          onPressed: _busy || p.changes.isEmpty ? null : _apply,
        ),
        TextButton(onPressed: _busy ? null : () => setState(() => _preview = null), child: Text(t('اختيار عمود آخر', 'Choose another column'))),
      ],
    ]);
  }
}

/// What the file held: matched, unmatched, invalid.
class ResultDegreeSummary extends StatelessWidget {
  const ResultDegreeSummary({super.key, required this.preview});
  final DegreePreviewData preview;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = preview;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        _Count(t('تطابقت', 'Matched'), p.matched, color: c.success),
        if (p.unmatched.isNotEmpty) _Count(t('بلا طالب', 'No student found'), p.unmatched.length, color: c.warning),
        if (p.invalid.isNotEmpty) _Count(t('غير صالحة', 'Not valid'), p.invalid.length, color: c.danger),
      ]),
      const SizedBox(height: AppSpace.sm),
      for (final x in [
        ...p.unmatched.take(5).map((u) => t('الصف ${u.row}: «${u.value}» لا يطابق طالبًا', 'Row ${u.row}: "${u.value}" matches no student')),
        ...p.invalid.take(5).map((u) => t('الصف ${u.row}: ${degreeReasonText(u.reason)}', 'Row ${u.row}: ${degreeReasonText(u.reason)}')),
      ])
        Padding(padding: const EdgeInsets.only(bottom: AppSpace.xxs), child: Text(x, style: appText(12.5, c: c.textMedium))),
    ]);
  }
}

/// Opens the import sheet; true when totals were saved.
Future<bool> showResultImportSheet(BuildContext context, {required int examId, required String title, ResultsHubApi? api}) async =>
    await showAppSheet<bool>(context, (_) => _ImportSheet(examId: examId, title: title, api: api ?? ResultsHubApi())) ?? false;

class _ImportSheet extends StatefulWidget {
  const _ImportSheet({required this.examId, required this.title, required this.api});
  final int examId;
  final String title;
  final ResultsHubApi api;

  @override
  State<_ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends State<_ImportSheet> {
  String? _name;
  Uint8List? _bytes;
  DegreePreviewData? _p;
  String? _match, _degree, _error;
  final _max = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _max.dispose();
    super.dispose();
  }

  Future<void> _template() async {
    try {
      final b = await widget.api.degreesTemplate(widget.examId);
      await p8SaveBytes(b, 'degrees_${widget.examId}.xlsx', mime: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    } catch (_) {
      if (mounted) setState(() => _error = t('تعذّر تنزيل النموذج', 'The template could not be downloaded'));
    }
  }

  Future<void> _pick() async {
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['xlsx']);
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
    _name = f.name;
    _bytes = bytes;
    _match = _degree = null;
    await _preview();
  }

  Future<void> _preview() async {
    final bytes = _bytes, name = _name;
    if (bytes == null || name == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await widget.api.degreesPreview(widget.examId, fileName: name, bytes: bytes, matchColumn: _match, degreeColumn: _degree);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!r.ok) {
        _error = resultErrorText(r);
        return;
      }
      final p = DegreePreviewData.fromJson(r.map);
      _p = p;
      _match = p.matchColumn;
      _degree = p.degreeColumn;
      if (p.maxScore != null) _max.text = omrNum(p.maxScore);
    });
  }

  Future<void> _commit() async {
    final key = _p?.importKey;
    final max = double.tryParse(_max.text.trim().replaceAll(',', '.'));
    if (key == null) return;
    if (max == null || max <= 0) {
      setState(() => _error = t('اكتب الدرجة العظمى', 'Enter the full mark'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await widget.api.degreesCommit(widget.examId, key, max);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      setState(() => _error = resultErrorText(r));
      return;
    }
    showAppNotice(t('حُفظت ${(r.map['written'] as num?)?.toInt() ?? 0} درجة', '${(r.map['written'] as num?)?.toInt() ?? 0} totals saved'));
    Navigator.of(context).pop(true);
  }

  Widget _columnPicker(String label, String? value, ValueChanged<String?> onChanged) => AppDropdown<String>(
        value: value,
        decoration: InputDecoration(labelText: label),
        items: [for (final x in _p!.columns) DropdownMenuItem(value: x, child: Text(x, maxLines: 1, overflow: TextOverflow.ellipsis))],
        onChanged: (v) {
          onChanged(v);
          _preview();
        },
      );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = _p;
    return AppSheetContent(title: t('استيراد الدرجات من Excel', 'Import totals from Excel'), children: [
      Text(t('ارفع ملف Excel فيه اسم الطالب أو رقمه ودرجته. ستراجع ما تطابق قبل الحفظ.', 'Upload an Excel file with each student\'s name or number and their total. You check what matched before anything is saved.'), style: appText(13, c: c.textMedium, h: 1.5)),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(key: const ValueKey('result.import.template'), onPressed: _template, icon: const Icon(Icons.download_rounded, size: 18), label: Text(t('تنزيل نموذج بأسماء الطلاب', 'Download a template with the students'))),
      ),
      OutlinedButton.icon(key: const ValueKey('result.import.pick'), onPressed: _busy ? null : _pick, icon: const Icon(Icons.upload_file_rounded, size: 18), label: Text(_name ?? t('اختيار الملف', 'Choose the file'))),
      if (_busy && p == null) ...[const SizedBox(height: AppSpace.sm), const AppListSkeleton(items: 2, withAvatar: false, padding: EdgeInsets.zero)],
      if (p != null) ...[
        const SizedBox(height: AppSpace.sm),
        if (p.needsColumns || p.columns.length > 2) ...[
          _columnPicker(t('عمود الطالب', 'Student column'), _match, (v) => _match = v),
          const SizedBox(height: AppSpace.xs),
          _columnPicker(t('عمود الدرجة', 'Degree column'), _degree, (v) => _degree = v),
          const SizedBox(height: AppSpace.sm),
        ],
        if (!p.needsColumns) ...[
          ResultDegreeSummary(preview: p),
          const SizedBox(height: AppSpace.xs),
          AppField(controller: _max, label: t('الدرجة العظمى', 'Full mark'), keyboard: const TextInputType.numberWithOptions(decimal: true), ltr: true),
        ] else
          AppBanner(icon: Icons.help_outline_rounded, color: c.warning, text: t('حدّد عمود الطالب وعمود الدرجة', 'Choose the student column and the degree column')),
      ],
      if (_error != null) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: _error!),
      ],
      if (p?.importKey != null && p!.matched > 0) ...[
        const SizedBox(height: AppSpace.md),
        AppPrimaryButton(key: const ValueKey('result.import.commit'), label: t('حفظ ${p.matched} درجة', 'Save ${p.matched} totals'), icon: Icons.check_rounded, busy: _busy, onPressed: _busy ? null : _commit),
      ],
    ]);
  }
}
