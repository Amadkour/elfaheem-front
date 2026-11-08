// lib/features/shared/chat/chat_widgets.dart — the pieces of every chat screen, plain values only (D-330): one design
// for every role. Colours from context.colors, spacing from AppSpace, type from appText; nothing here reads a provider
// or the network, so the layout harness and the visual renders pump them directly.
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_bidi.dart';
import 'package:flutter_education_app/design/app_display.dart' show syncMotionLoop;
import 'package:flutter_education_app/design/app_kit.dart';

import 'chat_models.dart';
import 'chat_store.dart';

const double kChatListWidth = 380;
const double kChatBubbleMaxWidth = 560;

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
    final prefix = conversation.isGroup && last.senderName != null && !mine ? '${last.senderName!.split(' ').first}: ' : '';
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

const _senderTones = <Color Function(ThemeConfigProvider c)>[_tone0, _tone1, _tone2, _tone3, _tone4];
Color _tone0(ThemeConfigProvider c) => chatInk(c);
Color _tone1(ThemeConfigProvider c) => c.accent2;
Color _tone2(ThemeConfigProvider c) => c.purple;
Color _tone3(ThemeConfigProvider c) => c.success;
Color _tone4(ThemeConfigProvider c) => c.warning;

/// One message. [showSender] draws the name (groups, the first of a run); [tail] the pointed corner of the last of a run.
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.message,
    required this.mine,
    this.tick,
    this.showSender = false,
    this.tail = true,
    this.maxWidth = kChatBubbleMaxWidth,
    this.imageOf,
    this.onOpenAttachment,
    this.onLongPress,
    this.onRetry,
  });

  final ChatMessage message;
  final bool mine, showSender, tail;
  final ChatTick? tick;
  final double maxWidth;
  final Future<String> Function(ChatAttachment a)? imageOf;
  final void Function(ChatAttachment a)? onOpenAttachment;
  final VoidCallback? onLongPress, onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const r = Radius.circular(AppRadius.card + 2);
    const s = Radius.circular(5);
    final shape = BorderRadiusDirectional.only(
      topStart: mine ? r : (tail ? s : r),
      topEnd: mine ? (tail ? s : r) : r,
      bottomStart: r,
      bottomEnd: r,
    );
    final bg = mine ? c.primary : c.cardBg;
    final ink = mine ? c.onHero : c.textDark;
    final inkSoft = mine ? c.onHeroMuted : c.textLight;
    final failed = message.sendState == ChatSendState.failed;
    final text = (message.body ?? '').trim();
    final hasFiles = message.attachments.isNotEmpty || message.local.isNotEmpty;

    final meta = Row(mainAxisSize: MainAxisSize.min, children: [
      Text(AppTime.time(message.createdAt), style: appText(10.5, w: FontWeight.w400, c: inkSoft)),
      if (mine && tick != null) ...[
        const SizedBox(width: 3),
        ChatTickIcon(tick: tick!, size: 14, muted: inkSoft, read: c.onHero),
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
        for (final a in message.attachments.where((x) => !x.image)) _FilePart(name: a.name, ext: a.ext, size: a.size, mine: mine, onTap: () => onOpenAttachment?.call(a)),
        for (final f in message.local) _FilePart(name: f.name, ext: f.name.split('.').last, size: f.size, mine: mine),
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
          boxShadow: mine ? null : c.cardShadow,
        ),
        padding: const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.xs, AppSpace.sm, 6),
        child: content,
      ),
    );

    return Align(
      alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: Padding(
        padding: EdgeInsets.only(top: tail ? AppSpace.xs : 2),
        child: Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          GestureDetector(onLongPress: onLongPress, child: content),
          if (failed && onRetry != null)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: InkWell(
                onTap: onRetry,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.refresh_rounded, size: AppIconSize.xs, color: c.danger),
                    const SizedBox(width: 3),
                    Flexible(child: Text(message.error ?? 'chat_tap_retry'.tr, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(11.5, w: FontWeight.w600, c: c.danger))),
                  ]),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// The brand colour as readable ink on the current surface (a dark surface needs the lighter tone).
Color chatInk(ThemeConfigProvider c) => c.isDark ? c.heroTint(c.primary, 0.55) : c.primary;

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
                        : CachedNetworkImage(imageUrl: s.data!, fit: BoxFit.cover, placeholder: (_, _) => ColoredBox(color: c.inputBg)),
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
                child: Text(ext.toUpperCase(), maxLines: 1, style: appText(10.5, w: FontWeight.w800, c: mine ? c.onHero : c.primary)),
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
  const ChatComposerNotice({super.key, required this.state, this.onUnblock});
  final ChatComposerState state;
  final VoidCallback? onUnblock;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (IconData icon, String text) = switch (state) {
      ChatComposerState.blocked => (Icons.chat_bubble_outline_rounded, 'chat_state_blocked'.tr),
      ChatComposerState.youBlocked => (Icons.block_rounded, 'chat_state_you_blocked'.tr),
      ChatComposerState.closed => (Icons.lock_outline_rounded, 'chat_state_closed'.tr),
      ChatComposerState.disabled => (Icons.lock_outline_rounded, 'chat_state_disabled'.tr),
      _ => (Icons.schedule_rounded, 'chat_state_ended'.tr),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.sm),
      decoration: BoxDecoration(color: c.cardBg, border: Border(top: BorderSide(color: c.divider.withValues(alpha: 0.5)))),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
        ]),
      ),
    );
  }
}

/// A file waiting in the composer, with its remove button.
class ChatPendingFileChip extends StatelessWidget {
  const ChatPendingFileChip({super.key, required this.name, required this.onRemove});
  final String name;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      constraints: const BoxConstraints(maxWidth: 230),
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm, AppSpace.xxs, AppSpace.xxs, AppSpace.xxs),
      decoration: BoxDecoration(color: c.primaryTint, borderRadius: BorderRadius.circular(AppRadius.hero)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
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
