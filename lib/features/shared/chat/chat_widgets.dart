// lib/features/shared/chat/chat_widgets.dart — the pieces of every chat screen, plain values only (D-330): one design
// for every role. Colours from context.colors, spacing from AppSpace, type from appText; nothing here reads a provider
// or the network, so the layout harness and the visual renders pump them directly.
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_bidi.dart';
import 'package:flutter_education_app/design/app_display.dart' show syncMotionLoop;
import 'package:flutter_education_app/design/app_kit.dart';

import 'chat_models.dart';
import 'chat_store.dart';

const double kChatListWidth = 380;
const double kChatBubbleMaxWidth = 560;

/// The reading column of a thread on a wide screen: past this a conversation stops feeling like one.
const double kChatColumnMaxWidth = 860;

/// Keeps [child] in the reading column; its background may still span the pane.
Widget chatColumn(Widget child) => Center(heightFactor: 1, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: kChatColumnMaxWidth), child: child));

String chatLevelLabel(String level) => switch (level) {
      'course' => 'chat_level_course'.tr,
      'all_courses' => 'chat_level_all'.tr,
      _ => 'chat_level_person'.tr,
    };

/// A list row's time: the clock today, "Yesterday", the weekday this week, else a short date.
String chatRowTime(DateTime utc, {DateTime? now}) {
  final local = AppTime.toZone(utc);
  final today = AppTime.toZone((now ?? DateTime.now()).toUtc());
  final days = DateTime(today.year, today.month, today.day).difference(DateTime(local.year, local.month, local.day)).inDays;
  if (days <= 0) return AppTime.time(utc);
  if (days == 1) return 'chat_yesterday'.tr;
  if (days < 7) return AppTime.date(utc, pattern: 'EEE');
  return AppTime.date(utc, pattern: 'd/M/yy');
}

/// A date separator's words.
String chatDayLabel(DateTime utc, {DateTime? now}) {
  final local = AppTime.toZone(utc);
  final today = AppTime.toZone((now ?? DateTime.now()).toUtc());
  final days = DateTime(today.year, today.month, today.day).difference(DateTime(local.year, local.month, local.day)).inDays;
  if (days <= 0) return 'chat_today'.tr;
  if (days == 1) return 'chat_yesterday'.tr;
  return AppTime.date(utc, pattern: 'EEEE d MMM');
}

bool chatSameDay(DateTime a, DateTime b) {
  final x = AppTime.toZone(a), y = AppTime.toZone(b);
  return x.year == y.year && x.month == y.month && x.day == y.day;
}

/// A round picture with an online dot (or a group icon).
class ChatAvatar extends StatelessWidget {
  const ChatAvatar({super.key, required this.name, this.url, this.size = 48, this.online = false, this.group = false});

  final String name;
  final String? url;
  final double size;
  final bool online, group;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final avatar = group
        ? Container(
            width: size,
            height: size,
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: c.primaryGradient),
            child: Icon(Icons.groups_rounded, size: size * 0.52, color: c.onHero),
          )
        : AppAvatar(name: name, url: url, size: size);
    if (!online) return avatar;
    final dot = (size * 0.24).clamp(10.0, 15.0);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(children: [
        avatar,
        PositionedDirectional(
          end: 0,
          bottom: 0,
          child: Container(
            width: dot,
            height: dot,
            decoration: BoxDecoration(color: c.success, shape: BoxShape.circle, border: Border.all(color: c.cardBg, width: 2)),
          ),
        ),
      ]),
    );
  }
}

/// One row of the chat list.
class ChatConversationTile extends StatelessWidget {
  const ChatConversationTile({super.key, required this.conversation, required this.myId, this.selected = false, this.typingName, this.draft, this.onTap, this.onMenu, this.now});

  final ChatConversation conversation;
  final int myId;
  final bool selected;
  final String? typingName, draft;
  final VoidCallback? onTap, onMenu;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final conv = conversation;
    final unread = conv.unread > 0;
    final preview = _preview(c);
    final bg = selected ? c.primaryTint : Colors.transparent;
    final line2 = conv.isGroup
        ? 'chat_course_group'.tr
        : conv.child != null
            ? '${'chat_parent_of'.tr} ${conv.child!.name.split(' ').first}'
            : conv.contextLine;
    return Semantics(
      button: true,
      label: '${conv.title}, ${unread ? '${conv.unread} ${'chat_new'.tr}' : ''}',
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: onTap,
          onLongPress: onMenu,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.sm),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ChatAvatar(name: conv.title, url: conv.isGroup ? conv.course?.imageUrl : conv.peer?.imageUrl, size: 50, online: conv.online, group: conv.isGroup && conv.course?.imageUrl == null),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text(conv.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(14.5, w: unread ? FontWeight.w700 : FontWeight.w600, c: c.textDark)),
                    ),
                    if (conv.pinned) Padding(padding: const EdgeInsetsDirectional.only(start: AppSpace.xxs), child: Icon(Icons.push_pin_rounded, size: AppIconSize.xs, color: c.textLight)),
                    if (conv.muted) Padding(padding: const EdgeInsetsDirectional.only(start: AppSpace.xxs), child: Icon(Icons.notifications_off_outlined, size: AppIconSize.xs, color: c.textLight)),
                    const SizedBox(width: AppSpace.xs),
                    Text(chatRowTime(conv.lastAt, now: now), style: appText(11.5, w: unread ? FontWeight.w600 : FontWeight.w400, c: unread ? chatInk(c) : c.textLight)),
                  ]),
                  if (line2.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(line2, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(11.5, w: FontWeight.w500, c: c.textMedium)),
                  ],
                  const SizedBox(height: 3),
                  Row(children: [
                    Expanded(child: preview),
                    if (unread) ...[
                      const SizedBox(width: AppSpace.xs),
                      Container(
                        constraints: const BoxConstraints(minWidth: 21),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: conv.muted ? c.textLight : c.primary, borderRadius: BorderRadius.circular(AppRadius.hero)),
                        alignment: Alignment.center,
                        child: Text(conv.unread > 99 ? '99+' : '${conv.unread}', style: appText(11, w: FontWeight.w700, c: c.onHero)),
                      ),
                    ],
                  ]),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _preview(ThemeConfigProvider c) {
    final style = appText(13, w: conversation.unread > 0 ? FontWeight.w500 : FontWeight.w400, c: conversation.unread > 0 ? c.textDark : c.textMedium);
    if (typingName != null) {
      return Text(conversation.isGroup ? '$typingName ${'chat_is_typing'.tr}' : 'chat_typing'.tr,
          maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13, w: FontWeight.w500, c: chatInk(c)));
    }
    if (draft != null && draft!.trim().isNotEmpty) {
      return Text.rich(
        TextSpan(children: [
          TextSpan(text: '${'chat_draft'.tr}: ', style: appText(13, w: FontWeight.w600, c: c.danger)),
          TextSpan(text: draft!.replaceAll('\n', ' '), style: style),
        ]),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    final last = conversation.last;
    if (last == null) return Text('chat_no_messages'.tr, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    final mine = last.senderId == myId;
    final tick = mine && !conversation.isGroup
        ? chatTickFor(ChatMessage(id: last.id, clientId: '', conversationId: 0, createdAt: last.createdAt), peerReadId: conversation.peerReadId, peerDeliveredId: conversation.peerDeliveredId)
        : null;
    final prefix = !conversation.isGroup
        ? ''
        : mine
            ? '${'chat_you'.tr}: '
            : last.senderName != null
                ? '${last.senderName!.split(' ').first}: '
                : '';
    final (IconData? kindIcon, String body) = switch (last.kind) {
      'image' => (Icons.photo_outlined, last.body.isNotEmpty ? last.body : 'chat_photo'.tr),
      'file' => (Icons.attach_file_rounded, last.body.isNotEmpty ? last.body : 'chat_file'.tr),
      _ => (null, last.body),
    };
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (tick != null) Padding(padding: const EdgeInsetsDirectional.only(end: 3), child: ChatTickIcon(tick: tick, size: 15, muted: c.textLight, read: chatInk(c))),
      if (kindIcon != null) Padding(padding: const EdgeInsetsDirectional.only(end: 3), child: Icon(kindIcon, size: 15, color: c.textLight)),
      Flexible(child: Text('$prefix$body', maxLines: 1, overflow: TextOverflow.ellipsis, style: style)),
    ]);
  }
}

class ChatTickIcon extends StatelessWidget {
  const ChatTickIcon({super.key, required this.tick, required this.muted, required this.read, this.size = 15});

  final ChatTick tick;
  final Color muted, read;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color, String label) = switch (tick) {
      ChatTick.sending => (Icons.schedule_rounded, muted, 'chat_tick_sending'.tr),
      ChatTick.queued => (Icons.cloud_queue_rounded, muted, 'chat_tick_queued'.tr),
      ChatTick.failed => (Icons.error_outline_rounded, context.colors.danger, 'chat_tick_failed'.tr),
      ChatTick.sent => (Icons.check_rounded, muted, 'chat_tick_sent'.tr),
      ChatTick.delivered => (Icons.done_all_rounded, muted, 'chat_tick_delivered'.tr),
      ChatTick.read => (Icons.done_all_rounded, read, 'chat_tick_read'.tr),
    };
    return Semantics(label: label, child: ExcludeSemantics(child: Icon(icon, size: size, color: color)));
  }
}

class ChatDateChip extends StatelessWidget {
  const ChatDateChip({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: AppSpace.sm),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 5),
        decoration: BoxDecoration(color: c.cardBg, borderRadius: BorderRadius.circular(AppRadius.hero), boxShadow: c.cardShadow),
        child: Text(label, style: appText(11.5, w: FontWeight.w600, c: c.textMedium)),
      ),
    );
  }
}

/// The thin "new messages" line above the first unread message.
class ChatUnreadDivider extends StatelessWidget {
  const ChatUnreadDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final line = Expanded(child: Container(height: 1, color: chatInk(c).withValues(alpha: 0.28)));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
      child: Row(children: [
        line,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
          child: Text('chat_new_messages'.tr, style: appText(11.5, w: FontWeight.w700, c: chatInk(c))),
        ),
        line,
      ]),
    );
  }
}

/// Above a thread and an inbox while there is no connection: what happens to what is written meanwhile.
class ChatOfflineStrip extends StatelessWidget {
  const ChatOfflineStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      color: c.warning.withValues(alpha: c.isDark ? 0.18 : 0.12),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
      child: Row(children: [
        Icon(Icons.cloud_off_rounded, size: AppIconSize.xs, color: c.warning),
        const SizedBox(width: AppSpace.xs),
        Expanded(child: Text('chat_offline_strip'.tr, style: appText(12, w: FontWeight.w500, c: c.textDark))),
      ]),
    );
  }
}

/// A section title in the inbox.
class ChatSectionLabel extends StatelessWidget {
  const ChatSectionLabel({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm, AppSpace.sm, AppSpace.sm, AppSpace.xxs),
      child: Text(label, style: appText(12, w: FontWeight.w700, c: c.textLight)),
    );
  }
}

/// The floating "back to the newest message" button, with what came in meanwhile.
class ChatJumpToLatest extends StatelessWidget {
  const ChatJumpToLatest({super.key, required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: count > 0 ? '${'chat_jump_latest'.tr}, $count ${'chat_new'.tr}' : 'chat_jump_latest'.tr,
      child: ExcludeSemantics(
        child: Material(
          color: c.cardBg,
          shape: const CircleBorder(),
          elevation: 3,
          shadowColor: c.textDark.withValues(alpha: 0.3),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: AppTouch.min,
              height: AppTouch.min,
              child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
                Icon(Icons.keyboard_arrow_down_rounded, size: AppIconSize.lg, color: c.textMedium),
                if (count > 0)
                  PositionedDirectional(
                    top: -AppSpace.xxs,
                    end: -AppSpace.xxs,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 20),
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(color: c.primary, borderRadius: BorderRadius.circular(AppRadius.hero)),
                      alignment: Alignment.center,
                      child: Text(count > 99 ? '99+' : '$count', style: appText(11, w: FontWeight.w700, c: c.onHero)),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

const _senderTones = <Color Function(ThemeConfigProvider c)>[_tone0, _tone1, _tone2, _tone3, _tone4];
Color _tone0(ThemeConfigProvider c) => chatInk(c);
Color _tone1(ThemeConfigProvider c) => c.accent2;
Color _tone2(ThemeConfigProvider c) => c.purple;
Color _tone3(ThemeConfigProvider c) => c.success;
Color _tone4(ThemeConfigProvider c) => c.warning;

/// One message. [showSender] draws the name (groups, the first of a run); [runStart] / [runEnd] say where it sits in a
/// run from one person: the inner corners of a run are tight, so a run reads as one block.
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.message,
    required this.mine,
    this.tick,
    this.showSender = false,
    this.runStart = true,
    this.runEnd = true,
    this.maxWidth = kChatBubbleMaxWidth,
    this.imageOf,
    this.onOpenAttachment,
    this.onLongPress,
    this.onRetry,
    this.onDiscard,
  });

  final ChatMessage message;
  final bool mine, showSender, runStart, runEnd;
  final ChatTick? tick;
  final double maxWidth;
  final Future<String> Function(ChatAttachment a)? imageOf;
  final void Function(ChatAttachment a)? onOpenAttachment;
  final VoidCallback? onLongPress, onRetry, onDiscard;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const big = Radius.circular(AppRadius.card + 2);
    const tight = Radius.circular(AppRadius.chip - 2);
    final shape = BorderRadiusDirectional.only(
      topStart: mine ? big : (runStart ? big : tight),
      bottomStart: mine ? big : (runEnd ? big : tight),
      topEnd: mine ? (runStart ? big : tight) : big,
      bottomEnd: mine ? (runEnd ? big : tight) : big,
    );
    final failed = message.sendState == ChatSendState.failed;
    final bg = mine ? (failed ? c.danger.withValues(alpha: c.isDark ? 0.35 : 0.14) : c.primary) : c.cardBg;
    final ink = mine && !failed ? c.onHero : c.textDark;
    final inkSoft = mine && !failed ? c.onHeroMuted : c.textLight;
    final text = (message.body ?? '').trim();
    final hasFiles = message.attachments.isNotEmpty || message.local.isNotEmpty;

    final meta = Row(mainAxisSize: MainAxisSize.min, children: [
      Text(AppTime.time(message.createdAt), style: appText(10.5, w: FontWeight.w400, c: inkSoft)),
      if (mine && tick != null) ...[
        const SizedBox(width: 3),
        ChatTickIcon(tick: tick!, size: 14, muted: inkSoft, read: failed ? c.danger : c.onHero),
      ],
    ]);

    Widget content = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      if (showSender && !mine)
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(
              child: Text(message.senderName ?? '',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12.5, w: FontWeight.w700, c: _senderTones[(message.senderId ?? 0) % _senderTones.length](c))),
            ),
            if (message.senderIsTeacher) ...[
              const SizedBox(width: AppSpace.xxs),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: c.primaryTint, borderRadius: BorderRadius.circular(AppRadius.chip)),
                child: Text('chat_teacher'.tr, style: appText(10, w: FontWeight.w700, c: chatInk(c))),
              ),
            ],
          ]),
        ),
      if (hasFiles) ...[
        for (final a in message.attachments.where((x) => x.image)) _ImagePart(attachment: a, resolve: imageOf, onTap: () => onOpenAttachment?.call(a)),
        for (final a in message.attachments.where((x) => !x.image)) _FilePart(name: a.name, ext: a.ext, size: a.size, mine: mine && !failed, onTap: () => onOpenAttachment?.call(a)),
        for (final f in message.local)
          if (f.isImage && f.bytes != null)
            _LocalImagePart(bytes: f.bytes!, busy: message.sendState == ChatSendState.sending)
          else
            _FilePart(name: f.name, ext: f.name.split('.').last, size: f.size, mine: mine && !failed),
      ],
      if (text.isNotEmpty)
        Padding(
          padding: EdgeInsets.only(top: hasFiles ? AppSpace.xs : 0),
          child: Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: AppSpace.xs,
            children: [
              Text(
                text,
                textDirection: contentDirection(text),
                style: appText(14.5, w: FontWeight.w400, c: ink, h: 1.38),
              ),
              Padding(padding: const EdgeInsets.only(top: 1), child: meta),
            ],
          ),
        )
      else
        Align(alignment: AlignmentDirectional.centerEnd, widthFactor: 1, child: Padding(padding: const EdgeInsets.only(top: AppSpace.xxs), child: meta)),
    ]);
    content = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: shape,
          border: failed ? Border.all(color: c.danger.withValues(alpha: 0.5)) : null,
          boxShadow: mine ? null : c.cardShadow,
        ),
        padding: const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.xs, AppSpace.sm, 6),
        child: content,
      ),
    );

    final body = onRetry == null ? content : InkWell(borderRadius: BorderRadius.circular(AppRadius.card), onTap: onRetry, child: content);

    return Align(
      alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: Padding(
        padding: EdgeInsets.only(top: runStart ? AppSpace.sm : 2),
        child: Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          GestureDetector(onLongPress: onLongPress, child: body),
          if (message.sendState == ChatSendState.queued)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text('chat_queued_note'.tr, style: appText(11, w: FontWeight.w500, c: c.textLight)),
            ),
          if (failed && onRetry != null) _FailedActions(error: message.error, onRetry: onRetry!, onDiscard: onDiscard),
        ]),
      ),
    );
  }
}

class _FailedActions extends StatelessWidget {
  const _FailedActions({this.error, required this.onRetry, this.onDiscard});
  final String? error;
  final VoidCallback onRetry;
  final VoidCallback? onDiscard;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lost = error == ChatMessage.lostFileError;
    final words = lost ? 'chat_attachment_lost'.tr : (error ?? 'chat_not_sent'.tr);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.xxs),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(child: Text(words, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(11.5, w: FontWeight.w600, c: c.danger))),
        if (!lost) ...[
          const SizedBox(width: AppSpace.xxs),
          TextButton.icon(
            style: TextButton.styleFrom(minimumSize: const Size(0, AppTouch.min), padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs), foregroundColor: c.danger),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: AppIconSize.xs),
            label: Text('chat_retry'.tr, style: appText(12, w: FontWeight.w700, c: c.danger)),
          ),
        ],
        if (onDiscard != null)
          IconButton(
            tooltip: 'chat_delete_unsent'.tr,
            constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
            padding: EdgeInsets.zero,
            icon: Icon(Icons.delete_outline_rounded, size: AppIconSize.sm, color: c.textLight),
            onPressed: onDiscard,
          ),
      ]),
    );
  }
}

/// The brand colour as readable ink on the current surface (a dark surface needs the lighter tone).
Color chatInk(ThemeConfigProvider c) => c.isDark ? c.heroTint(c.primary, 0.55) : c.primary;

/// A picked image still going out: its own bytes, dimmed while it uploads.
class _LocalImagePart extends StatelessWidget {
  const _LocalImagePart({required this.bytes, required this.busy});
  final Uint8List bytes;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card - 2),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 280),
          child: Stack(alignment: Alignment.center, children: [
            Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, _, _) => ColoredBox(color: c.inputBg, child: const SizedBox(width: 120, height: 90))),
            if (busy) Positioned.fill(child: ColoredBox(color: c.background.withValues(alpha: 0.35))),
            if (busy) const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
          ]),
        ),
      ),
    );
  }
}

class _ImagePart extends StatefulWidget {
  const _ImagePart({required this.attachment, this.resolve, this.onTap});
  final ChatAttachment attachment;
  final Future<String> Function(ChatAttachment a)? resolve;
  final VoidCallback? onTap;

  @override
  State<_ImagePart> createState() => _ImagePartState();
}

class _ImagePartState extends State<_ImagePart> {
  Future<String>? _url;

  @override
  void initState() {
    super.initState();
    _url = widget.resolve?.call(widget.attachment);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = widget.attachment;
    final w = (a.width ?? 4).toDouble(), h = (a.height ?? 3).toDouble();
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card - 2),
        child: AspectRatio(
          aspectRatio: (w / h).clamp(0.62, 1.8),
          child: InkWell(
            onTap: widget.onTap,
            child: _url == null
                ? ColoredBox(color: c.inputBg, child: Icon(Icons.image_rounded, color: c.textLight))
                : FutureBuilder<String>(
                    future: _url,
                    builder: (_, s) => s.data == null
                        ? ColoredBox(color: c.inputBg, child: const AppSkeletonBox())
                        : CachedNetworkImage(
                            imageUrl: s.data!,
                            cacheKey: 'chat-attachment-${a.id}', // the link is signed and short-lived; the picture is not
                            fit: BoxFit.cover,
                            placeholder: (_, _) => ColoredBox(color: c.inputBg),
                            errorWidget: (_, _, _) => ColoredBox(color: c.inputBg, child: Icon(Icons.broken_image_outlined, color: c.textLight)),
                          ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _FilePart extends StatelessWidget {
  const _FilePart({required this.name, required this.ext, required this.size, required this.mine, this.onTap});
  final String name, ext;
  final int size;
  final bool mine;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bg = mine ? c.heroGlass : c.inputBg;
    final ink = mine ? c.onHero : c.textDark;
    final soft = mine ? c.onHeroMuted : c.textLight;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.chip + 2),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.chip + 2),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.xs),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: mine ? c.heroGlassBorder : c.primaryTint, borderRadius: BorderRadius.circular(AppRadius.chip)),
                child: Text(ext.toUpperCase(), maxLines: 1, style: appText(10.5, w: FontWeight.w800, c: mine ? c.onHero : chatInk(c))),
              ),
              const SizedBox(width: AppSpace.xs),
              Flexible(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13, w: FontWeight.w600, c: ink)),
                  if (size > 0) Text(ltrIsolate(fileSizeLabel(size)), style: appText(11, w: FontWeight.w400, c: soft)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Three dots rising in turn in a bubble (parked under Reduce motion).
class ChatTypingBubble extends StatefulWidget {
  const ChatTypingBubble({super.key, this.name});
  final String? name;

  @override
  State<ChatTypingBubble> createState() => _ChatTypingBubbleState();
}

class _ChatTypingBubbleState extends State<ChatTypingBubble> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    syncMotionLoop(context, _c);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsets.only(top: AppSpace.xs),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 10),
        decoration: BoxDecoration(color: c.cardBg, borderRadius: BorderRadius.circular(AppRadius.card + 2), boxShadow: c.cardShadow),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (widget.name != null) ...[
            ConstrainedBox(constraints: const BoxConstraints(maxWidth: 150), child: Text(widget.name!, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(11.5, w: FontWeight.w500, c: c.textMedium))),
            const SizedBox(width: AppSpace.xs),
          ],
          AnimatedBuilder(
            animation: _c,
            builder: (_, _) => Row(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < 3; i++) ...[
                Transform.translate(
                  offset: Offset(0, -2.5 * _pulse((_c.value - i * 0.18) % 1.0)),
                  child: Container(width: 6, height: 6, decoration: BoxDecoration(color: c.textLight.withValues(alpha: 0.55 + 0.45 * _pulse((_c.value - i * 0.18) % 1.0)), shape: BoxShape.circle)),
                ),
                if (i < 2) const SizedBox(width: 4),
              ],
            ]),
          ),
        ]),
      ),
    );
  }

  double _pulse(double v) => v < 0.5 ? (v * 2) : (2 - v * 2);
}

/// The calm line that replaces the composer when messaging is off (the server said why).
class ChatComposerNotice extends StatelessWidget {
  const ChatComposerNotice({super.key, required this.state, this.onUnblock, this.reason});
  final ChatComposerState state;
  final VoidCallback? onUnblock;

  /// The server's own words, when it gave some.
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (IconData icon, String text) = switch (state) {
      ChatComposerState.blocked => (Icons.chat_bubble_outline_rounded, 'chat_state_blocked'.tr),
      ChatComposerState.youBlocked => (Icons.block_rounded, 'chat_state_you_blocked'.tr),
      ChatComposerState.closed => (Icons.lock_outline_rounded, 'chat_state_closed'.tr),
      ChatComposerState.disabled => (Icons.lock_outline_rounded, 'chat_state_disabled'.tr),
      ChatComposerState.requestSent => (Icons.mark_email_read_outlined, reason ?? 'chat_state_request_sent'.tr),
      _ => (Icons.schedule_rounded, 'chat_state_ended'.tr),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.sm),
      decoration: BoxDecoration(color: c.cardBg, border: Border(top: BorderSide(color: c.divider.withValues(alpha: 0.5)))),
      child: SafeArea(
        top: false,
        child: chatColumn(Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(icon, size: AppIconSize.md, color: c.textLight),
            const SizedBox(width: AppSpace.sm),
            Expanded(child: Text(text, style: appText(13.5, w: FontWeight.w500, c: c.textMedium, h: 1.35))),
          ]),
          if (state == ChatComposerState.youBlocked && onUnblock != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xs),
              child: Align(alignment: AlignmentDirectional.centerEnd, child: AppButton.tonal(label: 'chat_unblock'.tr, onPressed: onUnblock)),
            ),
        ])),
      ),
    );
  }
}

/// A file waiting in the composer, with its remove button.
class ChatPendingFileChip extends StatelessWidget {
  const ChatPendingFileChip({super.key, required this.name, required this.onRemove, this.preview});
  final String name;
  final VoidCallback onRemove;

  /// A picked image's bytes: the chip shows the picture.
  final Uint8List? preview;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      constraints: const BoxConstraints(maxWidth: 230),
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm, AppSpace.xxs, AppSpace.xxs, AppSpace.xxs),
      decoration: BoxDecoration(color: c.primaryTint, borderRadius: BorderRadius.circular(AppRadius.hero)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (preview != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.chip),
            child: Image.memory(preview!, width: 40, height: 40, fit: BoxFit.cover, errorBuilder: (_, _, _) => Icon(Icons.image_outlined, size: AppIconSize.sm, color: c.primary)),
          )
        else
          Icon(Icons.attach_file_rounded, size: AppIconSize.xs, color: c.primary),
        const SizedBox(width: AppSpace.xxs),
        Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12, w: FontWeight.w600, c: c.textDark))),
        const SizedBox(width: AppSpace.xxs),
        IconButton(
          tooltip: 'chat_remove'.tr,
          constraints: const BoxConstraints(minWidth: AppTouch.min - 12, minHeight: AppTouch.min - 12),
          padding: EdgeInsets.zero,
          icon: Icon(Icons.close_rounded, size: AppIconSize.sm, color: c.textMedium),
          onPressed: onRemove,
        ),
      ]),
    );
  }
}

/// A small tile of a filter row.
class ChatFilterChip extends StatelessWidget {
  const ChatFilterChip({super.key, required this.label, required this.selected, required this.onTap, this.icon});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: selected ? c.primary : c.cardBg,
      borderRadius: BorderRadius.circular(AppRadius.hero),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.hero),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 36),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
          decoration: selected ? null : BoxDecoration(borderRadius: BorderRadius.circular(AppRadius.hero), border: Border.all(color: c.divider.withValues(alpha: 0.6))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: AppIconSize.xs, color: selected ? c.onHero : c.textMedium), const SizedBox(width: 5)],
            Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12.5, w: FontWeight.w600, c: selected ? c.onHero : c.textMedium))),
          ]),
        ),
      ),
    );
  }
}

/// `true` when the app is showing Arabic.
bool get chatIsAr => AppConfig.lang == 'ar';

/// Enter sends on a keyboard-first device (the web on a computer, Windows, macOS, Linux); a phone's Enter is a new line.
bool chatEnterSendsOn(TargetPlatform p) => p != TargetPlatform.android && p != TargetPlatform.iOS && p != TargetPlatform.fuchsia;

bool get chatEnterSends => chatEnterSendsOn(defaultTargetPlatform);

/// Pure: whether this key press is "send". Shift+Enter stays a new line; an IME still composing keeps its Enter.
bool chatIsSendKey(KeyEvent e, {required bool enterSends, required bool shift, required bool composing}) {
  if (e is! KeyDownEvent || !enterSends || shift || composing) return false;
  return e.logicalKey == LogicalKeyboardKey.enter || e.logicalKey == LogicalKeyboardKey.numpadEnter;
}

/// The writing box of a chat, plain values only: grows to six lines, holds its focus, sends on Enter where that fits.
class ChatComposerBar extends StatelessWidget {
  const ChatComposerBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.onChanged,
    this.onAttach,
    this.files = const [],
    this.onRemoveFile,
    this.enterSends = false,
    this.maxLength = 4000,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final ValueChanged<String> onChanged;
  final VoidCallback? onAttach;
  final List<ChatLocalFile> files;
  final void Function(int index)? onRemoveFile;
  final bool enterSends;
  final int maxLength;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final canSend = controller.text.trim().isNotEmpty || files.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(AppSpace.xs),
      decoration: BoxDecoration(color: c.cardBg, border: Border(top: BorderSide(color: c.divider.withValues(alpha: 0.5)))),
      child: SafeArea(
        top: false,
        child: chatColumn(Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (files.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xs),
              child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                for (var i = 0; i < files.length; i++)
                  ChatPendingFileChip(name: files[i].name, preview: files[i].isImage ? files[i].bytes : null, onRemove: () => onRemoveFile?.call(i)),
              ]),
            ),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (onAttach != null) IconButton(tooltip: 'chat_attach'.tr, icon: Icon(Icons.attach_file_rounded, color: c.textMedium), onPressed: onAttach),
            Expanded(
              child: Focus(
                skipTraversal: true,
                canRequestFocus: false,
                onKeyEvent: (node, ev) {
                  final composing = controller.value.composing;
                  final send = chatIsSendKey(ev, enterSends: enterSends, shift: HardwareKeyboard.instance.isShiftPressed, composing: composing.isValid && !composing.isCollapsed);
                  if (!send) return KeyEventResult.ignored;
                  onSend();
                  return KeyEventResult.handled;
                },
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  autofocus: enterSends,
                  minLines: 1,
                  maxLines: 6,
                  maxLength: maxLength,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  textDirection: controller.text.isEmpty ? null : contentDirection(controller.text),
                  style: appText(14.5, w: FontWeight.w400, c: c.textDark),
                  onChanged: onChanged,
                  decoration: InputDecoration(
                    hintText: 'chat_message_hint'.tr,
                    counterText: '',
                    filled: true,
                    fillColor: c.inputBg,
                    contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide(color: c.primary.withValues(alpha: 0.45), width: 1.2)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpace.xs),
            ChatSendButton(enabled: canSend, onTap: onSend),
          ]),
        ])),
      ),
    );
  }
}

class ChatSendButton extends StatelessWidget {
  const ChatSendButton({super.key, required this.enabled, required this.onTap});
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: 'chat_send'.tr,
      enabled: enabled,
      child: InkResponse(
        onTap: enabled ? onTap : null,
        radius: AppTouch.min / 2 + 4,
        child: AnimatedContainer(
          duration: AppMotion.of(context).fast,
          width: AppTouch.min,
          height: AppTouch.min,
          decoration: BoxDecoration(shape: BoxShape.circle, gradient: enabled ? c.primaryGradient : null, color: enabled ? null : c.inputBg),
          child: Icon(Icons.send_rounded, size: AppIconSize.md, color: enabled ? c.onHero : c.textLight),
        ),
      ),
    );
  }
}

/// One calm row above the inbox: "Message requests (n)".
class ChatRequestsRow extends StatelessWidget {
  const ChatRequestsRow({super.key, required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs, vertical: AppSpace.xxs),
      child: Material(
        color: c.primaryTint,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.sm),
            child: Row(children: [
              Icon(Icons.mark_email_unread_outlined, size: AppIconSize.md, color: chatInk(c)),
              const SizedBox(width: AppSpace.sm),
              Expanded(child: Text('chat_requests'.tr, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13.5, w: FontWeight.w600, c: c.textDark))),
              Container(
                constraints: const BoxConstraints(minWidth: 22),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: c.primary, borderRadius: BorderRadius.circular(AppRadius.hero)),
                alignment: Alignment.center,
                child: Text(count > 99 ? '99+' : '$count', style: appText(11, w: FontWeight.w700, c: c.onHero)),
              ),
              const SizedBox(width: AppSpace.xxs),
              Icon(Icons.chevron_right_rounded, size: AppIconSize.md, color: c.textLight),
            ]),
          ),
        ),
      ),
    );
  }
}

/// One message request in its section: who, what they wrote, and the three answers.
class ChatRequestCard extends StatelessWidget {
  const ChatRequestCard({super.key, required this.conversation, this.onOpen, required this.onAccept, required this.onDecline, required this.onBlock, this.busy = false, this.now});
  final ChatConversation conversation;
  final VoidCallback? onOpen;
  final VoidCallback onAccept, onDecline, onBlock;
  final bool busy;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final conv = conversation;
    final body = conv.last?.body ?? '';
    return Container(
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(color: c.cardBg, borderRadius: BorderRadius.circular(AppRadius.card), boxShadow: c.cardShadow),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ChatAvatar(name: conv.title, url: conv.peer?.imageUrl, size: 44),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(conv.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(14.5, w: FontWeight.w700, c: c.textDark))),
                  const SizedBox(width: AppSpace.xs),
                  Text(chatRowTime(conv.lastAt, now: now), style: appText(11.5, w: FontWeight.w400, c: c.textLight)),
                ]),
                if (body.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.xxs),
                  Text(body, maxLines: 3, overflow: TextOverflow.ellipsis, textDirection: contentDirection(body), style: appText(13, w: FontWeight.w400, c: c.textMedium, h: 1.35)),
                ],
              ]),
            ),
          ]),
        ),
        const SizedBox(height: AppSpace.sm),
        ChatRequestActions(onAccept: onAccept, onDecline: onDecline, onBlock: onBlock, busy: busy),
      ]),
    );
  }
}

/// Accept is the answer the screen expects; Decline is quiet; Block is there, and last.
class ChatRequestActions extends StatelessWidget {
  const ChatRequestActions({super.key, required this.onAccept, required this.onDecline, required this.onBlock, this.busy = false});
  final VoidCallback onAccept, onDecline, onBlock;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, alignment: WrapAlignment.end, crossAxisAlignment: WrapCrossAlignment.center, children: [
      TextButton(onPressed: busy ? null : onBlock, child: Text('chat_block'.tr, style: appText(13, w: FontWeight.w600, c: c.danger))),
      AppButton.tonal(label: 'chat_request_decline'.tr, onPressed: busy ? null : onDecline),
      AppButton(label: 'chat_request_accept'.tr, onPressed: busy ? null : onAccept),
    ]);
  }
}

/// In a request I received, the composer's place: what this is and the three answers.
class ChatRequestDecisionBar extends StatelessWidget {
  const ChatRequestDecisionBar({super.key, required this.onAccept, required this.onDecline, required this.onBlock, this.busy = false, this.reason});
  final VoidCallback onAccept, onDecline, onBlock;
  final bool busy;
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(color: c.cardBg, border: Border(top: BorderSide(color: c.divider.withValues(alpha: 0.5)))),
      child: SafeArea(
        top: false,
        child: chatColumn(Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text(reason ?? 'chat_request_received_body'.tr, style: appText(13.5, w: FontWeight.w500, c: c.textMedium, h: 1.35)),
          const SizedBox(height: AppSpace.sm),
          ChatRequestActions(onAccept: onAccept, onDecline: onDecline, onBlock: onBlock, busy: busy),
        ])),
      ),
    );
  }
}
