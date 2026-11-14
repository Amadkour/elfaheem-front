// lib/features/org/advising/adv_plan.dart — support plans (docs/advising/PHASE7.md "Support plans", #14): a plan is a
// title, a measure (a term GPA / CGPA to reach, an absence to stay under, or a measure in words), a follow-up date,
// whether the student sees it, and items — a goal, the action, who does it (the student · the advisor · someone
// else, e.g. "Student Affairs office") and by when. Draft → active → completed (with an outcome note and the
// measure's result from the stats) | cancelled; a finished plan can be made active again. The student ticks their
// own items (adv_support_hub.dart); staff tick any.
//
//   AdvPlanCard  AdvPlanItemRow  AdvPlanForm (+ AdvPlanItemFields)  AdvPlanStatusForm   (plain values)
//   showAdvPlanEditor · showAdvPlanStatusSheet                                          (through AdvSupportApi)
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t;
import '../org_v3.dart' show orgCall;
import 'adv_case_parts.dart' show AdvTypedField, AdvTypedText;
import 'adv_models.dart' show advNoteMaxLength;
import 'adv_parts.dart' show AdvFieldLabel, AdvPersonField, advDate;
import 'adv_support_api.dart';
import 'adv_support_models.dart';
import 'adv_support_parts.dart';
import 'adv_support_texts.dart';

Color advPlanStatusColor(BuildContext context, String status) {
  final c = context.colors;
  return switch (status) {
    'active' => c.primary,
    'completed' => c.success,
    'cancelled' => c.textMedium,
    _ => c.warning,
  };
}

IconData advPlanStatusIcon(String status) => switch (status) {
      'active' => Icons.play_circle_outline_rounded,
      'completed' => Icons.check_circle_rounded,
      'cancelled' => Icons.block_rounded,
      _ => Icons.edit_note_rounded,
    };

// ═════════════════════════════════════════════════════════════════════════════
//  The card
// ═════════════════════════════════════════════════════════════════════════════

class AdvPlanItemRow extends StatelessWidget {
  const AdvPlanItemRow({super.key, required this.item, this.onTick, this.busy = false, this.mine = false});
  final AdvSupportPlanItem item;

  /// Ticks it done / open (null: the caller may not).
  final VoidCallback? onTick;
  final bool busy;

  /// The student's own view: "You" instead of "Student".
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final it = item;
    final done = it.done;
    final col = done ? c.success : (it.dropped ? c.textLight : (it.overdue ? c.danger : c.textMedium));
    final owner = mine && it.owner == 'student' ? t('أنت', 'You') : it.ownerText;
    final when = [
      owner,
      if (done && it.doneAt != null) t('تم ${advDate(it.doneAt)}', 'done ${advDate(it.doneAt)}') else if (it.dueAt != null) (it.overdue && !done ? t('فات موعده ${advDate(it.dueAt)}', 'was due ${advDate(it.dueAt)}') : t('قبل ${advDate(it.dueAt)}', 'by ${advDate(it.dueAt)}')),
      if (it.dropped) advPlanItemStatusLabel('dropped'),
    ].join(' · ');
    final tick = onTick;
    return Semantics(
      checked: done,
      button: tick != null,
      label: '${it.goal}. $when',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: AppRadius.chipAll,
        onTap: busy ? null : tick,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTouch.min),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs, horizontal: AppSpace.xxs),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: AppTouch.min - AppSpace.sm,
                height: AppTouch.min - AppSpace.sm,
                child: Center(
                  child: busy
                      ? const SizedBox.square(dimension: AppIconSize.md, child: CircularProgressIndicator(strokeWidth: AppBorder.focus))
                      : Icon(
                          done ? Icons.check_circle_rounded : (it.dropped ? Icons.remove_circle_outline_rounded : Icons.radio_button_unchecked_rounded),
                          size: AppIconSize.lg,
                          color: tick == null && !done ? c.textLight : appInk(context, done ? c.success : c.primary),
                        ),
                ),
              ),
              const SizedBox(width: AppSpace.xs),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: AppSpace.xxs),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    AdvTypedText(
                      it.goal.isEmpty ? '—' : it.goal,
                      style: AppType.row(context).copyWith(
                        fontWeight: FontWeight.w600,
                        color: done || it.dropped ? c.textMedium : c.textDark,
                        decoration: done || it.dropped ? TextDecoration.lineThrough : null,
                        decorationColor: c.textLight,
                      ),
                    ),
                    if (it.action.isNotEmpty) AdvTypedText(it.action, maxLines: 4, style: AppType.meta(context).copyWith(color: c.textMedium)),
                    Text(when, style: AppType.meta(context).copyWith(color: it.overdue && !done ? appInk(context, col) : null, fontWeight: it.overdue && !done ? FontWeight.w600 : null)),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class AdvPlanCard extends StatelessWidget {
  const AdvPlanCard({
    super.key,
    required this.plan,
    this.student = false,
    this.canTick,
    this.ticking = const {},
    this.onTick,
    this.onEdit,
    this.onStatus,
    this.onDelete,
    this.onReview,
  });

  final AdvSupportPlan plan;

  /// The student's own view: no visibility badge, "You" for their items.
  final bool student;
  final bool Function(AdvSupportPlanItem)? canTick;

  /// Item ids being ticked right now.
  final Set<int> ticking;
  final ValueChanged<AdvSupportPlanItem>? onTick;
  final VoidCallback? onEdit, onStatus, onDelete;

  /// The follow-up review (offered while [AdvSupportPlan.reviewDue]).
  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = plan;
    final col = advPlanStatusColor(context, p.status);
    final m = p.measure;
    final res = p.result;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: AppCard(
        padding: AppSpace.card,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ExcludeSemantics(
              child: Container(
                width: AppTouch.min - AppSpace.xs,
                height: AppTouch.min - AppSpace.xs,
                decoration: BoxDecoration(color: col.withValues(alpha: 0.12), borderRadius: AppRadius.chipAll),
                child: Icon(Icons.route_rounded, size: AppIconSize.md, color: appInk(context, col)),
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Semantics(header: true, child: AdvTypedText(p.shownTitle, maxLines: 2, style: AppType.row(context).copyWith(fontWeight: FontWeight.w700, color: c.textDark))),
                const SizedBox(height: AppSpace.xxs),
                Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
                  AppBadgePill(advPlanStatusLabel(p.status), color: col, icon: advPlanStatusIcon(p.status)),
                  if (!student)
                    p.studentVisible
                        ? AppBadgePill(t('يراها الطالب', 'Shown to the student'), color: c.primary, icon: Icons.visibility_outlined)
                        : AppBadgePill(t('للفريق فقط', 'Team only'), color: c.textMedium, icon: Icons.visibility_off_outlined),
                ]),
              ]),
            ),
          ]),
          if (p.total > 0) ...[
            const SizedBox(height: AppSpace.sm),
            Row(children: [
              Expanded(child: AppProgressBar(value: p.done.toDouble(), max: p.total.toDouble(), color: p.done == p.total ? c.success : c.primary, height: 6)),
              const SizedBox(width: AppSpace.sm),
              Text(t('${p.done} من ${p.total}', '${p.done} of ${p.total}'), style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600)),
            ]),
          ],
          if (m != null || p.followUpAt != null) ...[
            const SizedBox(height: AppSpace.sm),
            if (m != null) AppInfoRow(Icons.flag_outlined, t('الهدف: ${m.summary}', 'Target: ${m.summary}')),
            if (!p.finished && p.measureNow?.value != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.xxs),
                child: Row(children: [
                  ExcludeSemantics(child: Icon(Icons.insights_rounded, size: AppIconSize.sm, color: p.measureNow!.met == true ? appInk(context, c.success) : appInk(context, c.warning))),
                  const SizedBox(width: AppSpace.xs),
                  Expanded(
                    child: Text(
                      [
                        t('الآن: ${_value(m?.kind, p.measureNow!.value!)}', 'Now: ${_value(m?.kind, p.measureNow!.value!)}'),
                        if (p.measureNow!.met == true) t('الهدف متحقق', 'on target') else if (p.measureNow!.met == false) t('لم يبلغ الهدف بعد', 'not on target yet'),
                      ].join(' · '),
                      style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: p.measureNow!.met == true ? appInk(context, c.success) : appInk(context, c.warning)),
                    ),
                  ),
                ]),
              ),
            if (res != null && (res.value != null || res.met != null))
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.xxs),
                child: Row(children: [
                  ExcludeSemantics(
                    child: Icon(res.met == true ? Icons.verified_rounded : (res.met == false ? Icons.error_outline_rounded : Icons.insights_rounded),
                        size: AppIconSize.sm, color: res.met == true ? appInk(context, c.success) : (res.met == false ? appInk(context, c.danger) : c.textMedium)),
                  ),
                  const SizedBox(width: AppSpace.xs),
                  Expanded(
                    child: Text(
                      [
                        if (res.value != null) t('النتيجة: ${_value(m?.kind, res.value!)}', 'Result: ${_value(m?.kind, res.value!)}'),
                        if (res.met == true) t('تحقق الهدف', 'target met') else if (res.met == false) t('لم يتحقق الهدف', 'target not met'),
                      ].join(' · '),
                      style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: res.met == true ? appInk(context, c.success) : (res.met == false ? appInk(context, c.danger) : null)),
                    ),
                  ),
                ]),
              ),
            if (p.followUpAt != null && !p.finished && !p.reviewDue) AppInfoRow(Icons.event_repeat_rounded, t('المتابعة ${advDate(p.followUpAt)}', 'Follow-up on ${advDate(p.followUpAt)}')),
            if (p.reviewedAt != null && !p.reviewDue && !student) AppInfoRow(Icons.task_alt_rounded, t('آخر مراجعة ${advDate(p.reviewedAt)}', 'Last reviewed ${advDate(p.reviewedAt)}')),
          ],
          if (p.reviewDue && !p.finished && !student) ...[
            const SizedBox(height: AppSpace.sm),
            AppBanner(
              icon: Icons.event_repeat_rounded,
              color: c.warning,
              text: t('حان موعد مراجعة الخطة${p.reviewDueAt == null ? '' : ' (${advDate(p.reviewDueAt)})'} — راجع التقدم وحدد المتابعة القادمة.',
                  'This plan is due for review${p.reviewDueAt == null ? '' : ' (${advDate(p.reviewDueAt)})'} — check the progress and set the next follow-up.'),
            ),
          ],
          if (p.items.isNotEmpty) ...[
            Divider(height: AppSpace.lg, color: c.divider),
            for (final it in p.items)
              AdvPlanItemRow(
                item: it,
                mine: student,
                busy: it.id != null && ticking.contains(it.id),
                onTick: onTick != null && it.id != null && !it.dropped && p.active && (canTick?.call(it) ?? false) ? () => onTick!(it) : null,
              ),
          ],
          if (p.finished && p.outcomeNote != null) ...[
            const SizedBox(height: AppSpace.xs),
            Container(
              padding: const EdgeInsets.all(AppSpace.xs),
              decoration: BoxDecoration(color: col.withValues(alpha: 0.07), borderRadius: AppRadius.chipAll),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t('الخلاصة', 'Outcome'), style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600)),
                AdvTypedText(p.outcomeNote!, maxLines: 6),
              ]),
            ),
          ],
          if (!student && (p.createdBy != null || p.createdAt != null)) ...[
            const SizedBox(height: AppSpace.xs),
            Text(
              [if (p.createdBy != null) t('وضعها ${advIso(p.createdBy!.shown)}', 'By ${advIso(p.createdBy!.shown)}'), if (p.createdAt != null) advDate(p.createdAt)].join(' · '),
              style: AppType.meta(context),
            ),
          ],
          if (onEdit != null || onStatus != null || onDelete != null || (onReview != null && p.reviewDue))
            Wrap(spacing: AppSpace.xxs, children: [
              if (onReview != null && p.reviewDue && !p.finished) AdvSmallAction(icon: Icons.fact_check_outlined, label: t('مراجعة الخطة', 'Review the plan'), onTap: onReview),
              if (onStatus != null) AdvSmallAction(icon: Icons.published_with_changes_rounded, label: p.status == 'draft' ? t('تفعيل أو إلغاء', 'Activate or cancel') : t('تغيير الحالة', 'Change status'), onTap: onStatus),
              if (onEdit != null) AdvSmallAction(icon: Icons.edit_outlined, label: t('تعديل', 'Edit'), onTap: onEdit),
              if (onDelete != null) AdvSmallAction(icon: Icons.delete_outline_rounded, label: t('حذف', 'Delete'), danger: true, onTap: onDelete),
            ]),
        ]),
      ),
    );
  }

  static String _value(String? kind, double v) => kind == 'absence_max' ? '${v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1)}%' : v.toStringAsFixed(2);
}

// ═════════════════════════════════════════════════════════════════════════════
//  The editor
// ═════════════════════════════════════════════════════════════════════════════

/// One item row of the editor: its text fields and choices (the sheet owns the controllers).
class AdvPlanItemFields {
  AdvPlanItemFields({this.id, String goal = '', String action = '', String ownerNote = '', this.owner = 'student', this.dueAt, this.status = 'open'})
      : goal = TextEditingController(text: goal),
        action = TextEditingController(text: action),
        ownerNote = TextEditingController(text: ownerNote);

  factory AdvPlanItemFields.of(AdvSupportPlanItem i) => AdvPlanItemFields(id: i.id, goal: i.goal, action: i.action, ownerNote: i.ownerNote ?? '', owner: i.owner, dueAt: i.dueAt, status: i.status);

  final int? id;
  final TextEditingController goal, action, ownerNote;
  String owner;
  DateTime? dueAt;

  /// Kept as it is: the PUT replaces the items, a done item stays done.
  final String status;

  AdvSupportPlanItem get item => AdvSupportPlanItem(id: id, goal: goal.text, action: action.text, owner: owner, ownerNote: ownerNote.text, dueAt: dueAt, status: status);
}

class AdvPlanForm extends StatelessWidget {
  const AdvPlanForm({
    super.key,
    required this.title,
    required this.draft,
    required this.target,
    required this.measureText,
    required this.items,
    this.editing = false,
    this.busy = false,
    this.error,
    this.onMeasureKind,
    this.onPickFollowUp,
    this.onClearFollowUp,
    this.onVisible,
    this.onOwner,
    this.onPickDue,
    this.onClearDue,
    this.onAddItem,
    this.onRemoveItem,
    this.onSaveDraft,
    this.onSave,
  });

  final TextEditingController title, target, measureText;
  final AdvPlanDraft draft;
  final List<AdvPlanItemFields> items;
  final bool editing, busy;
  final String? error;

  /// null: no measure.
  final ValueChanged<String?>? onMeasureKind;
  final VoidCallback? onPickFollowUp, onClearFollowUp, onAddItem, onSaveDraft, onSave;
  final ValueChanged<bool>? onVisible;
  final void Function(AdvPlanItemFields, String)? onOwner;
  final ValueChanged<AdvPlanItemFields>? onPickDue, onClearDue, onRemoveItem;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final kind = draft.measure?.kind;
    final off = busy;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      AdvTypedField(controller: title, label: t('عنوان الخطة', 'Plan title'), hint: t('مثل: رفع المعدل هذا الفصل', 'e.g. Raise the GPA this term'), minLines: 1, maxLines: 2, maxLength: 200, enabled: !off),
      const SizedBox(height: AppSpace.md),
      AdvFieldLabel(t('مقياس النجاح', 'How success is measured'), hint: t('تُسجَّل نتيجته من سجل الطالب عند إكمال الخطة', 'Its result is read from the student\'s record when the plan is completed')),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        AppChoiceChip(label: t('بلا مقياس', 'None'), selected: kind == null, onTap: off || onMeasureKind == null ? () {} : () => onMeasureKind!(null)),
        for (final k in advPlanMeasureKinds) AppChoiceChip(label: advPlanMeasureLabel(k), selected: kind == k, onTap: off || onMeasureKind == null ? () {} : () => onMeasureKind!(k)),
      ]),
      if (kind != null) ...[
        const SizedBox(height: AppSpace.sm),
        if (kind == 'custom')
          AdvTypedField(controller: measureText, label: t('صف المقياس', 'Describe the measure'), minLines: 1, maxLines: 3, maxLength: 300, enabled: !off)
        else
          TextField(
            controller: target,
            enabled: !off,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: advMeasureLowerIsBetter(kind) ? t('لا يتجاوز (٪)', 'At most (%)') : t('لا يقل عن', 'At least'),
              hintText: advMeasureLowerIsBetter(kind) ? '15' : '2.50',
              prefixIcon: Icon(advMeasureLowerIsBetter(kind) ? Icons.south_rounded : Icons.north_rounded, size: AppIconSize.md),
            ),
          ),
      ],
      const SizedBox(height: AppSpace.md),
      AdvPersonField(
        label: t('موعد المتابعة', 'Follow-up date'),
        name: draft.followUpAt == null ? null : advDate(draft.followUpAt),
        placeholder: t('بلا موعد', 'No date'),
        icon: Icons.event_repeat_rounded,
        avatar: false,
        onPick: off ? null : onPickFollowUp,
        onClear: off ? null : onClearFollowUp,
      ),
      const SizedBox(height: AppSpace.xs),
      AppSwitchTile(
        icon: Icons.visibility_outlined,
        title: t('يراها الطالب', 'Shown to the student'),
        subtitle: t('عندما تكون نشطة أو مكتملة، ويؤشر على بنوده بنفسه', 'When active or completed; they tick their own items'),
        value: draft.studentVisible,
        onChanged: off || onVisible == null ? null : onVisible!,
      ),
      const SizedBox(height: AppSpace.sm),
      AdvFieldLabel(t('البنود', 'Items'), hint: t('هدف، وما يُفعل لتحقيقه، ومن يفعله، ومتى', 'A goal, what is done to reach it, who does it, by when')),
      for (var i = 0; i < items.length; i++) _ItemEditor(
        index: i,
        fields: items[i],
        busy: off,
        onOwner: onOwner,
        onPickDue: onPickDue,
        onClearDue: onClearDue,
        onRemove: onRemoveItem,
      ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          style: TextButton.styleFrom(minimumSize: const Size(0, AppTouch.min)),
          onPressed: off || onAddItem == null || items.length >= AdvPlanDraft.maxItems ? null : onAddItem,
          icon: const Icon(Icons.add_rounded, size: AppIconSize.md),
          label: Text(t('إضافة بند', 'Add an item')),
        ),
      ),
      if (error != null) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!),
      ],
      const SizedBox(height: AppSpace.md),
      AppPrimaryButton(
        icon: editing ? Icons.check_rounded : Icons.play_arrow_rounded,
        label: editing ? t('حفظ', 'Save') : t('حفظ وتفعيل', 'Save and activate'),
        busy: busy,
        onPressed: onSave,
      ),
      if (!editing && onSaveDraft != null) ...[
        const SizedBox(height: AppSpace.xs),
        Center(
          child: TextButton.icon(
            style: TextButton.styleFrom(minimumSize: const Size(0, AppTouch.min)),
            onPressed: off ? null : onSaveDraft,
            icon: const Icon(Icons.edit_note_rounded, size: AppIconSize.md),
            label: Text(t('حفظ كمسودة', 'Save as a draft')),
          ),
        ),
      ],
    ]);
  }
}

class _ItemEditor extends StatelessWidget {
  const _ItemEditor({required this.index, required this.fields, required this.busy, this.onOwner, this.onPickDue, this.onClearDue, this.onRemove});
  final int index;
  final AdvPlanItemFields fields;
  final bool busy;
  final void Function(AdvPlanItemFields, String)? onOwner;
  final ValueChanged<AdvPlanItemFields>? onPickDue, onClearDue, onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final f = fields;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(color: c.inputBg.withValues(alpha: 0.5), borderRadius: AppRadius.cardAll, border: Border.all(color: c.divider)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(t('البند ${index + 1}', 'Item ${index + 1}'), style: AppType.bodyStrong(context))),
          if (onRemove != null)
            IconButton(
              tooltip: t('حذف البند', 'Remove the item'),
              constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
              onPressed: busy ? null : () => onRemove!(f),
              icon: Icon(Icons.delete_outline_rounded, size: AppIconSize.md, color: c.textMedium),
            ),
        ]),
        AdvTypedField(controller: f.goal, label: t('الهدف', 'Goal'), minLines: 1, maxLines: 3, maxLength: 500, enabled: !busy),
        const SizedBox(height: AppSpace.xs),
        AdvTypedField(controller: f.action, label: t('الإجراء', 'Action'), minLines: 1, maxLines: 4, maxLength: 2000, enabled: !busy),
        const SizedBox(height: AppSpace.xs),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(t('المسؤول:', 'Who:'), style: AppType.meta(context)),
          for (final o in advPlanItemOwners)
            AppChoiceChip(label: advPlanOwnerLabel(o), selected: f.owner == o, onTap: busy || onOwner == null ? () {} : () => onOwner!(f, o)),
        ]),
        if (f.owner == 'other') ...[
          const SizedBox(height: AppSpace.xs),
          AdvTypedField(controller: f.ownerNote, label: t('من؟', 'Who is it?'), hint: t('مثل: مكتب شؤون الطلاب', 'e.g. Student Affairs office'), minLines: 1, maxLines: 1, maxLength: 120, enabled: !busy),
        ],
        const SizedBox(height: AppSpace.xs),
        AdvPersonField(
          label: t('الموعد', 'Due'),
          name: f.dueAt == null ? null : advDate(f.dueAt),
          placeholder: t('بلا موعد', 'No date'),
          icon: Icons.event_rounded,
          avatar: false,
          onPick: busy || onPickDue == null ? null : () => onPickDue!(f),
          onClear: busy || onClearDue == null ? null : () => onClearDue!(f),
        ),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Status
// ═════════════════════════════════════════════════════════════════════════════

class AdvPlanStatusForm extends StatelessWidget {
  const AdvPlanStatusForm({super.key, required this.plan, required this.outcome, this.chosen, this.busy = false, this.error, this.onChoose, this.onSubmit});
  final AdvSupportPlan plan;
  final TextEditingController outcome;
  final String? chosen;
  final bool busy;
  final String? error;
  final ValueChanged<String>? onChoose;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final next = advPlanNext(plan.status);
    final ch = chosen;
    final needs = ch == 'completed';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Wrap(spacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(t('الآن:', 'Now:'), style: AppType.meta(context)),
        AppBadgePill(advPlanStatusLabel(plan.status), color: advPlanStatusColor(context, plan.status), icon: advPlanStatusIcon(plan.status)),
      ]),
      const SizedBox(height: AppSpace.sm),
      for (final s in next)
        AdvChoiceCard(
          title: s == 'active' && plan.status != 'draft' ? t('إعادة تفعيل', 'Make active again') : advPlanStatusLabel(s),
          hint: advPlanStatusHint(s),
          selected: s == ch,
          color: advPlanStatusColor(context, s),
          icon: advPlanStatusIcon(s),
          onTap: busy || onChoose == null ? null : () => onChoose!(s),
        ),
      if (ch == 'completed' || ch == 'cancelled') ...[
        const SizedBox(height: AppSpace.xs),
        AdvTypedField(
          controller: outcome,
          label: needs ? t('الخلاصة (مطلوبة)', 'Outcome (required)') : t('السبب (اختياري)', 'Why (optional)'),
          hint: needs ? t('ما الذي تحقق، وما الذي يلي', 'What was achieved, and what comes next') : null,
          minLines: 2,
          maxLength: advNoteMaxLength,
          enabled: !busy,
        ),
      ],
      if (error != null) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!),
      ],
      const SizedBox(height: AppSpace.md),
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: outcome,
        builder: (context, v, _) => AppPrimaryButton(icon: Icons.check_rounded, label: t('تطبيق', 'Apply'), busy: busy, onPressed: ch == null || (needs && v.text.trim().isEmpty) ? null : onSubmit),
      ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Sheets
// ═════════════════════════════════════════════════════════════════════════════

/// A new plan for [memberId] (or edits [plan]); returns the saved plan.
Future<AdvSupportPlan?> showAdvPlanEditor(BuildContext context, AdvSupportApi api, {required int memberId, AdvSupportPlan? plan, int? flagId, int? requestId}) {
  final title = TextEditingController(text: plan?.title ?? '');
  final m = plan?.measure;
  final target = TextEditingController(text: m?.target == null ? '' : (m!.kind == 'absence_max' ? '${m.target!.round()}' : m.target!.toStringAsFixed(2)));
  final measureText = TextEditingController(text: m?.kind == 'custom' ? (m?.text ?? '') : '');
  var draft = plan == null ? AdvPlanDraft(flagId: flagId, requestId: requestId) : AdvPlanDraft.of(plan);
  final items = plan == null ? [AdvPlanItemFields()] : [for (final i in plan.items) AdvPlanItemFields.of(i)];
  var busy = false;
  String? error;
  return showAppSheet<AdvSupportPlan>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        AdvPlanDraft current({String? status}) {
          final kind = draft.measure?.kind;
          final measure = kind == null ? null : AdvPlanMeasure(kind: kind, target: kind == 'custom' ? null : double.tryParse(target.text.trim()), text: kind == 'custom' ? measureText.text : null);
          return draft.copyWith(
            title: title.text,
            status: status,
            measure: () => measure,
            items: [for (final f in items) if (f.goal.text.trim().isNotEmpty || f.action.text.trim().isNotEmpty) f.item],
          );
        }

        Future<void> save({required String status}) async {
          final d = current(status: status);
          final why = d.error;
          if (why != null) {
            set(() => error = why);
            return;
          }
          set(() {
            busy = true;
            error = null;
          });
          final p = plan;
          final r = await orgCall(() => p == null ? api.createPlan(memberId, d) : api.savePlan(p.id, d, version: p.version), quiet: true);
          if (!ctx.mounted) return;
          if (!r.ok) {
            if (advSupportStaleCodes.contains(r.code)) {
              showAppNotice(advSupportErrorText(r.error!), error: true);
              Navigator.pop(ctx);
              return;
            }
            set(() {
              busy = false;
              error = advSupportErrorText(r.error!);
            });
            return;
          }
          showAppNotice(p != null
              ? t('حُفظت الخطة', 'Plan saved')
              : (status == 'active' ? t('فُعّلت خطة الدعم', 'Support plan activated') : t('حُفظت الخطة كمسودة', 'Plan saved as a draft')));
          Navigator.pop(ctx, r.data as AdvSupportPlan);
        }

        Future<void> pick(DateTime? initial, void Function(DateTime) apply) async {
          final d = await pickAdvDate(ctx, initial, days: 14);
          if (d != null) set(() => apply(DateTime(d.year, d.month, d.day, 12)));
        }

        return AppSheetContent(
          title: plan == null ? t('خطة دعم جديدة', 'New support plan') : t('تعديل الخطة', 'Edit the plan'),
          children: [
            AdvPlanForm(
              title: title,
              draft: draft,
              target: target,
              measureText: measureText,
              items: items,
              editing: plan != null,
              busy: busy,
              error: error,
              onMeasureKind: (k) => set(() => draft = draft.copyWith(measure: () => k == null ? null : AdvPlanMeasure(kind: k))),
              onPickFollowUp: () => pick(draft.followUpAt, (d) => draft = draft.copyWith(followUpAt: () => d)),
              onClearFollowUp: () => set(() => draft = draft.copyWith(followUpAt: () => null)),
              onVisible: (v) => set(() => draft = draft.copyWith(studentVisible: v)),
              onOwner: (f, o) => set(() => f.owner = o),
              onPickDue: (f) => pick(f.dueAt, (d) => f.dueAt = d),
              onClearDue: (f) => set(() => f.dueAt = null),
              onAddItem: () => set(() => items.add(AdvPlanItemFields())),
              onRemoveItem: (f) => set(() => items.remove(f)),
              onSaveDraft: () => save(status: 'draft'),
              onSave: busy ? null : () => save(status: plan?.status ?? 'active'),
            ),
          ],
        );
      }));
}

/// Moves [plan] to a status its lifecycle allows next; returns the updated plan. [onStale]: someone moved it first.
Future<AdvSupportPlan?> showAdvPlanStatusSheet(BuildContext context, AdvSupportApi api, AdvSupportPlan plan, {VoidCallback? onStale}) {
  final outcome = TextEditingController(text: plan.outcomeNote ?? '');
  final next = advPlanNext(plan.status);
  String? chosen = next.length == 1 ? next.first : null;
  var busy = false;
  String? error;
  return showAppSheet<AdvSupportPlan>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        Future<void> submit() async {
          final s = chosen;
          if (s == null) return;
          set(() {
            busy = true;
            error = null;
          });
          final r = await orgCall(() => api.setPlanStatus(plan.id, s, outcomeNote: s == 'completed' || s == 'cancelled' ? outcome.text : null), quiet: true);
          if (!ctx.mounted) return;
          if (!r.ok && advSupportStaleCodes.contains(r.code)) {
            showAppNotice(advSupportErrorText(r.error!), error: true);
            Navigator.pop(ctx);
            onStale?.call();
            return;
          }
          if (!r.ok) {
            set(() {
              busy = false;
              error = advSupportErrorText(r.error!);
            });
            return;
          }
          showAppNotice(switch (s) {
            'active' => plan.status == 'draft' ? t('فُعّلت الخطة', 'Plan activated') : t('عادت الخطة نشطة', 'The plan is active again'),
            'completed' => t('اكتملت الخطة وسُجّلت نتيجتها', 'Plan completed and its result recorded'),
            _ => t('أُلغيت الخطة', 'Plan cancelled'),
          });
          Navigator.pop(ctx, r.data as AdvSupportPlan);
        }

        return AppSheetContent(
          title: t('حالة الخطة', 'Plan status'),
          children: [
            AdvTypedText(plan.shownTitle, style: AppType.section(ctx)),
            const SizedBox(height: AppSpace.xs),
            AdvPlanStatusForm(plan: plan, outcome: outcome, chosen: chosen, busy: busy, error: error, onChoose: (s) => set(() => chosen = s), onSubmit: submit),
          ],
        );
      }));
}

// ═════════════════════════════════════════════════════════════════════════════
//  Follow-up review
// ═════════════════════════════════════════════════════════════════════════════

/// The review the follow-up date asked for: how it is going, and when to look again.
class AdvPlanReviewForm extends StatelessWidget {
  const AdvPlanReviewForm({super.key, required this.plan, required this.note, this.next, this.busy = false, this.error, this.onPickNext, this.onClearNext, this.onSubmit});
  final AdvSupportPlan plan;
  final TextEditingController note;
  final DateTime? next;
  final bool busy;
  final String? error;
  final VoidCallback? onPickNext, onClearNext, onSubmit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = plan;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      AdvTypedText(p.shownTitle, style: AppType.section(context)),
      const SizedBox(height: AppSpace.xs),
      if (p.total > 0)
        Row(children: [
          Expanded(child: AppProgressBar(value: p.done.toDouble(), max: p.total.toDouble(), color: p.done == p.total ? c.success : c.primary, height: 6)),
          const SizedBox(width: AppSpace.sm),
          Text(t('${p.done} من ${p.total}', '${p.done} of ${p.total}'), style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600)),
        ]),
      if (p.measure != null) ...[
        const SizedBox(height: AppSpace.xs),
        AppInfoRow(Icons.flag_outlined, t('الهدف: ${p.measure!.summary}', 'Target: ${p.measure!.summary}')),
      ],
      const SizedBox(height: AppSpace.md),
      AdvTypedField(controller: note, label: t('ما الذي وجدته؟ (اختياري)', 'What did you find? (optional)'), minLines: 2, maxLength: 2000, enabled: !busy),
      const SizedBox(height: AppSpace.sm),
      AdvPersonField(
        label: t('المتابعة القادمة', 'Next follow-up'),
        name: next == null ? null : advDate(next),
        placeholder: t('بلا موعد', 'No date'),
        icon: Icons.event_repeat_rounded,
        avatar: false,
        onPick: busy ? null : onPickNext,
        onClear: busy ? null : onClearNext,
      ),
      if (error != null) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!),
      ],
      const SizedBox(height: AppSpace.md),
      AppPrimaryButton(icon: Icons.fact_check_rounded, label: t('تسجيل المراجعة', 'Record the review'), busy: busy, onPressed: onSubmit),
    ]);
  }
}

/// Records the follow-up review of [plan]; returns the updated plan.
Future<AdvSupportPlan?> showAdvPlanReviewSheet(BuildContext context, AdvSupportApi api, AdvSupportPlan plan) {
  final note = TextEditingController();
  final now = DateTime.now();
  DateTime? next = DateTime(now.year, now.month, now.day + 14, 12);
  var busy = false;
  String? error;
  return showAppSheet<AdvSupportPlan>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        Future<void> submit() async {
          set(() {
            busy = true;
            error = null;
          });
          final r = await orgCall(() => api.reviewPlan(plan.id, note: note.text, nextFollowUpAt: next), quiet: true);
          if (!ctx.mounted) return;
          if (!r.ok) {
            set(() {
              busy = false;
              error = advSupportErrorText(r.error!);
            });
            return;
          }
          final n = next;
          showAppNotice(n == null ? t('سُجّلت مراجعة الخطة', 'Plan review recorded') : t('سُجّلت المراجعة — المتابعة القادمة ${advDate(n.toUtc())}', 'Review recorded — next follow-up ${advDate(n.toUtc())}'));
          Navigator.pop(ctx, r.data as AdvSupportPlan);
        }

        return AppSheetContent(
          title: t('مراجعة الخطة', 'Review the plan'),
          children: [
            AdvPlanReviewForm(
              plan: plan,
              note: note,
              next: next,
              busy: busy,
              error: error,
              onPickNext: () async {
                final d = await pickAdvDate(ctx, next, first: DateTime(now.year, now.month, now.day + 1), days: 14);
                if (d != null) set(() => next = DateTime(d.year, d.month, d.day, 12));
              },
              onClearNext: () => set(() => next = null),
              onSubmit: submit,
            ),
          ],
        );
      }));
}
