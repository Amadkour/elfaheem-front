// lib/features/messaging/chat/chat_widgets.dart — the pieces of every chat screen, plain values only (D-330, D-541): one
// design for every role. Colours from context.colors, spacing from AppSpace, type from appText; nothing here reads a
// provider or the network, so the layout harness and the visual renders pump them directly. A message itself is in
// chat_bubble.dart.
library;

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_bidi.dart';
import 'package:flutter_education_app/design/app_display.dart' show syncMotionLoop;
import 'package:flutter_education_app/design/app_kit.dart';

import 'package:flutter_education_app/features/messaging/chat/chat_bubble.dart';
import 'package:flutter_education_app/features/messaging/chat/chat_models.dart';
import 'package:flutter_education_app/features/messaging/chat/chat_store.dart';

export 'package:flutter_education_app/features/messaging/chat/chat_bubble.dart';

/// The side-by-side list: 30 % of the window, between a usable and a sensible width.
const double kChatListWidth = 380;
double chatListWidth(double window) => (window * 0.3).clamp(340.0, 440.0);

const double kChatBubbleMaxWidth = 620;

/// The reading column of a thread on a very wide screen. A window is not left with empty sides: the bubbles only stop
/// spreading further apart.
const double kChatColumnMaxWidth = 1120;

/// One bar's height in the inbox and the open chat, so the two headers share one line across the split.
const double kChatBarHeight = 64;

/// A bubble's widest: a phone's bubble nearly fills the row, a wide column keeps lines short enough to read.
double chatBubbleWidth(double column) => column < 600 ? (column * 0.84).clamp(220.0, kChatBubbleMaxWidth) : (column * 0.68).clamp(320.0, kChatBubbleMaxWidth);

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
  const ChatAvatar({super.key, required this.name, this.url, this.size = 48, this.online = false, this.group = false, this.ring});

  final String name;
  final String? url;
  final double size;
  final bool online, group;

  /// The colour behind the avatar, so the online dot's edge matches the row.
  final Color? ring;

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
    final dot = (size * 0.26).clamp(11.0, 15.0);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(children: [
        avatar,
        PositionedDirectional(
          end: 0,
          bottom: 0,
          child: Semantics(
            label: 'chat_online'.tr,
            child: Container(
              width: dot,
              height: dot,
              decoration: BoxDecoration(color: c.success, shape: BoxShape.circle, border: Border.all(color: ring ?? c.cardBg, width: 2)),
            ),
          ),
        ),
      ]),
    );
  }
}

/// A count: the brand's colour, or a quiet grey when the chat is muted.
class ChatCountPill extends StatelessWidget {
  const ChatCountPill({super.key, required this.count, this.muted = false});
  final int count;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bg = muted ? c.textLight : c.primary;
    return Container(
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.pill)),
      alignment: Alignment.center,
      child: Text(count > 99 ? '99+' : '$count', style: appText(11, w: FontWeight.w600, c: chatReadableOn(bg, c.onHero))),
    );
  }
}

/// One row of the chat list.
class ChatConversationTile extends StatefulWidget {
  const ChatConversationTile({super.key, required this.conversation, required this.myId, this.selected = false, this.typingName, this.draft, this.onTap, this.onMenu, this.now, this.pointerFirst = false});

  final ChatConversation conversation;
  final int myId;
  final bool selected, pointerFirst;
  final String? typingName, draft;
  final VoidCallback? onTap;

  /// The row's menu: a rectangle to open it at (a mouse), or null for a sheet (a long press).
  final void Function(Rect? anchor)? onMenu;
  final DateTime? now;

  @override
  State<ChatConversationTile> createState() => _ChatConversationTileState();
}

class _ChatConversationTileState extends State<ChatConversationTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final conv = widget.conversation;
    final unread = conv.unread > 0;
    final preview = _preview(c);
    final bg = widget.selected ? c.primaryTint : Colors.transparent;
    final child = conv.child;
    final who = conv.isGroup
        ? null
        : child != null
            ? '${'chat_parent_of'.tr} ${child.name.split(' ').first}'
            : null;
    final showMenu = _hover && widget.onMenu != null;
    return Semantics(
      button: true,
      selected: widget.selected,
      label: '${conv.title}, ${unread ? '${conv.unread} ${'chat_new'.tr}' : ''}',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.chip + 2),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.chip + 2),
            onTap: widget.onTap,
            onLongPress: widget.onMenu == null ? null : () => widget.onMenu!(null),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs + 2, vertical: 10),
              child: Row(children: [
                ChatAvatar(name: conv.title, url: conv.isGroup ? conv.course?.imageUrl : conv.peer?.imageUrl, size: 48, online: conv.online, group: conv.isGroup && conv.course?.imageUrl == null, ring: widget.selected ? c.primaryTint : null),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(text: conv.title, style: appText(14.5, w: unread ? FontWeight.w600 : FontWeight.w500, c: c.textDark)),
                            if (who != null) TextSpan(text: '  $who', style: appText(11.5, w: FontWeight.w500, c: c.textMedium)),
                          ]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppSpace.xs),
                      Text(chatRowTime(conv.lastAt, now: widget.now), style: appText(11.5, w: unread ? FontWeight.w600 : FontWeight.w400, c: unread ? chatInk(c) : c.textMedium)),
                    ]),
                    const SizedBox(height: 3),
                    SizedBox(
                      height: 20,
                      child: Row(children: [
                        Expanded(child: Align(alignment: AlignmentDirectional.centerStart, child: preview)),
                        if (conv.muted) Padding(padding: const EdgeInsetsDirectional.only(start: AppSpace.xxs), child: Icon(Icons.notifications_off_outlined, size: AppIconSize.sm, color: c.textLight)),
                        if (conv.pinned) Padding(padding: const EdgeInsetsDirectional.only(start: AppSpace.xxs), child: Icon(Icons.push_pin_rounded, size: AppIconSize.sm, color: c.textLight)),
                        if (unread) ...[
                          const SizedBox(width: AppSpace.xxs + 2),
                          ChatCountPill(count: conv.unread, muted: conv.muted),
                        ],
                        if (showMenu) ...[
                          const SizedBox(width: AppSpace.xxs),
                          Builder(builder: (context) => SizedBox(
                                width: 24,
                                height: 20,
                                child: IconButton(
                                  tooltip: 'chat_more'.tr,
                                  padding: EdgeInsets.zero,
                                  iconSize: AppIconSize.lg - 2,
                                  icon: Icon(Icons.expand_more_rounded, color: c.textMedium),
                                  onPressed: () {
                                    final box = context.findRenderObject() as RenderBox?;
                                    widget.onMenu!(box == null ? null : box.localToGlobal(Offset.zero) & box.size);
                                  },
                                ),
                              )),
                        ],
                      ]),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _preview(ThemeConfigProvider c) {
    final conversation = widget.conversation;
    final unread = conversation.unread > 0;
    final style = appText(13, w: unread ? FontWeight.w500 : FontWeight.w400, c: unread ? c.textDark : c.textMedium, h: 1.25);
    final typingName = widget.typingName;
    if (typingName != null) {
      return Text(conversation.isGroup ? '$typingName ${'chat_is_typing'.tr}' : 'chat_typing'.tr,
          maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13, w: FontWeight.w500, c: chatInk(c), h: 1.25));
    }
    final draft = widget.draft;
    if (draft != null && draft.trim().isNotEmpty) {
      return Text.rich(
        TextSpan(children: [
          TextSpan(text: '${'chat_draft'.tr}: ', style: appText(13, w: FontWeight.w600, c: c.danger, h: 1.25)),
          TextSpan(text: draft.replaceAll('\n', ' '), style: style),
        ]),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    final last = conversation.last;
    if (last == null) return Text('chat_no_messages'.tr, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    if (last.deleted) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.block_rounded, size: AppIconSize.xs, color: c.textLight),
        const SizedBox(width: 3),
        Flexible(child: Text('chat_deleted'.tr, maxLines: 1, overflow: TextOverflow.ellipsis, style: style.copyWith(fontStyle: FontStyle.italic))),
      ]);
    }
    final mine = last.senderId == widget.myId;
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
    final line = body.replaceAll('\n', ' ');
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (tick != null) Padding(padding: const EdgeInsetsDirectional.only(end: 3), child: ChatTickIcon(tick: tick, size: 15, muted: c.textLight, read: chatInk(c))),
      if (kindIcon != null) Padding(padding: const EdgeInsetsDirectional.only(end: 3), child: Icon(kindIcon, size: 15, color: c.textLight)),
      Flexible(child: Text('$prefix$line', maxLines: 1, overflow: TextOverflow.ellipsis, style: style, textDirection: prefix.isEmpty ? contentDirection(line) : null)),
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
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs),
        decoration: BoxDecoration(
          color: c.cardBg,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: c.divider, width: AppBorder.hairline),
        ),
        child: Text(label, style: appText(11.5, w: FontWeight.w600, c: c.textMedium)),
      ),
    );
  }
}

/// The "new messages" band above the first unread message.
class ChatUnreadDivider extends StatelessWidget {
  const ChatUnreadDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final line = Expanded(child: Container(height: 1, color: chatInk(c).withValues(alpha: 0.32)));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
      child: Row(children: [
        line,
        Container(
          margin: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs),
          decoration: BoxDecoration(color: c.blockEmerald, borderRadius: BorderRadius.circular(AppRadius.pill)),
          child: Text('chat_new_messages'.tr, style: appText(11.5, w: FontWeight.w600, c: c.blockAccentInk(c.primary, c.blockEmerald))),
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
        child: Tooltip(
          message: 'chat_jump_latest'.tr,
          child: Material(
            color: c.cardBg,
            shape: const CircleBorder(),
            elevation: 3,
            shadowColor: c.shadowTone,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(
                width: AppTouch.min,
                height: AppTouch.min,
                child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
                  Icon(Icons.keyboard_double_arrow_down_rounded, size: AppIconSize.lg, color: c.textMedium),
                  if (count > 0) PositionedDirectional(top: -AppSpace.xxs, end: -AppSpace.xxs, child: ChatCountPill(count: count)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The brand colour as readable ink on the current surface (a dark surface needs the lighter tone).
Color chatInk(ThemeConfigProvider c) => chatBrandOn(c.cardBg, c.isDark ? c.heroTint(c.primary, 0.55) : c.primary);

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
    final rtl = Directionality.of(context) == TextDirection.rtl;
    const big = Radius.circular(AppRadius.card - 1);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsetsDirectional.only(top: AppSpace.xs, start: ChatBubbleBorder.tail),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 12),
        decoration: ShapeDecoration(
          color: c.cardBg,
          shape: ChatBubbleBorder(radius: BorderRadiusDirectional.only(topStart: big, topEnd: big, bottomEnd: big, bottomStart: const Radius.circular(3)).resolve(Directionality.of(context)), tailRight: rtl, side: BorderSide(color: c.divider, width: AppBorder.hairline)),
        ),
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

/// A thread loading: bubbles, not rows.
class ChatThreadSkeleton extends StatelessWidget {
  const ChatThreadSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const rows = [(false, 210.0, 16.0), (false, 150.0, 16.0), (true, 240.0, 16.0), (false, 280.0, 40.0), (true, 130.0, 16.0), (true, 220.0, 40.0), (false, 180.0, 16.0)];
    return ExcludeSemantics(
      child: LayoutBuilder(builder: (context, box) {
        return OverflowBox(
          alignment: Alignment.bottomCenter,
          maxHeight: double.infinity,
          child: chatColumn(Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final (mine, w, h) in rows)
                Align(
                  alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
                  child: Container(
                    margin: const EdgeInsets.only(top: AppSpace.xs),
                    width: w.clamp(0.0, box.maxWidth * 0.75),
                    padding: const EdgeInsets.all(AppSpace.sm),
                    decoration: BoxDecoration(color: mine ? c.blockEmerald : c.cardBg, borderRadius: BorderRadius.circular(AppRadius.card - 1)),
                    child: AppSkeletonBox(height: h),
                  ),
                ),
            ]),
          )),
        );
      }),
    );
  }
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
    final unblock = state == ChatComposerState.youBlocked && onUnblock != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
      decoration: BoxDecoration(color: c.cardBg, border: Border(top: BorderSide(color: c.divider.withValues(alpha: 0.5)))),
      child: SafeArea(
        top: false,
        child: chatColumn(Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: c.inputBg, shape: BoxShape.circle),
                  child: Icon(icon, size: AppIconSize.md, color: c.textMedium),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(child: Text(text, style: appText(13.5, w: FontWeight.w500, c: c.textMedium, h: 1.35))),
              ]),
              if (unblock)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpace.xs),
                  child: Align(alignment: AlignmentDirectional.centerEnd, child: AppButton.tonal(label: 'chat_unblock'.tr, onPressed: onUnblock)),
                ),
            ]),
          ),
        )),
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
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.xxs, AppSpace.xxs, AppSpace.xxs, AppSpace.xxs),
      decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(AppRadius.chip + 2)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.chip - 2),
          child: SizedBox(
            width: 40,
            height: 40,
            child: preview != null
                ? Image.memory(preview!, fit: BoxFit.cover, errorBuilder: (_, _, _) => Icon(Icons.image_outlined, size: AppIconSize.sm, color: c.primary))
                : ColoredBox(color: c.primaryTint, child: Icon(Icons.insert_drive_file_rounded, size: AppIconSize.md, color: chatInk(c))),
          ),
        ),
        const SizedBox(width: AppSpace.xs),
        Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12, w: FontWeight.w600, c: c.textDark))),
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
    final fg = selected ? chatInk(c) : c.textMedium;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? c.primaryTint : c.inputBg,
        borderRadius: BorderRadius.circular(AppRadius.hero),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.hero),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 34),
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
            alignment: Alignment.center,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[Icon(icon, size: AppIconSize.xs, color: fg), const SizedBox(width: 5)],
              Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12.5, w: FontWeight.w600, c: fg))),
            ]),
          ),
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

/// "Replying to …" above the writing box.
class ChatReplyBar extends StatelessWidget {
  const ChatReplyBar({super.key, required this.reply, this.you = false, required this.onCancel});
  final ChatReplyRef reply;
  final bool you;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(children: [
      Icon(Icons.reply_rounded, size: AppIconSize.md, color: chatInk(c)),
      const SizedBox(width: AppSpace.xs),
      Expanded(
        child: ChatQuote(reply: reply, you: you, bar: chatInk(c), ink: c.textDark, soft: c.textMedium, fill: c.inputBg),
      ),
      IconButton(
        tooltip: 'chat_reply_cancel'.tr,
        constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
        icon: Icon(Icons.close_rounded, size: AppIconSize.md, color: c.textMedium),
        onPressed: onCancel,
      ),
    ]);
  }
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
    this.replyTo,
    this.replyIsMine = false,
    this.onCancelReply,
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
  final ChatReplyRef? replyTo;
  final bool replyIsMine;
  final VoidCallback? onCancelReply;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final canSend = controller.text.trim().isNotEmpty || files.isNotEmpty;
    final length = controller.text.length;
    final border = OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.block), borderSide: BorderSide.none);
    return Container(
      padding: const EdgeInsets.all(AppSpace.xs),
      decoration: BoxDecoration(color: c.cardBg, border: Border(top: BorderSide(color: c.divider.withValues(alpha: 0.5)))),
      child: SafeArea(
        top: false,
        child: chatColumn(Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (replyTo != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xs),
              child: ChatReplyBar(reply: replyTo!, you: replyIsMine, onCancel: () => onCancelReply?.call()),
            ),
          if (files.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xs),
              child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                for (var i = 0; i < files.length; i++)
                  ChatPendingFileChip(name: files[i].name, preview: files[i].isImage ? files[i].bytes : null, onRemove: () => onRemoveFile?.call(i)),
              ]),
            ),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (onAttach != null) IconButton(tooltip: 'chat_attach'.tr, constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min), icon: Transform.rotate(angle: 0.7, child: Icon(Icons.attach_file_rounded, color: c.textMedium)), onPressed: onAttach),
            Expanded(
              child: Focus(
                skipTraversal: true,
                canRequestFocus: false,
                onKeyEvent: (node, ev) {
                  if (ev is KeyDownEvent && ev.logicalKey == LogicalKeyboardKey.escape && replyTo != null) {
                    onCancelReply?.call();
                    return KeyEventResult.handled;
                  }
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
                  style: appText(14.5, w: FontWeight.w400, c: c.textDark, h: 1.35),
                  onChanged: onChanged,
                  decoration: InputDecoration(
                    hintText: 'chat_message_hint'.tr,
                    hintStyle: appText(14.5, w: FontWeight.w400, c: c.textMedium),
                    isDense: true,
                    counterText: '',
                    filled: true,
                    fillColor: c.inputBg,
                    contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: 14),
                    border: border,
                    enabledBorder: border,
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.block), borderSide: BorderSide(color: chatInk(c).withValues(alpha: 0.45), width: AppBorder.strong)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpace.xs),
            ChatSendButton(enabled: canSend, onTap: onSend),
          ]),
          if (length > maxLength - 200)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xxs),
              child: Text(ltrIsolate('$length / $maxLength'), textAlign: TextAlign.end, style: appText(11, w: FontWeight.w500, c: length >= maxLength ? c.danger : c.textMedium)),
            ),
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
    final motion = AppMotion.of(context).fast;
    return Semantics(
      button: true,
      label: 'chat_send'.tr,
      enabled: enabled,
      child: Tooltip(
        message: 'chat_send'.tr,
        child: InkResponse(
          onTap: enabled ? onTap : null,
          radius: AppTouch.min / 2 + 4,
          child: AnimatedContainer(
            duration: motion,
            width: AppTouch.min,
            height: AppTouch.min,
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: enabled ? c.primaryGradient : null, color: enabled ? null : c.inputBg),
            child: AnimatedScale(
              duration: motion,
              scale: enabled ? 1 : 0.88,
              child: Icon(Icons.send_rounded, size: AppIconSize.md, color: enabled ? c.onHero : c.textMedium),
            ),
          ),
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
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.chip + 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.chip + 2),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs + 2, vertical: 10),
          child: Row(children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: c.primaryTint, shape: BoxShape.circle),
              child: Icon(Icons.mark_email_unread_outlined, size: AppIconSize.lg, color: chatInk(c)),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('chat_requests'.tr, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(14.5, w: FontWeight.w600, c: c.textDark)),
                const SizedBox(height: 2),
                Text('chat_requests_sub'.tr, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13, w: FontWeight.w400, c: c.textMedium)),
              ]),
            ),
            const SizedBox(width: AppSpace.xs),
            ChatCountPill(count: count),
          ]),
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
      decoration: BoxDecoration(color: c.cardBg, borderRadius: BorderRadius.circular(AppRadius.card), border: Border.all(color: c.divider.withValues(alpha: 0.7))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          child: Row(children: [
            ChatAvatar(name: conv.title, url: conv.peer?.imageUrl, size: 44),
            const SizedBox(width: AppSpace.sm),
            Expanded(child: Text(conv.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(14.5, w: FontWeight.w600, c: c.textDark))),
            const SizedBox(width: AppSpace.xs),
            Text(chatRowTime(conv.lastAt, now: now), style: appText(11.5, w: FontWeight.w400, c: c.textMedium)),
          ]),
        ),
        if (body.isNotEmpty) ...[
          const SizedBox(height: AppSpace.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs + 2),
            decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(AppRadius.chip + 2)),
            child: Text(body, maxLines: 4, overflow: TextOverflow.ellipsis, textDirection: contentDirection(body), style: appText(13.5, w: FontWeight.w400, c: c.textDark, h: 1.4)),
          ),
        ],
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
      TextButton(onPressed: busy ? null : onBlock, style: TextButton.styleFrom(minimumSize: const Size(0, AppTouch.min)), child: Text('chat_block'.tr, style: appText(13, w: FontWeight.w600, c: c.danger))),
      AppButton.tonal(label: 'chat_request_decline'.tr, onPressed: busy ? null : onDecline),
      AppButton(label: 'chat_request_accept'.tr, onPressed: busy ? null : onAccept),
    ]);
  }
}

/// In a request I received, the composer's place: what this is and the three answers.
class ChatRequestDecisionBar extends StatelessWidget {
  const ChatRequestDecisionBar({super.key, required this.onAccept, required this.onDecline, required this.onBlock, this.busy = false, this.reason, this.name});
  final VoidCallback onAccept, onDecline, onBlock;
  final bool busy;
  final String? reason;

  /// Who is asking.
  final String? name;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final title = name == null || name!.isEmpty ? 'chat_requests'.tr : 'chat_request_from'.tr.replaceAll('{name}', name!);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
      decoration: BoxDecoration(color: c.cardBg, border: Border(top: BorderSide(color: c.divider.withValues(alpha: 0.5)))),
      child: SafeArea(
        top: false,
        child: chatColumn(Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(14.5, w: FontWeight.w600, c: c.textDark)),
              const SizedBox(height: 2),
              Text(reason ?? 'chat_request_received_body'.tr, style: appText(13, w: FontWeight.w400, c: c.textMedium, h: 1.35)),
              const SizedBox(height: AppSpace.sm),
              ChatRequestActions(onAccept: onAccept, onDecline: onDecline, onBlock: onBlock, busy: busy),
            ]),
          ),
        )),
      ),
    );
  }
}
