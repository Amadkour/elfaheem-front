// "Get result" (Exam Hub, F5): writing the results to a Data Lab column the teacher chooses (contract 1.4: choose or create,
// preview, a plain before / after, confirm). [ResultLabDiff] takes plain values for the layout harness. Totals from Excel are
// the Hub's one import, `../hub_degrees_import_sheet.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../../../admin/admin_common.dart' show t;
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
    final done = countText(written, ar1: 'كُتبت درجة واحدة', ar2: 'كُتبت درجتان', arFew: 'كُتبت {n} درجات', arMany: 'كُتبت {n} درجة', en1: '1 mark written', en: '{n} marks written', ar0: 'لم تُكتب أي درجة', en0: 'No marks written');
    showAppNotice(skipped == 0 ? t('$done في «${p.label}»', '$done to "${p.label}"') : t('$done في «${p.label}»، وتعذّرت كتابة $skipped', '$done to "${p.label}", $skipped not written'));
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
          Padding(padding: const EdgeInsets.only(bottom: AppSpace.sm), child: AppNumberField(controller: _max, label: t('الدرجة العظمى', 'Full mark'), min: 0, decimals: 2)),
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
          label: p.changes.isEmpty ? t('لا يوجد ما يُكتب', 'Nothing to write') : countText(p.changes.length, ar1: 'كتابة درجة واحدة', ar2: 'كتابة درجتين', arFew: 'كتابة {n} درجات', arMany: 'كتابة {n} درجة', en1: 'Write 1 mark', en: 'Write {n} marks'),
          icon: Icons.check_rounded,
          busy: _busy,
          onPressed: _busy || p.changes.isEmpty ? null : _apply,
        ),
        TextButton(onPressed: _busy ? null : () => setState(() => _preview = null), child: Text(t('اختيار عمود آخر', 'Choose another column'))),
      ],
    ]);
  }
}
