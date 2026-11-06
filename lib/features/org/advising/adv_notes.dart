// lib/features/org/advising/adv_notes.dart — a student's advising notes in the 360 (docs/advising/PHASE4.md "Notes",
// #8 #23): the composer (who may read it, sensitive, category, "log as a contact" with how and when), the notes with
// edit / delete of one's own, and the notes written offline that wait for a connection (adv_draft_store.dart).
//
//   AdvNoteComposer   the composer (new note, or an edit in a sheet)   AdvNoteCard   one note
//   AdvQueuedNoteCard a note written offline, waiting or refused      AdvNotesPane  the notes block of the 360
//   showAdvNoteEditSheet   the edit sheet (whole-object PUT)
// Everything but the sheet function takes plain values (test/ui/adv_case_layout_test.dart).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t;
import '../org_v3.dart' show orgCall;
import 'adv_api.dart';
import 'adv_case_parts.dart';
import 'adv_draft_store.dart' show AdvQueuedNote;
import 'adv_models.dart';
import 'adv_parts.dart';

IconData advContactModeIcon(String? mode) => switch (mode) {
      'phone' => Icons.call_rounded,
      'video' => Icons.videocam_rounded,
      'chat' => Icons.chat_bubble_outline_rounded,
      'email' => Icons.mail_outline_rounded,
      _ => Icons.groups_rounded,
    };

IconData advVisibilityIcon(String v) => switch (v) {
      'private' => Icons.person_rounded,
      'student' => Icons.school_rounded,
      _ => Icons.groups_rounded,
    };

/// The composer: a new note (with the offline state) or an edit ([editing]).
class AdvNoteComposer extends StatelessWidget {
  const AdvNoteComposer({
    super.key,
    required this.body,
    required this.draft,
    this.categories = const [],
    this.canSensitive = false,
    this.editing = false,
    this.offline = false,
    this.draftSaved = false,
    this.queued = const [],
    this.busy = false,
    this.error,
    this.onVisibility,
    this.onSensitive,
    this.onCategory,
    this.onContact,
    this.onMode,
    this.onPickContactDate,
    this.onSubmit,
    this.onDiscardQueued,
    this.onReopenQueued,
  });

  final TextEditingController body;

  /// Everything but the body (the controller holds it).
  final AdvNoteDraft draft;
  final List<AdvCategory> categories;

  /// The caller may write sensitive notes.
  final bool canSensitive;
  final bool editing;

  /// No connection: the note is kept on the device and sent later.
  final bool offline;

  /// The text typed so far is kept on this device.
  final bool draftSaved;

  /// This student's notes written offline (waiting, or refused by the server).
  final List<AdvQueuedNote> queued;
  final bool busy;
  final String? error;
  final ValueChanged<String>? onVisibility, onMode;
  final ValueChanged<bool>? onSensitive, onContact;
  final ValueChanged<int?>? onCategory;
  final VoidCallback? onPickContactDate, onSubmit;
  final ValueChanged<AdvQueuedNote>? onDiscardQueued, onReopenQueued;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = draft;
    final err = error;
    final waiting = [for (final q in queued) if (!q.failed) q];
    final refused = [for (final q in queued) if (q.failed) q];
    final visibilities = [for (final v in advNoteVisibilities) if (!(d.sensitive && v == 'student')) v];
    final cats = [for (final x in categories) if (x.active || x.id == d.categoryId) x];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      for (final q in refused) AdvQueuedNoteCard(note: q, onDiscard: onDiscardQueued, onReopen: onReopenQueued),
      AdvTypedField(
        controller: body,
        label: editing ? t('الملاحظة', 'Note') : t('ملاحظة إرشادية', 'Advising note'),
        hint: t('ما نوقش، وما اتُّفق عليه، والخطوة التالية', 'What was discussed, what was agreed, the next step'),
        maxLength: advNoteMaxLength,
        enabled: !busy,
      ),
      const SizedBox(height: AppSpace.sm),
      AdvFieldLabel(t('من يقرؤها', 'Who can read it'), hint: advVisibilityHint(d.visibility)),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final v in visibilities)
          AppChoiceChip(
            label: advVisibilityLabel(v),
            icon: advVisibilityIcon(v),
            selected: v == d.visibility,
            onTap: busy || onVisibility == null ? () {} : () => onVisibility!(v),
          ),
      ]),
      if (canSensitive)
        AppSwitchTile(
          icon: Icons.lock_outline_rounded,
          title: t('ملاحظة حساسة', 'Sensitive note'),
          subtitle: t('لك وللمرشد الأساسي ومديري الإرشاد فقط، وكل قراءة لها مسجّلة', 'Only you, the primary advisor and the directors; every read is recorded'),
          value: d.sensitive,
          onChanged: busy ? null : onSensitive,
        ),
      if (cats.isNotEmpty) ...[
        const SizedBox(height: AppSpace.xs),
        AppDropdown<int>(
          value: d.categoryId ?? 0,
          decoration: InputDecoration(labelText: t('التصنيف (اختياري)', 'Category (optional)')),
          items: [
            DropdownMenuItem(value: 0, child: Text(t('بلا تصنيف', 'No category'))),
            for (final x in cats) DropdownMenuItem(value: x.id, child: Text(x.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: busy || onCategory == null ? null : (v) => onCategory!(v == null || v == 0 ? null : v),
        ),
      ],
      AppSwitchTile(
        icon: Icons.forum_outlined,
        title: t('تسجيلها كتواصل مع الطالب', 'Log it as a contact'),
        subtitle: t('تُحتسب آخر تواصل مع الطالب', 'It counts as the last contact with the student'),
        value: d.isContact,
        onChanged: busy ? null : onContact,
      ),
      if (d.isContact) ...[
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final m in advContactModes)
            AppChoiceChip(
              label: advMeetingModeLabel(m),
              icon: advContactModeIcon(m),
              selected: m == d.contactMode,
              onTap: busy || onMode == null ? () {} : () => onMode!(m),
            ),
        ]),
        const SizedBox(height: AppSpace.sm),
        AdvPersonField(
          label: t('متى', 'When'),
          name: d.contactAt == null ? t('الآن', 'Now') : AppTime.dateTime(d.contactAt!.toUtc()),
          icon: Icons.schedule_rounded,
          avatar: false,
          onPick: busy ? null : onPickContactDate,
        ),
      ],
      if (!editing && (offline || waiting.isNotEmpty || draftSaved)) ...[
        const SizedBox(height: AppSpace.sm),
        _SaveLine(offline: offline, waiting: waiting.length, draftSaved: draftSaved),
      ],
      if (err != null) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: err),
      ],
      const SizedBox(height: AppSpace.sm),
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: body,
        builder: (context, v, _) => AppPrimaryButton(
          icon: editing ? Icons.check_rounded : (offline ? Icons.save_alt_rounded : Icons.send_rounded),
          label: editing ? t('حفظ', 'Save') : (offline ? t('حفظ للإرسال لاحقاً', 'Save to send later') : t('إضافة الملاحظة', 'Add the note')),
          busy: busy,
          onPressed: v.text.trim().isEmpty ? null : onSubmit,
        ),
      ),
    ]);
  }
}

/// "Saved on this device · will send when online" / "2 notes will send when online" / "Draft saved on this device".
class _SaveLine extends StatelessWidget {
  const _SaveLine({required this.offline, required this.waiting, required this.draftSaved});
  final bool offline, draftSaved;
  final int waiting;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final String text;
    final IconData icon;
    if (waiting > 0) {
      icon = Icons.cloud_upload_outlined;
      text = waiting == 1
          ? t('محفوظة على هذا الجهاز · تُرسل عند عودة الاتصال', 'Saved on this device · will send when online')
          : t('$waiting ملاحظات محفوظة على هذا الجهاز · تُرسل عند عودة الاتصال', '$waiting notes saved on this device · will send when online');
    } else if (offline) {
      icon = Icons.wifi_off_rounded;
      text = t('لا اتصال: تُحفظ الملاحظة على هذا الجهاز وتُرسل عند عودة الاتصال', 'Offline: the note is kept on this device and sent when you are back online');
    } else {
      icon = Icons.save_outlined;
      text = t('المسودة محفوظة على هذا الجهاز', 'Draft saved on this device');
    }
    return Semantics(
      liveRegion: true,
      child: Row(children: [
        ExcludeSemantics(child: Icon(icon, size: AppIconSize.sm, color: waiting > 0 || offline ? appInk(context, c.warning) : c.textMedium)),
        const SizedBox(width: AppSpace.xs),
        Expanded(child: Text(text, style: AppType.meta(context))),
      ]),
    );
  }
}

/// A note written offline that the server refused: its reason, Edit (back into the composer) and Discard.
class AdvQueuedNoteCard extends StatelessWidget {
  const AdvQueuedNoteCard({super.key, required this.note, this.onDiscard, this.onReopen});
  final AdvQueuedNote note;
  final ValueChanged<AdvQueuedNote>? onDiscard, onReopen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Container(
        padding: const EdgeInsets.all(AppSpace.sm),
        decoration: BoxDecoration(color: c.danger.withValues(alpha: 0.05), borderRadius: AppRadius.chipAll, border: Border.all(color: c.danger.withValues(alpha: 0.25))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            ExcludeSemantics(child: Icon(Icons.error_outline_rounded, size: AppIconSize.md, color: appInk(context, c.danger))),
            const SizedBox(width: AppSpace.xs),
            Expanded(child: Text(t('لم تُرسل ملاحظة كُتبت دون اتصال', 'A note written offline was not sent'), style: AppType.row(context).copyWith(fontWeight: FontWeight.w600))),
          ]),
          if ((note.message ?? '').isNotEmpty) Text(note.message!, style: AppType.meta(context)),
          const SizedBox(height: AppSpace.xxs),
          AdvTypedText(note.draft.body, maxLines: 3),
          Wrap(spacing: AppSpace.xxs, children: [
            if (onReopen != null)
              TextButton.icon(
                style: TextButton.styleFrom(minimumSize: const Size(0, AppTouch.min)),
                onPressed: () => onReopen!(note),
                icon: const Icon(Icons.edit_outlined, size: AppIconSize.sm),
                label: Text(t('تعديل وإعادة الإرسال', 'Edit and send again')),
              ),
            if (onDiscard != null)
              TextButton.icon(
                style: TextButton.styleFrom(minimumSize: const Size(0, AppTouch.min), foregroundColor: appInk(context, c.danger)),
                onPressed: () => onDiscard!(note),
                icon: const Icon(Icons.delete_outline_rounded, size: AppIconSize.sm),
                label: Text(t('حذف', 'Discard')),
              ),
          ]),
        ]),
      ),
    );
  }
}

class AdvNoteCard extends StatelessWidget {
  const AdvNoteCard({super.key, required this.note, this.onEdit, this.onDelete});
  final AdvNote note;
  final VoidCallback? onEdit, onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final n = note;
    final when = [
      if (n.createdAt != null) AppTime.dateTime(n.createdAt!),
      if (n.editedAt != null) t('عُدّلت', 'edited'),
    ].join(' · ');
    final menu = onEdit != null || onDelete != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpace.sm),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            AppAvatar(name: n.author.shown, size: 36),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(n.mine ? t('${n.author.shown} (أنت)', '${n.author.shown} (you)') : n.author.shown,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(fontWeight: FontWeight.w600)),
                if (when.isNotEmpty) Text(when, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
              ]),
            ),
            if (menu)
              PopupMenuButton<String>(
                tooltip: t('خيارات الملاحظة', 'Note options'),
                icon: Icon(Icons.more_horiz_rounded, color: c.textMedium),
                constraints: const BoxConstraints(minWidth: AppTouch.min * 3),
                onSelected: (v) => v == 'edit' ? onEdit?.call() : onDelete?.call(),
                itemBuilder: (_) => [
                  if (onEdit != null)
                    PopupMenuItem(value: 'edit', height: AppTouch.min, child: Row(children: [const Icon(Icons.edit_outlined, size: AppIconSize.md), AppSpace.gapXs, Text(t('تعديل', 'Edit'))])),
                  if (onDelete != null)
                    PopupMenuItem(
                      value: 'delete',
                      height: AppTouch.min,
                      child: Row(children: [
                        Icon(Icons.delete_outline_rounded, size: AppIconSize.md, color: appInk(context, c.danger)),
                        AppSpace.gapXs,
                        Text(t('حذف', 'Delete'), style: TextStyle(color: appInk(context, c.danger))),
                      ]),
                    ),
                ],
              ),
          ]),
          const SizedBox(height: AppSpace.xs),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
            AppBadgePill(advVisibilityLabel(n.visibility), color: n.visibility == 'student' ? c.success : (n.visibility == 'private' ? c.textMedium : c.primary), icon: advVisibilityIcon(n.visibility)),
            if (n.sensitive) AppBadgePill(t('حساسة', 'Sensitive'), color: c.warning, icon: Icons.lock_outline_rounded),
            if (n.category != null) AppBadgePill(n.category!.name, color: c.textMedium, icon: Icons.label_outline_rounded),
            if (n.contactMode != null)
              AppBadgePill(
                n.contactAt == null ? advMeetingModeLabel(n.contactMode!) : '${advMeetingModeLabel(n.contactMode!)} · ${advDate(n.contactAt)}',
                color: c.primary,
                icon: advContactModeIcon(n.contactMode),
              ),
          ]),
          const SizedBox(height: AppSpace.xs),
          SelectionArea(child: AdvTypedText(n.body)),
        ]),
      ),
    );
  }
}

/// The notes block of the 360: the composer, the notes, "Load more", the hidden count.
class AdvNotesPane extends StatelessWidget {
  const AdvNotesPane({
    super.key,
    required this.load,
    this.composer,
    this.notes,
    this.total = 0,
    this.restricted = 0,
    this.hasMore = false,
    this.loadingMore = false,
    this.errorText,
    this.onRetry,
    this.onMore,
    this.canEdit,
    this.canDelete,
    this.onEdit,
    this.onDelete,
  });

  final AdvLoad load;

  /// null: the caller may not write notes.
  final Widget? composer;
  final List<AdvNote>? notes;
  final int total, restricted;
  final bool hasMore, loadingMore;
  final String? errorText;
  final VoidCallback? onRetry, onMore;
  final bool Function(AdvNote)? canEdit, canDelete;
  final ValueChanged<AdvNote>? onEdit, onDelete;

  @override
  Widget build(BuildContext context) {
    final list = notes;
    final children = <Widget>[
      if (composer != null) ...[
        AppCard(padding: AppSpace.card, child: composer!),
        const SizedBox(height: AppSpace.sm),
      ],
    ];
    if (load != AdvLoad.ready || list == null) {
      children.add(AdvLoadState(state: load == AdvLoad.ready ? AdvLoad.loading : load, errorText: errorText, onRetry: onRetry, items: 2));
    } else {
      if (list.isEmpty) {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
          child: Column(children: [
            ExcludeSemantics(child: Icon(Icons.sticky_note_2_outlined, size: AppIconSize.xl, color: context.colors.textLight)),
            const SizedBox(height: AppSpace.xs),
            Text(t('لا ملاحظات بعد', 'No notes yet'), textAlign: TextAlign.center, style: AppType.body(context)),
          ]),
        ));
      } else if (total > 0) {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: Text(t('الملاحظات · $total', 'Notes · $total'), style: AppType.meta(context)),
        ));
      }
      for (final n in list) {
        children.add(AdvNoteCard(
          note: n,
          onEdit: onEdit == null || !(canEdit?.call(n) ?? false) ? null : () => onEdit!(n),
          onDelete: onDelete == null || !(canDelete?.call(n) ?? false) ? null : () => onDelete!(n),
        ));
      }
      if (hasMore && onMore != null) {
        children.add(Align(
          child: TextButton.icon(
            style: TextButton.styleFrom(minimumSize: const Size(0, AppTouch.min)),
            onPressed: loadingMore ? null : onMore,
            icon: loadingMore ? const SizedBox.square(dimension: AppIconSize.sm, child: CircularProgressIndicator(strokeWidth: AppBorder.focus)) : const Icon(Icons.expand_more_rounded),
            label: Text(t('ملاحظات أقدم', 'Older notes')),
          ),
        ));
      }
      children.add(AdvRestrictedLine(count: restricted, notes: true));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children);
  }
}

/// When a contact happened: a date, then a time (default: now).
Future<DateTime?> pickAdvContactTime(BuildContext context, DateTime? initial) async {
  final now = DateTime.now();
  final init = (initial ?? now).toLocal();
  final d = await showDatePicker(context: context, initialDate: init.isAfter(now) ? now : init, firstDate: DateTime(now.year - 1), lastDate: now);
  if (d == null || !context.mounted) return null;
  final tm = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(init));
  final picked = DateTime(d.year, d.month, d.day, tm?.hour ?? init.hour, tm?.minute ?? init.minute);
  return picked.isAfter(now) ? now : picked;
}

/// Edits [note] (the author): the whole note is sent back. Returns the saved note.
Future<AdvNote?> showAdvNoteEditSheet(BuildContext context, AdvApi api, AdvNote note, {List<AdvCategory> categories = const [], bool canSensitive = false}) {
  final body = TextEditingController(text: note.body);
  var draft = AdvNoteDraft.of(note);
  var busy = false;
  String? error;
  return showAppSheet<AdvNote>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        Future<void> submit() async {
          final d = draft.copyWith(body: body.text);
          final why = d.error();
          if (why != null) {
            set(() => error = why);
            return;
          }
          set(() {
            busy = true;
            error = null;
          });
          final r = await orgCall(() => api.saveNote(note.id, d), quiet: true);
          if (!ctx.mounted) return;
          if (!r.ok) {
            set(() {
              busy = false;
              error = advErrorText(r.error!);
            });
            return;
          }
          showAppNotice(t('حُفظت الملاحظة', 'Note saved'));
          Navigator.pop(ctx, r.data as AdvNote);
        }

        Future<void> pickWhen() async {
          final d = await pickAdvContactTime(ctx, draft.contactAt);
          if (d != null) set(() => draft = draft.copyWith(contactAt: () => d));
        }

        return AppSheetContent(
          title: t('تعديل الملاحظة', 'Edit the note'),
          children: [
            AdvNoteComposer(
              body: body,
              draft: draft,
              categories: categories,
              canSensitive: canSensitive || note.sensitive,
              editing: true,
              busy: busy,
              error: error,
              onVisibility: (v) => set(() => draft = draft.copyWith(visibility: v)),
              onSensitive: (v) => set(() => draft = draft.copyWith(sensitive: v)),
              onCategory: (id) => set(() => draft = draft.copyWith(categoryId: () => id)),
              onContact: (on) => set(() => draft = draft.copyWith(contactMode: () => on ? (draft.contactMode ?? 'in_person') : null, contactAt: () => null)),
              onMode: (m) => set(() => draft = draft.copyWith(contactMode: () => m)),
              onPickContactDate: pickWhen,
              onSubmit: submit,
            ),
          ],
        );
      }));
}
