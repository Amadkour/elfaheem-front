// Chat sessions, the presentational side (Track E.5): the conversations panel ([RagSessionsPanel] — a bottom sheet
// on phones, a side panel on a wide window — with its rows [RagSessionRow]), the rename dialog ([RagRenameDialog])
// and the thumbs-down sheet ([RagRatingCommentSheet]: reason chips + comment). All take plain values and callbacks; [RagChatView]
// (rag_chat_screen.dart) owns the API calls. Texts come from translation.json (`rag_*` keys).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t, trp;
import 'rag_chat.dart';
import 'rag_learning.dart' show RagDownVote, chatReasonLabel, chatReasons;

/// The asker's conversations, newest first, with New chat on top and the retention notice at the bottom.
/// [currentId] is highlighted; tapping a row opens it, its menu (and a long press) renames or deletes it.
class RagSessionsPanel extends StatelessWidget {
  const RagSessionsPanel({
    super.key,
    required this.items,
    required this.onOpen,
    required this.onNew,
    this.currentId,
    this.retentionDays,
    this.onRename,
    this.onDelete,
    this.onClose,
    this.loading = false,
    this.now,
  });
  final List<RagConversation> items;
  final int? currentId;
  final int? retentionDays;
  final ValueChanged<RagConversation> onOpen;
  final VoidCallback onNew;
  final ValueChanged<RagConversation>? onRename;
  final ValueChanged<RagConversation>? onDelete;

  /// Shown as a close button (the bottom sheet closes itself; the side panel hides).
  final VoidCallback? onClose;
  final bool loading;

  /// For tests: the instant the relative times count from.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final retention = retentionText(retentionDays, AppConfig.lang);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 6, 4),
        child: Row(children: [
          Expanded(child: Text('rag_chats'.tr, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(16, w: FontWeight.w800, c: c.textDark))),
          IconButton(tooltip: 'rag_new_chat'.tr, onPressed: onNew, icon: Icon(Icons.add_comment_outlined, color: appInk(context, c.primary))),
          if (onClose != null) IconButton(tooltip: MaterialLocalizations.of(context).closeButtonLabel, onPressed: onClose, icon: const Icon(Icons.close_rounded)),
        ]),
      ),
      Flexible(
        child: loading
            ? const AppListSkeleton(items: 3, withAvatar: false, padding: EdgeInsets.fromLTRB(12, 4, 12, 8))
            : items.isEmpty
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: AppEmpty(icon: Icons.forum_outlined, title: 'rag_chats_empty'.tr, actionLabel: 'rag_new_chat'.tr, onAction: onNew))
                : ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    itemCount: items.length,
                    itemBuilder: (_, i) => RagSessionRow(
                        item: items[i],
                        current: items[i].id == currentId,
                        now: now,
                        onTap: () => onOpen(items[i]),
                        onRename: onRename == null ? null : () => onRename!(items[i]),
                        onDelete: onDelete == null ? null : () => onDelete!(items[i]))),
      ),
      if (retention.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.auto_delete_outlined, size: 15, color: c.textLight),
            const SizedBox(width: 6),
            Expanded(child: Text(retention, style: appText(11.5, c: c.textLight))),
          ]),
        ),
    ]);
  }
}

/// One conversation: title, when its last question was, how many turns; the current one is tinted.
class RagSessionRow extends StatelessWidget {
  const RagSessionRow({super.key, required this.item, required this.onTap, this.current = false, this.onRename, this.onDelete, this.now});
  final RagConversation item;
  final bool current;
  final VoidCallback onTap;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final meta = [
      if (item.lastAt != null) ragRelativeTime(item.lastAt, now: now),
      if (item.turns > 0) trp('rag_turns', {'n': item.turns}),
    ].join(' · ');
    final menu = onRename != null || onDelete != null;
    return Material(
      color: current ? c.primary.withValues(alpha: .08) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onLongPress: menu ? () => _menuAt(context, null) : null,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 4, 8),
          child: Row(children: [
            Icon(current ? Icons.chat_bubble_rounded : Icons.chat_bubble_outline_rounded, size: 18, color: current ? appInk(context, c.primary) : c.textLight),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(item.displayTitle, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: appText(13.5, w: current ? FontWeight.w800 : FontWeight.w600, c: c.textDark)),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(11.5, c: c.textLight)),
                ],
              ]),
            ),
            if (menu)
              PopupMenuButton<String>(
                  tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
                  padding: EdgeInsets.zero,
                  onSelected: _pick,
                  itemBuilder: (_) => _entries(c),
                  icon: Icon(Icons.more_vert_rounded, size: 18, color: c.textLight))
            else
              const SizedBox(width: 8),
          ]),
        ),
      ),
    );
  }

  List<PopupMenuEntry<String>> _entries(ThemeConfigProvider c) => [
        if (onRename != null)
          PopupMenuItem(
              value: 'rename',
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.edit_outlined, size: 18),
                const SizedBox(width: 8),
                Flexible(child: Text('rag_chat_rename'.tr, overflow: TextOverflow.ellipsis)),
              ])),
        if (onDelete != null)
          PopupMenuItem(
              value: 'delete',
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.delete_outline_rounded, size: 18, color: c.danger),
                const SizedBox(width: 8),
                Flexible(child: Text('rag_chat_delete'.tr, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.danger))),
              ])),
      ];

  void _pick(String? v) {
    if (v == 'rename') onRename?.call();
    if (v == 'delete') onDelete?.call();
  }

  /// The long-press menu, beside the row (the overflow button has its own PopupMenuButton).
  Future<void> _menuAt(BuildContext context, Offset? global) async {
    final box = context.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final at = global ?? box.localToGlobal(box.size.center(Offset.zero));
    final pick = await showMenu<String>(
        context: context,
        position: RelativeRect.fromLTRB(at.dx, at.dy, overlay.size.width - at.dx, overlay.size.height - at.dy),
        items: _entries(context.colors));
    _pick(pick);
  }
}

/// "Chat title" with the current title to edit; pops the new title (trimmed), null when cancelled.
class RagRenameDialog extends StatefulWidget {
  const RagRenameDialog({super.key, required this.title});
  final String title;

  static Future<String?> show(BuildContext context, String title) =>
      showDialog<String>(context: context, builder: (_) => RagRenameDialog(title: title));

  @override
  State<RagRenameDialog> createState() => _RagRenameDialogState();
}

class _RagRenameDialogState extends State<RagRenameDialog> {
  late final _ctrl = TextEditingController(text: widget.title);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _save() {
    final v = _ctrl.text.trim();
    if (v.isEmpty) return;
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    final l = MaterialLocalizations.of(context);
    return Directionality(
      textDirection: pageDirection,
      child: AlertDialog(
        title: Text('rag_chat_rename'.tr),
        content: SingleChildScrollView(child: AppField(controller: _ctrl, label: 'rag_chat_title'.tr, onSubmitted: (_) => _save())),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l.cancelButtonLabel)),
          FilledButton(onPressed: _save, child: Text(l.saveButtonLabel)),
        ],
      ),
    );
  }
}

/// After a thumbs-down: why (reason chips, Track F — one or none) and an optional comment. Pops a [RagDownVote] on
/// Send (the comment possibly empty) and on Skip (the picked reason, no comment); a dismissed sheet pops null — the
/// caller sends the rating either way. [reasons] false (an older server) shows the comment only.
class RagRatingCommentSheet extends StatefulWidget {
  const RagRatingCommentSheet({super.key, this.reasons = true});
  final bool reasons;

  @override
  State<RagRatingCommentSheet> createState() => _RagRatingCommentSheetState();
}

class _RagRatingCommentSheetState extends State<RagRatingCommentSheet> {
  final _ctrl = TextEditingController();
  String? _reason;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _send() => Navigator.of(context).pop(RagDownVote(reason: _reason, comment: _ctrl.text.trim()));

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.thumb_down_alt_outlined, color: c.danger, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text('rag_feedback_title'.tr, style: appText(16, w: FontWeight.w800, c: c.textDark))),
        ]),
        if (widget.reasons) ...[
          const SizedBox(height: 12),
          Text(t('ما المشكلة؟', 'What was wrong?'), style: appText(13, w: FontWeight.w700, c: c.textMedium)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final r in chatReasons)
              AppChoiceChip(label: chatReasonLabel(r), selected: _reason == r, onTap: () => setState(() => _reason = _reason == r ? null : r)),
          ]),
        ],
        const SizedBox(height: 12),
        EnterSubmits(onSubmit: _send, child: AppField(controller: _ctrl, label: 'rag_feedback_hint'.tr, maxLines: 4)),
        const SizedBox(height: 12),
        Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
          TextButton(onPressed: () => Navigator.of(context).pop(RagDownVote(reason: _reason)), child: Text('rag_feedback_skip'.tr)),
          AppPrimaryButton(label: 'rag_feedback_send'.tr, icon: Icons.send_rounded, onPressed: _send),
        ]),
      ]),
    );
  }
}
