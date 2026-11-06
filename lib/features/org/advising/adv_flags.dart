// lib/features/org/advising/adv_flags.dart — a student's flags in the 360 (docs/advising/PHASE4.md "Flags", #6 #7 #24):
// one card per flag (category, priority, state, note, review date, accommodations, the outcome once closed), the
// add / edit sheet (category, priority, note, review date, the category's accommodations), the status sheet (only the
// states the lifecycle allows next; an outcome is required to resolve) and the history.
//
//   AdvFlagCard        one flag                          AdvFlagsPane       the flags block of the 360
//   AdvFlagForm        the add / edit sheet's content    AdvFlagStatusForm  the status sheet's content
//   AdvFlagHistoryList the history (newest first)
//   showAdvFlagSheet / showAdvFlagStatusSheet / showAdvFlagHistorySheet   the sheets that call AdvApi
// Everything but the three sheet functions takes plain values (test/ui/adv_case_layout_test.dart).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t;
import '../org_page_kit.dart' show OrgSegmented;
import '../org_v3.dart' show orgCall;
import 'adv_api.dart';
import 'adv_case_parts.dart';
import 'adv_models.dart';
import 'adv_parts.dart';

/// The flags block's filter: `open` · `closed` · `all`.
const advFlagViews = ['open', 'closed', 'all'];

String advFlagViewLabel(String v) => switch (v) {
      'closed' => t('المغلقة', 'Closed'),
      'all' => t('الكل', 'All'),
      _ => t('المفتوحة', 'Open'),
    };

class AdvFlagCard extends StatelessWidget {
  const AdvFlagCard({super.key, required this.flag, this.onStatus, this.onEdit, this.onHistory, this.onAlerts});
  final AdvFlag flag;

  /// null: the action is not offered (not the owner, nothing allowed next).
  final VoidCallback? onStatus, onEdit, onHistory;

  /// Phase 6: a rule flag's early-warning alerts (shown for `source: rule` only).
  final VoidCallback? onAlerts;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final f = flag;
    final col = advPriorityColor(context, f.priority);
    final meta = [
      if (f.createdAt != null) t('فُتح ${advDate(f.createdAt)}', 'Opened ${advDate(f.createdAt)}'),
      if (f.reopenedAt != null && !f.closed) t('أُعيد فتحه ${advDate(f.reopenedAt)}', 'Reopened ${advDate(f.reopenedAt)}'),
      if (f.source == 'rule') t('من الإنذار المبكر', 'by early warning') else if (f.createdBy != null) t('بواسطة ${f.createdBy!.shown}', 'by ${f.createdBy!.shown}'),
      if (f.owner != null && f.owner!.userId != f.createdBy?.userId) t('المتابِع: ${f.owner!.shown}', 'Owner: ${f.owner!.shown}'),
    ].join(' · ');
    final review = f.reviewDueAt;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpace.sm),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ExcludeSemantics(
              child: Container(
                width: AppTouch.min - AppSpace.xs,
                height: AppTouch.min - AppSpace.xs,
                decoration: BoxDecoration(color: col.withValues(alpha: 0.12), borderRadius: AppRadius.chipAll),
                child: Icon(f.category.sensitive ? Icons.lock_rounded : Icons.flag_rounded, size: AppIconSize.md, color: appInk(context, col)),
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Semantics(
                  header: true,
                  child: Text(f.category.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: AppSpace.xxs),
                Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
                  AdvPriorityPill(priority: f.priority),
                  AdvFlagStatusPill(status: f.status),
                  if (f.category.sensitive) AppBadgePill(t('حساس', 'Sensitive'), color: c.textMedium, icon: Icons.lock_outline_rounded),
                  if (f.escalatedAt != null && !f.closed) AppBadgePill(t('صُعّد للمديرين', 'Escalated'), color: c.danger, icon: Icons.trending_up_rounded),
                ]),
              ]),
            ),
          ]),
          if (f.note != null) ...[
            const SizedBox(height: AppSpace.xs),
            AdvTypedText(f.note!, maxLines: 6),
          ],
          if (f.accommodations.isNotEmpty) ...[
            const SizedBox(height: AppSpace.xs),
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
              for (final a in f.accommodations) AppBadgePill(f.category.accommodationLabel(a), color: c.primary, icon: Icons.accessible_rounded),
            ]),
          ],
          if (f.closed && f.outcomeNote != null) ...[
            const SizedBox(height: AppSpace.xs),
            Container(
              padding: const EdgeInsets.all(AppSpace.xs),
              decoration: BoxDecoration(color: c.success.withValues(alpha: 0.07), borderRadius: AppRadius.chipAll),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t('النتيجة', 'Outcome'), style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600)),
                AdvTypedText(f.outcomeNote!, maxLines: 4),
              ]),
            ),
          ],
          const SizedBox(height: AppSpace.xs),
          if (meta.isNotEmpty) Text(meta, style: AppType.meta(context), maxLines: 2, overflow: TextOverflow.ellipsis),
          if (!f.closed && review != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xxs),
              child: Row(children: [
                ExcludeSemantics(child: Icon(Icons.event_rounded, size: AppIconSize.sm, color: f.overdue ? appInk(context, c.danger) : c.textMedium)),
                const SizedBox(width: AppSpace.xxs),
                Expanded(
                  child: Text(
                    f.overdue ? t('فات موعد المراجعة: ${advDate(review)}', 'Review was due ${advDate(review)}') : t('المراجعة قبل ${advDate(review)}', 'Review by ${advDate(review)}'),
                    style: AppType.meta(context).copyWith(color: f.overdue ? appInk(context, c.danger) : null, fontWeight: f.overdue ? FontWeight.w600 : null),
                  ),
                ),
              ]),
            ),
          if (f.closed && f.resolvedInHours != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xxs),
              child: Text(_took(f.resolvedInHours!), style: AppType.meta(context)),
            ),
          if (onStatus != null || onEdit != null || onHistory != null || (onAlerts != null && f.source == 'rule')) ...[
            const SizedBox(height: AppSpace.xxs),
            Wrap(spacing: AppSpace.xxs, children: [
              if (onStatus != null) _Action(icon: Icons.published_with_changes_rounded, label: f.closed ? t('إعادة فتح', 'Reopen') : t('تغيير الحالة', 'Change status'), onTap: onStatus!),
              if (onEdit != null) _Action(icon: Icons.edit_outlined, label: t('تعديل', 'Edit'), onTap: onEdit!),
              if (onHistory != null) _Action(icon: Icons.history_rounded, label: t('السجل', 'History'), onTap: onHistory!),
              if (onAlerts != null && f.source == 'rule') _Action(icon: Icons.radar_rounded, label: t('تنبيهات القواعد', 'Rule alerts'), onTap: onAlerts!),
            ]),
          ],
        ]),
      ),
    );
  }

  static String _took(int hours) {
    if (hours < 24) return t('عولج خلال $hours ساعة', 'Dealt with in $hours h');
    final d = (hours / 24).round();
    return t('عولج خلال $d يوم', 'Dealt with in $d days');
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TextButton.icon(
        style: TextButton.styleFrom(minimumSize: const Size(0, AppTouch.min), padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs)),
        onPressed: onTap,
        icon: Icon(icon, size: AppIconSize.sm),
        label: Text(label),
      );
}

/// The flags block of the 360: the filter, Add, the cards, the hidden count.
class AdvFlagsPane extends StatelessWidget {
  const AdvFlagsPane({
    super.key,
    required this.load,
    this.page,
    this.view = 'open',
    this.errorText,
    this.onView,
    this.onAdd,
    this.onRetry,
    this.canChange,
    this.canEdit,
    this.onStatus,
    this.onEdit,
    this.onHistory,
    this.onAlerts,
  });

  final AdvLoad load;
  final AdvPage<AdvFlag>? page;
  final String view;
  final String? errorText;
  final ValueChanged<String>? onView;

  /// null: the caller may not open flags.
  final VoidCallback? onAdd, onRetry;

  /// May the caller move / edit this flag (its owner or a director).
  final bool Function(AdvFlag)? canChange, canEdit;
  final ValueChanged<AdvFlag>? onStatus, onEdit, onHistory;

  /// Phase 6: a rule flag's alerts.
  final ValueChanged<AdvFlag>? onAlerts;

  @override
  Widget build(BuildContext context) {
    final p = page;
    final children = <Widget>[
      Row(children: [
        Expanded(
          child: onView == null
              ? const SizedBox.shrink()
              : OrgSegmented<String>(value: view, options: [for (final v in advFlagViews) (v, advFlagViewLabel(v))], onChanged: onView!),
        ),
        if (onAdd != null) ...[
          const SizedBox(width: AppSpace.xs),
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(minimumSize: const Size(0, AppTouch.min)),
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded, size: AppIconSize.md),
            label: Text(t('تنبيه', 'Flag')),
          ),
        ],
      ]),
      const SizedBox(height: AppSpace.sm),
    ];
    if (load != AdvLoad.ready || p == null) {
      children.add(AdvLoadState(state: load == AdvLoad.ready ? AdvLoad.loading : load, errorText: errorText, onRetry: onRetry, items: 2));
    } else {
      if (p.items.isEmpty) {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
          child: Column(children: [
            ExcludeSemantics(child: Icon(view == 'open' ? Icons.verified_rounded : Icons.flag_outlined, size: AppIconSize.xl, color: context.colors.textLight)),
            const SizedBox(height: AppSpace.xs),
            Text(
              switch (view) {
                'open' => t('لا تنبيهات مفتوحة', 'No open flags'),
                'closed' => t('لا تنبيهات مغلقة بعد', 'No closed flags yet'),
                _ => t('لا تنبيهات بعد', 'No flags yet'),
              },
              textAlign: TextAlign.center,
              style: AppType.body(context),
            ),
          ]),
        ));
      }
      for (final f in p.items) {
        final change = canChange?.call(f) ?? false;
        final next = f.nextStates(canReopen: change);
        // the server's allowed_next decides when it is sent; else my own rights do
        final may = f.allowedNext != null ? next.isNotEmpty : change && next.isNotEmpty;
        children.add(AdvFlagCard(
          flag: f,
          onStatus: onStatus == null || !may ? null : () => onStatus!(f),
          onEdit: onEdit == null || f.closed || !(canEdit?.call(f) ?? false) ? null : () => onEdit!(f),
          onHistory: onHistory == null ? null : () => onHistory!(f),
          onAlerts: onAlerts == null ? null : () => onAlerts!(f),
        ));
      }
      children.add(AdvRestrictedLine(count: p.restricted));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Add / edit
// ═════════════════════════════════════════════════════════════════════════════

class AdvFlagForm extends StatelessWidget {
  const AdvFlagForm({
    super.key,
    required this.categories,
    required this.draft,
    required this.note,
    this.editing = false,
    this.busy = false,
    this.error,
    this.onCategory,
    this.onPriority,
    this.onPickDate,
    this.onClearDate,
    this.onAccommodation,
    this.onSubmit,
  });

  /// The active categories (the flag's own stays listed while editing).
  final List<AdvCategory> categories;
  final AdvFlagDraft draft;
  final TextEditingController note;
  final bool editing, busy;
  final String? error;
  final ValueChanged<AdvCategory>? onCategory;
  final ValueChanged<String>? onPriority, onAccommodation;
  final VoidCallback? onPickDate, onClearDate, onSubmit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cat = categories.where((x) => x.id == draft.categoryId).firstOrNull;
    final err = error;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      AdvFieldLabel(t('التصنيف', 'Category')),
      if (categories.isEmpty)
        Text(t('لا توجد تصنيفات مفعّلة — يضيفها مدير الإرشاد.', 'There are no active categories — the advising director adds them.'), style: AppType.body(context))
      else
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final x in categories)
            AppChoiceChip(
              label: x.name,
              icon: x.sensitive ? Icons.lock_outline_rounded : null,
              selected: x.id == draft.categoryId,
              onTap: busy || onCategory == null ? () {} : () => onCategory!(x),
            ),
        ]),
      if (cat != null && cat.sensitive) ...[
        const SizedBox(height: AppSpace.xs),
        AppBanner(
          icon: Icons.lock_outline_rounded,
          text: t('تصنيف حساس: لا يراه إلا أنت والمرشد الأساسي ومديرو الإرشاد، وكل قراءة له مسجّلة.',
              'A sensitive category: only you, the primary advisor and the advising directors see it, and every read is recorded.'),
        ),
      ],
      const SizedBox(height: AppSpace.md),
      AdvFieldLabel(t('الأولوية', 'Priority')),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final p in advPriorities)
          AppChoiceChip(
            label: advPriorityLabel(p),
            icon: p == 'urgent' ? Icons.priority_high_rounded : null,
            selected: p == draft.priority,
            onTap: busy || onPriority == null ? () {} : () => onPriority!(p),
          ),
      ]),
      if (draft.priority == 'urgent' && !editing) ...[
        const SizedBox(height: AppSpace.xs),
        AppBanner(
          icon: Icons.notifications_active_outlined,
          color: c.danger,
          text: t('يُبلَّغ مرشدو الطالب ومديرو الإرشاد فوراً.', 'The student\'s advisors and the advising directors are notified at once.'),
        ),
      ],
      const SizedBox(height: AppSpace.md),
      AdvTypedField(controller: note, label: t('ما الذي لاحظته؟', 'What did you notice?'), hint: t('حقائق قصيرة تساعد من يتابع', 'Short facts that help whoever follows up'), maxLength: advNoteMaxLength, enabled: !busy),
      const SizedBox(height: AppSpace.sm),
      AdvPersonField(
        label: t('موعد المراجعة', 'Review by'),
        name: draft.reviewDueAt == null ? null : advDate(draft.reviewDueAt),
        placeholder: t('بلا موعد', 'No date'),
        icon: Icons.event_rounded,
        avatar: false,
        onPick: busy ? null : onPickDate,
        onClear: busy ? null : onClearDate,
      ),
      if (cat != null && cat.accommodations.isNotEmpty) ...[
        const SizedBox(height: AppSpace.md),
        AdvFieldLabel(t('التسهيلات الموصى بها', 'Recommended accommodations'), hint: t('ما يحتاجه الطالب من المؤسسة', 'What the student needs from the organization')),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final a in cat.accommodations)
            AppChoiceChip(
              label: a.label,
              icon: draft.accommodations.contains(a.key) ? Icons.check_rounded : Icons.add_rounded,
              selected: draft.accommodations.contains(a.key),
              onTap: busy || onAccommodation == null ? () {} : () => onAccommodation!(a.key),
            ),
        ]),
      ],
      if (err != null) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: err),
      ],
      const SizedBox(height: AppSpace.md),
      AppPrimaryButton(
        icon: editing ? Icons.check_rounded : Icons.flag_rounded,
        label: editing ? t('حفظ', 'Save') : t('فتح التنبيه', 'Open the flag'),
        busy: busy,
        onPressed: draft.categoryId == null ? null : onSubmit,
      ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Status
// ═════════════════════════════════════════════════════════════════════════════

class AdvFlagStatusForm extends StatelessWidget {
  const AdvFlagStatusForm({
    super.key,
    required this.flag,
    required this.outcome,
    this.chosen,
    this.canReopen = true,
    this.busy = false,
    this.error,
    this.onChoose,
    this.onSubmit,
  });

  final AdvFlag flag;
  final TextEditingController outcome;
  final String? chosen;
  final bool canReopen, busy;
  final String? error;
  final ValueChanged<String>? onChoose;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final next = flag.nextStates(canReopen: canReopen);
    final ch = chosen;
    final err = error;
    final needsOutcome = ch == 'resolved';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(t('الآن:', 'Now:'), style: AppType.meta(context)),
        AdvFlagStatusPill(status: flag.status),
      ]),
      const SizedBox(height: AppSpace.sm),
      for (final s in next)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: Semantics(
            button: true,
            selected: s == ch,
            inMutuallyExclusiveGroup: true,
            child: Material(
              color: s == ch ? c.primary.withValues(alpha: 0.06) : c.cardBg,
              borderRadius: AppRadius.cardAll,
              child: InkWell(
                borderRadius: AppRadius.cardAll,
                onTap: busy || onChoose == null ? null : () => onChoose!(s),
                child: Container(
                  constraints: const BoxConstraints(minHeight: AppTouch.primary),
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
                  decoration: BoxDecoration(
                    borderRadius: AppRadius.cardAll,
                    border: Border.all(color: s == ch ? c.primary : c.divider, width: s == ch ? AppBorder.strong : AppBorder.hairline),
                  ),
                  child: Row(children: [
                    ExcludeSemantics(child: Icon(Icons.circle, size: AppIconSize.xs, color: advFlagStatusColor(context, s))),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text(advFlagStatusLabel(s), style: AppType.row(context).copyWith(fontWeight: FontWeight.w600)),
                        Text(advFlagStatusHint(s), style: AppType.meta(context)),
                      ]),
                    ),
                    ExcludeSemantics(
                      child: Icon(s == ch ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, size: AppIconSize.md, color: s == ch ? c.primary : c.textLight),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      if (ch == 'resolved' || ch == 'dismissed') ...[
        const SizedBox(height: AppSpace.xs),
        AdvTypedField(
          controller: outcome,
          label: needsOutcome ? t('النتيجة (مطلوبة)', 'Outcome (required)') : t('السبب (اختياري)', 'Why (optional)'),
          hint: needsOutcome ? t('ماذا حدث، وما الذي اتُّفق عليه', 'What happened and what was agreed') : null,
          minLines: 2,
          maxLength: advNoteMaxLength,
          enabled: !busy,
        ),
      ],
      if (err != null) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: err),
      ],
      const SizedBox(height: AppSpace.md),
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: outcome,
        builder: (context, v, _) => AppPrimaryButton(
          icon: Icons.check_rounded,
          label: t('تطبيق', 'Apply'),
          busy: busy,
          onPressed: ch == null || (needsOutcome && v.text.trim().isEmpty) ? null : onSubmit,
        ),
      ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  History
// ═════════════════════════════════════════════════════════════════════════════

class AdvFlagHistoryList extends StatelessWidget {
  const AdvFlagHistoryList({super.key, required this.entries});

  /// null: loading.
  final List<AdvFlagEvent>? entries;

  @override
  Widget build(BuildContext context) {
    final list = entries;
    if (list == null) return const AppListSkeleton(items: 3, withAvatar: false, padding: EdgeInsets.zero);
    if (list.isEmpty) return Text(t('لا سجل بعد.', 'No history yet.'), style: AppType.body(context));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < list.length; i++)
        AdvRailRow(
          last: i == list.length - 1,
          color: i == 0 ? context.colors.primary : null,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(list[i].text, style: AppType.row(context)),
            Text([if (list[i].at != null) AppTime.dateTime(list[i].at!), ?list[i].actor].join(' · '), style: AppType.meta(context)),
            if (list[i].outcome != null) ...[const SizedBox(height: AppSpace.xxs), AdvTypedText(list[i].outcome!, maxLines: 4)],
          ]),
        ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Sheets
// ═════════════════════════════════════════════════════════════════════════════

Future<DateTime?> _pickReviewDate(BuildContext context, DateTime? initial) {
  final now = DateTime.now();
  final first = DateTime(now.year, now.month, now.day);
  final init = initial == null || initial.isBefore(first) ? first.add(const Duration(days: 7)) : initial.toLocal();
  return showDatePicker(context: context, initialDate: init, firstDate: first, lastDate: DateTime(now.year + 2));
}

/// Opens (no [flag]) or edits a flag of [memberId]; returns the saved flag.
Future<AdvFlag?> showAdvFlagSheet(BuildContext context, AdvApi api, {required int memberId, required List<AdvCategory> categories, AdvFlag? flag}) {
  final note = TextEditingController(text: flag?.note ?? '');
  var draft = flag == null ? const AdvFlagDraft() : AdvFlagDraft.of(flag);
  final cats = [for (final c in categories) if (c.active || c.id == flag?.category.id) c];
  var busy = false;
  String? error;
  return showAppSheet<AdvFlag>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        Future<void> submit() async {
          final body = draft.copyWith(note: note.text);
          final why = body.error(category: cats.where((c) => c.id == body.categoryId).firstOrNull);
          if (why != null) {
            set(() => error = why);
            return;
          }
          set(() {
            busy = true;
            error = null;
          });
          final r = await orgCall(() => flag == null ? api.addFlag(memberId, body) : api.saveFlag(flag.id, body), quiet: true);
          if (!ctx.mounted) return;
          if (!r.ok) {
            set(() {
              busy = false;
              error = advErrorText(r.error!);
            });
            return;
          }
          showAppNotice(flag == null ? t('فُتح التنبيه', 'Flag opened') : t('حُفظ التنبيه', 'Flag saved'));
          Navigator.pop(ctx, r.data as AdvFlag);
        }

        Future<void> pickDate() async {
          final d = await _pickReviewDate(ctx, draft.reviewDueAt);
          if (d != null) set(() => draft = draft.copyWith(reviewDueAt: () => DateTime(d.year, d.month, d.day, 12)));
        }

        return AppSheetContent(
          title: flag == null ? t('تنبيه جديد', 'New flag') : t('تعديل التنبيه', 'Edit the flag'),
          children: [
            AdvFlagForm(
              categories: cats,
              draft: draft,
              note: note,
              editing: flag != null,
              busy: busy,
              error: error,
              onCategory: (c) => set(() => draft = draft.withCategory(c)),
              onPriority: (p) => set(() => draft = draft.copyWith(priority: p)),
              onPickDate: pickDate,
              onClearDate: () => set(() => draft = draft.copyWith(reviewDueAt: () => null)),
              onAccommodation: (k) => set(() => draft = draft.toggleAccommodation(k)),
              onSubmit: submit,
            ),
          ],
        );
      }));
}

/// Moves [flag] to one of the states allowed next; returns the updated flag.
/// [onStale]: someone else moved the flag first (409 `advising_bad_transition`); the sheet closes and the caller
/// reloads the flag.
Future<AdvFlag?> showAdvFlagStatusSheet(BuildContext context, AdvApi api, AdvFlag flag, {bool canReopen = true, VoidCallback? onStale}) {
  final outcome = TextEditingController(text: flag.outcomeNote ?? '');
  final next = flag.nextStates(canReopen: canReopen);
  String? chosen = next.length == 1 ? next.first : null;
  var busy = false;
  String? error;
  return showAppSheet<AdvFlag>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        Future<void> submit() async {
          final s = chosen;
          if (s == null) return;
          set(() {
            busy = true;
            error = null;
          });
          final keepOutcome = s == 'resolved' || s == 'dismissed';
          final r = await orgCall(() => api.setFlagStatus(flag.id, s, outcomeNote: keepOutcome ? outcome.text : null), quiet: true);
          if (!ctx.mounted) return;
          if (r.code == 'advising_bad_transition') {
            // someone moved it first: close, say so, and let the page read the flag again
            showAppNotice(advErrorText(r.error!), error: true);
            Navigator.pop(ctx);
            onStale?.call();
            return;
          }
          if (!r.ok) {
            set(() {
              busy = false;
              error = advErrorText(r.error!);
            });
            return;
          }
          showAppNotice(t('التنبيه الآن: ${advFlagStatusLabel(s)}', 'The flag is now: ${advFlagStatusLabel(s)}'));
          Navigator.pop(ctx, r.data as AdvFlag);
        }

        return AppSheetContent(
          title: flag.closed ? t('إعادة فتح التنبيه', 'Reopen the flag') : t('حالة التنبيه', 'Flag status'),
          children: [
            Text(flag.category.name, style: AppType.section(ctx)),
            const SizedBox(height: AppSpace.xs),
            AdvFlagStatusForm(
              flag: flag,
              outcome: outcome,
              chosen: chosen,
              canReopen: canReopen,
              busy: busy,
              error: error,
              onChoose: (s) => set(() => chosen = s),
              onSubmit: submit,
            ),
          ],
        );
      }));
}

Future<void> showAdvFlagHistorySheet(BuildContext context, AdvApi api, AdvFlag flag) {
  List<AdvFlagEvent>? rows;
  String? error;
  var started = false;
  return showAppSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        if (!started) {
          started = true;
          orgCall(() => api.flagHistory(flag.id), quiet: true).then((r) {
            if (!ctx.mounted) return;
            set(() {
              rows = r.ok ? r.data as List<AdvFlagEvent> : const [];
              error = r.ok ? null : advErrorText(r.error!);
            });
          });
        }
        return AppSheetContent(
          title: t('سجل التنبيه', 'Flag history'),
          children: [
            Text(flag.category.name, style: AppType.section(ctx)),
            const SizedBox(height: AppSpace.sm),
            if (error != null) AppBanner(icon: Icons.error_outline_rounded, color: ctx.colors.danger, text: error!) else AdvFlagHistoryList(entries: rows),
          ],
        );
      }));
}
