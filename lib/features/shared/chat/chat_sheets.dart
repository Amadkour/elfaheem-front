// lib/features/shared/chat/chat_sheets.dart — the chat's sheets and small pages (D-330): new chat, row / message actions,
// block (three levels for a teacher), report, group info, an image, the blocked people page, the admins' reports.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';

import 'chat_api.dart';
import 'chat_models.dart';
import 'chat_new_message.dart';
import 'chat_page.dart' show chatErrorText;
import 'chat_store.dart';
import 'chat_widgets.dart';

ChatApi get _api => ChatHub.instance.api;

const _kBlockingKey = 'chat.blocking';
const _kReportKey = 'chat.report';

// ── new chat ─────────────────────────────────────────────────────────────────────────────────────────────────

Future<ChatContact?> showChatContactPicker(BuildContext context) => showAppSheet<ChatContact>(context, (_) => const ChatNewMessageSheet());

// ── actions ──────────────────────────────────────────────────────────────────────────────────────────────────

/// One action of a menu: the same list opens as a popup at a mouse and as a sheet on a phone.
class ChatMenuAction {
  const ChatMenuAction({required this.icon, required this.label, required this.onTap, this.danger = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
}

Future<void> _showActions(BuildContext context, {required String title, required List<ChatMenuAction> actions, Rect? anchor}) async {
  if (actions.isEmpty) return;
  if (anchor == null) {
    await showAppSheet<void>(
      context,
      (sheet) => AppSheetContent(title: title, children: [
        for (final a in actions)
          _ActionRow(
            icon: a.icon,
            label: a.label,
            danger: a.danger,
            onTap: () {
              Navigator.of(sheet).pop();
              a.onTap();
            },
          ),
      ]),
    );
    return;
  }
  final c = context.colors;
  final overlay = Overlay.of(context, rootOverlay: true).context.findRenderObject()! as RenderBox;
  final picked = await showMenu<ChatMenuAction>(
    context: context,
    useRootNavigator: true,
    color: c.cardBg,
    elevation: 6,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.chip + 2)),
    position: RelativeRect.fromRect(anchor, Offset.zero & overlay.size),
    items: [
      for (final a in actions)
        PopupMenuItem<ChatMenuAction>(
          value: a,
          height: AppTouch.min - 4,
          child: Row(children: [
            Icon(a.icon, size: AppIconSize.md, color: a.danger ? c.danger : c.textMedium),
            const SizedBox(width: AppSpace.sm),
            Flexible(child: Text(a.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13.5, w: FontWeight.w500, c: a.danger ? c.danger : c.textDark))),
          ]),
        ),
    ],
  );
  picked?.onTap();
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.icon, required this.label, required this.onTap, this.danger = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = danger ? c.danger : c.textDark;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.chip),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.sm, horizontal: AppSpace.xxs),
        child: Row(children: [
          Icon(icon, size: AppIconSize.md, color: danger ? c.danger : c.textMedium),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(label, style: appText(14.5, w: FontWeight.w500, c: color)),
          ),
        ]),
      ),
    );
  }
}

Future<void> showChatRowActions(BuildContext context, ChatConversation conv, {bool inThread = false, Rect? anchor}) => _showActions(
      context,
      title: conv.title,
      anchor: anchor,
      actions: [
        ChatMenuAction(icon: conv.pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined, label: conv.pinned ? 'chat_unpin'.tr : 'chat_pin'.tr, onTap: () => ChatHub.instance.togglePin(conv)),
        ChatMenuAction(
          icon: conv.muted ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
          label: conv.muted ? 'chat_unmute'.tr : 'chat_mute'.tr,
          onTap: () {
            if (conv.muted) {
              ChatHub.instance.setMute(conv, 'off');
            } else {
              _showMute(context, conv);
            }
          },
        ),
        if (conv.isGroup && inThread) ChatMenuAction(icon: Icons.info_outline_rounded, label: 'chat_group_info'.tr, onTap: () => showChatInfoSheet(context, conv)),
        if (!conv.isGroup && conv.peer != null && !AppConfig.disableList.contains(_kBlockingKey))
          ChatMenuAction(icon: Icons.block_rounded, danger: true, label: 'chat_block'.tr, onTap: () => showChatBlockSheet(context, conv.peer!)),
        if (!AppConfig.disableList.contains(_kReportKey))
          ChatMenuAction(icon: Icons.flag_outlined, danger: true, label: 'chat_report'.tr, onTap: () => showChatReportSheet(context, conv)),
      ],
    );

void _showMute(BuildContext context, ChatConversation conv) {
  showAppSheet<void>(
    context,
    (sheet) => AppSheetContent(title: 'chat_mute'.tr, children: [
      for (final m in const ['8h', '1w', 'always'])
        _ActionRow(
          icon: Icons.notifications_off_outlined,
          label: 'chat_mute_$m'.tr,
          onTap: () {
            Navigator.of(sheet).pop();
            ChatHub.instance.setMute(conv, m);
          },
        ),
    ]),
  );
}

Future<void> showChatMessageActions(BuildContext context, ChatConversation conv, ChatMessage m, {required bool mine, Rect? anchor, VoidCallback? onReply, VoidCallback? onCopy}) async {
  final canReport = !mine && !AppConfig.disableList.contains(_kReportKey) && m.id != null && !m.deleted;
  await _showActions(
    context,
    title: 'chat_message'.tr,
    anchor: anchor,
    actions: [
      if (onReply != null) ChatMenuAction(icon: Icons.reply_rounded, label: 'chat_reply'.tr, onTap: onReply),
      if (onCopy != null && (m.body ?? '').trim().isNotEmpty && !m.deleted) ChatMenuAction(icon: Icons.copy_rounded, label: 'chat_copy'.tr, onTap: onCopy),
      if (canReport) ChatMenuAction(icon: Icons.flag_outlined, danger: true, label: 'chat_report_message'.tr, onTap: () => showChatReportSheet(context, conv, messageId: m.id)),
    ],
  );
}

// ── block ────────────────────────────────────────────────────────────────────────────────────────────────────

Future<void> showChatBlockSheet(BuildContext context, ChatPerson user) => showAppSheet<void>(context, (_) => ChatBlockSheet(user: user));

class ChatBlockSheet extends StatefulWidget {
  const ChatBlockSheet({super.key, required this.user, this.preloaded});
  final ChatPerson user;
  final ChatBlockOptions? preloaded;

  @override
  State<ChatBlockSheet> createState() => _ChatBlockSheetState();
}

class _ChatBlockSheetState extends State<ChatBlockSheet> {
  ChatBlockOptions? _options;
  String _level = 'person';
  int? _courseId;
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _options = widget.preloaded;
    if (_options == null) {
      _api.blockOptions(widget.user.id).then((o) {
        if (mounted) setState(() => _options = o);
      }).catchError((Object e) {
        if (mounted) setState(() => _error = chatErrorText(e));
      });
    }
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_level == 'course' && _courseId == null) {
      setState(() => _error = 'chat_block_pick_course'.tr);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.block(userId: widget.user.id, level: _level, courseId: _courseId, reason: _reason.text.trim());
      if (!mounted) return;
      showAppNotice('chat_blocked_done'.tr);
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = chatErrorText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final o = _options;
    final first = widget.user.name.split(' ').first;
    if (o == null && _error == null) return const SizedBox(height: 160, child: AppListSkeleton(items: 3, withAvatar: false));
    final levels = o?.levels ?? const ['person'];
    return AppSheetContent(title: '${'chat_block'.tr} $first', children: [
      Text('chat_block_note'.tr, style: appText(12.5, w: FontWeight.w400, c: c.textMedium, h: 1.4)),
      const SizedBox(height: AppSpace.sm),
      for (final lvl in levels)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: _LevelOption(
            title: chatLevelLabel(lvl),
            body: 'chat_level_${lvl}_body'.tr,
            selected: _level == lvl,
            onTap: () => setState(() => _level = lvl),
          ),
        ),
      if (_level == 'course') ...[
        const SizedBox(height: AppSpace.xxs),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final course in o?.courses ?? const <ChatCourse>[])
            AppChoiceChip(label: course.label, selected: _courseId == course.id, onTap: () => setState(() => _courseId = course.id)),
        ]),
      ],
      const SizedBox(height: AppSpace.xs),
      AppField(controller: _reason, label: 'chat_block_reason'.tr, hint: 'chat_block_reason_hint'.tr, maxLines: 2),
      if (_error != null) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.error_outline_rounded, text: _error!, color: c.danger),
      ],
      const SizedBox(height: AppSpace.md),
      AppButton.danger(label: 'chat_block_confirm'.tr, icon: Icons.block_rounded, busy: _busy, onPressed: _busy ? null : _submit),
    ]);
  }
}

class _LevelOption extends StatelessWidget {
  const _LevelOption({required this.title, required this.body, required this.selected, required this.onTap});
  final String title, body;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: selected ? c.primaryTint : c.inputBg,
      borderRadius: BorderRadius.circular(AppRadius.chip + 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.chip + 2),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpace.sm),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadius.control), border: Border.all(color: selected ? c.primary : Colors.transparent, width: AppBorder.strong)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, size: AppIconSize.md, color: selected ? c.primary : c.textLight),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: appText(14, w: FontWeight.w600, c: c.textDark)),
                const SizedBox(height: 2),
                Text(body, style: appText(12, w: FontWeight.w400, c: c.textMedium, h: 1.35)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// The composer's "Unblock": the active blocks I made on this person, undone one-tap.
Future<void> unblockFromThread(BuildContext context, ChatConversation conv, VoidCallback done) async {
  final peer = conv.peer;
  if (peer == null) return;
  try {
    final options = await _api.blockOptions(peer.id);
    for (final b in options.active) {
      await _api.unblock(b.id);
    }
    showAppNotice('chat_unblocked_done'.tr);
    done();
  } catch (e) {
    showAppNotice(chatErrorText(e), error: true);
  }
}

// ── report ───────────────────────────────────────────────────────────────────────────────────────────────────

Future<void> showChatReportSheet(BuildContext context, ChatConversation conv, {int? messageId}) => showAppSheet<void>(context, (_) => ChatReportSheet(conversation: conv, messageId: messageId));

class ChatReportSheet extends StatefulWidget {
  const ChatReportSheet({super.key, required this.conversation, this.messageId});
  final ChatConversation conversation;
  final int? messageId;

  @override
  State<ChatReportSheet> createState() => _ChatReportSheetState();
}

class _ChatReportSheetState extends State<ChatReportSheet> {
  String _reason = 'harassment';
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      await _api.report(conversationId: widget.conversation.id, messageId: widget.messageId, reason: _reason, note: _note.text.trim());
      if (!mounted) return;
      showAppNotice('chat_report_done'.tr);
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = chatErrorText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppSheetContent(title: widget.messageId == null ? 'chat_report'.tr : 'chat_report_message'.tr, children: [
      Text('chat_report_body'.tr, style: appText(12.5, w: FontWeight.w400, c: c.textMedium, h: 1.4)),
      const SizedBox(height: AppSpace.sm),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final r in const ['harassment', 'inappropriate', 'spam', 'safety', 'other'])
          AppChoiceChip(label: 'chat_reason_$r'.tr, selected: _reason == r, onTap: () => setState(() => _reason = r)),
      ]),
      const SizedBox(height: AppSpace.sm),
      AppField(controller: _note, label: 'chat_report_note'.tr, maxLines: 3),
      if (_error != null) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.error_outline_rounded, text: _error!, color: c.danger),
      ],
      const SizedBox(height: AppSpace.md),
      AppButton.primary(label: 'chat_report_send'.tr, busy: _busy, onPressed: _busy ? null : _submit),
    ]);
  }
}

// ── group / person info ──────────────────────────────────────────────────────────────────────────────────────

Future<void> showChatInfoSheet(BuildContext context, ChatConversation conv, {VoidCallback? onChanged}) => showAppSheet<void>(context, (_) => ChatInfoSheet(conversation: conv, onChanged: onChanged));

class ChatInfoSheet extends StatefulWidget {
  const ChatInfoSheet({super.key, required this.conversation, this.onChanged});
  final ChatConversation conversation;
  final VoidCallback? onChanged;

  @override
  State<ChatInfoSheet> createState() => _ChatInfoSheetState();
}

class _ChatInfoSheetState extends State<ChatInfoSheet> {
  late bool _open = widget.conversation.groupOpen;
  bool _busy = false;
  Future<List<ChatMemberRow>>? _members;

  @override
  void initState() {
    super.initState();
    if (widget.conversation.isGroup) _members = _api.members(widget.conversation.id);
  }

  Future<void> _toggle(bool v) async {
    setState(() {
      _busy = true;
      _open = v;
    });
    try {
      await _api.setGroupOpen(widget.conversation.id, v);
      widget.onChanged?.call();
      showAppNotice(v ? 'chat_group_opened'.tr : 'chat_group_closed'.tr);
    } catch (e) {
      if (mounted) setState(() => _open = !v);
      showAppNotice(chatErrorText(e), error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final conv = widget.conversation;
    final role = conv.isGroup ? '' : chatRoleLabel(conv.peer?.role ?? '');
    final username = conv.isGroup ? null : conv.peer?.username;
    final facts = [role, if (conv.child != null) '${'chat_parent_of'.tr} ${conv.child!.name.split(' ').first}', if (!conv.isGroup && conv.contextLine.isNotEmpty) conv.contextLine].where((x) => x.isNotEmpty).join(' · ');
    return AppSheetContent(title: conv.isGroup ? 'chat_group_info'.tr : 'chat_person_info'.tr, children: [
      Center(child: ChatAvatar(name: conv.title, url: conv.isGroup ? conv.course?.imageUrl : conv.peer?.imageUrl, size: 84, online: conv.online, group: conv.isGroup && conv.course?.imageUrl == null)),
      const SizedBox(height: AppSpace.sm),
      Text(conv.title, textAlign: TextAlign.center, style: AppType.headline(context)),
      if (username != null) Text('@$username', textAlign: TextAlign.center, style: appText(13, w: FontWeight.w500, c: chatInk(c))),
      if (facts.isNotEmpty) ...[
        const SizedBox(height: AppSpace.xxs),
        Text(facts, textAlign: TextAlign.center, style: appText(13, w: FontWeight.w500, c: c.textMedium, h: 1.35)),
      ],
      if (conv.canManage) ...[
        const SizedBox(height: AppSpace.sm),
        AppSwitchTile(title: 'chat_group_open'.tr, subtitle: 'chat_group_open_body'.tr, icon: Icons.lock_open_rounded, value: _open, onChanged: _busy ? null : _toggle),
      ],
      if (_members != null) ...[
        const SizedBox(height: AppSpace.sm),
        Text('chat_members'.tr, style: AppType.section(context)),
        const SizedBox(height: AppSpace.xs),
        FutureBuilder<List<ChatMemberRow>>(
          future: _members,
          builder: (context, s) {
            if (!s.hasData) return const SizedBox(height: 120, child: AppListSkeleton(items: 3));
            return Column(children: [
              for (final m in s.data!)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    AppAvatar(name: m.person.name, url: m.person.imageUrl, size: 36),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(child: Text(m.person.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13.5, w: FontWeight.w500, c: c.textDark))),
                    if (m.teacher) AppBadgePill('chat_teacher'.tr, color: c.accent),
                    if (conv.canManage && !m.teacher)
                      IconButton(
                        tooltip: 'chat_block'.tr,
                        icon: Icon(Icons.block_rounded, size: AppIconSize.sm, color: c.textLight),
                        onPressed: () => showChatBlockSheet(context, m.person),
                      ),
                  ]),
                ),
            ]);
          },
        ),
      ],
    ]);
  }
}

Future<void> showChatImage(BuildContext context, String url, String name) => showDialog<void>(
      context: context,
      useSafeArea: false,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (ctx) => _ChatImageViewer(url: url, name: name),
    );

/// A picture full-screen: zoom, a name and the close and open buttons in the top bar; Escape or a tap on the dark closes it.
class _ChatImageViewer extends StatelessWidget {
  const _ChatImageViewer({required this.url, required this.name});
  final String url, name;

  @override
  Widget build(BuildContext context) {
    final close = Navigator.of(context).pop;
    return SafeArea(
      child: Column(children: [
        SizedBox(
          height: kChatBarHeight,
          child: Row(children: [
            const SizedBox(width: AppSpace.md),
            Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w600, c: Colors.white))),
            IconButton(tooltip: 'chat_open_external'.tr, constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min), icon: const Icon(Icons.open_in_new_rounded, color: Colors.white), onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)),
            IconButton(tooltip: 'chat_close'.tr, constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min), icon: const Icon(Icons.close_rounded, color: Colors.white), onPressed: () => close()),
            const SizedBox(width: AppSpace.xxs),
          ]),
        ),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => close(),
            child: Center(
              child: InteractiveViewer(
                maxScale: 5,
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.contain,
                  placeholder: (_, _) => const Center(child: SizedBox(width: 32, height: 32, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))),
                  errorWidget: (_, _, _) => const Icon(Icons.broken_image_outlined, color: Colors.white70, size: AppIconSize.xl),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// ── blocked people ───────────────────────────────────────────────────────────────────────────────────────────

class ChatBlocksPage extends StatefulWidget {
  const ChatBlocksPage({super.key, this.api});
  final ChatApi? api;

  @override
  State<ChatBlocksPage> createState() => _ChatBlocksPageState();
}

class _ChatBlocksPageState extends State<ChatBlocksPage> {
  late final ChatApi _a = widget.api ?? ChatHub.instance.api;
  late Future<List<ChatBlock>> _future = _a.blocks();
  bool? _studentDm;

  @override
  void initState() {
    super.initState();
    _a.teacherStudentDm().then((v) {
      if (mounted) setState(() => _studentDm = v);
    }).catchError((_) {});
  }

  void _reload() => setState(() => _future = _a.blocks());

  Future<void> _unblock(ChatBlock b) async {
    try {
      await _a.unblock(b.id);
      showAppNotice('chat_unblocked_done'.tr);
      _reload();
    } catch (e) {
      showAppNotice(chatErrorText(e), error: true);
    }
  }

  Future<void> _setDm(bool v) async {
    final was = _studentDm;
    setState(() => _studentDm = v);
    try {
      await _a.setTeacherStudentDm(v);
    } catch (e) {
      if (mounted) setState(() => _studentDm = was);
      showAppNotice(chatErrorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return BasePage(
      appBar: AppHeader(title: 'chat_blocked_people'.tr),
      child: FutureBuilder<List<ChatBlock>>(
        future: _future,
        builder: (context, s) {
          if (s.connectionState != ConnectionState.done) return const AppListSkeleton(items: 6);
          if (s.hasError) return AppEmpty(icon: Icons.cloud_off_rounded, title: chatErrorText(s.error!), actionLabel: 'chat_retry'.tr, onAction: _reload);
          final items = s.data ?? const <ChatBlock>[];
          return ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
            if (_studentDm != null) ...[
              AppCard(
                child: AppSwitchTile(
                  title: 'chat_student_dm'.tr,
                  subtitle: 'chat_student_dm_body'.tr,
                  icon: Icons.groups_2_outlined,
                  value: _studentDm!,
                  onChanged: _setDm,
                ),
              ),
              const SizedBox(height: AppSpace.md),
            ],
            if (items.isEmpty)
              AppEmpty(icon: Icons.shield_outlined, title: 'chat_blocks_none'.tr, message: 'chat_blocks_none_body'.tr)
            else
              for (final b in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.sm),
                  child: AppCard(
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      ChatAvatar(name: b.user.name, url: b.user.imageUrl, size: 44),
                      const SizedBox(width: AppSpace.sm),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(b.user.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(14.5, w: FontWeight.w600, c: c.textDark)),
                          const SizedBox(height: 3),
                          Wrap(spacing: AppSpace.xxs, runSpacing: AppSpace.xxs, children: [
                            AppBadgePill(chatLevelLabel(b.level), color: b.level == 'all_courses' ? c.danger : c.warning),
                            if (b.course != null) AppBadgePill(b.course!.label, color: c.textMedium),
                          ]),
                          if ((b.reason ?? '').isNotEmpty) ...[
                            const SizedBox(height: AppSpace.xxs),
                            Text(b.reason!, style: appText(12.5, w: FontWeight.w400, c: c.textMedium, h: 1.35)),
                          ],
                          Text(AppTime.date(b.createdAt), style: appText(11.5, w: FontWeight.w400, c: c.textLight)),
                        ]),
                      ),
                      const SizedBox(width: AppSpace.xs),
                      AppButton.tonal(label: 'chat_unblock'.tr, onPressed: () => _unblock(b)),
                    ]),
                  ),
                ),
          ]);
        },
      ),
    );
  }
}

// ── the admins' review ───────────────────────────────────────────────────────────────────────────────────────

class ChatReportsPage extends StatefulWidget {
  const ChatReportsPage({super.key, this.api});
  final ChatApi? api;

  @override
  State<ChatReportsPage> createState() => _ChatReportsPageState();
}

class _ChatReportsPageState extends State<ChatReportsPage> {
  late final ChatApi _a = widget.api ?? ChatHub.instance.api;
  String _status = 'open';
  late Future<(List<ChatReport>, int)> _future = _a.adminReports(status: _status);

  void _reload() => setState(() => _future = _a.adminReports(status: _status));

  Future<void> _review(ChatReport r, String status) async {
    try {
      await _a.reviewReport(r.id, status: status);
      showAppNotice('chat_report_reviewed'.tr);
      _reload();
    } catch (e) {
      showAppNotice(chatErrorText(e), error: true);
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return BasePage(
      appBar: AppHeader(title: 'chat_reports_title'.tr),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, 0),
          child: Wrap(spacing: AppSpace.xs, children: [
            for (final s in const ['open', 'actioned', 'dismissed'])
              ChatFilterChip(
                label: 'chat_status_$s'.tr,
                selected: _status == s,
                onTap: () {
                  _status = s;
                  _reload();
                },
              ),
          ]),
        ),
        Expanded(
          child: FutureBuilder<(List<ChatReport>, int)>(
            future: _future,
            builder: (context, s) {
              if (s.connectionState != ConnectionState.done) return const AppListSkeleton(items: 5);
              if (s.hasError) return AppEmpty(icon: Icons.cloud_off_rounded, title: chatErrorText(s.error!), actionLabel: 'chat_retry'.tr, onAction: _reload);
              final items = s.data!.$1;
              if (items.isEmpty) return AppEmpty(icon: Icons.verified_user_outlined, title: 'chat_reports_none'.tr);
              return ListView.separated(
                padding: const EdgeInsets.all(AppSpace.md),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: AppSpace.sm),
                itemBuilder: (_, i) => _reportCard(context, items[i], c),
              );
            },
          ),
        ),
      ]),
    );
  }

  Widget _reportCard(BuildContext context, ChatReport r, ThemeConfigProvider c) {
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          AppBadgePill('chat_reason_${r.reason}'.tr, color: c.danger),
          const Spacer(),
          Text(AppTime.dateTime(r.createdAt), style: appText(11.5, w: FontWeight.w400, c: c.textLight)),
        ]),
        const SizedBox(height: AppSpace.xs),
        Text('${r.reporter?.name ?? '-'}  →  ${r.target?.name ?? '-'}', maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w600, c: c.textDark)),
        if ((r.note ?? '').isNotEmpty) ...[
          const SizedBox(height: AppSpace.xxs),
          Text(r.note!, style: appText(13, w: FontWeight.w400, c: c.textMedium, h: 1.4)),
        ],
        if (r.snapshot.isNotEmpty) ...[
          const SizedBox(height: AppSpace.xs),
          Container(
            padding: const EdgeInsets.all(AppSpace.sm),
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(AppRadius.chip + 2)),
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final m in r.snapshot)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.xs),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${m['sender_name'] ?? ''}', style: appText(11.5, w: FontWeight.w600, c: '${m['id']}' == '${r.messageId}' ? c.danger : c.textMedium)),
                      Text('${m['body'] ?? 'chat_file'.tr}', style: appText(13, w: FontWeight.w400, c: c.textDark, h: 1.35)),
                    ]),
                  ),
              ]),
            ),
          ),
        ],
        if (r.status == 'open') ...[
          const SizedBox(height: AppSpace.sm),
          Row(children: [
            Expanded(child: AppButton.secondary(label: 'chat_report_dismiss'.tr, onPressed: () => _review(r, 'dismissed'))),
            const SizedBox(width: AppSpace.xs),
            Expanded(child: AppButton.primary(label: 'chat_report_action'.tr, onPressed: () => _review(r, 'actioned'))),
          ]),
        ],
      ]),
    );
  }
}
