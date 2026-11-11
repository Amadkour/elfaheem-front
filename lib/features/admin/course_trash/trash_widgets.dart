// lib/features/admin/course_trash/trash_widgets.dart
//
// Presentational pieces of the "Deleted courses" console: plain values in, callbacks out, no provider and no
// network (so the layout harness can pump them).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../admin_common.dart' show t;
import 'trash_models.dart';

String _when(DateTime? d) => d == null ? '-' : AppTime.dateTime(d);

BoxDecoration _cardDeco(BuildContext context) {
  final c = context.colors;
  return BoxDecoration(color: c.cardBg, borderRadius: AppRadius.cardAll, border: Border.all(color: c.divider));
}

/// A small icon + text pair that never overflows.
class _Metric extends StatelessWidget {
  const _Metric(this.icon, this.text, {this.tone});
  final IconData icon;
  final String text;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final col = tone == null ? context.colors.textMedium : appInk(context, tone!);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 15, color: col),
      const SizedBox(width: AppSpace.xxs),
      Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: col))),
    ]);
  }
}

/// A labelled line of a card ("Reason", text ...), wrapping instead of overflowing.
class _Line extends StatelessWidget {
  const _Line(this.icon, this.text, {this.maxLines = 2});
  final IconData icon;
  final String text;
  final int maxLines;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: AppSpace.xxs),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 15, color: context.colors.textMedium),
          const SizedBox(width: AppSpace.xs),
          Expanded(child: Text(text, maxLines: maxLines, overflow: TextOverflow.ellipsis, style: AppType.meta(context))),
        ]),
      );
}

/// The course image, or its first letter on a tinted square.
class TrashAvatar extends StatelessWidget {
  const TrashAvatar({super.key, required this.name, this.imageUrl, this.size = 44});
  final String name;
  final String? imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final letter = name.trim().isEmpty ? '?' : String.fromCharCode(name.trim().runes.first);
    // a course without a cover keeps its subject's block tone (stable per name), the letter in the block's ink
    final tone = AppBlockColors.of(context, AppBlockTone.forKey(name));
    final fallback = Center(child: Text(letter, style: AppType.section(context).copyWith(color: tone.ink)));
    return ClipRRect(
      borderRadius: AppRadius.controlAll,
      child: Container(
        width: size,
        height: size,
        color: tone.surface,
        child: imageUrl == null
            ? fallback
            : Image.network(imageUrl!, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback),
      ),
    );
  }
}

/// "Legacy" chip: deleted before the trash existed.
class TrashLegacyChip extends StatelessWidget {
  const TrashLegacyChip({super.key});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: t('حُذف قبل وجود سلة المحذوفات: الاسترجاع يعيد الكورس فقط دون طلابه', 'Deleted before the trash existed: restoring brings back the course only, not its students'),
        child: AppBadgePill(t('قديم', 'Legacy'), color: context.colors.warning, icon: Icons.history_rounded),
      );
}

/// Students / paid / sessions / payments of a trashed course.
class TrashImpactStrip extends StatelessWidget {
  const TrashImpactStrip(this.item, {super.key});
  final TrashItem item;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Wrap(spacing: AppSpace.md, runSpacing: AppSpace.xs, children: [
      _Metric(Icons.group_outlined, countText(item.students, ar1: 'طالب', ar2: 'طالبان', arFew: '{n} طلاب', arMany: '{n} طالباً', en1: '{n} student', en: '{n} students')),
      _Metric(Icons.verified_outlined, t('${item.paidStudents} مدفوع', '${item.paidStudents} paid'), tone: item.paidStudents > 0 ? c.success : null),
      _Metric(Icons.play_lesson_outlined, t('${item.sessions} جلسة', '${item.sessions} sessions')),
      _Metric(Icons.payments_outlined, t('${item.payments} دفعة', '${item.payments} payments')),
    ]);
  }
}

/// A course in the trash: tap opens the detail.
class TrashCourseCard extends StatelessWidget {
  const TrashCourseCard({super.key, required this.item, required this.onTap});
  final TrashItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: AppRadius.cardAll,
        onTap: onTap,
        child: Ink(
          padding: AppSpace.card,
          decoration: _cardDeco(context),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TrashAvatar(name: item.name, imageUrl: item.imageUrl),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
                  if (item.teacher != null)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpace.xxs),
                      child: Text(item.teacher!.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                    ),
                ]),
              ),
              const SizedBox(width: AppSpace.xs),
              Icon(Icons.chevron_right_rounded, color: c.textMedium),
            ]),
            _Line(Icons.schedule_rounded, '${_when(item.deletedAt)} · ${trashPersonText(item.deletedBy)}'),
            if (item.reason != null) _Line(Icons.notes_rounded, item.reason!),
            const SizedBox(height: AppSpace.sm),
            TrashImpactStrip(item),
            if (item.legacy || item.wasPublished) ...[
              const SizedBox(height: AppSpace.sm),
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                if (item.wasPublished) AppBadgePill(t('كان منشوراً', 'Was published'), color: c.success),
                if (item.legacy) const TrashLegacyChip(),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}

/// A permanently deleted course (read-only row).
class TrashPurgedCard extends StatelessWidget {
  const TrashPurgedCard({super.key, required this.item});
  final PurgedItem item;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = item.summary;
    return Container(
      padding: AppSpace.card,
      decoration: _cardDeco(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TrashAvatar(name: item.name),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
              if (item.teacher != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpace.xxs),
                  child: Text(item.teacher!.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                ),
            ]),
          ),
        ]),
        const SizedBox(height: AppSpace.sm),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          item.erased
              ? AppBadgePill(t('مُسح بالكامل', 'Erased'), color: c.danger, icon: Icons.delete_forever_outlined)
              : AppBadgePill(t('محفوظ كسجل مالي', 'Kept as a financial record'), color: c.warning, icon: Icons.receipt_long_outlined),
        ]),
        _Line(Icons.delete_outline_rounded, t('حُذف: ${_when(item.deletedAt)} · ${trashPersonText(item.deletedBy)}', 'Deleted: ${_when(item.deletedAt)} · ${trashPersonText(item.deletedBy)}')),
        if (item.deleteReason != null) _Line(Icons.notes_rounded, item.deleteReason!),
        _Line(Icons.delete_forever_outlined, t('مسح نهائي: ${_when(item.purgedAt)} · ${trashPersonText(item.purgedBy)}', 'Permanently deleted: ${_when(item.purgedAt)} · ${trashPersonText(item.purgedBy)}')),
        if (item.purgeReason != null) _Line(Icons.notes_rounded, item.purgeReason!),
        const SizedBox(height: AppSpace.sm),
        _Metric(Icons.storage_rounded, t('${s.rowsRemoved} سجل مُسح', '${s.rowsRemoved} records removed')),
      ]),
    );
  }
}

/// A tiny "table: n" list that opens and closes.
class _CountList extends StatelessWidget {
  const _CountList(this.counts);
  final TrashCounts counts;

  @override
  Widget build(BuildContext context) {
    final e = counts.byTable.entries.where((x) => x.value > 0).toList();
    return Column(children: [
      for (final x in e)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
          child: Row(children: [
            Expanded(child: Text(trashTableLabel(x.key), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context))),
            Text('${x.value}', style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: context.colors.textDark)),
          ]),
        ),
    ]);
  }
}

/// What a permanent delete would do, in plain words, with the per-table list one tap away.
class TrashPurgePlanView extends StatefulWidget {
  const TrashPurgePlanView(this.plan, {super.key});
  final TrashPurgePlan plan;

  @override
  State<TrashPurgePlanView> createState() => _TrashPurgePlanViewState();
}

class _TrashPurgePlanViewState extends State<TrashPurgePlanView> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = widget.plan;
    final keptTotal = p.kept.total;
    final String text;
    final Color tone;
    final IconData icon;
    if (p.erased) {
      text = t('سيُمسح كل شيء: الكورس وكل محتواه، ولا يبقى منه أثر.', 'Everything is erased: the course and all of its content, leaving no trace.');
      tone = c.danger;
      icon = Icons.delete_forever_outlined;
    } else if (p.purged) {
      text = t('سيُمسح محتوى الكورس، وتبقى مدفوعاته وأرباحه وشهاداته كسجلات مالية.',
          "The course's content is erased; its payments, earnings and certificates are kept as financial records.");
      tone = c.warning;
      icon = Icons.receipt_long_outlined;
    } else {
      final why = p.blockedBy == null ? '' : ' (${p.blockedBy})';
      text = t('لا يمكن حذف هذا الكورس نهائياً الآن$why. أزل ما يمنع ذلك أولاً.', 'This course cannot be permanently deleted right now$why. Remove what blocks it first.');
      tone = c.danger;
      icon = Icons.block_rounded;
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AppBanner(icon: icon, text: text, color: tone),
      if (!p.blocked) ...[
        const SizedBox(height: AppSpace.sm),
        Text(t('${p.rowsRemoved} سجل سيُمسح', '${p.rowsRemoved} records will be removed'), style: AppType.row(context)),
        if (keptTotal > 0)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xxs),
            child: Text(t('$keptTotal سجل يبقى', '$keptTotal records are kept'), style: AppType.meta(context)),
          ),
        if (!p.removed.isEmpty || !p.kept.isEmpty || !p.detached.isEmpty)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => setState(() => _open = !_open),
              icon: Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded),
              label: Text(_open ? t('إخفاء التفاصيل', 'Hide details') : t('التفاصيل لكل جدول', 'Details per table')),
            ),
          ),
        if (_open) ...[
          if (!p.removed.isEmpty) ...[
            Text(t('يُمسح', 'Removed'), style: AppType.section(context)),
            _CountList(p.removed),
          ],
          if (!p.kept.isEmpty) ...[
            const SizedBox(height: AppSpace.xs),
            Text(t('يبقى', 'Kept'), style: AppType.section(context)),
            _CountList(p.kept),
          ],
          if (!p.detached.isEmpty) ...[
            const SizedBox(height: AppSpace.xs),
            Text(t('يُفصل عن الكورس', 'Detached from the course'), style: AppType.section(context)),
            _CountList(p.detached),
          ],
        ],
      ],
    ]);
  }
}

/// The course's life: deleted, restored, permanently deleted. Newest first.
class TrashHistoryTimeline extends StatelessWidget {
  const TrashHistoryTimeline(this.entries, {super.key});
  final List<TrashHistoryEntry> entries;

  @override
  Widget build(BuildContext context) {
    final rows = <_Event>[];
    for (final e in entries) {
      if (e.purgedAt != null || e.state == 'purged' || e.state == 'erased') {
        rows.add(_Event(Icons.delete_forever_outlined, t('حُذف نهائياً', 'Permanently deleted'), e.purgedAt, e.purgedBy, e.purgeReason, danger: true));
      }
      if (e.restoredAt != null) {
        rows.add(_Event(Icons.restore_from_trash_rounded, t('تم الاسترجاع', 'Restored'), e.restoredAt, e.restoredBy, e.restoreReason, success: true));
      }
      final via = trashViaLabel(e.via);
      rows.add(_Event(Icons.delete_outline_rounded, via.isEmpty ? t('حُذف', 'Deleted') : via, e.deletedAt, e.deletedBy, e.deleteReason));
    }
    if (rows.isEmpty) return Text(t('لا سجل', 'No history'), style: AppType.meta(context));
    return Column(children: [for (final r in rows) _EventTile(r)]);
  }
}

class _Event {
  const _Event(this.icon, this.title, this.at, this.by, this.reason, {this.danger = false, this.success = false});
  final IconData icon;
  final String title;
  final DateTime? at;
  final TrashPerson? by;
  final String? reason;
  final bool danger;
  final bool success;
}

class _EventTile extends StatelessWidget {
  const _EventTile(this.e);
  final _Event e;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = e.danger ? c.danger : (e.success ? c.success : c.textMedium);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(e.icon, size: 18, color: appInk(context, tone)),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
            Text('${_when(e.at)} · ${trashPersonText(e.by)}', maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
            if (e.reason != null) Text(e.reason!, maxLines: 4, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
          ]),
        ),
      ]),
    );
  }
}

/// The whole detail: impact, what restoring brings back, history, the two actions.
class TrashDetailBody extends StatelessWidget {
  const TrashDetailBody({super.key, required this.detail, required this.onRestore, required this.onPurge});
  final TrashDetail detail;
  final VoidCallback onRestore;
  final VoidCallback onPurge;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final it = detail.item;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TrashAvatar(name: it.name, imageUrl: it.imageUrl, size: 56),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(it.name, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
            if (it.teacher != null) Text(it.teacher!.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
          ]),
        ),
      ]),
      const SizedBox(height: AppSpace.sm),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        if (it.wasPublished) AppBadgePill(t('كان منشوراً', 'Was published'), color: c.success),
        if (it.legacy) const TrashLegacyChip(),
      ]),
      _Line(Icons.schedule_rounded, '${_when(it.deletedAt)} · ${trashPersonText(it.deletedBy)}', maxLines: 3),
      if (it.reason != null) _Line(Icons.notes_rounded, it.reason!, maxLines: 6),
      const SizedBox(height: AppSpace.md),
      Text(t('الأثر', 'Impact'), style: AppType.section(context)),
      const SizedBox(height: AppSpace.xs),
      TrashImpactStrip(it),
      const SizedBox(height: AppSpace.sm),
      AppBanner(
        icon: Icons.info_outline_rounded,
        color: c.primary,
        text: it.legacy
            ? t('الاسترجاع يعيد الكورس فقط، ولا يعيد طلابه لأنه حُذف قبل وجود سلة المحذوفات.', 'Restoring brings back the course only, not its students, because it was deleted before the trash existed.')
            : t('الاسترجاع يعيد الكورس بحالة نشره السابقة، وطلابه بحالة اشتراكهم السابقة.', 'Restoring brings back the course with its previous published state, and its students with their previous status.'),
      ),
      const SizedBox(height: AppSpace.md),
      Text(t('السجل', 'History'), style: AppType.section(context)),
      const SizedBox(height: AppSpace.xs),
      TrashHistoryTimeline(detail.history),
      const SizedBox(height: AppSpace.sm),
      Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
        AppButton(label: t('استرجاع', 'Restore'), icon: Icons.restore_from_trash_rounded, onPressed: onRestore),
        AppButton(label: t('حذف نهائي', 'Delete permanently'), icon: Icons.delete_forever_outlined, variant: AppButtonVariant.danger, onPressed: onPurge),
      ]),
    ]);
  }
}

/// Body of the restore dialog: what comes back, an optional reason, two buttons.
class TrashRestoreForm extends StatefulWidget {
  const TrashRestoreForm({super.key, required this.item, required this.onCancel, required this.onConfirm});
  final TrashItem item;
  final VoidCallback onCancel;
  final ValueChanged<String> onConfirm;

  @override
  State<TrashRestoreForm> createState() => _TrashRestoreFormState();
}

class _TrashRestoreFormState extends State<TrashRestoreForm> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        it.legacy
            ? t('سيعود الكورس فقط. لن يعود طلابه لأنه حُذف قبل وجود سلة المحذوفات.', 'Only the course comes back. Its students do not, because it was deleted before the trash existed.')
            : t('سيعود الكورس بحالة نشره السابقة، ويعود طلابه بحالة اشتراكهم السابقة. الاشتراكات التي انتهت أثناء الحذف تبقى منتهية ويمكن تمديدها.',
                'The course comes back with its previous published state, and its students with their previous status. Subscriptions that ended while it was deleted stay ended and can be extended.'),
        style: AppType.meta(context),
      ),
      const SizedBox(height: AppSpace.sm),
      AppField(controller: _reason, label: t('السبب (اختياري)', 'Reason (optional)'), maxLines: 2),
      Wrap(alignment: WrapAlignment.end, spacing: AppSpace.sm, runSpacing: AppSpace.xs, children: [
        TextButton(onPressed: widget.onCancel, child: Text(t('إلغاء', 'Cancel'))),
        AppButton(label: t('استرجاع', 'Restore'), icon: Icons.restore_from_trash_rounded, onPressed: () => widget.onConfirm(_reason.text)),
      ]),
    ]);
  }
}

/// Body of the permanent-delete dialog: the plan, a reason (5+ characters) and the course id typed back.
class TrashPurgeForm extends StatefulWidget {
  const TrashPurgeForm({super.key, required this.courseId, required this.plan, required this.onCancel, required this.onConfirm});
  final int courseId;
  final TrashPurgePlan plan;
  final VoidCallback onCancel;
  final void Function(String reason) onConfirm;

  @override
  State<TrashPurgeForm> createState() => _TrashPurgeFormState();
}

class _TrashPurgeFormState extends State<TrashPurgeForm> {
  final _reason = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _ready => !widget.plan.blocked && _reason.text.trim().length >= 5 && _confirm.text.trim() == '${widget.courseId}';

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Flexible(
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TrashPurgePlanView(widget.plan),
            if (!widget.plan.blocked) ...[
              const SizedBox(height: AppSpace.md),
              AppField(controller: _reason, label: t('السبب (5 أحرف على الأقل)', 'Reason (at least 5 characters)'), maxLines: 2, onChanged: (_) => setState(() {})),
              AppField(
                controller: _confirm,
                label: t('اكتب رقم الكورس ${widget.courseId} للتأكيد', 'Type the course id ${widget.courseId} to confirm'),
                ltr: true,
                keyboard: TextInputType.number,
                onChanged: (_) => setState(() {}),
              ),
            ],
          ]),
        ),
      ),
      Wrap(alignment: WrapAlignment.end, spacing: AppSpace.sm, runSpacing: AppSpace.xs, children: [
        TextButton(onPressed: widget.onCancel, child: Text(t('إلغاء', 'Cancel'))),
        AppButton(
          label: t('حذف نهائي', 'Delete permanently'),
          icon: Icons.delete_forever_outlined,
          variant: AppButtonVariant.danger,
          onPressed: _ready ? () => widget.onConfirm(_reason.text) : null,
        ),
      ]),
    ]);
  }
}
