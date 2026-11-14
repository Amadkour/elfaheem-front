// The editor's side panel (desktop) / bottom sheet (phone): the template's name, the problems in plain words, the
// selected box's form, the list of boxes and the sum rule. It reads the model and writes to it; it owns no state of
// the sheet itself.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_tokens.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/exams/marks/mark_templates_api.dart';
import 'package:flutter_education_app/features/exams/marks/templates/mark_canvas.dart' show fieldCaption;
import 'package:flutter_education_app/features/exams/marks/templates/mark_editor_model.dart';
import 'package:flutter_education_app/features/exams/marks/templates/mark_field_form.dart';
import 'package:flutter_education_app/features/exams/marks/templates/mark_template_common.dart';

class MarkEditorPanel extends StatelessWidget {
  const MarkEditorPanel({super.key, required this.model, required this.nameController, this.showForm = true, this.onNameChanged, this.padding = const EdgeInsets.all(AppSpace.md)});

  final MarkEditorModel model;
  final TextEditingController nameController;

  /// The selected box's form inside the panel (desktop); the phone opens it in its own sheet.
  final bool showForm;
  final VoidCallback? onNameChanged;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: model,
      builder: (context, _) {
        final sel = model.selected;
        return ListView(padding: padding, children: [
          AppField(controller: nameController, label: t('اسم القالب', 'Template name'), onChanged: (_) => onNameChanged?.call()),
          MarkIssuesBlock(model: model),
          if (showForm && sel != null) ...[
            AppSpace.gapXs,
            AppCard(
              child: MarkFieldForm(
                key: ValueKey('${sel.id}#${model.epoch}'),
                field: sel,
                issues: model.issuesOf(sel.id),
                onType: (ty) => model.setType(sel.id, ty),
                onChanged: (f, {coalesce}) => model.update(f, coalesce: coalesce),
                onDelete: () => model.delete(sel.id),
              ),
            ),
          ],
          AppSpace.gapMd,
          AppSectionTitle(t('المربعات (${model.fields.length})', 'Boxes (${model.fields.length})')),
          MarkFieldList(model: model),
          AppSpace.gapMd,
          AppSectionTitle(t('قاعدة المجموع', 'Sum rule')),
          MarkSumRuleCard(model: model),
        ]);
      },
    );
  }
}

/// Errors first, then warnings; "all good" when there are none. Tap a line to select the box it is about.
class MarkIssuesBlock extends StatelessWidget {
  const MarkIssuesBlock({super.key, required this.model});
  final MarkEditorModel model;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final issues = [...model.issues.where((i) => i.error), ...model.issues.where((i) => !i.error)];
    if (issues.isEmpty) {
      return AppBanner(icon: Icons.check_circle_outline_rounded, text: t('لا توجد مشاكل. القالب جاهز للحفظ.', 'No problems. The template is ready to save.'), color: c.success);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final i in issues)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: InkWell(
            borderRadius: AppRadius.cardAll,
            onTap: i.fieldIds.isEmpty ? null : () => model.select(i.fieldIds.first),
            child: AppBanner(icon: i.error ? Icons.error_outline_rounded : Icons.warning_amber_rounded, text: i.text, color: i.error ? c.danger : c.warning),
          ),
        ),
    ]);
  }
}

class MarkFieldList extends StatelessWidget {
  const MarkFieldList({super.key, required this.model});
  final MarkEditorModel model;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (model.fields.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
        child: Text(t('لا توجد مربعات. اسحب على الورقة لرسم مربع.', 'No boxes yet. Drag on the sheet to draw one.'), style: AppType.meta(context)),
      );
    }
    return Column(children: [
      for (final f in model.fields)
        Material(
          key: ValueKey('markbox.${f.id}'),
          color: f.id == model.selectedId ? c.lightPrimary : Colors.transparent,
          borderRadius: AppRadius.cardAll,
          child: InkWell(
            borderRadius: AppRadius.cardAll,
            onTap: () => model.select(f.id),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.min),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs),
                child: Row(children: [
                  Icon(fieldIcon(f.type), size: 20, color: fieldColor(context, f.type)),
                  AppSpace.gapXs,
                  Expanded(child: Text('${f.type.label} · ${fieldCaption(f)}', maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context))),
                  if (model.issuesOf(f.id).any((i) => i.error)) Icon(Icons.error_rounded, size: 18, color: c.danger),
                ]),
              ),
            ),
          ),
        ),
    ]);
  }
}

/// Which box is the total and which marks add up to it; warns when the maxima do not match.
class MarkSumRuleCard extends StatelessWidget {
  const MarkSumRuleCard({super.key, required this.model});
  final MarkEditorModel model;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final spec = model.spec;
    final totals = spec.fields.where((f) => f.type == FieldType.total).toList();
    final marks = spec.questionMarks.toList();
    if (totals.isEmpty) {
      return AppCard(child: Text(t('لا يوجد مربع مجموع. حدّد مربعًا كمجموع إن أردت أن يتحقق النظام من الجمع.', 'There is no total box. Mark one as the total if you want the system to check the addition.'), style: AppType.meta(context)));
    }
    final total = spec.field(spec.sumTotal);
    final parts = spec.effectiveParts;
    final sum = partsMaxSum(spec);
    final tm = total?.max ?? 0;
    final differs = total != null && parts.isNotEmpty && (sum - tm).abs() > 0.0001;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppDropdown<String?>(
          value: total?.id,
          decoration: InputDecoration(labelText: t('مربع المجموع', 'Total box')),
          items: [
            DropdownMenuItem<String?>(value: null, child: Text(t('بدون قاعدة', 'No rule'))),
            for (final f in totals) DropdownMenuItem<String?>(value: f.id, child: Text(fieldCaption(f), overflow: TextOverflow.ellipsis)),
          ],
          onChanged: model.setSumTotal,
        ),
        if (total != null) ...[
          AppSpace.gapSm,
          Text(t('الأجزاء التي تُجمع', 'The parts that add up'), style: AppType.meta(context)),
          AppSpace.gapXs,
          if (marks.isEmpty)
            Text(t('لا توجد مربعات درجات بعد.', 'There are no question marks yet.'), style: AppType.meta(context))
          else
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
              for (final f in marks)
                FilterChip(
                  label: Text(fieldCaption(f)),
                  selected: parts.contains(f.id),
                  onSelected: (_) => model.togglePart(f.id),
                ),
            ]),
          AppSpace.gapSm,
          Row(children: [
            Icon(differs ? Icons.warning_amber_rounded : Icons.check_circle_outline_rounded, size: 18, color: differs ? c.warning : c.success),
            AppSpace.gapXs,
            Expanded(
              child: Text(
                t('مجموع الدرجات العظمى للأجزاء = ${numText(sum)}، والدرجة العظمى للمجموع = ${numText(tm)}', 'Parts max sum = ${numText(sum)}, total max = ${numText(tm)}'),
                style: AppType.row(context).copyWith(color: differs ? c.warning : c.textDark),
              ),
            ),
          ]),
        ],
      ]),
    );
  }
}
