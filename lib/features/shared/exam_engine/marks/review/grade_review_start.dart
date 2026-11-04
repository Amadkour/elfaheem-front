// The start of a grade review / mark import: mode · exam (optional) · template · gradebook column · rounding. Plain
// values in, one callback out (`onStart`), so the harness can pump it; the entry function that shows it in a sheet and
// creates the session is in grade_review_entry.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_tokens.dart';

import '../../../../admin/admin_common.dart' show t;
import '../mark_sessions_api.dart';

/// Opens the template list in picking mode (agent FB1's `openMarkTemplates(context, orgId:, pick: true)`), answering
/// the chosen template or null. Injected, so this folder does not import the templates screens.
typedef MarkTemplatePicker = Future<({int id, String name, double totalMax})?> Function(BuildContext context);

/// A gradebook column that can receive marks: its key, its title and its maximum.
class GradeColumn {
  const GradeColumn(this.key, this.label, this.max);
  final String key, label;
  final double max;
}

class GradeStudent {
  const GradeStudent(this.id, this.name);
  final int id;
  final String name;
}

class GradeExam {
  const GradeExam(this.id, this.title);
  final int id;
  final String title;
}

class GradeStartParams {
  const GradeStartParams({required this.mode, required this.templateId, required this.templateName, required this.paperMax, required this.column, this.examId, this.roundingStep});
  final MarkMode mode;
  final int templateId;
  final String templateName;
  final double paperMax;
  final GradeColumn column;
  final int? examId;
  final double? roundingStep;
}

/// "Marks will be converted /50 → /20" when the paper's total and the column's maximum differ.
String gradeConversionText(double paperMax, double columnMax) =>
    t('ستُحوَّل الدرجات من ${markNumberText(paperMax)} إلى ${markNumberText(columnMax)}', 'Marks will be converted /${markNumberText(paperMax)} → /${markNumberText(columnMax)}');

class GradeStartForm extends StatefulWidget {
  const GradeStartForm({
    super.key,
    required this.columns,
    required this.pickTemplate,
    required this.onStart,
    this.exams = const [],
    this.earlier = const [],
    this.onOpenEarlier,
    this.initialMode = MarkMode.review,
  });

  final List<GradeColumn> columns;
  final List<GradeExam> exams;
  final MarkTemplatePicker pickTemplate;

  /// Creates the session; the form shows a busy button until it answers.
  final Future<void> Function(GradeStartParams p) onStart;

  /// Open sessions of this course, to continue instead of starting again.
  final List<MarkSession> earlier;
  final void Function(MarkSession s)? onOpenEarlier;
  final MarkMode initialMode;

  @override
  State<GradeStartForm> createState() => _GradeStartFormState();
}

class _GradeStartFormState extends State<GradeStartForm> {
  late MarkMode _mode = widget.initialMode;
  int? _examId;
  ({int id, String name, double totalMax})? _tpl;
  GradeColumn? _column;
  double _step = 0.5;
  bool _busy = false;

  bool get _converts => _tpl != null && _column != null && (_tpl!.totalMax - _column!.max).abs() > 0.0001;

  Future<void> _pickTemplate() async {
    final r = await widget.pickTemplate(context);
    if (r != null && mounted) setState(() => _tpl = r);
  }

  Future<void> _start() async {
    final tpl = _tpl, col = _column;
    if (tpl == null || col == null || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.onStart(GradeStartParams(
        mode: _mode,
        templateId: tpl.id,
        templateName: tpl.name,
        paperMax: tpl.totalMax,
        column: col,
        examId: _examId,
        roundingStep: _converts ? _step : null,
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final body = appText(13, c: c.textMedium, h: 1.4);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(
        _mode == MarkMode.review
            ? t('صوّر الأوراق وسنقارن درجاتها بما هو مسجّل في الدفتر. لا تتغير أي درجة إلا بقرارك.',
                'Photograph the papers and we compare their marks with what the gradebook holds. No grade changes unless you decide.')
            : t('صوّر الأوراق لاستيراد درجاتها إلى الدفتر. تُكتب كل درجة بعد موافقتك.',
                'Photograph the papers to bring their marks into the gradebook. Each mark is written only after you approve it.'),
        style: body,
      ),
      const SizedBox(height: AppSpace.sm),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        AppChoiceChip(
          key: const ValueKey('gr.mode.review'),
          label: t('مراجعة الدرجات المسجّلة', 'Review recorded grades'),
          icon: Icons.fact_check_outlined,
          selected: _mode == MarkMode.review,
          onTap: () => setState(() => _mode = MarkMode.review),
        ),
        AppChoiceChip(
          key: const ValueKey('gr.mode.import'),
          label: t('استيراد الدرجات من الورق', 'Import marks from paper'),
          icon: Icons.document_scanner_outlined,
          selected: _mode == MarkMode.import,
          onTap: () => setState(() => _mode = MarkMode.import),
        ),
      ]),
      if (widget.exams.isNotEmpty) ...[
        const SizedBox(height: AppSpace.sm),
        AppPicker<int>(
          label: t('الاختبار (اختياري)', 'Exam (optional)'),
          value: _examId,
          options: {for (final e in widget.exams) e.id: e.title},
          allowNone: true,
          noneLabel: t('بدون اختبار', 'No exam'),
          onChanged: (v) => setState(() => _examId = v),
        ),
      ],
      const SizedBox(height: AppSpace.sm),
      AppCard(
        key: const ValueKey('gr.template'),
        onTap: _pickTemplate,
        padding: const EdgeInsets.all(AppSpace.sm),
        child: Row(children: [
          Icon(Icons.grid_on_rounded, color: c.primary),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('نموذج الورقة', 'Paper template'), style: appText(12, c: c.textLight)),
              Text(_tpl == null ? t('اختر نموذجًا', 'Choose a template') : '${_tpl!.name} · ${t('من', 'out of')} ${markNumberText(_tpl!.totalMax)}',
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w700, c: c.textDark)),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: c.textLight),
        ]),
      ),
      const SizedBox(height: AppSpace.sm),
      if (widget.columns.isEmpty)
        AppBanner(icon: Icons.info_outline_rounded, text: t('لا يوجد عمود رقمي في الدفتر لاستقبال الدرجات. أضف عمودًا أولًا.', 'The gradebook has no numeric column to receive marks. Add one first.'), color: c.warning)
      else
        AppPicker<String>(
          label: t('عمود الدفتر', 'Gradebook column'),
          value: _column?.key,
          options: {for (final col in widget.columns) col.key: '${col.label} · ${t('من', 'out of')} ${markNumberText(col.max)}'},
          onChanged: (k) => setState(() => _column = widget.columns.where((e) => e.key == k).firstOrNull),
        ),
      if (_converts) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(key: const ValueKey('gr.convert'), icon: Icons.swap_horiz_rounded, text: gradeConversionText(_tpl!.totalMax, _column!.max), color: c.primary),
        const SizedBox(height: AppSpace.xs),
        Text(t('تقريب الدرجة إلى أقرب', 'Round the mark to the nearest'), style: body),
        const SizedBox(height: AppSpace.xxs),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final s in const [0.25, 0.5, 1.0])
            AppChoiceChip(key: ValueKey('gr.step.$s'), label: markNumberText(s), selected: _step == s, onTap: () => setState(() => _step = s)),
        ]),
      ],
      const SizedBox(height: AppSpace.md),
      AppPrimaryButton(
        label: t('ابدأ التصوير', 'Start scanning'),
        icon: Icons.photo_camera_outlined,
        busy: _busy,
        onPressed: (_tpl != null && _column != null) ? _start : null,
      ),
      if (widget.earlier.isNotEmpty) ...[
        const SizedBox(height: AppSpace.md),
        AppSectionTitle(t('جلسات سابقة مفتوحة', 'Earlier open sessions')),
        for (final s in widget.earlier)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xs),
            child: AppCard(
              onTap: widget.onOpenEarlier == null ? null : () => widget.onOpenEarlier!(s),
              padding: const EdgeInsets.all(AppSpace.sm),
              child: Row(children: [
                Icon(s.mode == MarkMode.review ? Icons.fact_check_outlined : Icons.document_scanner_outlined, color: c.primary),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text(
                    '${s.mode == MarkMode.review ? t('مراجعة', 'Review') : t('استيراد', 'Import')} · ${s.columnKey} · ${s.counts.read}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: appText(13.5, w: FontWeight.w600, c: c.textDark),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: c.textLight),
              ]),
            ),
          ),
      ],
    ]);
  }
}
